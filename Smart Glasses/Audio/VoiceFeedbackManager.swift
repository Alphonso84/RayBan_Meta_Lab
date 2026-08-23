//
//  VoiceFeedbackManager.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import AVFoundation
import AudioToolbox
import UIKit
import Combine
import SwiftUI

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

    /// Whether audio is currently routed to glasses (Bluetooth)
    @Published var isRoutedToGlasses: Bool = false

    // MARK: - Private Properties

    /// Speech synthesizer
    private let synthesizer = AVSpeechSynthesizer()

    /// Audio player for OpenAI TTS playback
    private var audioPlayer: AVAudioPlayer?

    /// Bumped by every `stopSpeaking()`.
    ///
    /// OpenAI speech is fetched over the network before anything can play, and
    /// a stop arriving during that window has nothing to cancel — the request
    /// would come back afterwards and start talking. Work captures the value it
    /// started under and discards its result if it no longer matches.
    private var speechGeneration = 0

    /// Queue of pending utterances
    private var utteranceQueue: [String] = []

    /// Resolved Apple voice, cached to avoid re-enumerating installed voices on
    /// every utterance. `cachedVoiceTag` records which setting produced it.
    private var cachedVoice: AVSpeechSynthesisVoice?
    private var cachedVoiceTag: String?

    // MARK: - User Settings

    @AppStorage("selectedProvider") private var selectedProvider = "apple"
    @AppStorage("openAIVoice") private var openAIVoice = "nova"
    @AppStorage("appleVoiceIdentifier") private var appleVoiceIdentifier = VoiceFeedbackManager.bestAvailableVoiceTag

    // MARK: - Initialization

    private override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        observeAudioRouteChanges()
        observeAvailableVoiceChanges()
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

    /// Invalidate the cached voice when the user downloads or removes a voice
    /// in Settings while the app is running.
    private func observeAvailableVoiceChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAvailableVoicesChange),
            name: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleAvailableVoicesChange(_ notification: Notification) {
        Task { @MainActor in
            cachedVoice = nil
            cachedVoiceTag = nil
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        Task { @MainActor in
            updateAudioRoute()

            // If Bluetooth disconnected mid-session, reroute to phone speaker
            if let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init),
               reason == .oldDeviceUnavailable {
                if !isBluetoothConnected {
                    configureAudioRoute(forGlasses: false)
                }
            }
        }
    }

    private func updateAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        if let bluetoothOutput = outputs.first(where: {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }) {
            audioOutputRoute = "Bluetooth: \(bluetoothOutput.portName)"
            isRoutedToGlasses = true
        } else if let output = outputs.first {
            audioOutputRoute = output.portName
            isRoutedToGlasses = false
        } else {
            audioOutputRoute = "No output"
            isRoutedToGlasses = false
        }
    }

    /// Configure audio routing based on whether glasses are connected
    /// - Parameter forGlasses: true to route to glasses via Bluetooth, false for phone speaker
    func configureAudioRoute(forGlasses: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if forGlasses {
                try session.setCategory(
                    .playback,
                    mode: .default,
                    options: [.allowBluetooth, .allowBluetoothA2DP]
                )
            } else {
                try session.setCategory(
                    .playback,
                    mode: .default,
                    options: [.defaultToSpeaker]
                )
                try session.overrideOutputAudioPort(.speaker)
            }
            try session.setActive(true)
            updateAudioRoute()
            print("[VoiceFeedback] Audio routed to \(forGlasses ? "glasses (Bluetooth)" : "phone speaker")")
        } catch {
            print("[VoiceFeedback] Failed to configure audio route: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Methods

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

    /// Stop any current speech (Apple TTS or OpenAI audio)
    func stopSpeaking() {
        // Invalidate any OpenAI request still in flight before tearing down.
        speechGeneration &+= 1
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
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

        // Configure voice from the user's preference. A nil voice is valid and
        // means "use whatever the user picked in Spoken Content settings".
        utterance.voice = resolvedVoice()

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

// MARK: - Apple Voice Selection
extension VoiceFeedbackManager {

    /// Stored in `appleVoiceIdentifier` to mean "pick the highest quality
    /// English voice installed on this device".
    static let bestAvailableVoiceTag = "best"

    /// Stored in `appleVoiceIdentifier` to mean "defer to the voice the user
    /// chose in Settings → Accessibility → Spoken Content".
    static let systemDefaultVoiceTag = "system"

    /// Voices that sound closest to Siri, in descending preference. Used only
    /// to break ties between voices of equal quality.
    private static let preferredVoiceNames = ["Ava", "Evan", "Zoe", "Nathan", "Noelle", "Samantha"]

    /// English voices installed on this device, best quality first.
    /// Enhanced and premium voices only appear here once the user downloads
    /// them in Settings → Accessibility → Spoken Content → Voices.
    static func availableEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                if lhs.language != rhs.language {
                    return lhs.language < rhs.language
                }
                return lhs.name < rhs.name
            }
    }

    /// Highest quality English voice installed, preferring premium over
    /// enhanced over the basic compact voices.
    static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        func rank(_ voice: AVSpeechSynthesisVoice) -> (Int, Int, Int) {
            let nameRank = preferredVoiceNames.firstIndex(of: voice.name)
                .map { preferredVoiceNames.count - $0 } ?? 0
            return (voice.quality.rawValue, voice.language == "en-US" ? 1 : 0, nameRank)
        }

        return availableEnglishVoices().max { rank($0) < rank($1) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Human-readable label for a voice, including its quality tier.
    static func displayName(for voice: AVSpeechSynthesisVoice) -> String {
        let quality = switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Basic"
        }
        return "\(voice.name) — \(quality)"
    }

    /// The voice to speak with, honoring the user's setting.
    /// Returns nil when the user wants the system default voice.
    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let tag = appleVoiceIdentifier

        guard tag != Self.systemDefaultVoiceTag else { return nil }

        if let cachedVoiceTag, cachedVoiceTag == tag {
            return cachedVoice
        }

        // A stored identifier can go stale if the user deletes a downloaded
        // voice, so fall back to the best remaining voice rather than nil.
        let voice = tag == Self.bestAvailableVoiceTag
            ? Self.bestAvailableVoice()
            : (AVSpeechSynthesisVoice(identifier: tag) ?? Self.bestAvailableVoice())

        cachedVoice = voice
        cachedVoiceTag = tag
        return voice
    }
}

// MARK: - OpenAI TTS
extension VoiceFeedbackManager {

    /// Speak summary text using the best available TTS provider.
    /// Uses OpenAI TTS when selected and API key exists, otherwise falls back to Apple TTS.
    /// Use this for longer content like summaries and card readback — short feedback
    /// ("Captured", "Hold steady") should still use `speak()` for instant response.
    func speakSummary(_ text: String) {
        if selectedProvider == "openai",
           KeychainHelper.loadString(key: "openai_api_key") != nil {
            speakWithOpenAI(text)
        } else {
            speak(text)
        }
    }

    /// Speak text using OpenAI's TTS API
    private func speakWithOpenAI(_ text: String) {
        guard !isSpeaking else { return }
        isSpeaking = true

        let generation = speechGeneration

        Task {
            do {
                let provider = OpenAIProvider()
                let audioData = try await provider.synthesizeSpeech(text: text, voice: openAIVoice)

                // Stopped while the audio was being fetched — starting playback
                // now would talk over whatever the user moved on to.
                guard generation == self.speechGeneration else {
                    print("[VoiceFeedback] Discarding OpenAI TTS: speech was stopped")
                    return
                }

                let player = try AVAudioPlayer(data: audioData)
                self.audioPlayer = player
                player.delegate = self
                player.play()

                print("[VoiceFeedback] Playing OpenAI TTS (\(openAIVoice))")
            } catch {
                guard generation == self.speechGeneration else { return }

                print("[VoiceFeedback] OpenAI TTS failed: \(error.localizedDescription), falling back to Apple TTS")
                self.isSpeaking = false
                self.speak(text)
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension VoiceFeedbackManager: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isSpeaking = false
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in
            self.audioPlayer = nil
            self.isSpeaking = false
            print("[VoiceFeedback] Audio decode error: \(error?.localizedDescription ?? "unknown")")
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

// MARK: - Capture Feedback
extension VoiceFeedbackManager {

    /// Feedback for successful document capture
    func captureSuccess() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // System sound (camera shutter-like)
        AudioServicesPlaySystemSound(1108) // Photo shutter sound

        // Brief spoken confirmation
        speak("Captured")
    }

    /// Feedback when document is detected but user needs to hold steady
    func holdSteady() {
        // Light haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Subtle tick sound
        AudioServicesPlaySystemSound(1104) // Tick sound
    }

    /// Feedback when capture failed due to insufficient text
    func captureFailedInsufficientText() {
        // Error haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Error sound
        AudioServicesPlaySystemSound(1053) // Error/failure sound

        // Spoken feedback
        speak("Not enough text detected. Try moving closer to the document.")
    }

    /// Feedback when no document is detected
    func noDocumentDetected() {
        // Warning haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Spoken feedback
        speak("No document detected. Point at a document and try again.")
    }

    /// Feedback when document is first detected
    func documentDetected() {
        // Light haptic to indicate detection
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Subtle sound
        AudioServicesPlaySystemSound(1057) // Subtle pop
    }

    /// Feedback for stability progress (called periodically)
    func stabilityTick() {
        // Very light haptic for each stability tick
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.5)
    }
}

// MARK: - Multi-Page Scanning Feedback
extension VoiceFeedbackManager {

    /// Feedback when a page is successfully captured in multi-page mode
    func pageCaptured(pageNumber: Int) {
        // Success haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Camera shutter sound
        AudioServicesPlaySystemSound(1108)

        // Announce page number
        speak("Page \(pageNumber) captured")
    }

    /// Feedback when multi-page scan session is complete
    func multiPageScanComplete(pageCount: Int) {
        // Strong success haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Completion sound
        AudioServicesPlaySystemSound(1025) // Positive acknowledgment

        // Announce completion
        let pageWord = pageCount == 1 ? "page" : "pages"
        speak("\(pageCount) \(pageWord) ready for summary")
    }

    /// Feedback prompting user to scan next page
    func readyForNextPage() {
        // Light haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Brief prompt
        speak("Ready for next page")
    }
}
