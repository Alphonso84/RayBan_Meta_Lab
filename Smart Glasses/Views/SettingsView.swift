//
//  SettingsView.swift
//  Smart Glasses
//
//  Settings and Meta glasses connection management
//

import SwiftUI
import AVFoundation
import MWDATCamera

/// Settings view for app configuration and glasses connection
struct SettingsView: View {
    @ObservedObject private var manager = WearablesManager.shared
    @AppStorage("autoSummarize") private var autoSummarize = true
    @AppStorage("speakSummaries") private var speakSummaries = false
    @AppStorage("distanceModeEnabled") private var distanceModeEnabled = true
    @AppStorage("multiPageModeEnabled") private var multiPageModeEnabled = false
    @AppStorage("selectedProvider") private var selectedProvider = "apple"
    @AppStorage("useVisionSummarization") private var useVisionSummarization = true
    @AppStorage("openAIModel") private var openAIModel = "gpt-4o-mini"
    @AppStorage("openAIVoice") private var openAIVoice = "nova"
    @AppStorage("appleVoiceIdentifier") private var appleVoiceIdentifier = VoiceFeedbackManager.bestAvailableVoiceTag

    @Environment(\.scenePhase) private var scenePhase

    @State private var apiKeyInput = ""
    @State private var apiKeySaved = false
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var installedVoices: [AVSpeechSynthesisVoice] = []

    private enum ConnectionTestResult {
        case success
        case failure(String)
    }

    /// Not every device's model variant supports image attachments, so hide the
    /// toggle rather than offer a dead control.
    private var visionSummarizationSupported: Bool {
        PageVisionPrompt.isVisionSupported
    }

    var body: some View {
        NavigationStack {
            List {
                // Meta Glasses Section
                Section {
                    // Connection status
                    HStack {
                        Label("Status", systemImage: "eyeglasses")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(manager.deviceStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Registration status
                    HStack {
                        Label("Registration", systemImage: "checkmark.shield")
                        Spacer()
                        Text(manager.registrationStateDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let registrationError = manager.registrationErrorMessage {
                        Label(registrationError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    // Stream status
                    HStack {
                        Label("Stream", systemImage: "video")
                        Spacer()
                        Text(streamStatusText)
                            .font(.subheadline)
                            .foregroundStyle(streamStatusColor)
                    }

                    // Camera permission
                    if let cameraStatus = manager.cameraStatus {
                        HStack {
                            Label("Camera", systemImage: "camera")
                            Spacer()
                            Text(cameraStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Action buttons
                    Button {
                        manager.startRegistration()
                    } label: {
                        Label("Connect Glasses", systemImage: "link")
                    }

                    Button {
                        Task {
                            await manager.requestCameraPermission()
                        }
                    } label: {
                        Label("Request Camera Access", systemImage: "camera.badge.ellipsis")
                    }

                    // Stream control button
                    if manager.streamState == .streaming {
                        Button(role: .destructive) {
                            manager.stopStream()
                        } label: {
                            Label("Stop Stream", systemImage: "stop.circle")
                        }
                    } else if manager.isRegistered {
                        Button {
                            manager.startStream()
                        } label: {
                            Label("Start Stream", systemImage: "play.circle")
                        }
                    }

                    Button(role: .destructive) {
                        manager.startUnregistration()
                    } label: {
                        Label("Disconnect Glasses", systemImage: "link.badge.plus")
                    }
                } header: {
                    Text("Meta Ray-Ban Glasses")
                } footer: {
                    Text("Connect your Meta Ray-Ban smart glasses to scan documents hands-free.")
                }

                // Scanning Settings
                Section {
                    Toggle(isOn: $distanceModeEnabled) {
                        Label("Distance Mode", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Toggle(isOn: $multiPageModeEnabled) {
                        Label("Multi-Page Mode", systemImage: "doc.on.doc")
                    }

                    Toggle(isOn: $autoSummarize) {
                        Label("Auto-Summarize", systemImage: "sparkles")
                    }

                    Toggle(isOn: $speakSummaries) {
                        Label("Speak Summaries", systemImage: "speaker.wave.2")
                    }

                    if visionSummarizationSupported {
                        Toggle(isOn: $useVisionSummarization) {
                            Label("Read Page Images", systemImage: "eye")
                        }
                    }
                } header: {
                    Text("Scanning")
                } footer: {
                    if visionSummarizationSupported {
                        Text("Single-page mode auto-summarizes immediately after capture. Multi-page mode lets you scan multiple pages before generating one combined summary.\n\nRead Page Images sends the scanned page to the on-device model alongside the extracted text, so it can correct misread words and describe diagrams, charts and tables. Summaries take slightly longer. The image never leaves your device.")
                    } else {
                        Text("Single-page mode auto-summarizes immediately after capture. Multi-page mode lets you scan multiple pages before generating one combined summary.")
                    }
                }

                // Voice Section
                Section {
                    Picker(selection: $appleVoiceIdentifier) {
                        Text("Best Available").tag(VoiceFeedbackManager.bestAvailableVoiceTag)
                        Text("System Default").tag(VoiceFeedbackManager.systemDefaultVoiceTag)

                        ForEach(installedVoices, id: \.identifier) { voice in
                            Text(VoiceFeedbackManager.displayName(for: voice))
                                .tag(voice.identifier)
                        }
                    } label: {
                        Label("Voice", systemImage: "waveform")
                    }

                    Button {
                        VoiceFeedbackManager.shared.speakImmediately(
                            "This is how your document summaries will sound."
                        )
                    } label: {
                        Label("Preview Voice", systemImage: "play.circle")
                    }

                    if !hasHighQualityVoice {
                        Label(
                            "Only basic voices are installed. Download an Enhanced or Premium voice in Settings → Accessibility → Spoken Content → Voices → English for a more natural sound.",
                            systemImage: "arrow.down.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Used for capture cues, and for reading summaries when the provider is Apple Intelligence. OpenAI summaries use the OpenAI voice below.")
                }

                // AI Provider Section
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("On-Device").tag("apple")
                        Text("Apple Cloud").tag("pcc")
                        Text("OpenAI").tag("openai")
                    }
                    .pickerStyle(.segmented)

                    if selectedProvider == "pcc" {
                        if let unavailable = AppleModelProvider.pccUnavailableMessage {
                            Label(unavailable, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Label("Private Cloud Compute is ready", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        if let quota = AppleModelProvider.pccQuotaMessage {
                            Button {
                                AppleModelProvider.showQuotaIncreaseSuggestion()
                            } label: {
                                Label(quota, systemImage: "gauge.with.needle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if selectedProvider == "openai" {
                        // API Key
                        HStack {
                            SecureField("API Key", text: $apiKeyInput)
                                .textContentType(.password)
                                .autocorrectionDisabled()

                            if apiKeySaved {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }

                            Button("Save") {
                                KeychainHelper.save(key: "openai_api_key", string: apiKeyInput)
                                apiKeySaved = true
                                apiKeyInput = ""
                            }
                            .disabled(apiKeyInput.isEmpty)
                        }

                        // Model Picker
                        HStack {
                            if availableModels.isEmpty {
                                TextField("Model", text: $openAIModel)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                Picker("Model", selection: $openAIModel) {
                                    ForEach(availableModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                            }

                            Button {
                                fetchModels()
                            } label: {
                                if isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .disabled(isFetchingModels)
                        }

                        // Voice Picker
                        Picker("Voice", selection: $openAIVoice) {
                            Text("Alloy").tag("alloy")
                            Text("Ash").tag("ash")
                            Text("Ballad").tag("ballad")
                            Text("Coral").tag("coral")
                            Text("Echo").tag("echo")
                            Text("Fable").tag("fable")
                            Text("Nova").tag("nova")
                            Text("Onyx").tag("onyx")
                            Text("Sage").tag("sage")
                            Text("Shimmer").tag("shimmer")
                        }

                        // Test Connection
                        Button {
                            testConnection()
                        } label: {
                            HStack {
                                Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                                Spacer()
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if let result = connectionTestResult {
                                    switch result {
                                    case .success:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    case .failure:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .disabled(isTestingConnection)

                        if case .failure(let message) = connectionTestResult {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("AI Provider")
                } footer: {
                    switch selectedProvider {
                    case "openai":
                        Text("Your API key is stored securely in the Keychain. Tap Refresh to load available models from OpenAI.")
                    case "pcc":
                        Text("Apple Cloud uses Private Cloud Compute: a larger model with a bigger context window, so deck summaries are written in one pass instead of being stitched together from batches. No API key, no billing, and Apple does not store your prompts.\n\nScanned page images are always read on-device — only text is sent. If the network is unavailable or you reach your limit, summaries fall back to the on-device model automatically.")
                    default:
                        Text("The on-device model runs entirely on your iPhone and works offline. Requires iOS 26+.")
                    }
                }

                // About Section
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                manager.refreshRegistrationState()
                Task {
                    await manager.refreshCameraPermissionStatus()
                }
                // Check if API key already exists
                apiKeySaved = KeychainHelper.loadString(key: "openai_api_key") != nil
                installedVoices = VoiceFeedbackManager.availableEnglishVoices()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Voices the user downloads in the Settings app only show up
                // after we re-enumerate, so refresh on return to foreground.
                if newPhase == .active {
                    installedVoices = VoiceFeedbackManager.availableEnglishVoices()
                }
            }
        }
    }

    /// Whether any enhanced or premium voice is installed.
    private var hasHighQualityVoice: Bool {
        installedVoices.contains { $0.quality != .default }
    }

    private var statusColor: Color {
        if manager.deviceStatus.contains("Connected") {
            return .green
        } else if manager.isRegistered {
            return .yellow
        } else {
            return .red
        }
    }

    private var streamStatusText: String {
        switch manager.streamState {
        case .streaming:
            return "Active"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .waitingForDevice:
            return "Waiting for glasses..."
        case .paused:
            return "Paused"
        case .stopped:
            return "Stopped"
        @unknown default:
            return "Unknown"
        }
    }

    private var streamStatusColor: Color {
        switch manager.streamState {
        case .streaming:
            return .green
        case .starting, .stopping, .waitingForDevice, .paused:
            return .orange
        case .stopped:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    // MARK: - AI Provider Helpers

    private func fetchModels() {
        isFetchingModels = true
        let provider = OpenAIProvider()
        Task {
            do {
                let models = try await provider.fetchAvailableModels()
                await MainActor.run {
                    availableModels = models
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                    connectionTestResult = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        let provider = OpenAIProvider()
        Task {
            do {
                let success = try await provider.testConnection()
                await MainActor.run {
                    connectionTestResult = success ? .success : .failure("Connection failed")
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = .failure(error.localizedDescription)
                    isTestingConnection = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
