//
//  StreamingSummarizer.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import Foundation
import Combine
import SwiftUI
import UIKit

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

    @Guide(description: "Plain-prose description of any diagram, chart, table, equation or figure on the page — what it shows and what it means. Empty string if the page is text only.")
    var visualDescription: String

    init(
        summary: String,
        keyPoints: [String],
        suggestedTitle: String,
        documentType: String,
        visualDescription: String = ""
    ) {
        self.summary = summary
        self.keyPoints = keyPoints
        self.suggestedTitle = suggestedTitle
        self.documentType = documentType
        self.visualDescription = visualDescription
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
    var visualDescription: String = ""
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

    /// Description of diagrams/figures on the page (empty for text-only pages,
    /// and always empty when summarizing without a page image)
    @Published var streamingVisualDescription: String = ""

    /// Error message if any
    @Published var errorMessage: String?

    /// Progress (0-1) for visual feedback
    @Published var progress: Double = 0

    // MARK: - Provider Selection

    @AppStorage("selectedProvider") var selectedProvider: String = "apple"

    /// Whether to attach the page image to the summarization prompt when one is
    /// available. Only affects the Apple on-device path; OpenAI stays text-only.
    @AppStorage("useVisionSummarization") var useVisionSummarization: Bool = true

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

    enum SummarizerError: Error {
        case sessionUnavailable
    }

    // MARK: - Instructions

    /// Shared by the on-device session and any Private Cloud Compute session, so
    /// a summary reads the same whichever tier produced it.
    static let documentInstructions = """
        You are a note taking assistant. Your job is to:
        1. Create a concise 1-3 sentence summary of the document text as if you were a college student
        2. Extract 3-5 key points as brief bullet points that would serve as good notes for learning the topic
        3. Suggest a short, descriptive title for this content based on the key points
        4. Classify the document type (e.g., article, letter, receipt, manual, book page, notes)
        5. When you are given an image of the page, describe any diagram, chart,
           table, equation or figure on it. Leave that description empty for
           text-only pages and whenever no image is provided.

        Be concise and focus on the most important information.
        Use clear, simple language suitable for text-to-speech.
        """

    static let deckInstructions = """
        You are a note taking assistant that creates deck summaries from study cards.
        Be concise and focus on synthesizing key themes across cards.
        Use clear language suitable for text-to-speech.
        """

    /// Tier to use for text-only work, honoring the user's provider choice and
    /// silently degrading to on-device when PCC is selected but unusable.
    var preferredTextTier: AppleModelTier {
        AppleModelProvider.textTier(for: selectedProvider)
    }

    /// What is actually generating the current summary.
    ///
    /// Deliberately not the same as `selectedProvider`, because the selection is
    /// not always honored: a page image is forced on-device even when Apple
    /// Cloud is chosen, a failed PCC round trip retries locally, and OpenAI is
    /// skipped when it has no API key. Progress text reads this so it reports
    /// what ran rather than what was asked for.
    @Published private(set) var activeProvider: SummarizationProvider = .onDevice

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
            session = LanguageModelSession(instructions: Self.documentInstructions)
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
    /// - Parameters:
    ///   - text: The OCR text to summarize
    ///   - pageImage: The scanned page itself. When supplied on iOS 27+, it is
    ///     attached to the prompt so the model can read the page directly —
    ///     repairing OCR errors and describing diagrams the text pipeline drops.
    ///     Pass `DocumentReadingResult.visionImage`, not `correctedImage`.
    ///   - mode: What was captured. Selects the prompt — a whiteboard is read
    ///     spatially, a page in reading order.
    /// - Returns: The final DocumentSummaryOutput
    func summarize(
        _ text: String,
        pageImage: UIImage? = nil,
        mode: CaptureMode = .document
    ) async -> DocumentSummaryOutput? {
        // Cancel any existing task
        currentTask?.cancel()

        // Reset state
        streamingSummary = ""
        streamingKeyPoints = []
        suggestedTitle = ""
        documentType = ""
        streamingVisualDescription = ""
        progress = 0
        errorMessage = nil
        state = .preparing

        // Route to OpenAI if selected and available
        if selectedProvider == "openai", await openAIProvider.isAvailable {
            activeProvider = .openAI
            return await summarizeWithOpenAI(text)
        }

        // Anything past here runs on an Apple model, even if OpenAI was selected
        // but unusable.
        activeProvider = preferredTextTier.provider

        #if canImport(FoundationModels)
        guard isAvailable else {
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackSummaryWithStreaming(from: text)
        }

        state = .summarizing

        // Prepare the page image for attachment. Skipped entirely on iOS 26,
        // where the attachment API does not exist.
        var visionCGImage: CGImage?
        if useVisionSummarization, PageVisionPrompt.isVisionSupported, let pageImage {
            visionCGImage = PageVisionImage.prepare(pageImage)
            if visionCGImage == nil {
                print("[StreamingSummarizer] Page image preparation failed; using text-only prompt")
            }
        }

        // Privacy boundary: scanned pages are read on-device only. A page image
        // never goes to Private Cloud Compute, so a capture with an attachment
        // stays local regardless of the selected provider. PCC is the big-context
        // tier for text, not a general replacement for the local model.
        let tier: AppleModelTier = visionCGImage != nil ? .onDevice : preferredTextTier
        activeProvider = tier.provider

        do {
            return try await runDocumentSummarization(
                text: text,
                visionCGImage: visionCGImage,
                tier: tier,
                mode: mode
            )
        } catch {
            // A PCC round trip can fail for reasons that have nothing to do with
            // the content — offline, quota, service blip. Retry locally before
            // giving the user an error mid-scan.
            if tier == .privateCloudCompute, AppleModelProvider.isRecoverablePCCError(error) {
                print("[StreamingSummarizer] Private Cloud Compute failed (\(error)); retrying on-device")
                activeProvider = .onDevice
                clearStreamedFields()
                if let output = try? await runDocumentSummarization(
                    text: text,
                    visionCGImage: visionCGImage,
                    tier: .onDevice,
                    mode: mode
                ) {
                    return output
                }
            }

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

    #if canImport(FoundationModels)

    /// One summarization pass on a specific tier.
    ///
    /// Throws rather than falling back internally so the caller can decide
    /// whether the failure is worth retrying somewhere else.
    private func runDocumentSummarization(
        text: String,
        visionCGImage: CGImage?,
        tier: AppleModelTier,
        mode: CaptureMode = .document
    ) async throws -> DocumentSummaryOutput {
        guard let session = documentSession(for: tier) else {
            throw SummarizerError.sessionUnavailable
        }

        // Guided generation: the model emits a DocumentSummaryOutput directly,
        // streaming partial snapshots whose fields fill in as tokens arrive.
        let stream: LanguageModelSession.ResponseStream<DocumentSummaryOutput>

        if let visionCGImage {
            // Text + image. The model reads the capture itself, so the OCR text
            // becomes a hint it can overrule rather than the sole input.
            print("[StreamingSummarizer] Summarizing on-device with \(mode.rawValue) image attached")
            let header = mode == .whiteboard
                ? PageVisionPrompt.whiteboardHeader
                : PageVisionPrompt.visionHeader
            let body = mode == .whiteboard
                ? PageVisionPrompt.whiteboardBody(documentText: text)
                : PageVisionPrompt.visionBody(documentText: text)

            stream = session.streamResponse(generating: DocumentSummaryOutput.self) {
                header
                Attachment(visionCGImage)
                body
            }
        } else {
            print("[StreamingSummarizer] Summarizing text-only via \(tier == .privateCloudCompute ? "Private Cloud Compute" : "on-device model")")
            // No reasoning here: condensing one page is a summarization task, and
            // the extra latency does not buy better notes. Deck synthesis and quiz
            // generation are where reasoning earns its cost.
            stream = AppleModelProvider.streamResponse(
                session: session,
                to: PageVisionPrompt.textOnly(documentText: text),
                generating: DocumentSummaryOutput.self
            )
        }

        for try await partial in stream {
            let snapshot = partial.content
            if let summary = snapshot.summary { streamingSummary = summary }
            if let keyPoints = snapshot.keyPoints { streamingKeyPoints = keyPoints }
            if let title = snapshot.suggestedTitle, !title.isEmpty { suggestedTitle = title }
            if let type = snapshot.documentType, !type.isEmpty { documentType = type }
            if let visual = snapshot.visualDescription { streamingVisualDescription = visual }
            progress = min(0.9, progress + 0.05)
        }

        // Build the final value from streamed fields, with text-derived
        // fallbacks for anything the model left empty.
        let output = DocumentSummaryOutput(
            summary: streamingSummary.isEmpty ? createSimpleSummary(from: text) : streamingSummary,
            keyPoints: streamingKeyPoints.isEmpty ? extractKeyPoints(from: text) : streamingKeyPoints,
            suggestedTitle: suggestedTitle.isEmpty ? createTitle(from: text) : suggestedTitle,
            documentType: documentType.isEmpty ? "Document" : documentType,
            // Trimmed because the model emits whitespace for a text-only page,
            // which would otherwise read as "has a figure" downstream.
            visualDescription: streamingVisualDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        streamingSummary = output.summary
        streamingKeyPoints = output.keyPoints
        suggestedTitle = output.suggestedTitle
        documentType = output.documentType
        streamingVisualDescription = output.visualDescription
        progress = 1.0
        state = .complete

        return output
    }

    /// The session to summarize a document with. On-device reuses the long-lived
    /// session built in `checkAvailability()`; PCC sessions are made per request.
    private func documentSession(for tier: AppleModelTier) -> LanguageModelSession? {
        guard tier == .privateCloudCompute else { return session }
        return AppleModelProvider.makeSession(
            tier: .privateCloudCompute,
            instructions: Self.documentInstructions
        )
    }

    #endif

    /// Reset the streamed fields between retries so a partial response from a
    /// failed attempt cannot leak into the next one.
    private func clearStreamedFields() {
        streamingSummary = ""
        streamingKeyPoints = []
        suggestedTitle = ""
        documentType = ""
        streamingVisualDescription = ""
        progress = 0
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

    /// Summarize an entire deck by aggregating card content.
    /// Uses a single pass when the deck fits the model's measured context budget,
    /// and otherwise falls back to chunked map-reduce: summarize batches of cards,
    /// then summarize the batch summaries.
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
            activeProvider = .openAI
            return await summarizeDeckWithOpenAI(cardSummaries: cardSummaries, cardCount: cardCount, deckTitle: deckTitle)
        }

        activeProvider = preferredTextTier.provider

        #if canImport(FoundationModels)
        guard isAvailable else {
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }

        // Split card summaries into individual cards
        let cardChunks = splitCardSummaries(cardSummaries)

        // Private Cloud Compute's context window is large enough that a deck
        // which needs map-reduce on-device fits in a single pass. That is worth
        // more than the convenience: chunking summarizes summaries, so a theme
        // spanning two batches is structurally invisible to the final pass.
        // One pass with deep reasoning can actually find it.
        if preferredTextTier == .privateCloudCompute {
            if let output = await summarizeDeckDirect(
                cardSummaries: cardSummaries,
                cardCount: cardCount,
                deckTitle: deckTitle,
                tier: .privateCloudCompute
            ) {
                return output
            }
            print("[StreamingSummarizer] Private Cloud Compute deck summary failed; falling back on-device")
            activeProvider = .onDevice
            clearStreamedFields()
        }

        // Measure rather than guess. The old rule was "more than 4 cards means
        // chunk", which wasted context on short cards and overflowed on long ones.
        let budget = await TokenBudget.makeBudget(
            instructions: Self.deckInstructions,
            schemaFor: GeneratedDeckSummary.self
        )
        let deckTokens = await TokenBudget.measure(cardSummaries)

        if deckTokens <= budget.availableForContent {
            print("[StreamingSummarizer] Deck fits one pass: \(deckTokens)/\(budget.availableForContent) tokens")
            if let output = await summarizeDeckDirect(
                cardSummaries: cardSummaries,
                cardCount: cardCount,
                deckTitle: deckTitle,
                tier: .onDevice
            ) {
                return output
            }
            // Measurement said it would fit but the model disagreed. Fall through
            // to chunking rather than failing.
            print("[StreamingSummarizer] One-pass deck summary overflowed; chunking instead")
            clearStreamedFields()
        }

        let batches = await TokenBudget.pack(cardChunks, into: budget)
        print("[StreamingSummarizer] Chunking \(cardChunks.count) cards into \(batches.count) batches")
        return await summarizeDeckChunked(batches: batches, cardCount: cardCount, deckTitle: deckTitle)
        #else
        return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        #endif
    }

    #if canImport(FoundationModels)
    /// Single-pass deck summarization.
    ///
    /// - Parameter tier: which model to run on. On `.privateCloudCompute` this
    ///   returns `nil` for recoverable failures instead of falling back
    ///   internally, so the caller can retry the chunked on-device path.
    private func summarizeDeckDirect(
        cardSummaries: String,
        cardCount: Int,
        deckTitle: String,
        tier: AppleModelTier
    ) async -> DeckSummaryOutput? {
        // Fresh session per summarization — deck summaries are one-shot and
        // should not inherit transcript history from an earlier card.
        guard let deckSession = AppleModelProvider.makeSession(
            tier: tier,
            instructions: Self.deckInstructions
        ) else {
            guard tier != .privateCloudCompute else { return nil }
            state = .error
            errorMessage = "Foundation Models not available"
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }

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
            // Synthesizing themes across cards is the one summarization step that
            // is genuinely a reasoning problem, so spend the extra compute here
            // when we are on PCC. The on-device model ignores the request.
            let stream = AppleModelProvider.streamResponse(
                session: deckSession,
                to: Prompt(prompt),
                generating: GeneratedDeckSummary.self,
                reasoning: tier == .privateCloudCompute
            )

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

            // Let the caller retry on-device rather than burning the attempt on
            // a fallback summary that ignores the deck entirely.
            if tier == .privateCloudCompute, AppleModelProvider.isRecoverablePCCError(error) {
                return nil
            }

            // Safety net behind the token measurement: if the content did not fit
            // after all, the caller can still chunk it.
            if AppleModelProvider.isContextSizeExceeded(error) {
                return nil
            }

            state = .error
            errorMessage = error.localizedDescription
            return await createFallbackDeckSummary(from: cardSummaries, cardCount: cardCount)
        }
    }

    /// Chunked map-reduce summarization for decks that exceed the context budget.
    /// Summarizes batches of cards separately, then combines batch summaries into a final summary.
    ///
    /// - Parameter batches: cards already grouped to fit the budget by
    ///   `TokenBudget.pack(_:into:)`. Grouping happens in the caller so the same
    ///   measurement decides both whether to chunk and how big each batch is.
    private func summarizeDeckChunked(batches: [[String]], cardCount: Int, deckTitle: String) async -> DeckSummaryOutput? {
        state = .summarizing
        streamingSummary = "Summarizing cards in batches..."

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
        let finalSession = LanguageModelSession(instructions: Self.deckInstructions)

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
        streamingVisualDescription = ""
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
