//
//  OpenAIProvider.swift
//  Smart Glasses
//
//  OpenAI API client for cloud-based LLM summarization
//

import Foundation
import SwiftUI

/// OpenAI API provider implementing the LLMProvider protocol
class OpenAIProvider: LLMProvider {

    let name = "OpenAI"

    private let baseURL = "https://api.openai.com/v1"
    @AppStorage("openAIModel") private var selectedModel = "gpt-4o-mini"

    // MARK: - API Request/Response Models

    struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: ResponseMessage
        }

        struct ResponseMessage: Decodable {
            let content: String?
        }
    }

    struct StreamChunk: Decodable {
        let choices: [StreamChoice]

        struct StreamChoice: Decodable {
            let delta: Delta
            let finish_reason: String?
        }

        struct Delta: Decodable {
            let content: String?
        }
    }

    struct ModelListResponse: Decodable {
        let data: [Model]

        struct Model: Decodable, Identifiable {
            let id: String
            let owned_by: String
        }
    }

    // MARK: - Availability

    var isAvailable: Bool {
        get async {
            guard let apiKey = KeychainHelper.loadString(key: "openai_api_key"),
                  !apiKey.isEmpty else {
                return false
            }
            return true
        }
    }

    // MARK: - Model Fetching

    /// Fetch available models from the OpenAI API
    func fetchAvailableModels() async throws -> [String] {
        guard let apiKey = KeychainHelper.loadString(key: "openai_api_key") else {
            throw OpenAIError.noAPIKey
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OpenAIError.apiError("Failed to fetch models")
        }

        let modelList = try JSONDecoder().decode(ModelListResponse.self, from: data)

        // Filter to chat completion models
        let chatModels = modelList.data
            .map(\.id)
            .filter { id in
                id.hasPrefix("gpt-4") || id.hasPrefix("gpt-3.5") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4")
            }
            .sorted()

        return chatModels
    }

    /// Test the API connection with a simple request
    func testConnection() async throws -> Bool {
        guard let apiKey = KeychainHelper.loadString(key: "openai_api_key") else {
            throw OpenAIError.noAPIKey
        }

        let chatRequest = ChatRequest(
            model: selectedModel,
            messages: [
                ChatRequest.Message(role: "user", content: "Say 'ok'")
            ],
            stream: false,
            temperature: 0
        )

        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.apiError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw OpenAIError.invalidAPIKey
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - LLMProvider Conformance

    func summarize(_ text: String, streaming: ((String) -> Void)?) async throws -> DocumentSummaryOutput {
        let systemPrompt = """
        You are a note taking assistant. Your job is to:
        1. Create a concise 1-3 sentence summary of the document text as if you were a college student
        2. Extract 3-5 key points as brief bullet points that would serve as good notes for learning the topic
        3. Suggest a short, descriptive title for this content based on the key points
        4. Classify the document type (e.g., article, letter, receipt, manual, book page, notes)

        Be concise and focus on the most important information.
        Use clear, simple language suitable for text-to-speech.

        Format your response exactly like this:
        Summary: <your summary>
        Key Points:
        - <point 1>
        - <point 2>
        - <point 3>
        Title: <suggested title>
        Type: <document type>
        """

        let userPrompt = """
        Summarize the following document text:

        ---
        \(text)
        ---
        """

        let fullResponse = try await sendChatRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            streaming: streaming
        )

        return parseDocumentResponse(fullResponse, originalText: text)
    }

    func summarizeDeck(cardSummaries: String, cardCount: Int, deckTitle: String, streaming: ((String) -> Void)?) async throws -> DeckSummaryOutput {
        let systemPrompt = """
        You are a note taking assistant that creates deck summaries from study cards.
        Be concise and focus on synthesizing key themes across cards.
        Use clear language suitable for text-to-speech.

        Format your response exactly like this:
        Overview: <your 3-5 sentence overview>
        Key Themes:
        - <theme 1>
        - <theme 2>
        - <theme 3>
        """

        let userPrompt = """
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
        """

        let fullResponse = try await sendChatRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            streaming: streaming
        )

        return parseDeckResponse(fullResponse, cardCount: cardCount)
    }

    // MARK: - Private Methods

    private func sendChatRequest(systemPrompt: String, userPrompt: String, streaming: ((String) -> Void)?) async throws -> String {
        guard let apiKey = KeychainHelper.loadString(key: "openai_api_key") else {
            throw OpenAIError.noAPIKey
        }

        let useStreaming = streaming != nil

        let chatRequest = ChatRequest(
            model: selectedModel,
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt),
                ChatRequest.Message(role: "user", content: userPrompt)
            ],
            stream: useStreaming,
            temperature: 0.3
        )

        var request = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(chatRequest)

        if useStreaming {
            return try await sendStreamingRequest(request: request, streaming: streaming!)
        } else {
            return try await sendNonStreamingRequest(request: request)
        }
    }

    private func sendNonStreamingRequest(request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.apiError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw OpenAIError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? ""
    }

    private func sendStreamingRequest(request: URLRequest, streaming: @escaping (String) -> Void) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.apiError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw OpenAIError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        var fullContent = ""

        for try await line in bytes.lines {
            // SSE format: lines starting with "data: "
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))

            if jsonString == "[DONE]" { break }

            guard let jsonData = jsonString.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
                if let content = chunk.choices.first?.delta.content {
                    fullContent += content
                    await MainActor.run {
                        streaming(fullContent)
                    }
                }
            } catch {
                // Skip malformed chunks
                continue
            }
        }

        return fullContent
    }

    // MARK: - Text-to-Speech

    /// Synthesize speech from text using OpenAI's TTS API
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use (e.g., "nova", "alloy", "echo")
    /// - Returns: MP3 audio data
    func synthesizeSpeech(text: String, voice: String) async throws -> Data {
        guard let apiKey = KeychainHelper.loadString(key: "openai_api_key") else {
            throw OpenAIError.noAPIKey
        }

        struct TTSRequest: Encodable {
            let model: String
            let voice: String
            let input: String
        }

        let ttsRequest = TTSRequest(model: "tts-1", voice: voice, input: text)

        var request = URLRequest(url: URL(string: "\(baseURL)/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ttsRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.apiError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw OpenAIError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenAIError.apiError("TTS HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        return data
    }

    // MARK: - Quiz Question Generation

    func generateQuestions(from text: String, cardTitles: [String], count: Int) async throws -> [QuizQuestion] {
        let systemPrompt = """
        You are a quiz generator for study material. Generate multiple-choice questions to test understanding.
        Each question must have exactly 4 options with 1 correct answer.
        Questions should test comprehension, not just recall.

        Respond with ONLY a JSON array, no other text:
        [{"question": "...", "options": ["A", "B", "C", "D"], "correctIndex": 2, "sourceCard": "card title"}]

        Rules:
        - correctIndex is 0-3 indicating which option is correct
        - IMPORTANT: Randomize the position of the correct answer. Do NOT always put it first. Distribute correctIndex evenly across 0, 1, 2, and 3.
        - sourceCard should match the most relevant card title from the provided list
        - Make wrong answers plausible but clearly incorrect
        - Vary question types: definitions, comparisons, applications
        """

        let cardTitleList = cardTitles.joined(separator: ", ")
        let userPrompt = """
        Generate \(count) multiple-choice questions from this study material.
        Card titles: \(cardTitleList)

        Study material:
        ---
        \(text)
        ---
        """

        let fullResponse = try await sendChatRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            streaming: nil
        )

        return parseQuizResponse(fullResponse, fallbackTitles: cardTitles)
    }

    private func parseQuizResponse(_ content: String, fallbackTitles: [String]) -> [QuizQuestion] {
        // Extract JSON array from response (handle markdown code blocks)
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let startRange = jsonString.range(of: "["),
           let endRange = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[startRange.lowerBound..<endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct RawQuestion: Decodable {
            let question: String
            let options: [String]
            let correctIndex: Int
            let sourceCard: String?
        }

        do {
            let rawQuestions = try JSONDecoder().decode([RawQuestion].self, from: data)
            return rawQuestions.compactMap { raw in
                guard raw.options.count == 4,
                      raw.correctIndex >= 0,
                      raw.correctIndex < 4 else { return nil }

                // Shuffle options to guarantee randomized answer positions
                let correctAnswer = raw.options[raw.correctIndex]
                var shuffledOptions = raw.options
                shuffledOptions.shuffle()
                let newCorrectIndex = shuffledOptions.firstIndex(of: correctAnswer) ?? 0

                return QuizQuestion(
                    question: raw.question,
                    options: shuffledOptions,
                    correctAnswerIndex: newCorrectIndex,
                    sourceCardTitle: raw.sourceCard ?? fallbackTitles.first ?? "Unknown"
                )
            }
        } catch {
            print("[OpenAIProvider] Quiz JSON parse error: \(error)")
            return []
        }
    }

    // MARK: - Flashcard Generation

    func generateFlashcards(from text: String, cardTitles: [String], count: Int) async throws -> [Flashcard] {
        let systemPrompt = """
        You are a flashcard generator for study material. Generate flashcards with a term/question on the front and answer/explanation on the back.
        Each flashcard should test one concept clearly.

        Respond with ONLY a JSON array, no other text:
        [{"front": "Question or term", "back": "Answer or explanation", "sourceCard": "card title", "category": "optional category"}]

        Rules:
        - Keep front side concise (question or term)
        - Back side should have complete but brief explanation
        - Cover the most important concepts
        - Vary between definitions, concepts, and applications
        - sourceCard should match the most relevant card title from the provided list
        """

        let cardTitleList = cardTitles.joined(separator: ", ")
        let userPrompt = """
        Generate \(count) flashcards from this study material.
        Card titles: \(cardTitleList)

        Study material:
        ---
        \(text)
        ---
        """

        let fullResponse = try await sendChatRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            streaming: nil
        )

        return parseFlashcardResponse(fullResponse, fallbackTitles: cardTitles)
    }

    private func parseFlashcardResponse(_ content: String, fallbackTitles: [String]) -> [Flashcard] {
        // Extract JSON array from response (handle markdown code blocks)
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let startRange = jsonString.range(of: "["),
           let endRange = jsonString.range(of: "]", options: .backwards) {
            jsonString = String(jsonString[startRange.lowerBound..<endRange.upperBound])
        }

        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct RawFlashcard: Decodable {
            let front: String
            let back: String
            let sourceCard: String?
            let category: String?
        }

        do {
            let rawFlashcards = try JSONDecoder().decode([RawFlashcard].self, from: data)
            return rawFlashcards.map { raw in
                Flashcard(
                    front: raw.front,
                    back: raw.back,
                    sourceCardTitle: raw.sourceCard ?? fallbackTitles.first ?? "Unknown",
                    category: raw.category
                )
            }
        } catch {
            print("[OpenAIProvider] Flashcard JSON parse error: \(error)")
            return []
        }
    }

    // MARK: - Response Parsing

    private func parseDocumentResponse(_ content: String, originalText: String) -> DocumentSummaryOutput {
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var summary = ""
        var keyPoints: [String] = []
        var title = ""
        var docType = "Document"
        var currentSection = ""

        for line in lines {
            if line.isEmpty { continue }

            let lowercased = line.lowercased()

            if lowercased.hasPrefix("summary:") {
                currentSection = "summary"
                summary = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if lowercased.hasPrefix("key points:") || lowercased.hasPrefix("key point:") {
                currentSection = "keypoints"
            } else if lowercased.hasPrefix("title:") || lowercased.hasPrefix("suggested title:") {
                currentSection = "title"
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    title = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                }
            } else if lowercased.hasPrefix("type:") || lowercased.hasPrefix("document type:") {
                currentSection = "type"
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    docType = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                }
            } else if line.hasPrefix("-") || line.hasPrefix("•") {
                let point = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !point.isEmpty {
                    keyPoints.append(point)
                }
            } else if currentSection == "summary" && !line.isEmpty {
                summary += " " + line
            }
        }

        // Fallbacks
        if summary.isEmpty {
            summary = createSimpleSummary(from: originalText)
        }
        if title.isEmpty {
            title = createTitle(from: originalText)
        }
        if keyPoints.isEmpty {
            keyPoints = extractKeyPoints(from: originalText)
        }

        return DocumentSummaryOutput(
            summary: summary,
            keyPoints: keyPoints,
            suggestedTitle: title,
            documentType: docType,
            // This provider is text-only; page images are never sent to OpenAI.
            visualDescription: ""
        )
    }

    private func parseDeckResponse(_ content: String, cardCount: Int) -> DeckSummaryOutput {
        let lines = content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var summary = ""
        var keyThemes: [String] = []
        var currentSection = ""

        for line in lines {
            if line.isEmpty { continue }

            let lowercased = line.lowercased()

            if lowercased.hasPrefix("overview:") || lowercased.hasPrefix("summary:") {
                currentSection = "summary"
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    summary = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                }
            } else if lowercased.contains("theme") || lowercased.contains("key point") {
                currentSection = "themes"
            } else if line.hasPrefix("-") || line.hasPrefix("•") {
                let theme = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !theme.isEmpty {
                    keyThemes.append(theme)
                }
            } else if currentSection == "summary" && !line.isEmpty {
                if summary.isEmpty {
                    summary = line
                } else {
                    summary += " " + line
                }
            }
        }

        if summary.isEmpty {
            summary = "This deck contains \(cardCount) cards with study material."
        }

        return DeckSummaryOutput(
            summary: summary,
            keyThemes: keyThemes,
            cardCount: cardCount
        )
    }

    // MARK: - Fallback Helpers

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

    private func extractKeyPoints(from text: String) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 20 }
        return Array(sentences.prefix(4)).map { sentence in
            sentence.count > 80 ? String(sentence.prefix(80)) + "..." : sentence
        }
    }

    private func createTitle(from text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let titleWords = words.prefix(5).joined(separator: " ")
        if titleWords.count > 40 {
            return String(titleWords.prefix(40)) + "..."
        }
        return titleWords.isEmpty ? "Untitled" : titleWords
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured. Add one in Settings."
        case .invalidAPIKey:
            return "Invalid OpenAI API key. Check your key in Settings."
        case .apiError(let message):
            return "OpenAI API error: \(message)"
        }
    }
}
