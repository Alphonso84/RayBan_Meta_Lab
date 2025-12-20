//
//  GeminiMessageModels.swift
//  Smart Glasses
//
//  Codable message structures for Gemini Live API WebSocket communication
//

import Foundation

// MARK: - Session State

enum GeminiSessionState: Equatable {
    case disconnected
    case connecting
    case connected
    case configuring
    case ready
    case streaming
    case responding
    case error(GeminiError)
    case reconnecting(attempt: Int)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

enum GeminiError: Error, Equatable {
    case connectionFailed(String)
    case setupFailed(String)
    case invalidAPIKey
    case rateLimited
    case serverError(String)
    case encodingError(String)
    case audioPlaybackError(String)
    case microphoneError(String)
    case timeout
}

// MARK: - Outgoing Messages

/// Initial setup message sent when connection opens
struct GeminiSetupMessage: Encodable {
    let setup: GeminiSetupContent
}

struct GeminiSetupContent: Encodable {
    let model: String
    let generationConfig: GeminiGenerationConfig?
    let systemInstruction: GeminiSystemInstruction?
}

struct GeminiGenerationConfig: Encodable {
    let responseModalities: [String]
    let speechConfig: GeminiSpeechConfig?
}

struct GeminiSpeechConfig: Encodable {
    let voiceConfig: GeminiVoiceConfig?
}

struct GeminiVoiceConfig: Encodable {
    let prebuiltVoiceConfig: GeminiPrebuiltVoiceConfig?
}

struct GeminiPrebuiltVoiceConfig: Encodable {
    let voiceName: String
}

struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiTextPart]
}

struct GeminiTextPart: Codable {
    let text: String
}

/// Real-time input message for audio/video streaming
struct GeminiRealtimeInputMessage: Encodable {
    let realtimeInput: GeminiRealtimeInput
}

struct GeminiRealtimeInput: Encodable {
    let mediaChunks: [GeminiMediaChunk]?

    init(mediaChunks: [GeminiMediaChunk]? = nil) {
        self.mediaChunks = mediaChunks
    }

    /// Convenience initializer for audio data
    static func audio(data: String) -> GeminiRealtimeInput {
        GeminiRealtimeInput(mediaChunks: [
            GeminiMediaChunk(mimeType: "audio/pcm;rate=16000", data: data)
        ])
    }

    /// Convenience initializer for video frame
    static func video(data: String) -> GeminiRealtimeInput {
        GeminiRealtimeInput(mediaChunks: [
            GeminiMediaChunk(mimeType: "image/jpeg", data: data)
        ])
    }

    /// Convenience initializer for both audio and video
    static func audioVideo(audioData: String, videoData: String) -> GeminiRealtimeInput {
        GeminiRealtimeInput(mediaChunks: [
            GeminiMediaChunk(mimeType: "audio/pcm;rate=16000", data: audioData),
            GeminiMediaChunk(mimeType: "image/jpeg", data: videoData)
        ])
    }
}

struct GeminiMediaChunk: Encodable {
    let mimeType: String
    let data: String  // base64 encoded
}

// MARK: - Incoming Messages

/// Server response wrapper - can contain different response types
struct GeminiServerMessage: Decodable {
    let setupComplete: GeminiSetupComplete?
    let serverContent: GeminiServerContent?
    let toolCall: GeminiToolCall?
    let toolCallCancellation: GeminiToolCallCancellation?
    let usageMetadata: GeminiUsageMetadata?
}

struct GeminiSetupComplete: Decodable {
    // Empty or may contain session info
}

struct GeminiServerContent: Decodable {
    let modelTurn: GeminiModelTurn?
    let generationComplete: Bool?
    let turnComplete: Bool?
    let interrupted: Bool?
    let inputTranscription: GeminiTranscription?
    let outputTranscription: GeminiTranscription?
}

struct GeminiModelTurn: Decodable {
    let parts: [GeminiResponsePart]?
}

struct GeminiResponsePart: Decodable {
    let text: String?
    let inlineData: GeminiInlineData?
}

struct GeminiInlineData: Decodable {
    let mimeType: String
    let data: String  // base64 encoded
}

struct GeminiTranscription: Decodable {
    let text: String?
}

struct GeminiToolCall: Decodable {
    let functionCalls: [GeminiFunctionCall]?
}

struct GeminiFunctionCall: Decodable {
    let id: String
    let name: String
    let args: [String: AnyCodableValue]?
}

struct GeminiToolCallCancellation: Decodable {
    let ids: [String]
}

struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let cachedContentTokenCount: Int?
    let responseTokenCount: Int?
    let totalTokenCount: Int?
}

// MARK: - Helper for decoding arbitrary JSON values

enum AnyCodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodableValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }
}
