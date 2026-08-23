//
//  FlashcardGenerator.swift
//  Smart Glasses
//
//  Generates flashcards from deck cards using the configured LLM provider
//

import Combine
import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels

/// Guided-generation schema for a set of flashcards produced by Foundation Models.
@Generable
private struct GeneratedFlashcardSet {
    @Guide(description: "The generated flashcards.")
    var flashcards: [GeneratedFlashcard]
}

@Generable
private struct GeneratedFlashcard {
    @Guide(description: "A concise question or term for the front of the card.")
    var front: String

    @Guide(description: "A complete but brief answer or explanation for the back.")
    var back: String

    @Guide(description: "The title of the source card this flashcard is based on.")
    var sourceCard: String

    @Guide(description: "A short category for grouping, or an empty string if none applies.")
    var category: String
}
#endif

@MainActor
class FlashcardGenerator: ObservableObject {

    // MARK: - State

    enum GeneratorState: Equatable {
        case idle
        case generating
        case complete
        case error(String)
    }

    @Published var state: GeneratorState = .idle
    @Published var flashcards: [Flashcard] = []
    @Published var progress: Double = 0

    @AppStorage("selectedProvider") private var selectedProvider = "apple"

    private lazy var openAIProvider = OpenAIProvider()

    // MARK: - Public

    func generateFlashcards(from cards: [SummaryCard], count: Int = 15) async {
        guard !cards.isEmpty else {
            state = .error("No cards to generate flashcards from")
            return
        }

        state = .generating
        flashcards = []
        progress = 0.1

        // Build combined text from all cards
        let combinedText = cards.map { card in
            """
            Card: \(card.title)
            Summary: \(card.summary)
            Key Points: \(card.keyPoints.joined(separator: "; "))
            """
        }.joined(separator: "\n\n")

        let cardTitles = cards.map(\.title)
        let flashcardCount = min(count, cards.count * 5) // Up to 5 flashcards per card

        progress = 0.2

        // Route to provider
        if selectedProvider == "openai", await openAIProvider.isAvailable {
            await generateWithOpenAI(text: combinedText, cardTitles: cardTitles, count: flashcardCount)
        } else {
            await generateWithAppleIntelligence(text: combinedText, cardTitles: cardTitles, count: flashcardCount)
        }
    }

    func reset() {
        state = .idle
        flashcards = []
        progress = 0
    }

    /// Load flashcards from cache (skips generation)
    func loadCachedFlashcards(_ cached: [Flashcard]) {
        flashcards = cached
        progress = 1.0
        state = .complete
    }

    // MARK: - OpenAI

    private func generateWithOpenAI(text: String, cardTitles: [String], count: Int) async {
        do {
            progress = 0.4
            let generated = try await openAIProvider.generateFlashcards(from: text, cardTitles: cardTitles, count: count)
            progress = 0.9

            if generated.isEmpty {
                flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            } else {
                flashcards = generated
            }

            progress = 1.0
            state = .complete
        } catch {
            print("[FlashcardGenerator] OpenAI error: \(error)")
            flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = flashcards.isEmpty ? .error(error.localizedDescription) : .complete
        }
    }

    // MARK: - Apple Intelligence

    private func generateWithAppleIntelligence(text: String, cardTitles: [String], count: Int) async {
        #if canImport(FoundationModels)
        await generateWithAppleIntelligence(
            text: text,
            cardTitles: cardTitles,
            count: count,
            tier: AppleModelProvider.textTier(for: selectedProvider)
        )
        #else
        flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
        progress = 1.0
        state = flashcards.isEmpty ? .error("Foundation Models requires iOS 26+") : .complete
        #endif
    }

    #if canImport(FoundationModels)

    static let flashcardInstructions = """
        You are a flashcard generator for study material. Each flashcard has a term or
        question on the front and a complete but brief answer or explanation on the back,
        and should test one concept clearly. Cover the most important concepts and vary
        between definition, concept, and application questions.
        """

    /// Generate on a specific tier, retrying on-device if Private Cloud Compute
    /// fails for a transient reason.
    private func generateWithAppleIntelligence(
        text: String,
        cardTitles: [String],
        count: Int,
        tier: AppleModelTier
    ) async {
        guard let session = AppleModelProvider.makeSession(
            tier: tier,
            instructions: Self.flashcardInstructions
        ) else {
            flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = flashcards.isEmpty ? .error("Apple Intelligence not available") : .complete
            return
        }

        let prompt = """
        Generate \(count) flashcards from this study material.
        Card titles: \(cardTitles.joined(separator: ", "))

        Study material:
        ---
        \(text)
        ---
        """

        do {
            progress = 0.4
            // Choosing which concepts deserve a card, and phrasing a back that is
            // brief but complete, benefits from deliberation when we are on PCC.
            let generated = try await AppleModelProvider.respond(
                session: session,
                to: prompt,
                generating: GeneratedFlashcardSet.self,
                reasoning: tier == .privateCloudCompute
            )
            progress = 0.8

            let parsed = mapGeneratedFlashcards(generated.flashcards, fallbackTitles: cardTitles)

            if parsed.isEmpty {
                flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            } else {
                flashcards = parsed
            }

            progress = 1.0
            state = .complete
        } catch {
            print("[FlashcardGenerator] Apple Intelligence error: \(error)")

            if tier == .privateCloudCompute, AppleModelProvider.isRecoverablePCCError(error) {
                print("[FlashcardGenerator] Private Cloud Compute failed; retrying on-device")
                await generateWithAppleIntelligence(
                    text: text,
                    cardTitles: cardTitles,
                    count: count,
                    tier: .onDevice
                )
                return
            }

            flashcards = generateFallbackFlashcards(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = flashcards.isEmpty ? .error(error.localizedDescription) : .complete
        }
    }

    #endif

    // MARK: - Mapping

    #if canImport(FoundationModels)
    /// Map guided-generation output into `Flashcard` values. The schema guarantees
    /// the shape, so there's no JSON to parse — we only normalize empty optionals.
    private func mapGeneratedFlashcards(_ generated: [GeneratedFlashcard], fallbackTitles: [String]) -> [Flashcard] {
        generated.compactMap { raw in
            guard !raw.front.isEmpty, !raw.back.isEmpty else { return nil }
            return Flashcard(
                front: raw.front,
                back: raw.back,
                sourceCardTitle: raw.sourceCard.isEmpty ? (fallbackTitles.first ?? "Unknown") : raw.sourceCard,
                category: raw.category.isEmpty ? nil : raw.category
            )
        }
    }
    #endif

    // MARK: - Fallback

    private func generateFallbackFlashcards(cardTitles: [String], text: String, count: Int) -> [Flashcard] {
        // Extract key points from the text to build basic flashcards
        let lines = text.components(separatedBy: "\n")
        var flashcards: [Flashcard] = []

        var currentTitle = cardTitles.first ?? "Study Material"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Card: ") {
                currentTitle = String(trimmed.dropFirst(6))
            } else if trimmed.hasPrefix("Key Points: ") {
                let points = String(trimmed.dropFirst(12)).components(separatedBy: "; ")
                for point in points where !point.isEmpty && flashcards.count < count {
                    flashcards.append(Flashcard(
                        front: "What is a key point about \(currentTitle)?",
                        back: point,
                        sourceCardTitle: currentTitle
                    ))
                }
            }
        }

        return flashcards
    }
}
