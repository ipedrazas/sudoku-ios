// Command export-fixtures emits the Go↔Swift cross-check corpus.
//
// This is the highest-value tool in the port. The technique rater is the most
// valuable code in the project and the easiest to get subtly wrong: a
// mis-ported elimination turns an "easy" puzzle into one that needs an X-wing,
// and nothing in the app would notice. Rating a large, varied corpus with the
// Go implementation and asserting the Swift port agrees on every entry turns "I
// think the port is right" into a proof.
//
// The tier values come from generator.Rate — the exact function being ported.
// The solution counts come from an independent counter written below rather
// than the generator's own, so the Swift solver is checked against a second
// implementation instead of a translation of itself.
//
// Usage: go run . -out ../../SudokuKit/Tests/SudokuKitTests/Fixtures/tier-corpus.json
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"os"
	"sort"
	"strings"

	"sudoku-and-cake/backend/internal/generator"
)

const (
	size    = 9
	boxSize = 3
)

// Entry is one corpus case: a puzzle, the tier Go assigns it, and how many
// solutions it has (counted up to 2 — "exactly one" is the property that
// matters).
type Entry struct {
	Puzzle    string `json:"puzzle"`    // 81 chars, '0' for empty
	Tier      int    `json:"tier"`      // generator.Rate
	Solutions int    `json:"solutions"` // 0, 1, or 2 meaning "2 or more"
	Clues     int    `json:"clues"`
	Kind      string `json:"kind"` // provenance, for diagnosing a failure
}

func main() {
	out := flag.String("out", "tier-corpus.json", "output path")
	seed := flag.Int64("seed", 20260810, "RNG seed; fixed so the corpus is reproducible")
	flag.Parse()

	rng := rand.New(rand.NewSource(*seed)) // #nosec G404 -- reproducibility is the point

	var entries []Entry
	entries = append(entries, generatedEntries()...)
	entries = append(entries, randomCarveEntries(rng)...)
	entries = append(entries, partiallySolvedEntries(rng)...)
	entries = append(entries, edgeCaseEntries()...)
	entries = dedupe(entries)

	payload, err := json.MarshalIndent(entries, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "marshal:", err)
		os.Exit(1)
	}
	if err := os.WriteFile(*out, append(payload, '\n'), 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "write:", err)
		os.Exit(1)
	}

	report(entries, *out)
}

// generatedEntries covers what players actually receive: 40 puzzles per
// shipped difficulty, straight from Generate.
func generatedEntries() []Entry {
	var entries []Entry
	for _, difficulty := range []string{"easy", "medium", "hard"} {
		for i := 0; i < 40; i++ {
			puzzle, _ := generator.Generate(difficulty)
			entries = append(entries, entryFor(puzzle, "generated-"+difficulty))
		}
	}
	return entries
}

// randomCarveEntries covers the space Generate never returns: unfiltered carves
// across the whole clue range, which is where TierBeyond and non-unique puzzles
// live. Without these the corpus would only ever exercise the tiers the
// generator is willing to ship.
func randomCarveEntries(rng *rand.Rand) []Entry {
	var entries []Entry
	for i := 0; i < 120; i++ {
		_, solution := generator.Generate("easy")
		puzzle := solution

		// Spread the clue counts from nearly-full down to below the 17-clue
		// minimum for a unique solution.
		remove := 20 + rng.Intn(50)
		order := rng.Perm(size * size)
		for _, cell := range order[:remove] {
			puzzle[cell/size][cell%size] = 0
		}
		entries = append(entries, entryFor(puzzle, "random-carve"))
	}
	return entries
}

// partiallySolvedEntries are what the hint engine actually rates at runtime: a
// puzzle with some of the player's correct entries already in place. Rating
// those is a different code path from rating a fresh puzzle, and it is the one
// the app exercises most.
func partiallySolvedEntries(rng *rand.Rand) []Entry {
	var entries []Entry
	for i := 0; i < 40; i++ {
		difficulty := []string{"easy", "medium", "hard"}[i%3]
		puzzle, solution := generator.Generate(difficulty)

		var empties [][2]int
		for r := 0; r < size; r++ {
			for c := 0; c < size; c++ {
				if puzzle[r][c] == 0 {
					empties = append(empties, [2]int{r, c})
				}
			}
		}
		fill := rng.Intn(len(empties))
		rng.Shuffle(len(empties), func(a, b int) { empties[a], empties[b] = empties[b], empties[a] })
		for _, cell := range empties[:fill] {
			puzzle[cell[0]][cell[1]] = solution[cell[0]][cell[1]]
		}
		entries = append(entries, entryFor(puzzle, "partially-solved"))
	}
	return entries
}

// edgeCaseEntries pin the boundaries: a solved grid, an empty grid, explicit
// contradictions, and published minimal puzzles. These are the cases where an
// off-by-one in candidate handling shows up first.
func edgeCaseEntries() []Entry {
	var entries []Entry

	_, solution := generator.Generate("easy")
	entries = append(entries, entryFor(solution, "solved-grid"))

	// One blank cell: only one digit can fit. Mirrors TestRate_NakedSingleOnly.
	oneBlank := solution
	oneBlank[4][4] = 0
	entries = append(entries, entryFor(oneBlank, "one-blank"))

	// Empty grid: no constraints at all.
	entries = append(entries, entryFor(generator.Grid{}, "empty-grid"))

	// Two 1s in a row leaves a cell with no candidates.
	var duplicateRow generator.Grid
	for c := 0; c < size; c++ {
		duplicateRow[0][c] = 1
	}
	entries = append(entries, entryFor(duplicateRow, "contradiction-row"))

	// A duplicate inside one box.
	var duplicateBox generator.Grid
	duplicateBox[0][0] = 5
	duplicateBox[1][1] = 5
	entries = append(entries, entryFor(duplicateBox, "contradiction-box"))

	// A near-empty grid: one clue, astronomically many solutions.
	var oneClue generator.Grid
	oneClue[0][0] = 1
	entries = append(entries, entryFor(oneClue, "one-clue"))

	// A solved grid with one cell overwritten by a wrong digit: full, but
	// contradictory. This is the shape of a player's board after a mistake, and
	// it is what the hint engine must recognise.
	wrongEntry := solution
	wrongEntry[3][3] = wrongDigit(solution[3][3])
	entries = append(entries, entryFor(wrongEntry, "wrong-entry"))

	// Deep carves that keep a unique solution, walking down towards the 17-clue
	// theoretical minimum. Generated rather than hard-coded: a puzzle string
	// copied from memory is unverifiable, and a malformed one turns the solution
	// count into an exhaustive unsatisfiability proof.
	for i := 0; i < 10; i++ {
		_, sol := generator.Generate("hard")
		puzzle := sol
		for _, cell := range rand.New(rand.NewSource(int64(i))).Perm(size * size) {
			r, c := cell/size, cell%size
			backup := puzzle[r][c]
			puzzle[r][c] = 0
			if countSolutions(puzzle, 2) != 1 {
				puzzle[r][c] = backup
			}
		}
		entries = append(entries, entryFor(puzzle, "minimal-carve"))
	}

	return entries
}

// wrongDigit returns any digit other than the given one.
func wrongDigit(correct int) int {
	if correct == 1 {
		return 2
	}
	return 1
}

func entryFor(g generator.Grid, kind string) Entry {
	return Entry{
		Puzzle:    formatGrid(g),
		Tier:      int(generator.Rate(g)),
		Solutions: countSolutions(g, 2),
		Clues:     clueCount(g),
		Kind:      kind,
	}
}

func dedupe(entries []Entry) []Entry {
	seen := make(map[string]bool, len(entries))
	out := entries[:0]
	for _, e := range entries {
		if seen[e.Puzzle] {
			continue
		}
		seen[e.Puzzle] = true
		out = append(out, e)
	}
	return out
}

func report(entries []Entry, path string) {
	byTier := map[int]int{}
	byKind := map[string]int{}
	bySolutions := map[int]int{}
	for _, e := range entries {
		byTier[e.Tier]++
		byKind[e.Kind]++
		bySolutions[e.Solutions]++
	}

	fmt.Printf("wrote %d entries to %s\n", len(entries), path)
	fmt.Println("  by tier:", sortedCounts(byTier))
	fmt.Println("  by solutions:", sortedCounts(bySolutions))

	kinds := make([]string, 0, len(byKind))
	for k := range byKind {
		kinds = append(kinds, k)
	}
	sort.Strings(kinds)
	parts := make([]string, 0, len(kinds))
	for _, k := range kinds {
		parts = append(parts, fmt.Sprintf("%s=%d", k, byKind[k]))
	}
	fmt.Println("  by kind:", strings.Join(parts, " "))
}

func sortedCounts(counts map[int]int) string {
	keys := make([]int, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Ints(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%d=%d", k, counts[k]))
	}
	return strings.Join(parts, " ")
}

// --- Grid helpers ---

func formatGrid(g generator.Grid) string {
	var sb strings.Builder
	sb.Grow(size * size)
	for r := 0; r < size; r++ {
		for c := 0; c < size; c++ {
			sb.WriteByte(byte('0' + g[r][c]))
		}
	}
	return sb.String()
}

func parseGrid(digits string) (generator.Grid, bool) {
	var g generator.Grid
	if len(digits) != size*size {
		return g, false
	}
	for i := 0; i < size*size; i++ {
		ch := digits[i]
		if ch == '.' {
			continue
		}
		if ch < '0' || ch > '9' {
			return g, false
		}
		g[i/size][i%size] = int(ch - '0')
	}
	return g, true
}

func clueCount(g generator.Grid) int {
	n := 0
	for r := 0; r < size; r++ {
		for c := 0; c < size; c++ {
			if g[r][c] != 0 {
				n++
			}
		}
	}
	return n
}

// --- Independent solution counter ---
//
// Deliberately not the generator's own countSolutions: checking the Swift
// solver against a translation of itself would prove only that the translation
// is faithful, not that either is correct. This is a plain
// most-constrained-cell backtracker written from the rules.

// maxNodes bounds the search. Proving a contradictory sparse grid has zero
// solutions can take effectively forever, and a fixture generator that can hang
// is a fixture generator nobody reruns. Exceeding the bound is reported, never
// silently rounded to an answer.
const maxNodes = 5_000_000

// errSearchTooDeep marks an entry whose solution count could not be settled
// within maxNodes.
var errSearchTooDeep = fmt.Errorf("search exceeded %d nodes", maxNodes)

func countSolutions(g generator.Grid, limit int) int {
	// A contradiction among the givens is invisible to the search: it only
	// inspects empty cells, so two 5s in one box would be found only after
	// exhausting the tree. Checking the rules once up front turns that from an
	// astronomical search into a single pass.
	if !obeysRules(&g) {
		return 0
	}
	nodes := 0
	count, err := countRecursive(&g, limit, &nodes)
	if err != nil {
		return -1
	}
	return count
}

func countRecursive(g *generator.Grid, limit int, nodes *int) (int, error) {
	if limit <= 0 {
		return 0, nil
	}
	*nodes++
	if *nodes > maxNodes {
		return 0, errSearchTooDeep
	}

	bestR, bestC, bestMask, bestCount := -1, -1, 0, size+1
	for r := 0; r < size; r++ {
		for c := 0; c < size; c++ {
			if g[r][c] != 0 {
				continue
			}
			mask := candidateMask(g, r, c)
			n := popCount(mask)
			if n == 0 {
				return 0, nil
			}
			if n < bestCount {
				bestR, bestC, bestMask, bestCount = r, c, mask, n
			}
		}
	}
	if bestR == -1 {
		// No empty cells. The grid is complete, but "complete" is not
		// "correct": a filled grid can still break the rules.
		if !obeysRules(g) {
			return 0, nil
		}
		return 1, nil
	}

	count := 0
	for d := 1; d <= size; d++ {
		if bestMask&(1<<uint(d)) == 0 {
			continue
		}
		g[bestR][bestC] = d
		sub, err := countRecursive(g, limit-count, nodes)
		if err != nil {
			g[bestR][bestC] = 0
			return 0, err
		}
		count += sub
		if count >= limit {
			g[bestR][bestC] = 0
			return count, nil
		}
	}
	g[bestR][bestC] = 0
	return count, nil
}

// obeysRules reports whether no digit repeats in any row, column or box.
func obeysRules(g *generator.Grid) bool {
	for i := 0; i < size; i++ {
		var rowSeen, colSeen int
		for j := 0; j < size; j++ {
			if v := g[i][j]; v != 0 {
				if rowSeen&(1<<uint(v)) != 0 {
					return false
				}
				rowSeen |= 1 << uint(v)
			}
			if v := g[j][i]; v != 0 {
				if colSeen&(1<<uint(v)) != 0 {
					return false
				}
				colSeen |= 1 << uint(v)
			}
		}
	}
	for br := 0; br < size; br += boxSize {
		for bc := 0; bc < size; bc += boxSize {
			var seen int
			for r := br; r < br+boxSize; r++ {
				for c := bc; c < bc+boxSize; c++ {
					if v := g[r][c]; v != 0 {
						if seen&(1<<uint(v)) != 0 {
							return false
						}
						seen |= 1 << uint(v)
					}
				}
			}
		}
	}
	return true
}

func candidateMask(g *generator.Grid, row, col int) int {
	used := 0
	for i := 0; i < size; i++ {
		used |= 1 << uint(g[row][i])
		used |= 1 << uint(g[i][col])
	}
	br, bc := row/boxSize*boxSize, col/boxSize*boxSize
	for r := br; r < br+boxSize; r++ {
		for c := bc; c < bc+boxSize; c++ {
			used |= 1 << uint(g[r][c])
		}
	}
	// Bits 1..9 that are not used. Empty peers set bit 0, which is masked off.
	return 0x03FE &^ used
}

func popCount(mask int) int {
	n := 0
	for mask != 0 {
		mask &= mask - 1
		n++
	}
	return n
}
