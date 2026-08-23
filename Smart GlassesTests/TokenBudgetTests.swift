//
//  TokenBudgetTests.swift
//  Smart GlassesTests
//
//  Covers the batching that replaced the old `maxCardsPerBatch = 4`, which was
//  wrong in both directions: it wasted context on short cards and overflowed on
//  long ones.
//
//  Every test supplies its own measurement so the assertions do not depend on
//  the on-device tokenizer, whose output varies by device and OS build.
//

import Testing
@testable import Smart_Glasses

struct TokenBudgetTests {

    /// One token per character, so a chunk's cost is just its length.
    private let byCharacter: (String) async -> Int = { $0.count }

    private func budget(contextSize: Int, overhead: Int = 0, outputReserve: Int = 0) -> TokenBudget.Budget {
        TokenBudget.Budget(contextSize: contextSize, overhead: overhead, outputReserve: outputReserve)
    }

    // MARK: - Budget arithmetic

    @Test func availableContentIsWhatRemainsAfterOverheadAndReserve() {
        let b = budget(contextSize: 4096, overhead: 500, outputReserve: 1024)

        #expect(b.availableForContent == 2572)
    }

    /// Instructions plus reserve can exceed the window on a small model variant.
    /// Clamping at zero keeps `pack` from computing a negative limit.
    @Test func availableContentNeverGoesNegative() {
        let b = budget(contextSize: 1000, overhead: 900, outputReserve: 500)

        #expect(b.availableForContent == 0)
    }

    // MARK: - Estimation

    /// Four characters per token is the fallback when the tokenizer throws, and
    /// it rounds up so the budget errs toward over-counting.
    @Test func estimateRoundsUp() {
        #expect(TokenBudget.estimate("abcd") == 1)
        #expect(TokenBudget.estimate("abcde") == 2)
        #expect(TokenBudget.estimate(String(repeating: "x", count: 400)) == 100)
    }

    /// Never zero: a chunk that costs nothing would let packing loop forever
    /// believing it always fits.
    @Test func estimateOfEmptyTextIsOneNotZero() {
        #expect(TokenBudget.estimate("") == 1)
    }

    // MARK: - Packing

    @Test func chunksThatFitTogetherShareOneBatch() async {
        let chunks = ["aaaa", "bbbb", "cccc"]

        let batches = await TokenBudget.pack(chunks, into: budget(contextSize: 100), measuring: byCharacter)

        #expect(batches == [chunks])
    }

    @Test func packingSplitsWhenTheLimitIsReached() async {
        let chunks = ["aaaaa", "bbbbb", "ccccc"]

        // Limit of 10 fits exactly two five-character chunks.
        let batches = await TokenBudget.pack(chunks, into: budget(contextSize: 10), measuring: byCharacter)

        #expect(batches == [["aaaaa", "bbbbb"], ["ccccc"]])
    }

    /// The boundary itself: a batch exactly at the limit is still allowed.
    @Test func aBatchMayFillTheLimitExactly() async {
        let batches = await TokenBudget.pack(
            ["aaaaa", "bbbbb"],
            into: budget(contextSize: 10),
            measuring: byCharacter
        )

        #expect(batches.count == 1)
    }

    /// A single card longer than the whole window cannot be split without
    /// cutting it in half, so it gets its own batch and the model truncates —
    /// better than dropping it silently.
    @Test func anOversizedChunkGetsItsOwnBatch() async {
        let chunks = ["aa", String(repeating: "x", count: 500), "bb"]

        let batches = await TokenBudget.pack(chunks, into: budget(contextSize: 10), measuring: byCharacter)

        #expect(batches.count == 3)
        #expect(batches[1] == [String(repeating: "x", count: 500)])
    }

    /// An oversized chunk must not drag its neighbours into an overflowing batch.
    @Test func anOversizedChunkDoesNotAbsorbTheNextChunk() async {
        let big = String(repeating: "x", count: 500)

        let batches = await TokenBudget.pack([big, "bb"], into: budget(contextSize: 10), measuring: byCharacter)

        #expect(batches == [[big], ["bb"]])
    }

    /// When overhead alone exhausts the window there is no sane grouping, so
    /// every chunk goes alone rather than into one doomed batch.
    @Test func aZeroLimitPutsEveryChunkInItsOwnBatch() async {
        let chunks = ["a", "b", "c"]

        let batches = await TokenBudget.pack(
            chunks,
            into: budget(contextSize: 100, overhead: 100),
            measuring: byCharacter
        )

        #expect(batches == [["a"], ["b"], ["c"]])
    }

    @Test func packingNothingProducesNoBatches() async {
        let batches = await TokenBudget.pack([], into: budget(contextSize: 100), measuring: byCharacter)

        #expect(batches.isEmpty)
    }

    /// Packing must never lose a card.
    @Test func everyChunkSurvivesPacking() async {
        let chunks = (1...20).map { String(repeating: "\($0 % 10)", count: $0) }

        let batches = await TokenBudget.pack(chunks, into: budget(contextSize: 25), measuring: byCharacter)

        #expect(batches.flatMap { $0 } == chunks)
    }
}
