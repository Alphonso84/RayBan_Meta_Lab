//
//  TokenBudget.swift
//  Smart Glasses
//
//  Measures how much of the model's context a piece of text actually consumes,
//  so batching decisions come from the model instead of a magic number.
//
//  Replaces the old `maxCardsPerBatch = 4`, which was wrong in both directions:
//  it wasted context on short cards and overflowed on long ones.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum TokenBudget {

    // MARK: - Configuration

    /// Tokens held back for the model's own response.
    ///
    /// A deck summary is 3-5 sentences plus 4-6 themes; 1024 leaves comfortable
    /// room for that plus the guided-generation scaffolding around it.
    ///
    /// `nonisolated` because it is used as a default argument, and those are
    /// evaluated outside the actor.
    nonisolated static let defaultOutputReserve = 1_024

    /// Characters per token for English prose.
    ///
    /// Only used if the real tokenizer throws. Four is the conventional rule of
    /// thumb and errs slightly toward over-counting, which is the safe direction
    /// for a budget.
    private static let charactersPerToken = 4

    // MARK: - Model Limits

    /// Context window of the on-device model, in tokens.
    ///
    /// Reports the real per-device value: the property only back-deploys to a
    /// hardcoded 4096 below iOS 27, which this app no longer targets.
    static var contextSize: Int {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.contextSize
        #else
        return 4_096
        #endif
    }

    // MARK: - Budget

    struct Budget {
        /// Total context window.
        let contextSize: Int

        /// Tokens consumed before any content: instructions plus output schema.
        let overhead: Int

        /// Tokens held back for the response.
        let outputReserve: Int

        /// What is actually left for the content being summarized.
        var availableForContent: Int {
            max(0, contextSize - overhead - outputReserve)
        }
    }

    /// Measure the fixed cost of a request so the remainder can be spent on content.
    static func makeBudget(
        instructions: String,
        schemaFor generableType: (any Generable.Type)? = nil,
        outputReserve: Int = defaultOutputReserve
    ) async -> Budget {
        var overhead = await measure(instructions)

        #if canImport(FoundationModels)
        if let generableType,
           let schemaTokens = try? await SystemLanguageModel.default.tokenCount(
               for: generableType.generationSchema
           ) {
            overhead += schemaTokens
        }
        #endif

        return Budget(
            contextSize: contextSize,
            overhead: overhead,
            outputReserve: outputReserve
        )
    }

    // MARK: - Measurement

    /// Token count for a piece of text, measured when possible and estimated otherwise.
    static func measure(_ text: String) async -> Int {
        #if canImport(FoundationModels)
        if let count = try? await SystemLanguageModel.default.tokenCount(for: text) {
            return count
        }
        #endif
        return estimate(text)
    }

    /// Character-based approximation, used only if the tokenizer fails.
    static func estimate(_ text: String) -> Int {
        max(1, Int((Double(text.count) / Double(charactersPerToken)).rounded(.up)))
    }

    // MARK: - Packing

    /// Greedily group chunks into batches that each fit the budget.
    ///
    /// A single chunk larger than the whole budget still gets its own batch — it
    /// cannot be split further without cutting a card in half, and letting the
    /// model truncate one oversized card beats dropping it silently.
    ///
    /// `measuring` defaults to the real tokenizer and exists so tests can supply
    /// a deterministic count — the on-device tokenizer's output varies by device
    /// and OS build, which would make packing assertions unreproducible.
    static func pack(
        _ chunks: [String],
        into budget: Budget,
        measuring: (String) async -> Int = measure
    ) async -> [[String]] {
        let limit = budget.availableForContent
        guard limit > 0 else { return chunks.map { [$0] } }

        var batches: [[String]] = []
        var currentBatch: [String] = []
        var currentTokens = 0

        for chunk in chunks {
            let chunkTokens = await measuring(chunk)

            if currentBatch.isEmpty {
                currentBatch = [chunk]
                currentTokens = chunkTokens
                continue
            }

            if currentTokens + chunkTokens <= limit {
                currentBatch.append(chunk)
                currentTokens += chunkTokens
            } else {
                batches.append(currentBatch)
                currentBatch = [chunk]
                currentTokens = chunkTokens
            }
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    /// Whether `text` fits alongside the given fixed costs in a single request.
    static func fits(_ text: String, in budget: Budget) async -> Bool {
        await measure(text) <= budget.availableForContent
    }
}
