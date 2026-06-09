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
import Photos
import MWDATCore
import MWDATCamera

/// Manager for Meta smart glasses connection and document scanning
@MainActor
class WearablesManager: ObservableObject {
    static let shared = WearablesManager()

    // MARK: - Published Properties

    @Published var registrationStateDescription: String = "Unknown"
    @Published var cameraStatus: String? = nil
    @Published var streamState: StreamSessionState = .stopped
    @Published var latestFrameImage: UIImage? = nil
    @Published var deviceStatus: String = "No device"

    // MARK: - Photo Capture Properties

    /// Whether a photo capture is in progress
    @Published var isCapturingPhoto: Bool = false

    /// The latest captured high-resolution photo
    @Published var capturedPhoto: UIImage? = nil

    // MARK: - Document Reader

    @Published var latestDocumentResult: DocumentReadingResult?

    /// Document reader processor instance
    let documentReaderProcessor = DocumentReaderProcessor()

    // MARK: - Private Properties

    private var registrationTask: Task<Void, Never>?
    private var frameToken: AnyListenerToken?
    private var stateToken: AnyListenerToken?
    private var errorToken: AnyListenerToken?
    private var photoToken: AnyListenerToken?
    private let deviceSelector: AutoDeviceSelector
    private var streamSession: StreamSession?

    /// Completion handler for photo capture
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    // Combine subscriptions
    private var documentResultCancellable: AnyCancellable?

    private init() {
        deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        setupDocumentReaderSubscriptions()
        Task {
            await refreshRegistrationState()
            await monitorDevices()
        }
    }

    /// Set up Combine subscriptions for document reader results
    private func setupDocumentReaderSubscriptions() {
        documentResultCancellable = documentReaderProcessor.$latestResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.latestDocumentResult = result
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
            print("Failed to get camera status \(error)")
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

    /// Start streaming from Meta glasses
    func startStream() {
        stopStream()

        print("[WearablesManager] Starting stream...")
        print("[WearablesManager] Registration state: \(registrationStateDescription)")
        print("[WearablesManager] Device status: \(deviceStatus)")

        let session = StreamSession(deviceSelector: deviceSelector)
        streamSession = session

        stateToken = session.statePublisher.listen { [weak self] (state: StreamSessionState) in
            guard let self = self else { return }
            Task { @MainActor in
                self.streamState = state
            }
        }

        errorToken = session.errorPublisher.listen { (error: StreamSessionError) in
            print("[WearablesManager] Stream error: \(error)")
        }

        frameToken = session.videoFramePublisher.listen { [weak self] (frame: VideoFrame) in
            guard let self = self else { return }
            Task { @MainActor in
                self.latestFrameImage = frame.makeUIImage()
                // Pass frame to document processor if scanning
                if let frameImage = self.latestFrameImage {
                    self.documentReaderProcessor.updateFrame(frameImage)
                }
            }
        }

        // Listen for photo captures (high resolution still images)
        photoToken = session.photoDataPublisher.listen { [weak self] photoData in
            guard let self = self else { return }
            Task { @MainActor in
                let image = UIImage(data: photoData.data)
                self.capturedPhoto = image
                self.isCapturingPhoto = false

                if let image = image {
                    print("[WearablesManager] Photo captured: \(image.size.width)x\(image.size.height)")
                    // Call completion handler if set
                    self.photoCaptureCompletion?(image)
                    self.photoCaptureCompletion = nil
                } else {
                    print("[WearablesManager] Failed to create image from photo data")
                    self.photoCaptureCompletion?(nil)
                    self.photoCaptureCompletion = nil
                }
            }
        }

        Task {
            await session.start()
        }
    }

    /// Stop streaming
    func stopStream() {
        guard streamSession != nil else { return }

        let session = streamSession
        let frame = frameToken
        let state = stateToken
        let error = errorToken
        let photo = photoToken

        Task {
            await frame?.cancel()
            await state?.cancel()
            await error?.cancel()
            await photo?.cancel()
            await session?.stop()
        }

        frameToken = nil
        stateToken = nil
        errorToken = nil
        photoToken = nil
        streamSession = nil
        streamState = .stopped
        latestFrameImage = nil
        capturedPhoto = nil
        isCapturingPhoto = false
        photoCaptureCompletion = nil
        documentReaderProcessor.reset()
    }

    // MARK: - Photo Capture

    /// Capture a high-resolution still photo from the glasses
    /// - Parameter completion: Called with the captured image, or nil if capture failed
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let session = streamSession else {
            print("[WearablesManager] No active stream session for photo capture")
            completion(nil)
            return
        }

        guard !isCapturingPhoto else {
            print("[WearablesManager] Photo capture already in progress")
            return
        }

        isCapturingPhoto = true
        photoCaptureCompletion = completion

        print("[WearablesManager] Requesting photo capture...")
        session.capturePhoto(format: .jpeg)
    }

    /// Capture a high-resolution photo and return it asynchronously.
    /// Resolves to `nil` if no photo arrives within `timeout` seconds, so callers
    /// (e.g. Shortcuts intents) never hang on a dropped capture.
    func capturePhotoAsync(timeout: TimeInterval = 10) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let finish: (UIImage?) -> Void = { image in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }

            capturePhoto(completion: finish)

            // Safety net: if the photo data publisher never fires, recover.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard !didResume else { return }
                self?.isCapturingPhoto = false
                self?.photoCaptureCompletion = nil
                finish(nil)
            }
        }
    }

    // MARK: - Document Scanning

    /// Capture a high-resolution photo and process it for document scanning
    /// This uses the photo capture API for much better OCR accuracy
    func captureDocumentPhoto() {
        guard streamSession != nil else {
            print("[WearablesManager] No active stream session")
            return
        }

        capturePhoto { [weak self] image in
            guard let self = self, let image = image else {
                print("[WearablesManager] Photo capture failed")
                self?.documentReaderProcessor.errorMessage = "Photo capture failed"
                return
            }
            print("[WearablesManager] Processing high-res photo for OCR: \(image.size.width)x\(image.size.height)")
            self.documentReaderProcessor.captureAndProcess(image)
        }
    }

    /// Capture and process the current video frame for document scanning (legacy - lower resolution)
    func captureDocument() {
        guard let frameImage = latestFrameImage else {
            print("[WearablesManager] No frame available for capture")
            return
        }
        documentReaderProcessor.captureAndProcess(frameImage)
    }

    /// Reset document reader state
    func resetDocumentReader() {
        documentReaderProcessor.reset()
        latestDocumentResult = nil
    }

    /// Whether glasses are connected and streaming
    var isGlassesConnected: Bool {
        streamState == .streaming
    }
}
