//
//  AIAssistantOverlayView.swift
//  Smart Glasses
//
//  Overlay UI for AI Assistant mode showing connection status,
//  listening/speaking indicators, and controls
//

import SwiftUI
import MWDATCamera

// MARK: - Main Overlay View

struct AIAssistantOverlayView: View {
    @ObservedObject var geminiManager: GeminiLiveManager
    @ObservedObject var wearablesManager: WearablesManager

    var body: some View {
        VStack {
            // Top status area - combined badge and listening/speaking indicator
            HStack(spacing: 12) {
                // Connection status dot
                StatusBadgeView(geminiManager: geminiManager)

                // Listening/Speaking indicator (compact, next to status)
                if geminiManager.conversationActive {
                    CompactConversationIndicator(geminiManager: geminiManager)
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()
            }
            .padding(.top, 60)
            .padding(.horizontal, 16)

            Spacer()

            // Bottom controls
            AIAssistantControlsView(
                geminiManager: geminiManager,
                isStreaming: wearablesManager.streamState == .streaming
            )
            .padding(.bottom, 120)  // Space for mode picker
        }
        .animation(.easeInOut(duration: 0.3), value: geminiManager.conversationActive)
        .animation(.easeInOut(duration: 0.2), value: geminiManager.isSpeaking)
        .animation(.easeInOut(duration: 0.2), value: geminiManager.isListening)
    }
}

// MARK: - Status Badge

struct StatusBadgeView: View {
    @ObservedObject var geminiManager: GeminiLiveManager

    var body: some View {
        HStack(spacing: 8) {
            // Connection status dot
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 4)

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch geminiManager.state {
        case .disconnected:
            return .gray
        case .connecting, .configuring:
            return .yellow
        case .connected, .ready:
            return .blue
        case .streaming, .responding:
            return .green
        case .error:
            return .red
        case .reconnecting:
            return .orange
        }
    }

    private var statusText: String {
        switch geminiManager.state {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .configuring:
            return "Setting up..."
        case .ready:
            return "Ready"
        case .streaming:
            return "AI Active"
        case .responding:
            return "Responding"
        case .error:
            return "Error"
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))"
        }
    }
}

// MARK: - Compact Conversation Indicator (for top bar)

struct CompactConversationIndicator: View {
    @ObservedObject var geminiManager: GeminiLiveManager

    var body: some View {
        HStack(spacing: 8) {
            if geminiManager.isSpeaking {
                // Compact speaking animation
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        CompactSpeakingBar(delay: Double(index) * 0.1)
                    }
                }
                .frame(width: 20, height: 16)

                Text("Speaking")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            } else if geminiManager.isListening {
                // Compact listening indicator
                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundColor(.green)

                Text("Listening")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(geminiManager.isSpeaking ? Color.purple.opacity(0.8) : Color.green.opacity(0.8))
        .clipShape(Capsule())
    }
}

struct CompactSpeakingBar: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white)
            .frame(width: 3, height: isAnimating ? 14 : 4)
            .animation(
                .easeInOut(duration: 0.3)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Conversation Indicator (legacy, kept for reference)

struct ConversationIndicatorView: View {
    @ObservedObject var geminiManager: GeminiLiveManager

    var body: some View {
        VStack(spacing: 16) {
            if geminiManager.isSpeaking {
                // Speaking animation
                SpeakingAnimationView()

                Text("Gemini is speaking...")
                    .font(.caption)
                    .foregroundColor(.white)
            } else if geminiManager.isListening {
                // Listening indicator
                ListeningIndicatorView()

                Text("Listening...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .padding(24)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Speaking Animation

struct SpeakingAnimationView: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                SpeakingBar(delay: Double(index) * 0.1)
            }
        }
        .frame(height: 40)
    }
}

struct SpeakingBar: View {
    let delay: Double

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(
                colors: [.blue, .purple],
                startPoint: .bottom,
                endPoint: .top
            ))
            .frame(width: 6, height: isAnimating ? 35 : 8)
            .animation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Listening Indicator

struct ListeningIndicatorView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse
            Circle()
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 1)

            // Inner circle
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 50, height: 50)

            // Mic icon
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundColor(.green)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Controls View

struct AIAssistantControlsView: View {
    @ObservedObject var geminiManager: GeminiLiveManager
    let isStreaming: Bool

    @State private var showAPIKeyAlert = false
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 16) {
            // Error message if any
            if let error = geminiManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // API Key prompt if not configured
            if !geminiManager.hasAPIKey {
                Button {
                    showAPIKeyAlert = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                        Text("Add API Key to Start")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .clipShape(Capsule())
                }
                .alert("Gemini API Key", isPresented: $showAPIKeyAlert) {
                    TextField("Enter API Key", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Cancel", role: .cancel) {
                        apiKeyInput = ""
                    }
                    Button("Save") {
                        if GeminiAPIKeyManager.shared.setAPIKey(apiKeyInput) {
                            apiKeyInput = ""
                            // Auto-start after saving key
                            if isStreaming {
                                geminiManager.startSession()
                            }
                        }
                    }
                } message: {
                    Text("Enter your Gemini API key from Google AI Studio")
                }
            }
            // No manual start/stop button - it auto-starts when entering AI mode
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        AIAssistantOverlayView(
            geminiManager: GeminiLiveManager.shared,
            wearablesManager: WearablesManager.shared
        )
    }
    .ignoresSafeArea()
}
