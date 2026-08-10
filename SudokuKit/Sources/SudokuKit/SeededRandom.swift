/// A deterministic, reproducible random number generator.
///
/// SplitMix64: tiny, fast, well-distributed, and — the property that matters
/// here — specified precisely enough that it will produce the same sequence on
/// every device and every future Swift release.
///
/// Go's `math/rand` and Swift's RNG produce different sequences, so dailies
/// cannot be byte-identical with the web app. With sync off, they do not need to
/// be. What they *do* need is for every iOS device to agree, forever: a player's
/// daily history and streak are meaningless if the 3rd of March generates a
/// different puzzle after an OS update.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform value in `0..<upperBound`.
    ///
    /// Deliberately not `Int.random(in:using:)`. The stdlib's bounded draw is not
    /// a documented, stable algorithm, so a future implementation change would
    /// silently reshuffle every past daily. This is Lemire's method, written out
    /// so it can never drift.
    public mutating func nextBounded(_ upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let bound = UInt64(upperBound)

        var draw = next()
        var product = draw.multipliedFullWidth(by: bound)
        if product.low < bound {
            // Reject the biased tail so every value is equally likely.
            let threshold = (0 &- bound) % bound
            while product.low < threshold {
                draw = next()
                product = draw.multipliedFullWidth(by: bound)
            }
        }
        return Int(product.high)
    }
}

extension Array {
    /// Fisher-Yates, written out for the same reason as `nextBounded`:
    /// `Array.shuffle(using:)` does not promise a stable algorithm, and puzzle
    /// generation must be reproducible.
    public mutating func deterministicShuffle(using rng: inout SeededRandom) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = rng.nextBounded(i + 1)
            if i != j { swapAt(i, j) }
        }
    }

    /// A shuffled copy.
    public func deterministicShuffled(using rng: inout SeededRandom) -> [Element] {
        var copy = self
        copy.deterministicShuffle(using: &rng)
        return copy
    }
}
