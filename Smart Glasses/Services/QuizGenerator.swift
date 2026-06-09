//
//  QuizGenerator.swift
//  Smart Glasses
//
//  Generates quiz questions from deck cards using the configured LLM provider
//

import Combine
import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels

/// Guided-generation schema for a set of quiz questions produced by Foundation Models.
@Generable
private struct GeneratedQuizSet {
    @Guide(description: "The generated multiple-choice questions.")
    var questions: [GeneratedQuizQuestion]
}

@Generable
private struct GeneratedQuizQuestion {
    @Guide(description: "A question testing comprehension of the study material, not just recall.")
    var question: String

    @Guide(description: "Exactly four answer options. Wrong answers should be plausible but clearly incorrect.")
    var options: [String]

    @Guide(description: "Zero-based index (0, 1, 2, or 3) of the correct option. Distribute correct answers evenly across all four positions.")
    var correctIndex: Int

    @Guide(description: "The title of the source card this question is based on.")
    var sourceCard: String
}
#endif

@MainActor
class QuizGenerator: ObservableObject {

    // MARK: - State

    enum GeneratorState: Equatable {
        case idle
        case generating
        case complete
        case error(String)
    }

    @Published var state: GeneratorState = .idle
    @Published var questions: [QuizQuestion] = []
    @Published var progress: Double = 0

    @AppStorage("selectedProvider") private var selectedProvider = "apple"

    private lazy var openAIProvider = OpenAIProvider()

    // MARK: - Public

    func generateQuestions(from cards: [SummaryCard], count: Int = 10) async {
        guard !cards.isEmpty else {
            state = .error("No cards to generate questions from")
            return
        }

        state = .generating
        questions = []
        progress = 0.1

        let questionsPerCard = max(1, count / cards.count)
        let totalCount = min(count, cards.count * 3)

        // Build combined text from all cards
        let combinedText = cards.map { card in
            """
            Card: \(card.title)
            Summary: \(card.summary)
            Key Points: \(card.keyPoints.joined(separator: "; "))
            """
        }.joined(separator: "\n\n")

        let cardTitles = cards.map(\.title)

        progress = 0.2

        // Route to provider
        if selectedProvider == "openai", await openAIProvider.isAvailable {
            await generateWithOpenAI(text: combinedText, cardTitles: cardTitles, count: totalCount)
        } else {
            await generateWithAppleIntelligence(text: combinedText, cardTitles: cardTitles, count: totalCount)
        }
    }

    func reset() {
        state = .idle
        questions = []
        progress = 0
    }

    // MARK: - OpenAI

    private func generateWithOpenAI(text: String, cardTitles: [String], count: Int) async {
        do {
            progress = 0.4
            let generated = try await openAIProvider.generateQuestions(from: text, cardTitles: cardTitles, count: count)
            progress = 0.9

            if generated.isEmpty {
                questions = generateFallbackQuestions(cardTitles: cardTitles, text: text, count: count)
            } else {
                questions = generated
            }

            progress = 1.0
            state = .complete
        } catch {
            print("[QuizGenerator] OpenAI error: \(error)")
            questions = generateFallbackQuestions(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = questions.isEmpty ? .error(error.localizedDescription) : .complete
        }
    }

    // MARK: - Apple Intelligence

    private func generateWithAppleIntelligence(text: String, cardTitles: [String], count: Int) async {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            questions = generateFallbackQuestions(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = questions.isEmpty ? .error("Apple Intelligence not available") : .complete
            return
        }

        let session = LanguageModelSession(instructions: """
            You are a quiz generator for study material. Generate multiple-choice questions that
            test comprehension, not just recall. Each question must have exactly 4 options with
            exactly 1 correct answer. Vary question types: definitions, comparisons, applications.
            Randomize which option is correct — distribute correct answers evenly across all four positions.
            """)

        let prompt = """
        Generate \(count) multiple-choice questions from this study material.
        Card titles: \(cardTitles.joined(separator: ", "))

        Study material:
        ---
        \(text)
        ---
        """

        do {
            progress = 0.4
            let response = try await session.respond(to: prompt, generating: GeneratedQuizSet.self)
            progress = 0.8

            let parsed = mapGeneratedQuestions(response.content.questions, fallbackTitles: cardTitles)

            if parsed.isEmpty {
                questions = generateFallbackQuestions(cardTitles: cardTitles, text: text, count: count)
            } else {
                questions = parsed
            }

            progress = 1.0
            state = .complete
        } catch {
            print("[QuizGenerator] Apple Intelligence error: \(error)")
            questions = generateFallbackQuestions(cardTitles: cardTitles, text: text, count: count)
            progress = 1.0
            state = questions.isEmpty ? .error(error.localizedDescription) : .complete
        }
        #else
        questions = generateFallbackQuestions(cardTitles: cardTitles, text: text, count: count)
        progress = 1.0
        state = questions.isEmpty ? .error("Foundation Models requires iOS 26+") : .complete
        #endif
    }

    // MARK: - Mapping

    #if canImport(FoundationModels)
    /// Map guided-generation output into validated `QuizQuestion` values.
    /// The schema guarantees the shape, so there's no JSON to parse; we still
    /// validate the option count and re-shuffle so correct-answer positions stay
    /// evenly distributed regardless of what the model produced.
    private func mapGeneratedQuestions(_ generated: [GeneratedQuizQuestion], fallbackTitles: [String]) -> [QuizQuestion] {
        generated.compactMap { raw in
            guard raw.options.count == 4,
                  raw.correctIndex >= 0,
                  raw.correctIndex < 4 else { return nil }

            let correctAnswer = raw.options[raw.correctIndex]
            var shuffledOptions = raw.options
            shuffledOptions.shuffle()
            let newCorrectIndex = shuffledOptions.firstIndex(of: correctAnswer) ?? 0

            return QuizQuestion(
                question: raw.question,
                options: shuffledOptions,
                correctAnswerIndex: newCorrectIndex,
                sourceCardTitle: raw.sourceCard.isEmpty ? (fallbackTitles.first ?? "Unknown") : raw.sourceCard
            )
        }
    }
    #endif

    // MARK: - Fallback

    private func generateFallbackQuestions(cardTitles: [String], text: String, count: Int) -> [QuizQuestion] {
        // Extract key points from the text to build basic questions
        let lines = text.components(separatedBy: "\n")
        var keyPoints: [(title: String, point: String)] = []

        var currentTitle = cardTitles.first ?? "Study Material"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Card: ") {
                currentTitle = String(trimmed.dropFirst(6))
            } else if trimmed.hasPrefix("Key Points: ") {
                let points = String(trimmed.dropFirst(12)).components(separatedBy: "; ")
                for point in points where !point.isEmpty {
                    keyPoints.append((currentTitle, point))
                }
            }
        }

        guard !keyPoints.isEmpty else { return [] }

        var questions: [QuizQuestion] = []
        let shuffled = keyPoints.shuffled()

        for (index, kp) in shuffled.prefix(min(count, shuffled.count)).enumerated() {
            // Create a "Which of these is a key point from [card]?" question
            var options = [kp.point]

            // Add distractors from other key points or generate simple ones
            let others = keyPoints.filter { $0.point != kp.point }.shuffled()
            for other in others.prefix(3) {
                options.append(other.point)
            }

            // Pad with generic distractors if needed
            let distractors = ["None of the above", "All of the above", "This is not covered in the material"]
            while options.count < 4 {
                options.append(distractors[options.count - 1])
            }

            // Shuffle and track correct answer
            let correctAnswer = options[0]
            options.shuffle()
            let correctIndex = options.firstIndex(of: correctAnswer) ?? 0

            questions.append(QuizQuestion(
                question: "Which of these is a key point from \"\(kp.title)\"?",
                options: options,
                correctAnswerIndex: correctIndex,
                sourceCardTitle: kp.title
            ))
        }

        return questions
    }
}
