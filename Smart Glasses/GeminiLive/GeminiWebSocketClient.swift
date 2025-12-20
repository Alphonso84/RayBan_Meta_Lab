//
//  GeminiWebSocketClient.swift
//  Smart Glasses
//
//  WebSocket client for Gemini Live API communication
//

import Foundation

// MARK: - Delegate Protocol

protocol GeminiWebSocketDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceive(message: GeminiServerMessage)
    func webSocketDidReceive(audioData: Data)
}

// MARK: - WebSocket Client

class GeminiWebSocketClient: NSObject {

    // MARK: - Properties

    weak var delegate: GeminiWebSocketDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?

    private let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"

    private(set) var isConnected = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600  // 10 minutes max session
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Gemini API uses snake_case (matching Python docs)
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Connection Management

    func connect(apiKey: String) {
        guard !isConnected else {
            print("[GeminiWS] Already connected")
            return
        }

        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = urlComponents.url else {
            delegate?.webSocketDidDisconnect(error: GeminiError.connectionFailed("Invalid URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        startReceiving()
        startPingTimer()

        print("[GeminiWS] Connecting to Gemini Live API...")
    }

    func disconnect() {
        stopPingTimer()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("[GeminiWS] Disconnected")
    }

    // MARK: - Sending Messages

    func send(setup: GeminiSetupMessage) {
        sendEncodable(setup)
    }

    func send(realtimeInput: GeminiRealtimeInputMessage) {
        sendEncodable(realtimeInput)
    }

    private func sendEncodable<T: Encodable>(_ message: T) {
        guard isConnected else {
            print("[GeminiWS] Cannot send - not connected")
            return
        }

        do {
            let data = try encoder.encode(message)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                print("[GeminiWS] Failed to convert message to string")
                return
            }

            // Log all messages for debugging
            if jsonString.contains("setup") {
                print("[GeminiWS] === SENDING SETUP ===")
                print("[GeminiWS] \(jsonString)")
                print("[GeminiWS] === END SETUP ===")
            } else if jsonString.count < 200 {
                print("[GeminiWS] Sending: \(jsonString)")
            } else {
                print("[GeminiWS] Sending message: \(jsonString.prefix(100))... (\(jsonString.count) chars)")
            }

            webSocketTask?.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    print("[GeminiWS] Send error: \(error.localizedDescription)")
                    self?.handleSendError(error)
                } else {
                    print("[GeminiWS] Message sent successfully")
                }
            }
        } catch {
            print("[GeminiWS] Encoding error: \(error.localizedDescription)")
        }
    }

    private func handleSendError(_ error: Error) {
        // If send fails due to connection issue, trigger disconnect
        if (error as NSError).code == 57 {  // Socket not connected
            DispatchQueue.main.async {
                self.delegate?.webSocketDidDisconnect(error: error)
            }
        }
    }

    // MARK: - Receiving Messages

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.startReceiving()

            case .failure(let error):
                print("[GeminiWS] Receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.webSocketDidDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTextMessage(text)

        case .data(let data):
            // Binary messages - less common for Gemini
            parseDataMessage(data)

        @unknown default:
            print("[GeminiWS] Unknown message type received")
        }
    }

    private func parseTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            print("[GeminiWS] Failed to convert message to data")
            return
        }

        do {
            let serverMessage = try decoder.decode(GeminiServerMessage.self, from: data)

            // Log message type for debugging
            if serverMessage.setupComplete != nil {
                print("[GeminiWS] Received: setupComplete")
            }
            if serverMessage.serverContent != nil {
                if serverMessage.serverContent?.turnComplete == true {
                    print("[GeminiWS] Received: turnComplete")
                }
                if serverMessage.serverContent?.interrupted == true {
                    print("[GeminiWS] Received: interrupted")
                }
            }

            // Extract audio data if present and notify delegate
            if let parts = serverMessage.serverContent?.modelTurn?.parts {
                for part in parts {
                    // Check for text response
                    if let textContent = part.text {
                        print("[GeminiWS] Received text: \(textContent.prefix(100))...")
                    }

                    // Check for audio response
                    if let inlineData = part.inlineData {
                        print("[GeminiWS] Received inlineData: mimeType=\(inlineData.mimeType), dataLength=\(inlineData.data.count)")

                        if inlineData.mimeType.starts(with: "audio/"),
                           let audioData = Data(base64Encoded: inlineData.data) {
                            print("[GeminiWS] Decoded audio: \(audioData.count) bytes")
                            DispatchQueue.main.async {
                                self.delegate?.webSocketDidReceive(audioData: audioData)
                            }
                        }
                    }
                }
            }

            // Notify delegate of the full message
            DispatchQueue.main.async {
                self.delegate?.webSocketDidReceive(message: serverMessage)
            }

        } catch {
            print("[GeminiWS] Failed to decode message: \(error.localizedDescription)")
            // Print raw message for debugging
            if text.count < 500 {
                print("[GeminiWS] Raw message: \(text)")
            } else {
                print("[GeminiWS] Raw message (truncated): \(text.prefix(500))...")
            }
        }
    }

    private func parseDataMessage(_ data: Data) {
        // Attempt to decode as server message
        do {
            let serverMessage = try decoder.decode(GeminiServerMessage.self, from: data)
            DispatchQueue.main.async {
                self.delegate?.webSocketDidReceive(message: serverMessage)
            }
        } catch {
            print("[GeminiWS] Failed to decode binary message: \(error.localizedDescription)")
        }
    }

    // MARK: - Keep-Alive

    private func startPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
        }
    }

    private func stopPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = nil
        }
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("[GeminiWS] Ping failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.delegate?.webSocketDidDisconnect(error: error)
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiWebSocketClient: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        print("[GeminiWS] Connected successfully")
        DispatchQueue.main.async {
            self.delegate?.webSocketDidConnect()
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        isConnected = false
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        print("[GeminiWS] Connection closed: \(closeCode) - \(reasonString)")
        DispatchQueue.main.async {
            self.delegate?.webSocketDidDisconnect(error: nil)
        }
    }
}
