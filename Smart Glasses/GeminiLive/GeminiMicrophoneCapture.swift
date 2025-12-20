//
//  GeminiMicrophoneCapture.swift
//  Smart Glasses
//
//  Captures microphone audio in 16-bit PCM at 16kHz for Gemini Live API
//

import AVFoundation

// MARK: - Delegate Protocol

protocol GeminiMicrophoneCaptureDelegate: AnyObject {
    func microphoneDidCapture(audioData: Data)
    func microphoneDidFail(error: Error)
}

// MARK: - Microphone Capture

class GeminiMicrophoneCapture {

    // MARK: - Properties

    weak var delegate: GeminiMicrophoneCaptureDelegate?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var converter: AVAudioConverter?

    private let targetSampleRate: Double = 16000
    private let bufferSize: AVAudioFrameCount = 1024

    private(set) var isCapturing = false

    // Accumulator for chunking audio data
    private var audioBuffer = Data()
    private let chunkInterval: TimeInterval = 0.1  // Send every 100ms
    private var lastChunkTime = CACurrentMediaTime()
    private let bufferLock = NSLock()

    // Target format: 16-bit PCM, 16kHz, mono
    private lazy var targetFormat: AVAudioFormat? = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )
    }()

    // MARK: - Public Methods

    func startCapturing() throws {
        guard !isCapturing else {
            print("[GeminiMic] Already capturing")
            return
        }

        // Audio session is configured by GeminiLiveManager before calling this

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw GeminiError.microphoneError("Failed to create audio engine")
        }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            throw GeminiError.microphoneError("Failed to get input node")
        }

        // Get the native input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[GeminiMic] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        guard let targetFormat = targetFormat else {
            throw GeminiError.microphoneError("Failed to create target format")
        }

        // Create converter if sample rate differs
        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            if converter == nil {
                throw GeminiError.microphoneError("Failed to create audio converter")
            }
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        try audioEngine.start()
        isCapturing = true
        lastChunkTime = CACurrentMediaTime()

        print("[GeminiMic] Started capturing at \(inputFormat.sampleRate)Hz, converting to \(targetSampleRate)Hz")
    }

    func stopCapturing() {
        guard isCapturing else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        converter = nil
        isCapturing = false

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        print("[GeminiMic] Stopped capturing")
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        var pcmData: Data

        if let converter = converter, let targetFormat = targetFormat {
            // Convert to target format (16kHz mono)
            guard let convertedBuffer = convertBuffer(buffer, using: converter, targetFormat: targetFormat) else {
                return
            }
            pcmData = bufferToData(convertedBuffer)
        } else {
            // Already in correct format
            pcmData = bufferToData(buffer)
        }

        // Accumulate data
        bufferLock.lock()
        audioBuffer.append(pcmData)
        bufferLock.unlock()

        // Check if it's time to send a chunk
        let currentTime = CACurrentMediaTime()
        if currentTime - lastChunkTime >= chunkInterval {
            sendAccumulatedAudio()
            lastChunkTime = currentTime
        }
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer,
                               using converter: AVAudioConverter,
                               targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Calculate output frame count based on sample rate ratio
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        var inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, error == nil else {
            print("[GeminiMic] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    private func sendAccumulatedAudio() {
        bufferLock.lock()
        guard !audioBuffer.isEmpty else {
            bufferLock.unlock()
            return
        }
        let dataToSend = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        delegate?.microphoneDidCapture(audioData: dataToSend)
    }

    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.int16ChannelData else {
            // If not int16, try to get float data and convert
            if let floatData = buffer.floatChannelData {
                return convertFloatToInt16Data(floatData[0], frameLength: Int(buffer.frameLength))
            }
            return Data()
        }

        let frameLength = Int(buffer.frameLength)
        return Data(bytes: channelData[0], count: frameLength * 2)  // 2 bytes per Int16
    }

    private func convertFloatToInt16Data(_ floatPointer: UnsafeMutablePointer<Float>,
                                         frameLength: Int) -> Data {
        var int16Data = [Int16](repeating: 0, count: frameLength)

        for i in 0..<frameLength {
            // Clamp float value to [-1, 1] and convert to Int16 range
            let clampedValue = max(-1.0, min(1.0, floatPointer[i]))
            int16Data[i] = Int16(clampedValue * Float(Int16.max))
        }

        return Data(bytes: &int16Data, count: frameLength * 2)
    }
}
