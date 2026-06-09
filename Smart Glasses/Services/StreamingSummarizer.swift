//
//  StreamingSummarizer.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import Foundation
import Combine
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

/// Structured summary output for documents.
/// Marked `@Generable` so Foundation Models produces it directly via guided
/// generation — no string/JSON parsing required.
@Generable
struct DocumentSummaryOutput: Codable, Sendable {
    @Guide(description: "A concise 1-3 sentence summary of the document, written like college study notes.")
    var summary: String

    @Guide(description: "3 to 5 short key points capturing the most important information for learning the topic.")
    var keyPoints: [String]

    @Guide(description: "A short, descriptive title for the document based on its key points.")
    var suggestedTitle: String

    @Guide(description: "The document type, such as article, letter, receipt, manual, book page, or notes.")
    var documentType: String

    init(summary: String, keyPoints: [String], suggestedTitle: String, documentType: String) {
        self.summary = summary
        self.keyPoints = keyPoints
        self.suggestedTitle = suggestedTitle
        self.documentType = documentType
    }
}

/// Model-generated portion of a deck summary. `cardCount` is supplied by the
/// app (not the model), so it lives on `DeckSummaryOutput` rather than here.
@Generable
struct GeneratedDeckSummary {
    @Guide(description: "A comprehensive 3-5 sentence overview synthesizing the main content across all cards.")
    var summary: String

    @Guide(description: "4 to 6 key themes or important points that span multiple cards.")
    var keyThemes: [String]
}

#else

/// Structured summary output for documents
struct DocumentSummaryOutput: Codable, Sendable {
    var summary: String
    var keyPoints: [String]
    var suggestedTitle: String
    var documentType: String
}

#endif

/// Structured summary output for deck aggregation
struct DeckSummaryOutput: Codable, Sendable {
    /// Comprehensive summary of the entire deck
    var summary: String

    /// Key themes/points across all cards
    var keyThemes: [String]

    /// Number of cards summarized
    var cardCount: Int
}

/// Streaming summarizer using Apple Foundation Models
@MainActor
class StreamingSummarizer: ObservableObject {

    // MARK: - Published Properties

    /// Whether Foundation Models are available
    @Published var isAvailable: Bool = false

    /// Current streaming state
    @Published var state: SummarizerState = .idle

    /// Streaming summary text (updates as tokens arrive)
    @Published var streamingSummary: String = ""

    /// Streaming key points (updates as tokens arrive)
    @Published var streamingKeyPoints: [String] = []

    /// Suggested title from the model
    @Published var suggestedTitle: String = ""

    /// Document type classification
    @Published var documentType: String = ""

    /// Error message if any
    @Published var errorMessage: String?

    /// Progress (0-1) for visual feedback
    @Published var progress: Double = 0

    // MARK: - Provider Selection

    @AppStorage("selectedProvider") var selectedProvider: String = "apple"

    private lazy var openAIProvider = OpenAIProvider()

    // MARK: - Private Properties

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    private var currentTask: Task<Void, Never>?

    // MARK: - State Enum

    enum SummarizerState: Equatable {
        case idle
        case preparing
        case summarizing
        case complete
        case error
    }

    // MARK: - Initialization

    init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Public Methods

    /// Check if Foundation Models are available
    func checkAvailability() async {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability

        switch availability {
        case .available:
            isAvailable = true
            // Create session with instructions for document summarization
            session = LanguageModelSession(instructions: """
                You are a note taking assistant. Your job is to:
                1. Create a concise 1-3 sentence summary of the document text as if you were a college student
                2. Extract 3-5 key points as brief bullet points that would serve as good notes for learning the topic
                3. Suggest a short, descriptive title for this content based on the key points
                4. Classify the document type (e.g., article, letter, receipt, manual, book page, notes)

                Be concise and focus on the most important information.
                Use clear, simple language suitable for text-to-speech.
                """)
            print("[StreamingSummarizer] Foundation Models available")

        case .unavailable(let reason):
            isAvailable = false
            switch reason {
            case .deviceNotEligible:
                errorMessage = "Device does not support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                errorMessage = "Enable Apple Intelligence in Settings"
            case .modelNotReady:
                errorMessage = "Model downloading, try again later"
            @unknown default:
                errorMessage = "Foundation Models unavailable"
            }
            print("[StreamingSummarizer] Unavailable: \(errorMessage ?? "unknown")")

        @unknown default:
            isAvailable = false
        }
        #else
        isAvailable = false
        errorMessage = "Foundation Models requires iOS 26+"
        #endif
    }

    /// Summarize document text with streaming output
    /// - Parameter text: The OCR text to summarize
    /// - Returns: The final DocumentSummaryOutput
    func summarize(_ text: String) async -> DocumentSummaryOutput? {
        // Cancel any existing task
        currentTask?.cancel()

        // Reset state
        streamingSummary = ""
        streamingKeyPoints = []
        suggestedTitle = ""
        documentType = ""
        progress = 0
        errorMessage = nil
        state = .preparing

        // Route to OpenAI if selected and available
        if selectedProvider == "openai", await openAIProvider.isAvailable {
            return await summarizeWithOpenAI(text)
        }

        #if canImport(FoundationModels)
        guard isAvailable, let session = session else {
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackSummaryWithStreaming(from: text)
        }

        state = .summarizing

        let prompt = """
        Summarize the following document text:

        ---
        \(text)
        ---

        Provide:
        1. A concise summary as if taking notes in college (1-3 sentences)
        2. Key points that would be useful to learning the topic (3-5 bullet points)
        3. A suggested title
        4. The document type
        """

        do {
            // Guided generation: the model emits a DocumentSummaryOutput directly,
            // streaming partial snapshots whose fields fill in as tokens arrive.
            let stream = session.streamResponse(to: prompt, generating: DocumentSummaryOutput.self)

            for try await partial in stream {
                let snapshot = partial.content
                if let summary = snapshot.summary { streamingSummary = summary }
                if let keyPoints = snapshot.keyPoints { streamingKeyPoints = keyPoints }
                if let title = snapshot.suggestedTitle, !title.isEmpty { suggestedTitle = title }
                if let type = snapshot.documentType, !type.isEmpty { documentType = type }
                progress = min(0.9, progress + 0.05)
            }

            // Build the final value from streamed fields, with text-derived
            // fallbacks for anything the model left empty.
            let output = DocumentSummaryOutput(
                summary: streamingSummary.isEmpty ? createSimpleSummary(from: text) : streamingSummary,
                keyPoints: streamingKeyPoints.isEmpty ? extractKeyPoints(from: text) : streamingKeyPoints,
                suggestedTitle: suggestedTitle.isEmpty ? createTitle(from: text) : suggestedTitle,
                documentType: documentType.isEmpty ? "Document" : documentType
            )
            streamingSummary = output.summary
            streamingKeyPoints = output.keyPoints
            suggestedTitle = output.suggestedTitle
            documentType = output.documentType
            progress = 1.0
            state = .complete

            return output

        } catch {
            print("[StreamingSummarizer] Error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackSummaryWithStreaming(from: text)
        }
        #else
        // Fallback for non-iOS 26 devices - use typewriter effect
        return await createFallbackSummaryWithStreaming(from: text)
        #endif
    }

    /// Summarize using OpenAI provider
    private func summarizeWithOpenAI(_ text: String) async -> DocumentSummaryOutput? {
        state = .summarizing
        print("[StreamingSummarizer] Using OpenAI provider")

        do {
            let output = try await openAIProvider.summarize(text) { [weak self] partial in
                guard let self else { return }
                Task { @MainActor in
                    self.streamingSummary = partial
                    self.progress = min(0.9, self.progress + 0.02)
                }
            }

            streamingSummary = output.summary
            streamingKeyPoints = output.keyPoints
            suggestedTitle = output.suggestedTitle
            documentType = output.documentType
            progress = 1.0
            state = .complete
            return output

        } catch {
            print("[StreamingSummarizer] OpenAI error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackSummaryWithStreaming(from: text)
        }
    }

    /// Create fallback summary with typewriter streaming effect
    private func createFallbackSummaryWithStreaming(from text: String) async -> DocumentSummaryOutput {
        state = .summarizing

        let output = createFallbackSummary(from: text)

        // Stream the title first
        await streamText(output.suggestedTitle) { partial in
            self.suggestedTitle = partial
        }

        // Stream document type
        documentType = output.documentType
        progress = 0.2

        // Stream the summary with typewriter effect
        await streamText(output.summary) { partial in
            self.streamingSummary = partial
            self.progress = 0.2 + (Double(partial.count) / Double(output.summary.count)) * 0.5
        }

        // Stream key points one by one
        for (index, point) in output.keyPoints.enumerated() {
            var currentPoints = streamingKeyPoints
            currentPoints.append("")
            streamingKeyPoints = currentPoints

            await streamText(point) { partial in
                var points = self.streamingKeyPoints
                points[index] = partial
                self.streamingKeyPoints = points
            }

            progress = 0.7 + (Double(index + 1) / Double(output.keyPoints.count)) * 0.3
        }

        progress = 1.0
        state = .complete

        return output
    }

    /// Stream text with typewriter effect
    private func streamText(_ text: String, update: @escaping (String) -> Void) async {
        var current = ""
        let words = text.split(separator: " ")

        for word in words {
            current += (current.isEmpty ? "" : " ") + word
            update(current)
            // Small delay between words for typing effect
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms per word
        }
    }

    /// Maximum number of cards to summarize in a single prompt to stay within token limits
    private let maxCardsPerBatch = 4

    /// Summarize an entire deck by aggregating card content.
    /// For decks with more cards than `maxCardsPerBatch`, uses a chunked map-reduce
    /// approach: summarize batches of cards, then summarize the batch summaries.
    /// - Parameters:
    ///   - cardSummaries: Combined summaries from all cards
    ///   - cardCount: Number of cards in the deck
    ///   - deckTitle: Title of the deck for context
    /// - Returns: The DeckSummaryOutput with aggregated summary
    func summarizeDeck(cardSummaries: String, cardCount: Int, deckTitle: String) async -> DeckSummaryOutput? {
        // Cancel any existing task
        currentTask?.cancel()

        // Reset state
        streamingSummary = ""
        streamingKeyPoints = []
        progress = 0
        errorMessage = nil
        state = .preparing

        // Route to OpenAI if selected and available
        if selectedProvider == "openai", await openAIProvider.isAvailable {
            return await summarizeDeckWithOpenAI(cardSummaries: cardSummaries, cardCount: cardCount, deckTitle: deckTitle)
        }

        #if canImport(FoundationModels)
        guard isAvailable else {
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }

        // Split card summaries into individual cards
        let cardChunks = splitCardSummaries(cardSummaries)

        if cardChunks.count > maxCardsPerBatch {
            return await summarizeDeckChunked(cardChunks: cardChunks, cardCount: cardCount, deckTitle: deckTitle)
        } else {
            return await summarizeDeckDirect(cardSummaries: cardSummaries, cardCount: cardCount, deckTitle: deckTitle)
        }
        #else
        return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        #endif
    }

    #if canImport(FoundationModels)
    /// Direct single-pass summarization for small decks
    private func summarizeDeckDirect(cardSummaries: String, cardCount: Int, deckTitle: String) async -> DeckSummaryOutput? {
        // Create a fresh session for this summarization
        let deckSession = LanguageModelSession(instructions: """
            You are a note taking assistant that creates deck summaries from study cards.
            Be concise and focus on synthesizing key themes across cards.
            Use clear language suitable for text-to-speech.
            """)

        state = .summarizing

        let prompt = """
        You are summarizing a study deck titled "\(deckTitle)" containing \(cardCount) cards.

        Here are the summaries from each card:

        ---
        \(cardSummaries)
        ---

        Create a comprehensive deck summary that:
        1. Provides a cohesive overview (3-5 sentences) that synthesizes the main content across all cards
        2. Identifies 4-6 key themes or important points that span multiple cards
        3. Highlights connections between different cards when relevant

        Focus on creating a unified summary that helps the reader understand the complete content.
        Use clear language suitable for text-to-speech.
        """

        do {
            let stream = deckSession.streamResponse(to: prompt, generating: GeneratedDeckSummary.self)

            for try await partial in stream {
                let snapshot = partial.content
                if let summary = snapshot.summary { streamingSummary = summary }
                if let themes = snapshot.keyThemes { streamingKeyPoints = themes }
                progress = min(0.9, progress + 0.03)
            }

            let output = DeckSummaryOutput(
                summary: streamingSummary.isEmpty
                    ? "This deck contains \(cardCount) cards with study material."
                    : streamingSummary,
                keyThemes: streamingKeyPoints,
                cardCount: cardCount
            )
            streamingSummary = output.summary
            streamingKeyPoints = output.keyThemes
            progress = 1.0
            state = .complete
            return output

        } catch {
            print("[StreamingSummarizer] Deck summary error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }
    }

    /// Chunked map-reduce summarization for large decks.
    /// Summarizes batches of cards separately, then combines batch summaries into a final summary.
    private func summarizeDeckChunked(cardChunks: [String], cardCount: Int, deckTitle: String) async -> DeckSummaryOutput? {
        state = .summarizing
        streamingSummary = "Summarizing cards in batches..."

        // Step 1: Split into batches
        var batches: [[String]] = []
        for i in stride(from: 0, to: cardChunks.count, by: maxCardsPerBatch) {
            let end = min(i + maxCardsPerBatch, cardChunks.count)
            batches.append(Array(cardChunks[i..<end]))
        }

        let totalBatches = batches.count
        var batchSummaries: [String] = []

        // Step 2: Summarize each batch with a fresh session
        for (batchIndex, batch) in batches.enumerated() {
            let batchSession = LanguageModelSession(instructions: """
                You are a note taking assistant. Summarize the following study cards concisely.
                Focus on the most important points. Use clear, simple language.
                """)

            let batchText = batch.joined(separator: "\n\n")
            let batchPrompt = """
            Summarize these \(batch.count) study cards from the deck "\(deckTitle)" into a brief paragraph and list of key points:

            ---
            \(batchText)
            ---

            Provide:
            1. A brief summary (2-3 sentences)
            2. Key points (2-3 bullet points)
            """

            streamingSummary = "Summarizing batch \(batchIndex + 1) of \(totalBatches)..."
            progress = Double(batchIndex) / Double(totalBatches + 1) * 0.7

            do {
                let response = try await batchSession.respond(to: batchPrompt)
                batchSummaries.append(response.content)
                print("[StreamingSummarizer] Batch \(batchIndex + 1)/\(totalBatches) complete")
            } catch {
                print("[StreamingSummarizer] Batch \(batchIndex + 1) error: \(error)")
                // Use the raw card text as fallback for this batch
                batchSummaries.append(batchText)
            }
        }

        // Step 3: Final summary from batch summaries with a fresh session
        let finalSession = LanguageModelSession(instructions: """
            You are a note taking assistant that creates deck summaries from study cards.
            Be concise and focus on synthesizing key themes.
            Use clear language suitable for text-to-speech.
            """)

        let combinedBatchSummaries = batchSummaries.enumerated()
            .map { "Batch \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")

        let finalPrompt = """
        You are creating a final summary for a study deck titled "\(deckTitle)" with \(cardCount) cards.

        Here are summaries from different sections of the deck:

        ---
        \(combinedBatchSummaries)
        ---

        Create a comprehensive deck summary that:
        1. Provides a cohesive overview (3-5 sentences) synthesizing all sections
        2. Identifies 4-6 key themes or important points across the entire deck
        3. Highlights connections between different sections

        Focus on creating a unified summary. Use clear language suitable for text-to-speech.
        """

        streamingSummary = "Creating final deck summary..."
        progress = 0.75

        do {
            let stream = finalSession.streamResponse(to: finalPrompt, generating: GeneratedDeckSummary.self)

            for try await partial in stream {
                let snapshot = partial.content
                if let summary = snapshot.summary { streamingSummary = summary }
                if let themes = snapshot.keyThemes { streamingKeyPoints = themes }
                progress = 0.75 + min(0.24, (progress - 0.75) + 0.03)
            }

            let output = DeckSummaryOutput(
                summary: streamingSummary.isEmpty
                    ? "This deck contains \(cardCount) cards with study material."
                    : streamingSummary,
                keyThemes: streamingKeyPoints,
                cardCount: cardCount
            )
            streamingSummary = output.summary
            streamingKeyPoints = output.keyThemes
            progress = 1.0
            state = .complete
            return output

        } catch {
            print("[StreamingSummarizer] Final deck summary error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackDeckSummary(from: combinedBatchSummaries, cardCount: cardCount)
        }
    }

    /// Split combined card summaries string into individual card chunks
    private func splitCardSummaries(_ combined: String) -> [String] {
        // Split on the "Card N - " pattern used by combinedCardSummaries
        let chunks = combined.components(separatedBy: "\n\n")
            .reduce(into: [String]()) { result, part in
                if part.hasPrefix("Card ") {
                    result.append(part)
                } else if var last = result.last {
                    last += "\n\n" + part
                    result[result.count - 1] = last
                } else {
                    result.append(part)
                }
            }
        return chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    #endif

    /// Summarize deck using OpenAI provider
    private func summarizeDeckWithOpenAI(cardSummaries: String, cardCount: Int, deckTitle: String) async -> DeckSummaryOutput? {
        state = .summarizing
        print("[StreamingSummarizer] Using OpenAI for deck summary")

        do {
            let output = try await openAIProvider.summarizeDeck(
                cardSummaries: cardSummaries,
                cardCount: cardCount,
                deckTitle: deckTitle
            ) { [weak self] partial in
                guard let self else { return }
                Task { @MainActor in
                    self.streamingSummary = partial
                    self.progress = min(0.9, self.progress + 0.02)
                }
            }

            streamingSummary = output.summary
            streamingKeyPoints = output.keyThemes
            progress = 1.0
            state = .complete
            return output

        } catch {
            print("[StreamingSummarizer] OpenAI deck summary error: \(error)")
            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }
    }

    /// Create fallback deck summary
    private func createFallbackDeckSummary(from cardSummaries: String, cardCount: Int) async -> DeckSummaryOutput {
        state = .summarizing

        // Extract first few sentences as summary
        let sentences = cardSummaries.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }

        let summary = sentences.prefix(3).joined(separator: ". ") + "."

        // Extract key points from different cards
        let themes = sentences.prefix(5).map { sentence in
            if sentence.count > 100 {
                return String(sentence.prefix(100)) + "..."
            }
            return sentence
        }

        // Stream with typewriter effect
        await streamText(summary) { partial in
            self.streamingSummary = partial
            self.progress = Double(partial.count) / Double(summary.count) * 0.7
        }

        for (index, theme) in themes.enumerated() {
            var currentThemes = streamingKeyPoints
            currentThemes.append("")
            streamingKeyPoints = currentThemes

            await streamText(theme) { partial in
                var points = self.streamingKeyPoints
                points[index] = partial
                self.streamingKeyPoints = points
            }
            progress = 0.7 + (Double(index + 1) / Double(themes.count)) * 0.3
        }

        progress = 1.0
        state = .complete

        return DeckSummaryOutput(
            summary: summary,
            keyThemes: Array(themes),
            cardCount: cardCount
        )
    }

    /// Cancel current summarization
    func cancel() {
        currentTask?.cancel()
        state = .idle
        progress = 0
    }

    /// Reset the summarizer state
    func reset() {
        cancel()
        streamingSummary = ""
        streamingKeyPoints = []
        suggestedTitle = ""
        documentType = ""
        errorMessage = nil
    }

    // MARK: - Private Methods

    /// Create a fallback summary when Foundation Models unavailable
    private func createFallbackSummary(from text: String) -> DocumentSummaryOutput {
        DocumentSummaryOutput(
            summary: createSimpleSummary(from: text),
            keyPoints: extractKeyPoints(from: text),
            suggestedTitle: createTitle(from: text),
            documentType: "Document"
        )
    }

    /// Create a simple summary by extracting first sentences
    private func createSimpleSummary(from text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let firstSentences = sentences.prefix(2).joined(separator: ". ")
        if firstSentences.count > 200 {
            return String(firstSentences.prefix(200)) + "..."
        }
        return firstSentences + (firstSentences.isEmpty ? "" : ".")
    }

    /// Extract key points from text
    private func extractKeyPoints(from text: String) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }

        return Array(sentences.prefix(4)).map { sentence in
            if sentence.count > 80 {
                return String(sentence.prefix(80)) + "..."
            }
            return sentence
        }
    }

    /// Create a title from the text
    private func createTitle(from text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        let titleWords = words.prefix(5).joined(separator: " ")
        if titleWords.count > 40 {
            return String(titleWords.prefix(40)) + "..."
        }
        return titleWords.isEmpty ? "Untitled" : titleWords
    }
}
