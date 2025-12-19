//
//  VoiceFeedbackManager.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import AVFoundation
import Combine

/// Manages text-to-speech voice feedback through the glasses speakers via Bluetooth A2DP
@MainActor
class VoiceFeedbackManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = VoiceFeedbackManager()

    // MARK: - Published Properties

    /// Whether the synthesizer is currently speaking
    @Published var isSpeaking: Bool = false

    /// Whether audio session is properly configured
    @Published var isAudioConfigured: Bool = false

    /// Current audio output route (for debugging)
    @Published var audioOutputRoute: String = "Unknown"

    // MARK: - Private Properties

    /// Speech synthesizer
    private let synthesizer = AVSpeechSynthesizer()

    /// Queue of pending utterances
    private var utteranceQueue: [String] = []

    // MARK: - Initialization

    private override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        observeAudioRouteChanges()
    }

    // MARK: - Audio Session Setup

    /// Configure AVAudioSession for Bluetooth A2DP output
    /// Uses ambient category to avoid disrupting glasses Bluetooth streaming
    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()

            // Use ambient category - mixes with other audio and doesn't interrupt
            // This prevents disrupting the Bluetooth streaming from glasses
            try session.setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )

            isAudioConfigured = true
            updateAudioRoute()

            print("[VoiceFeedback] Audio session configured (ambient mode)")
            print("[VoiceFeedback] Current outputs: \(session.currentRoute.outputs.map { "\($0.portName)" })")

        } catch {
            print("[VoiceFeedback] Failed to configure audio session: \(error.localizedDescription)")
            isAudioConfigured = false
        }
    }

    /// Reconfigure audio session (call before speaking if needed)
    func reconfigureForSpeech() {
        updateAudioRoute()
        print("[VoiceFeedback] Audio route: \(audioOutputRoute)")
    }

    /// Observe audio route changes (e.g., Bluetooth connection/disconnection)
    private func observeAudioRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        Task { @MainActor in
            updateAudioRoute()
        }
    }

    private func updateAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        if let bluetoothOutput = outputs.first(where: {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }) {
            audioOutputRoute = "Bluetooth: \(bluetoothOutput.portName)"
        } else if let output = outputs.first {
            audioOutputRoute = output.portName
        } else {
            audioOutputRoute = "No output"
        }
    }

    // MARK: - Public Methods

    /// Describe the detection result using TTS
    /// - Parameter result: The detection result to describe
    func describe(_ result: DetectionResult?) {
        guard let result = result else {
            speak("No detection results available")
            return
        }

        let description = result.generateDescription()
        speak(description)
    }

    /// Describe a specific object
    /// - Parameter object: The detected object to describe
    func describeObject(_ object: DetectedObject) {
        speak("I see a \(object.label) with \(object.confidencePercent) confidence")
    }

    /// Speak arbitrary text
    /// - Parameter text: The text to speak
    func speak(_ text: String) {
        // Don't interrupt if already speaking, queue instead
        if isSpeaking {
            utteranceQueue.append(text)
            return
        }

        performSpeak(text)
    }

    /// Stop any current speech
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        utteranceQueue.removeAll()
        isSpeaking = false
    }

    /// Speak with high priority (interrupts current speech)
    /// - Parameter text: The text to speak immediately
    func speakImmediately(_ text: String) {
        stopSpeaking()
        performSpeak(text)
    }

    // MARK: - Private Methods

    private func performSpeak(_ text: String) {
        print("[VoiceFeedback] Speaking: \"\(text)\"")

        // Don't reconfigure audio session - just speak
        // Reconfiguring can disrupt Bluetooth streaming from glasses

        let utterance = AVSpeechUtterance(string: text)

        // Configure voice - try to get a high quality voice
        if let voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha") {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        // Configure speech parameters
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0  // Max volume

        // Minimal delays to avoid disruption
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.1

        isSpeaking = true
        synthesizer.speak(utterance)

        print("[VoiceFeedback] Utterance queued to synthesizer")
    }

    private func processQueue() {
        guard !utteranceQueue.isEmpty else {
            isSpeaking = false
            return
        }

        let nextText = utteranceQueue.removeFirst()
        performSpeak(nextText)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceFeedbackManager: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.processQueue()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.utteranceQueue.removeAll()
        }
    }
}

// MARK: - Convenience Methods
extension VoiceFeedbackManager {

    /// Check if Bluetooth audio is connected
    var isBluetoothConnected: Bool {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.contains {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }
    }

    /// Announce Bluetooth connection status
    func announceConnectionStatus() {
        if isBluetoothConnected {
            speak("Connected to \(audioOutputRoute)")
        } else {
            speak("No Bluetooth audio device connected. Sound will play through phone speakers.")
        }
    }
}
