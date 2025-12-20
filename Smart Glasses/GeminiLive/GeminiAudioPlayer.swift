//
//  GeminiAudioPlayer.swift
//  Smart Glasses
//
//  Plays 24kHz PCM audio responses from Gemini Live API
//

import AVFoundation

class GeminiAudioPlayer {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var outputFormat: AVAudioFormat?

    private(set) var isPlaying = false
    private(set) var hasScheduledAudio = false

    private let sampleRate: Double = 24000  // Gemini output format
    private let bufferLock = NSLock()

    // Debug counters
    private var audioChunksReceived = 0
    private var audioChunksPlayed = 0

    // MARK: - Initialization

    init() {
        // Don't setup engine in init - do it in start() after audio session is configured
    }

    // MARK: - Setup

    private func setupAudioEngine() throws {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let audioEngine = audioEngine,
              let playerNode = playerNode else {
            throw GeminiError.audioPlaybackError("Failed to create audio engine")
        }

        // Create format matching 24kHz mono float (standard for AVAudioEngine)
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )

        guard let format = outputFormat else {
            throw GeminiError.audioPlaybackError("Failed to create audio format")
        }

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        print("[GeminiAudio] Audio engine configured with format: \(format)")
    }

    // MARK: - Public Methods

    func start() throws {
        // Reset if already exists
        if audioEngine != nil {
            stop()
        }

        // Setup audio engine fresh
        try setupAudioEngine()

        guard let audioEngine = audioEngine else {
            throw GeminiError.audioPlaybackError("Audio engine not initialized")
        }

        // Log audio route
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { $0.portName }
        print("[GeminiAudio] Audio outputs: \(outputs)")

        // Start the engine
        try audioEngine.start()
        playerNode?.play()
        isPlaying = true

        audioChunksReceived = 0
        audioChunksPlayed = 0

        print("[GeminiAudio] Player started successfully")
    }

    func stop() {
        bufferLock.lock()
        playerNode?.stop()
        audioEngine?.stop()
        isPlaying = false
        hasScheduledAudio = false
        bufferLock.unlock()

        print("[GeminiAudio] Player stopped")
    }

    /// Enqueue audio data for playback
    func enqueue(audioData: Data) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        audioChunksReceived += 1

        guard isPlaying, let playerNode = playerNode else {
            print("[GeminiAudio] Cannot enqueue - not playing")
            return
        }

        guard audioData.count > 0 else {
            print("[GeminiAudio] Empty audio data received")
            return
        }

        // Gemini sends 24kHz 16-bit PCM mono audio
        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!

        // Convert Data to AVAudioPCMBuffer
        let frameCount = AVAudioFrameCount(audioData.count / 2)  // 2 bytes per Int16

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            print("[GeminiAudio] Failed to create input buffer")
            return
        }

        inputBuffer.frameLength = frameCount

        // Copy audio data to buffer
        audioData.withUnsafeBytes { rawBytes in
            guard let ptr = rawBytes.baseAddress else { return }
            memcpy(inputBuffer.int16ChannelData![0], ptr, audioData.count)
        }

        // Convert to float format for the audio engine
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[GeminiAudio] Failed to create output format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("[GeminiAudio] Failed to create converter")
            return
        }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            print("[GeminiAudio] Failed to create output buffer")
            return
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, error == nil else {
            print("[GeminiAudio] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Schedule buffer for playback
        playerNode.scheduleBuffer(outputBuffer) { [weak self] in
            DispatchQueue.main.async {
                self?.audioChunksPlayed += 1
            }
        }

        hasScheduledAudio = true

        if audioChunksReceived % 10 == 1 {
            print("[GeminiAudio] Audio chunk #\(audioChunksReceived): \(audioData.count) bytes, \(frameCount) frames")
        }
    }

    /// Interrupt current playback (when user starts speaking - barge-in)
    func interrupt() {
        bufferLock.lock()

        // Stop the player node to clear all scheduled buffers
        playerNode?.stop()
        hasScheduledAudio = false

        // Restart player node to be ready for new audio
        playerNode?.play()

        bufferLock.unlock()

        print("[GeminiAudio] Playback interrupted (barge-in)")
    }

    /// Check if there's audio currently playing or scheduled
    var isCurrentlyPlaying: Bool {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return hasScheduledAudio
    }

    // MARK: - Private Methods

    private func checkPlaybackComplete() {
        bufferLock.lock()
        // Check if there are no more scheduled buffers
        // This is a simplified check - in practice you might want more sophisticated tracking
        bufferLock.unlock()
    }

    // MARK: - Deinitialization

    deinit {
        stop()
    }
}

// MARK: - Audio Format Utilities

extension GeminiAudioPlayer {

    /// Get current audio route description
    var currentRoute: String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        if let bluetoothOutput = outputs.first(where: {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }) {
            return "Bluetooth: \(bluetoothOutput.portName)"
        } else if let output = outputs.first {
            return output.portName
        }
        return "Unknown"
    }

    /// Check if audio is routed to Bluetooth
    var isBluetoothConnected: Bool {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.contains {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP
        }
    }
}
