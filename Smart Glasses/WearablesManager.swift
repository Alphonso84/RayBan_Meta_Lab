//
//  WearablesManager.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import Vision
import Photos
import MWDATCore
import MWDATCamera

// MARK: - Streaming Mode
enum StreamingMode: String, CaseIterable, Identifiable {
    case liveView = "Live View"
    case objectDetection = "Object Detection"
    case textReader = "Text Reader"
    case aiAssistant = "AI Assistant"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .liveView: return "video.fill"
        case .objectDetection: return "viewfinder"
        case .textReader: return "doc.text.viewfinder"
        case .aiAssistant: return "sparkles"
        }
    }

    var description: String {
        switch self {
        case .liveView: return "View live stream only"
        case .objectDetection: return "Detect objects using Vision"
        case .textReader: return "Read text with OCR"
        case .aiAssistant: return "AI describes your view"
        }
    }
}

@MainActor
class WearablesManager: ObservableObject {
    static let shared = WearablesManager()

    // MARK: - Published Properties
    @Published var registrationStateDescription: String = "Unknown"
    @Published var cameraStatus: String? = nil
    @Published var streamState: StreamSessionState = .stopped
    @Published var latestFrameImage: UIImage? = nil
    @Published var lastCapturedPhoto: UIImage? = nil
    @Published var isRecording: Bool = false
    @Published var lastRecordedVideoURL: URL? = nil
    @Published var deviceStatus: String = "No device"
    @Published var currentMode: StreamingMode = .liveView
    @Published var photoSaveStatus: String? = nil

    // MARK: - Object Detection
    @Published var latestDetectionResult: DetectionResult?
    @Published var isDetectionProcessing: Bool = false

    /// Object detection processor instance
    let objectDetectionProcessor = ObjectDetectionProcessor()

    // MARK: - Private Properties
    private var registrationTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var frameToken: AnyListenerToken?
    private var photoToken: AnyListenerToken?
    private var stateToken: AnyListenerToken?
    private var errorToken: AnyListenerToken?
    private let deviceSelector: AutoDeviceSelector
    private var streamSession: StreamSession?

    // Video recording properties
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var recordingStartTime: CMTime?

    // Combine subscriptions
    private var detectionResultCancellable: AnyCancellable?
    private var detectionProcessingCancellable: AnyCancellable?
    private var modeCancellable: AnyCancellable?
    private var streamStateCancellable: AnyCancellable?

    /// Gemini Live manager for AI Assistant mode
    let geminiLiveManager = GeminiLiveManager.shared

    private init() {
        deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        setupDetectionSubscriptions()
        setupModeChangeObserver()
        setupStreamStateObserver()
        Task {
            await refreshRegistrationState()
            await monitorDevices()
        }
    }

    /// Set up observer for mode changes to auto-start/stop Gemini
    private func setupModeChangeObserver() {
        modeCancellable = $currentMode
            .dropFirst()  // Skip initial value
            .sink { [weak self] newMode in
                guard let self = self else { return }

                Task { @MainActor in
                    if newMode == .aiAssistant {
                        // Start Gemini session when entering AI Assistant mode
                        if self.streamState == .streaming {
                            self.geminiLiveManager.startSession()
                        }
                    } else {
                        // End session when leaving AI Assistant mode
                        self.geminiLiveManager.endSession()
                    }
                }
            }
    }

    /// Set up observer for stream state changes
    private func setupStreamStateObserver() {
        streamStateCancellable = $streamState
            .sink { [weak self] state in
                guard let self = self, self.currentMode == .aiAssistant else { return }

                Task { @MainActor in
                    if state == .streaming {
                        // Auto-start Gemini when stream becomes active in AI mode
                        if self.geminiLiveManager.state == .disconnected {
                            self.geminiLiveManager.startSession()
                        }
                    } else if state == .stopped {
                        // End session when streaming stops
                        self.geminiLiveManager.endSession()
                    }
                }
            }
    }

    /// Set up Combine subscriptions for object detection results
    private func setupDetectionSubscriptions() {
        // Subscribe to detection results
        detectionResultCancellable = objectDetectionProcessor.$latestResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.latestDetectionResult = result
            }

        // Subscribe to processing state
        detectionProcessingCancellable = objectDetectionProcessor.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                self?.isDetectionProcessing = isProcessing
            }
    }

    private func monitorDevices() async {
        for await deviceId in deviceSelector.activeDeviceStream() {
            if let id = deviceId {
                deviceStatus = "Connected: \(id)"
                print("Device connected: \(id)")
            } else {
                deviceStatus = "No device"
                print("No device connected")
            }
        }
    }

    /// Gets the currently active device, if any
    private func getActiveDevice() -> Device? {
        guard let deviceId = deviceSelector.activeDevice else { return nil }
        return Wearables.shared.deviceForIdentifier(deviceId)
    }

    // MARK: - Registration
    func startRegistration() {
        registrationTask?.cancel()
        registrationTask = Task {
            do {
                try await Wearables.shared.startRegistration()
                await refreshRegistrationState()
            } catch {
                registrationStateDescription = "Registration failed: \(error.localizedDescription)"
            }
        }
    }

    func startUnregistration() {
        registrationTask?.cancel()
        registrationTask = Task {
            do {
                try await Wearables.shared.startUnregistration()
                await refreshRegistrationState()
            } catch {
                registrationStateDescription = "Unregistration failed: \(error.localizedDescription)"
            }
        }
    }

    func refreshRegistrationState() async {
        let state = Wearables.shared.registrationState
        switch state {
        case .unavailable:
            registrationStateDescription = "Unavailable"
        case .available:
            registrationStateDescription = "Available (Not Registered)"
        case .registering:
            registrationStateDescription = "Registering..."
        case .registered:
            registrationStateDescription = "Registered"
        @unknown default:
            registrationStateDescription = "Unknown state"
        }
    }

    // MARK: - Camera Permissions
    func refreshCameraPermissionStatus() async {
        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            cameraStatus = String(describing: status)
        } catch {
            cameraStatus = "Error: \(error.localizedDescription)"
            print("Failed to fetch camera status: \(error)")
        }
    }

    func requestCameraPermission() async {
        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            cameraStatus = String(describing: status)
        } catch {
            print("Failed to request camera permission: \(error)")
        }
    }

    // MARK: - Streaming
    func startStream() {
        // Cancel any existing stream first
        stopStream()

        // Create a new StreamSession with our device selector
        let session = StreamSession(deviceSelector: deviceSelector)
        streamSession = session
        // Subscribe to state changes
        stateToken = session.statePublisher.listen { [weak self] (state: StreamSessionState) in
            guard let self = self else { return }
            Task { @MainActor in
                print("Stream state changed to: \(state)")
                self.streamState = state
            }
        }

        // Subscribe to errors
        errorToken = session.errorPublisher.listen { (error: StreamSessionError) in
            print("Stream error: \(error)")
        }

        // Subscribe to video frames
        frameToken = session.videoFramePublisher.listen { [weak self] (frame: VideoFrame) in
            guard let self = self else { return }
            Task { @MainActor in
                self.latestFrameImage = frame.makeUIImage()
                self.handleVideoFrame(frame)
            }
        }

        // Subscribe to photo captures
        photoToken = session.photoDataPublisher.listen { [weak self] (photoData: PhotoData) in
            guard let self = self else { return }
            Task { @MainActor in
                if let image = UIImage(data: photoData.data) {
                    self.lastCapturedPhoto = image
                    // Save to camera roll
                    self.savePhotoToCameraRoll(image)
                }
            }
        }

        // Start the stream
        Task {
            await session.start()
        }
    }

    func stopStream() {
        guard streamSession != nil else { return }

        let session = streamSession
        let frame = frameToken
        let photo = photoToken
        let state = stateToken
        let error = errorToken

        Task {
            await frame?.cancel()
            await photo?.cancel()
            await state?.cancel()
            await error?.cancel()
            await session?.stop()
        }

        frameToken = nil
        photoToken = nil
        stateToken = nil
        errorToken = nil
        streamSession = nil
        streamState = .stopped
        latestFrameImage = nil

        // Reset detection state
        resetDetection()
    }

    // MARK: - Photo Capture
    func capturePhoto() {
        guard let session = streamSession else {
            print("No active stream session - start streaming first")
            return
        }

        photoSaveStatus = nil  // Reset status
        let success = session.capturePhoto(format: .jpeg)
        if !success {
            print("Failed to initiate photo capture")
            photoSaveStatus = "Failed to capture"
        }
    }

    /// Save a photo to the camera roll
    private func savePhotoToCameraRoll(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            Task { @MainActor in
                guard let self = self else { return }

                switch status {
                case .authorized, .limited:
                    self.performSavePhoto(image)
                case .denied, .restricted:
                    self.photoSaveStatus = "Photo access denied"
                    print("Photo library access denied")
                case .notDetermined:
                    self.photoSaveStatus = "Permission not determined"
                @unknown default:
                    self.photoSaveStatus = "Unknown permission status"
                }
            }
        }
    }

    private func performSavePhoto(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: image.jpegData(compressionQuality: 0.9)!, options: nil)
            request.creationDate = Date()
        } completionHandler: { [weak self] success, error in
            Task { @MainActor in
                guard let self = self else { return }

                if success {
                    self.photoSaveStatus = "Saved to Photos"
                    print("Photo saved to camera roll")

                    // Clear status after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.photoSaveStatus = nil
                    }
                } else {
                    self.photoSaveStatus = "Failed to save"
                    print("Failed to save photo: \(error?.localizedDescription ?? "unknown error")")
                }
            }
        }
    }

    // MARK: - Video Recording
    func startRecording() {
        guard streamSession != nil, streamState == .streaming || streamState == .paused else {
            print("Must be streaming to record video")
            return
        }

        guard !isRecording else {
            print("Already recording")
            return
        }

        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let fileName = "video_\(dateFormatter.string(from: Date())).mp4"
            let outputURL = documentsPath.appendingPathComponent(fileName)

            // Remove existing file if needed
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720
            ]

            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true

            if let input = assetWriterInput, assetWriter?.canAdd(input) == true {
                assetWriter?.add(input)
            }

            assetWriter?.startWriting()
            recordingStartTime = nil
            isRecording = true
            lastRecordedVideoURL = outputURL

            print("Started recording to: \(outputURL.path)")

        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false

        assetWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = self.assetWriter?.error {
                    print("Recording finished with error: \(error)")
                } else {
                    print("Recording saved to: \(self.lastRecordedVideoURL?.path ?? "unknown")")
                }
                self.assetWriter = nil
                self.assetWriterInput = nil
                self.recordingStartTime = nil
            }
        }
    }

    private func handleVideoFrame(_ frame: VideoFrame) {
        let sampleBuffer = frame.sampleBuffer

        // Process for object detection if in that mode
        if currentMode == .objectDetection {
            objectDetectionProcessor.processFrame(sampleBuffer)
        }

        // Process for AI Assistant mode (Gemini Live)
        if currentMode == .aiAssistant {
            geminiLiveManager.processFrame(sampleBuffer)
        }

        // Handle recording separately (can record while detecting)
        guard isRecording,
              let writer = assetWriter,
              let input = assetWriterInput,
              writer.status == .writing,
              input.isReadyForMoreMediaData else {
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Start the session on first frame
        if recordingStartTime == nil {
            recordingStartTime = timestamp
            writer.startSession(atSourceTime: timestamp)
        }

        input.append(sampleBuffer)
    }

    /// Reset object detection state
    func resetDetection() {
        objectDetectionProcessor.reset()
        latestDetectionResult = nil
    }
}
