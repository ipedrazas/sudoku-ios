import Foundation
import Testing

@testable import SudokuKit

@Suite("Share code")
struct ShareCodeTests {

    @Test("every corpus puzzle round-trips")
    func roundTrip() throws {
        for entry in Fixtures.corpus where entry.solutions >= 1 {
            let encoded = ShareCode.encode(entry.grid)
            let decoded = try ShareCode.decode(encoded)
            #expect(decoded == entry.grid, "round trip failed for \(entry.puzzle)")
        }
    }

    @Test("an empty grid round-trips")
    func emptyGrid() throws {
        #expect(try ShareCode.decode(ShareCode.encode(Grid())) == Grid())
    }

    @Test("a full grid round-trips")
    func fullGrid() throws {
        let solved = Fixtures.single(kind: "solved-grid").grid
        #expect(try ShareCode.decode(ShareCode.encode(solved)) == solved)
    }

    @Test("encoding is stable and URL-safe")
    func encodingIsUrlSafe() {
        let grid = Fixtures.corpus(kind: "generated-medium")[0].grid
        let encoded = ShareCode.encode(grid)

        #expect(encoded == ShareCode.encode(grid), "encoding must be deterministic")
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    /// The mask-plus-nibbles layout exists to keep codes short enough to paste
    /// into a message. A naive four-bits-per-cell encoding would need 41 bytes.
    @Test("a typical puzzle encodes to well under 60 characters")
    func codesStayShort() {
        for entry in Fixtures.corpus(kind: "generated-medium").prefix(10) {
            let encoded = ShareCode.encode(entry.grid)
            #expect(encoded.count < 60, "\(entry.clues)-clue puzzle encoded to \(encoded.count) chars")
        }
    }

    // MARK: - Rejection
    //
    // Every case below must throw. A share code that silently decoded to a
    // *different* legal puzzle would be far worse than one that failed.

    @Test("a corrupted code is rejected by the checksum")
    func checksumCatchesCorruption() {
        let grid = Fixtures.corpus(kind: "generated-hard")[0].grid
        let encoded = ShareCode.encode(grid)

        var caught = 0
        for position in encoded.indices {
            let original = encoded[position]
            // Swap one character for a different valid base64url character.
            let replacement: Character = original == "A" ? "B" : "A"
            var mutated = encoded
            mutated.replaceSubrange(position...position, with: [replacement])
            if mutated == encoded { continue }

            do {
                let decoded = try ShareCode.decode(mutated)
                if decoded != grid {
                    Issue.record("a single-character change decoded to a different puzzle: \(mutated)")
                }
            } catch {
                caught += 1
            }
        }
        #expect(caught > 0, "no corruption was detected at all")
    }

    @Test("non-base64 input is rejected")
    func rejectsNonBase64() {
        #expect(throws: ShareCode.DecodeError.self) { try ShareCode.decode("not valid base64 !!!") }
    }

    @Test("a truncated code is rejected")
    func rejectsShortInput() {
        #expect(throws: ShareCode.DecodeError.tooShort) { try ShareCode.decode("AQID") }
    }

    @Test("an unknown version is rejected rather than guessed")
    func rejectsUnknownVersion() {
        let grid = Fixtures.corpus(kind: "generated-easy")[0].grid
        guard var bytes = ShareCode.base64URLDecode(ShareCode.encode(grid)) else {
            Issue.record("could not decode our own output")
            return
        }
        bytes[0] = 99
        let checksum = ShareCode.crc16(Array(bytes.dropLast(2)))
        bytes[bytes.count - 2] = UInt8(checksum >> 8)
        bytes[bytes.count - 1] = UInt8(checksum & 0xFF)

        #expect(throws: ShareCode.DecodeError.unsupportedVersion(99)) {
            try ShareCode.decode(ShareCode.base64URLEncode(bytes))
        }
    }

    @Test("a rule-breaking puzzle is rejected")
    func rejectsInvalidPuzzle() {
        var broken = Grid()
        broken[0, 0] = 5
        broken[0, 4] = 5

        // Encoding does not validate, so this produces a decodable code for an
        // illegal grid — decoding must be the thing that refuses it.
        #expect(throws: ShareCode.DecodeError.invalidPuzzle) {
            try ShareCode.decode(ShareCode.encode(broken))
        }
    }

    // MARK: - URLs

    @Test("the custom scheme round-trips through a URL")
    func customSchemeURL() throws {
        let grid = Fixtures.corpus(kind: "generated-medium")[1].grid
        guard let url = ShareCode.url(for: grid) else {
            Issue.record("could not build a URL")
            return
        }

        #expect(url.scheme == "sudokuandcake")
        guard let code = ShareCode.code(from: url) else {
            Issue.record("could not extract a code from \(url)")
            return
        }
        #expect(try ShareCode.decode(code) == grid)
    }

    @Test("the universal link round-trips through a URL")
    func universalLinkURL() throws {
        let grid = Fixtures.corpus(kind: "generated-hard")[1].grid
        guard let url = ShareCode.universalLink(for: grid) else {
            Issue.record("could not build a URL")
            return
        }

        #expect(url.host == "sudoku.ios.andcake.dev")
        guard let code = ShareCode.code(from: url) else {
            Issue.record("could not extract a code from \(url)")
            return
        }
        #expect(try ShareCode.decode(code) == grid)
    }

    @Test("unrelated URLs yield no code")
    func ignoresUnrelatedURLs() {
        for text in ["https://example.com/", "https://sudoku.ios.andcake.dev/stats", "sudokuandcake://settings"] {
            guard let url = URL(string: text) else { continue }
            #expect(ShareCode.code(from: url) == nil, "\(text) should not look like a share link")
        }
    }
}
