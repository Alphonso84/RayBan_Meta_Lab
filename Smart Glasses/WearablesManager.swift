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

    /// Live registration state, kept in sync by `registrationStateStream()`.
    /// Prefer this (or `isRegistered`) over string-matching `registrationStateDescription`.
    @Published private(set) var registrationState: RegistrationState = .unavailable
    @Published private(set) var registrationStateDescription: String = "Unknown"

    /// Last registration/unregistration failure, if any. Cleared once the SDK
    /// reports a new state, since the stream is the source of truth.
    @Published var registrationErrorMessage: String? = nil

    @Published var cameraStatus: String? = nil

    /// Whether the glasses camera permission is blocking streaming.
    ///
    /// Without this the app retries a refused session forever and shows only
    /// "Waiting for glasses", which is what made a revoked permission take an
    /// afternoon to identify — the SDK reports every refusal as the same
    /// opaque "Device unavailable".
    @Published private(set) var needsCameraPermission: Bool = false
    @Published var streamState: StreamState = .stopped
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

    private var registrationObservationTask: Task<Void, Never>?
    private var frameToken: (any AnyListenerToken)?
    private var stateToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?
    private var photoToken: (any AnyListenerToken)?
    private var sessionErrorToken: (any AnyListenerToken)?
    private let deviceSelector: AutoDeviceSelector

    /// The device session, the camera capability it owns, and that camera's stream.
    ///
    /// Since SDK 0.9.0 these are three separate objects with a strict ordering:
    /// the session must reach `.started` before a camera can be added, and the
    /// camera owns the stream. Stopping the camera cascades to the stream.
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var stream: MWDATCamera.Stream?

    /// Tracks the in-flight `startStream()` so `stopStream()` can cancel a start
    /// that is still waiting for the device session to come up.
    private var startTask: Task<Void, Never>?

    /// Set while the camera is being rebuilt after a still capture.
    @Published private(set) var isRebuildingCamera = false

    private var rebuildHoldTimeout: Task<Void, Never>?

    /// When the last frame arrived. Only used to tell "video is flowing" from
    /// "video has stalled" — the stream's own state cannot, because it goes on
    /// reporting `.streaming` after the glasses stop sending.
    private var lastFrameAt: Date?

    /// Completion handler for photo capture
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    // Combine subscriptions
    private var documentResultCancellable: AnyCancellable?

    private init() {
        deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        setupDocumentReaderSubscriptions()
        refreshRegistrationState()
        observeRegistrationState()
        // monitorDevices() never returns, so it gets its own task.
        Task { await monitorDevices() }
    }

    /// Registration completes asynchronously — the user approves in the Meta AI app and
    /// the result arrives later via `handleUrl`. Observe the stream so state stays live
    /// instead of only being sampled right after `startRegistration()` returns.
    private func observeRegistrationState() {
        registrationObservationTask?.cancel()
        registrationObservationTask = Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                guard let self = self else { return }
                self.apply(registrationState: state)
                if state == .registered {
                    self.registrationErrorMessage = nil
                }
            }
        }
    }

    private func apply(registrationState state: RegistrationState) {
        registrationState = state
        registrationStateDescription = Self.describe(state)
    }

    private static func describe(_ state: RegistrationState) -> String {
        switch state {
        case .unavailable: return "Unavailable"
        case .available: return "Available (Not Registered)"
        case .registering: return "Registering..."
        case .registered: return "Registered"
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

    /// Launches the Meta AI approval flow. This returns as soon as Meta AI is opened —
    /// the actual state change arrives later on the registration stream, so don't
    /// sample `registrationState` immediately after calling this.
    ///
    /// The SDK call is `async`, but this stays synchronous so the SwiftUI button
    /// actions that call it are unchanged — the real state change arrives on the
    /// registration stream regardless of when this returns.
    func startRegistration() {
        registrationErrorMessage = nil
        Task {
            do {
                try await Wearables.shared.startRegistration()
            } catch {
                registrationErrorMessage = "Registration failed: \(error)"
            }
            refreshRegistrationState()
        }
    }

    func startUnregistration() {
        registrationErrorMessage = nil
        Task {
            do {
                try await Wearables.shared.startUnregistration()
            } catch {
                registrationErrorMessage = "Unregistration failed: \(error)"
            }
            refreshRegistrationState()
        }
    }

    /// Re-syncs from the SDK's current value. The stream in `observeRegistrationState()`
    /// keeps this current; this exists for views that want an explicit refresh on appear.
    func refreshRegistrationState() {
        apply(registrationState: Wearables.shared.registrationState)
    }

    /// Whether the app is registered with Meta AI.
    var isRegistered: Bool {
        registrationState == .registered
    }

    // MARK: - Camera Permissions

    @discardableResult
    func refreshCameraPermissionStatus() async -> Bool {
        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            apply(permissionStatus: status)
            return status == .granted
        } catch {
            cameraStatus = "Error: \(error.localizedDescription)"
            print("Failed to get camera status \(error)")
            return false
        }
    }

    @discardableResult
    func requestCameraPermission() async -> Bool {
        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            apply(permissionStatus: status)
            return status == .granted
        } catch {
            print("Failed to request camera permission: \(error)")
            return false
        }
    }

    private func apply(permissionStatus status: PermissionStatus) {
        cameraStatus = String(describing: status)
        needsCameraPermission = status != .granted
    }

    /// Whether a refused permission should stop us attempting a session.
    ///
    /// Only a definitive answer blocks the attempt. Failing to *read* the
    /// status is not proof of denial, and trying anyway produces a better
    /// diagnosis than refusing to try.
    private func cameraPermissionBlocksStreaming() async -> Bool {
        guard let status = try? await Wearables.shared.checkPermissionStatus(.camera) else {
            return false
        }
        apply(permissionStatus: status)
        return status != .granted
    }

    // MARK: - Streaming

    /// What the live preview is being used for, which decides how much
    /// bandwidth it is worth.
    enum PreviewQuality {
        /// The preview is a viewfinder. A still is captured for the real work,
        /// so it only has to be good enough to frame a page and find its edges.
        case framing

        /// The preview *is* the data — barcode mode reads codes straight from
        /// these frames and never captures a still, so detail matters.
        case detail
    }

    @Published private(set) var previewQuality: PreviewQuality = .framing

    /// Video configuration for the live preview.
    ///
    /// Resolution is the whole reason this is not a constant. Taking a still
    /// while streaming at `.medium` ends video on the glasses and it never comes
    /// back — measured on device, frames stop at the capture while `Stream.state`
    /// goes on reporting `.streaming`. At `.low` it does not happen at all.
    ///
    /// The likely mechanism is bandwidth arbitration: MWDATCore runs a
    /// multi-transport link-lease layer (`_highLinkLeases` / `_mediumLinkLeases`
    /// / `_lowLinkLeases`, `AutomaticLinkSwitcher`, "No more lease left.
    /// Disconnecting BTC.") added with the Wi-Fi transport in SDK 0.8.0. A photo
    /// transfer appears to force a renegotiation that drops the video link, and
    /// only at low bitrate is there enough headroom to avoid it. Meta's own
    /// CameraAccess sample streams at `.low`, which is presumably why it never
    /// trips over this.
    ///
    /// The codec is deliberately raw. HEVC (`.hvc1`) was tried, on the theory
    /// that a different media pipeline might survive a capture: it does not work
    /// here, because the frames are compressed, `VideoFrame.makeUIImage()`
    /// returns nil for them, and the preview receives no image at all while the
    /// stream reports `.streaming`. Meta's sample uses `.hvc1` and ships its own
    /// `VideoFrameDecoder` for exactly this reason.
    private var streamConfiguration: StreamConfiguration {
        StreamConfiguration(
            videoCodec: .raw,
            resolution: previewQuality == .detail ? .medium : .low,
            frameRate: 24
        )
    }

    /// Match preview quality to what a capture mode needs.
    ///
    /// Only barcode mode reads the preview itself; the others capture a still,
    /// and at anything above `.low` that capture kills video. So the modes that
    /// capture cannot afford detail, and the mode that needs detail never
    /// captures.
    func matchPreviewQuality(to mode: CaptureMode) {
        setPreviewQuality(mode == .barcode ? .detail : .framing)
    }

    private func setPreviewQuality(_ quality: PreviewQuality) {
        guard quality != previewQuality else { return }
        previewQuality = quality

        // Configuration is fixed when the camera is added, so a change only
        // takes effect on a new one.
        guard deviceSession != nil else { return }

        print("[WearablesManager] Preview quality changed; rebuilding camera")
        rebuildCameraHoldingLastFrame()
    }

    /// Start streaming from Meta glasses.
    ///
    /// Stays synchronous for its callers, but the work behind it is not: since
    /// SDK 0.9.0 the device session has to reach `.started` before a camera can
    /// be added, so the handshake runs in `startTask`.
    func startStream() {
        stopStream()

        print("[WearablesManager] Starting stream...")
        print("[WearablesManager] Registration state: \(registrationStateDescription)")
        print("[WearablesManager] Device status: \(deviceStatus)")

        // No `Stream` exists yet, but the UI is already waiting on the glasses —
        // report that rather than leaving the state at `.stopped`.
        streamState = .waitingForDevice

        startTask = Task { [weak self] in
            await self?.openCameraSession()
        }
    }

    /// How long to wait before rebuilding a device session that would not start.
    ///
    /// Indexed by consecutive failures, so a momentary miss retries almost at
    /// once while genuinely absent glasses settle into a slow poll.
    private static let retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(3), .seconds(5)]

    /// Keep a camera session up for as long as the caller wants one.
    ///
    /// A device session is single-use: once it reaches `.stopped` it is terminal
    /// and a new one has to be built. It also routinely fails to start for
    /// transient reasons — entering the Scan tab while the glasses are still
    /// completing their accessory handshake reports "Device unavailable" — and
    /// the glasses can drop out later by being doffed or folded.
    ///
    /// So this retries rather than attempting once. The previous SDK's
    /// `StreamSession` absorbed all of this internally; the explicit `Camera`
    /// lifecycle does not, and a single attempt leaves the tab dead until the
    /// user navigates away and back.
    ///
    /// The loop lives as long as `startTask`, which `stopStream()` cancels, so
    /// it only ever runs while something actually wants the camera.
    private func openCameraSession() async {
        var consecutiveFailures = 0


        while !Task.isCancelled {
            // Re-checked every pass so that granting permission from the banner
            // this raises recovers on its own, with no need to leave the tab.
            if await cameraPermissionBlocksStreaming() {
                streamState = .stopped
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            let didStream = await runCameraSession()

            guard !Task.isCancelled else { return }

            // A session that streamed and then ended is not a failure — the
            // glasses were simply taken off, or a capture forced a rebuild — so
            // it reconnects immediately rather than sitting through a backoff.
            if didStream {
                consecutiveFailures = 0
                // Report the reconnect rather than leaving the stream's final
                // `.stopped`, which would offer a "Start Stream" button over a
                // stream that is already coming back.
                streamState = .waitingForDevice
                continue
            } else {
                consecutiveFailures += 1
                // The SDK reports only "Device unavailable" for every refused
                // start, so on the first failure dump the things it *will*
                // answer. Camera permission and device compatibility are both
                // invisible otherwise: registration, connection and link state
                // all keep reporting healthy while the session refuses.
                if consecutiveFailures == 1 {
                    await logStartDiagnostics()
                }
            }

            streamState = .waitingForDevice

            let index = min(max(consecutiveFailures - 1, 0), Self.retryDelays.count - 1)
            try? await Task.sleep(for: Self.retryDelays[index])
        }
    }

    /// Everything the SDK will tell us about why a session would not start.
    private func logStartDiagnostics() async {
        await refreshCameraPermissionStatus()
        print("[WearablesManager] Camera permission: \(cameraStatus ?? "unknown")")

        guard let id = deviceSelector.activeDevice else {
            print("[WearablesManager] No device selected")
            return
        }
        guard let device = Wearables.shared.deviceForIdentifier(id) else {
            print("[WearablesManager] Selected device \(id) could not be resolved")
            return
        }

        print("""
        [WearablesManager] Device \(device.nameOrId()) \
        type=\(device.deviceType().rawValue) \
        link=\(device.linkState) \
        compatibility=\(device.compatibility().displayString) \
        supportsDisplay=\(device.supportsDisplay())
        """)
    }

    /// Build one device session and run it until it ends.
    ///
    /// - Returns: whether the camera was actually attached, which distinguishes
    ///   "the glasses were not there" from "the glasses went away again".
    private func runCameraSession() async -> Bool {
        let session: DeviceSession
        do {
            session = try Wearables.shared.createSession(deviceSelector: deviceSelector)
            try session.start()
        } catch {
            print("[WearablesManager] Could not start device session: \(error)")
            deviceStatus = error.description
            return false
        }

        deviceSession = session

        sessionErrorToken = session.errorPublisher.listen { (error: DeviceSessionError) in
            // Thermal, battery and required-update conditions arrive here, and
            // they are usually the real reason a session stops.
            print("[WearablesManager] Device session error: \(error)")
        }

        var didAttach = false

        // One pass over the session's lifetime: attach the camera when it comes
        // up, and fall out when it ends. The stream finishes on `.stopped`, so
        // this cannot outlive the session it is watching.
        for await state in session.stateStream() {
            if Task.isCancelled { break }

            if state == .started, !didAttach {
                didAttach = attachCamera(to: session)
                if !didAttach { break }
            }
        }

        teardownSession()
        return didAttach
    }

    /// Add the camera capability to a started session and begin streaming.
    private func attachCamera(to session: DeviceSession) -> Bool {
        let camera: Camera
        do {
            guard let attached = try session.addCamera(config: streamConfiguration) else {
                print("[WearablesManager] Camera unavailable on this device")
                return false
            }
            camera = attached
        } catch {
            print("[WearablesManager] Could not add camera: \(error)")
            deviceStatus = error.description
            return false
        }

        self.camera = camera
        let stream = camera.stream
        self.stream = stream

        let active = stream.streamConfiguration
        print("[WearablesManager] Streaming \(active.resolution) \(active.resolution.videoFrameSize) at \(active.frameRate)fps")

        stateToken = stream.statePublisher.listen { [weak self] (state: StreamState) in
            print("[WearablesManager] Stream state: \(state)")
            guard let self else { return }
            Task { @MainActor in
                self.streamState = state
            }
        }

        errorToken = stream.errorPublisher.listen { (error: StreamError) in
            print("[WearablesManager] Stream error: \(error)")
        }

        frameToken = stream.videoFramePublisher.listen { [weak self] (frame: VideoFrame) in
            guard let self, let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self.lastFrameAt = Date()

                if self.isRebuildingCamera {
                    // Frames are back; stop holding and go live again.
                    self.isRebuildingCamera = false
                    self.rebuildHoldTimeout?.cancel()
                    self.rebuildHoldTimeout = nil
                }
                self.latestFrameImage = image
                // Pass frame to document processor if scanning
                self.documentReaderProcessor.updateFrame(image)
            }
        }

        // Listen for photo captures (high resolution still images)
        photoToken = stream.photoDataPublisher.listen { [weak self] (photoData: PhotoData) in
            guard let self else { return }
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

        stream.start()
        print("[WearablesManager] Camera attached, stream started")
        return true
    }

    /// Stop streaming
    func stopStream() {
        startTask?.cancel()
        startTask = nil
        rebuildHoldTimeout?.cancel()
        rebuildHoldTimeout = nil
        isRebuildingCamera = false

        teardownSession()

        streamState = .stopped
        latestFrameImage = nil
        capturedPhoto = nil
        isCapturingPhoto = false
        photoCaptureCompletion = nil
        documentReaderProcessor.reset()
    }

    /// Release the camera and device session and drop every listener.
    ///
    /// The camera is stopped first and synchronously: that halts delivery at the
    /// source, so no frame can land after the published state has been cleared.
    /// Token cancellation is `async` and only tidies up afterwards.
    private func teardownSession() {
        camera?.stop()      // cascades to the stream it owns
        deviceSession?.stop()

        let tokens = [frameToken, stateToken, errorToken, photoToken, sessionErrorToken]
            .compactMap { $0 }

        stream = nil
        camera = nil
        deviceSession = nil
        frameToken = nil
        stateToken = nil
        errorToken = nil
        photoToken = nil
        sessionErrorToken = nil

        guard !tokens.isEmpty else { return }
        Task {
            for token in tokens {
                await token.cancel()
            }
        }
    }

    // MARK: - Photo Capture

    /// Bring video back if it has stalled, doing nothing if it is still flowing.
    ///
    /// Taking a high-resolution photo can end video on the glasses without
    /// either side noticing: `Stream.state` goes on reporting `.streaming` while
    /// no frames arrive, so the live preview sits frozen on the last frame from
    /// before the capture. Verified by frame counting — the count stops at the
    /// capture and never advances again while the state publisher stays silent.
    ///
    /// Called when the user finishes with a capture rather than automatically
    /// after one. Rebuilding straight away means doing it while the on-device
    /// model is summarizing, competing with it for the CPU and the main actor,
    /// and the preview is showing a summary at that point anyway. Waiting until
    /// the user is back to scanning puts the work where it is actually needed.
    func resumeVideoIfStalled() {
        guard deviceSession != nil else { return }

        // Frames arrive roughly every 40ms, so half a second of silence is
        // unambiguous without being twitchy.
        guard let lastFrameAt, Date().timeIntervalSince(lastFrameAt) > 0.5 else { return }

        rebuildCameraHoldingLastFrame()
    }

    /// Rebuild the camera, holding the last frame so the preview does not blink.
    ///
    /// Used both to recover stalled video and to apply a new
    /// `PreviewQuality`, since configuration is fixed when a camera is added.
    ///
    /// The stream cannot be restarted in place. A stopped `Stream` is terminal
    /// in the same way a stopped `DeviceSession` is, and `stop()` followed by
    /// `start()` reports `videoStreamingError` whether the two are separated by
    /// a delay or sequenced on the state publisher. Both were tried on device.
    /// Ending the session drops `runCameraSession()` out of its loop and
    /// `openCameraSession()` builds a fresh session, camera and stream.
    ///
    /// Re-attaching just the camera — `camera.stop()`, wait for the stream to
    /// reach `.stopped`, then `session.addCamera()` again, keeping the session
    /// connected — looks like the cheaper option and is what Meta's CameraAccess
    /// sample does. It was tried here and measured *slower* on device than
    /// rebuilding the session outright, so this deliberately does the seemingly
    /// heavier thing.
    private func rebuildCameraHoldingLastFrame() {
        guard deviceSession != nil else { return }

        // Hold the last frame rather than blacking out while this happens.
        isRebuildingCamera = true
        rebuildHoldTimeout?.cancel()
        rebuildHoldTimeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }

            // Long past a normal rebuild. Whatever is on screen is stale, and
            // showing it as though it were live would be a lie.
            print("[WearablesManager] Rebuild took too long; releasing held frame")
            self.isRebuildingCamera = false
        }

        deviceSession?.stop()
    }

    /// Capture a high-resolution still photo from the glasses
    /// - Parameter completion: Called with the captured image, or nil if capture failed
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard let stream else {
            print("[WearablesManager] No active stream for photo capture")
            completion(nil)
            return
        }

        guard !isCapturingPhoto else {
            print("[WearablesManager] Photo capture already in progress")
            completion(nil)
            return
        }

        isCapturingPhoto = true
        photoCaptureCompletion = completion

        print("[WearablesManager] Requesting photo capture...")

        // `capturePhoto` returns false when the SDK rejects the request outright.
        // No photoDataPublisher event follows, so the in-flight flag has to be
        // released here — otherwise the `isCapturingPhoto` guard above blocks every
        // subsequent capture for the life of the stream session.
        guard stream.capturePhoto(format: .jpeg) else {
            print("[WearablesManager] Photo capture request rejected by SDK")
            isCapturingPhoto = false
            photoCaptureCompletion = nil
            completion(nil)
            return
        }
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
        guard stream != nil else {
            print("[WearablesManager] No active stream")
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

    /// Whether the preview should keep drawing the last frame it received.
    ///
    /// True only while the camera is being rebuilt after a still capture. The
    /// gap is a couple of seconds, the summary is generating through it, and
    /// blacking out would turn an invisible pause into a visible stop/restart.
    /// Bounded by `rebuildHoldTimeout` so a stream that never comes back stops
    /// masquerading as a live one.
    var shouldHoldLastFrame: Bool {
        isRebuildingCamera && latestFrameImage != nil
    }

    /// Whether glasses are connected and streaming
    var isGlassesConnected: Bool {
        streamState == .streaming
    }
}
