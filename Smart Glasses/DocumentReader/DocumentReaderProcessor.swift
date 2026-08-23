//
//  DocumentReaderProcessor.swift
//  Smart Glasses
//
//  Created by Claude on 1/20/26.
//

import Foundation
import Vision
import CoreImage
import AVFoundation
import Combine
import UIKit

/// Processes video frames to detect documents and extract text continuously
@MainActor
class DocumentReaderProcessor: ObservableObject {

    // MARK: - Published Properties

    /// Latest document reading result
    @Published var latestResult: DocumentReadingResult?

    /// Current state of the document reader
    @Published var state: DocumentReaderState = .idle

    /// Whether continuous scanning is active
    @Published var isScanning: Bool = false

    /// The last time text was updated (for change notification)
    @Published var lastTextUpdateTime: Date?

    /// Error message if any
    @Published var errorMessage: String?

    // MARK: - Auto-Capture Published Properties

    /// Whether auto-capture mode is enabled
    @Published var isAutoCaptureEnabled: Bool = false

    /// Current detected document boundary (for overlay display)
    @Published var detectedBoundary: DocumentBoundary?

    /// Stability progress (0.0 to 1.0) - shows how steady the document is held
    @Published var stabilityProgress: Float = 0.0

    /// Whether the document is currently stable enough to capture
    @Published var isDocumentStable: Bool = false

    /// Auto-capture status message
    @Published var autoCaptureStatus: String = "Point at a document"

    /// Idle prompt for the current mode.
    ///
    /// Whiteboard capture is usually manual — a frameless board gives the
    /// detector nothing to lock onto, so auto-capture is best-effort and the
    /// prompt should not imply the app is waiting to find an edge.
    var idlePrompt: String {
        switch captureMode {
        case .document: return "Point at a document"
        case .whiteboard: return "Point at the board and tap capture"
        case .barcode: return "Point at the book's barcode"
        }
    }

    /// Signals that auto-capture detected a stable document and photo capture should be triggered
    /// LibraryScannerView observes this and calls WearablesManager.captureDocumentPhoto()
    @Published var shouldTriggerPhotoCapture: Bool = false

    /// A barcode Vision read from the live preview, published once the same
    /// payload has held steady for `stableBarcodeFramesRequired` frames.
    @Published var recognizedBarcode: RecognizedBarcode?

    // MARK: - Multi-Page Scanning Properties

    /// Whether multi-page scanning mode is active
    @Published var isMultiPageMode: Bool = false

    /// Number of pages captured in current session
    @Published var capturedPageCount: Int = 0

    /// Accumulated text from all captured pages
    @Published var accumulatedText: String = ""

    /// Thumbnails from captured pages
    @Published var capturedPageThumbnails: [UIImage] = []

    /// Language-model-ready page images from captured pages, parallel to
    /// `capturedPageThumbnails`. Only pages that produced one are included.
    @Published var capturedPageVisionImages: [UIImage] = []

    /// Text from each individual page (for review)
    @Published var pageTexts: [String] = []

    // MARK: - Configuration

    /// What the user is pointing at. Drives whether a detected boundary is
    /// required, and which preprocessing profile applies.
    @Published var captureMode: CaptureMode = .document

    /// Interval between document captures (seconds)
    var captureInterval: TimeInterval = 5.0

    /// Minimum confidence for document detection
    var documentConfidenceThreshold: Float = 0.5

    /// Minimum confidence for text recognition (lowered for distance scanning)
    var textConfidenceThreshold: Float = 0.2

    /// Number of stable frames required before auto-capture
    var stableFramesRequired: Int = 8

    /// Maximum movement allowed between frames (as fraction of image)
    var stabilityThreshold: Float = 0.03

    /// Minimum number of text lines required for successful capture
    var minimumTextLines: Int = 2

    /// Minimum characters required for successful capture
    var minimumCharacters: Int = 30

    // MARK: - Image Enhancement Configuration

    /// Target dimension for the longer side of processed image
    /// Vision framework works best with images around 2000-3000px
    var targetProcessingDimension: CGFloat = 2500

    /// Whether to apply image preprocessing before OCR
    var preprocessImage: Bool = true

    /// Whether to convert to grayscale (can improve OCR accuracy)
    var convertToGrayscale: Bool = true

    /// Whether to apply adaptive thresholding for better text contrast
    var useAdaptiveThreshold: Bool = false

    // MARK: - Private Properties

    /// Timer for continuous scanning
    private var scanTimer: Timer?

    /// Dedicated queue for Vision processing
    private let processingQueue = DispatchQueue(
        label: "com.smartglasses.documentreader",
        qos: .userInitiated
    )

    /// CIContext for image processing
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Whether currently processing a frame
    private var isProcessing: Bool = false

    /// Latest frame for processing
    private var latestFrame: UIImage?

    /// Previous result for change detection
    private var previousResult: DocumentReadingResult?

    // MARK: - Auto-Capture Private Properties

    /// Counter for stable frames
    private var stableFrameCount: Int = 0

    /// Previous boundary for stability comparison
    private var previousBoundary: DocumentBoundary?

    /// Whether currently doing lightweight detection
    private var isDetecting: Bool = false

    /// Frame counter for detection throttling
    private var frameCounter: Int = 0

    /// Process every Nth frame for detection (performance)
    private let detectionFrameSkip: Int = 3

    /// Voice feedback manager for audio cues
    private let voiceFeedback = VoiceFeedbackManager.shared

    /// Track if we've played the document detected sound
    private var hasPlayedDetectionSound: Bool = false

    /// Last stability level for haptic feedback
    private var lastStabilityLevel: Int = 0

    /// Most recent barcode payload, for confirming a read across frames
    private var lastBarcodePayload: String?

    /// Consecutive frames that produced `lastBarcodePayload`
    private var stableBarcodeCount: Int = 0

    // MARK: - Public Methods

    /// Start continuous document scanning
    func startScanning() {
        guard !isScanning else { return }

        isScanning = true
        state = .scanning
        errorMessage = nil

        // Start the timer for periodic captures
        scanTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.processLatestFrame()
            }
        }

        // Process immediately
        processLatestFrame()
    }

    /// Stop continuous scanning
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        isScanning = false
        state = .idle
    }

    /// Update the latest frame (called from video stream)
    func updateFrame(_ image: UIImage) {
        latestFrame = image
    }

    /// Process the latest frame for document detection and OCR
    func processLatestFrame() {
        guard !isProcessing else { return }
        guard let image = latestFrame else {
            state = .scanning
            return
        }

        isProcessing = true
        state = .scanning
        let startTime = Date()

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let cgImage = image.cgImage else {
                Task { @MainActor in
                    self.isProcessing = false
                    self.state = .error("Failed to process image")
                }
                return
            }

            // Step 1: Detect document boundaries
            self.detectDocument(cgImage: cgImage) { boundary in
                guard let boundary = boundary else {
                    // No document detected - still show we're scanning
                    Task { @MainActor in
                        self.isProcessing = false
                        self.state = .scanning
                        self.latestResult = DocumentReadingResult(
                            documentBoundary: nil,
                            correctedImage: nil,
                            extractedText: "",
                            textBlocks: [],
                            timestamp: Date(),
                            processingTimeMs: Date().timeIntervalSince(startTime) * 1000
                        )
                    }
                    return
                }

                Task { @MainActor in
                    self.state = .documentDetected
                }

                // Step 2: Apply perspective correction
                guard let correctedImage = self.applyPerspectiveCorrection(
                    cgImage: cgImage,
                    boundary: boundary
                ) else {
                    Task { @MainActor in
                        self.isProcessing = false
                        self.state = .error("Failed to correct perspective")
                    }
                    return
                }

                Task { @MainActor in
                    self.state = .reading
                }

                // Step 3: Perform OCR on corrected image
                self.performOCR(on: correctedImage) { textBlocks, fullText in
                    Task { @MainActor in
                        let processingTime = Date().timeIntervalSince(startTime) * 1000
                        let result = DocumentReadingResult(
                            documentBoundary: boundary,
                            correctedImage: UIImage(cgImage: correctedImage),
                            extractedText: fullText,
                            textBlocks: textBlocks,
                            timestamp: Date(),
                            processingTimeMs: processingTime
                        )

                        // Check if text changed
                        if result.hasTextChanged(from: self.previousResult) {
                            self.lastTextUpdateTime = Date()
                        }

                        self.previousResult = self.latestResult
                        self.latestResult = result
                        self.isProcessing = false
                        self.state = result.hasText ? .documentDetected : .scanning
                    }
                }
            }
        }
    }

    /// Reset the processor
    func reset() {
        stopScanning()
        stopAutoCapture()
        resetMultiPageSession()
        latestResult = nil
        previousResult = nil
        latestFrame = nil
        lastTextUpdateTime = nil
        errorMessage = nil
        state = .idle
        isProcessing = false
    }

    // MARK: - Multi-Page Scanning Methods

    /// Start a multi-page scanning session
    func startMultiPageSession() {
        isMultiPageMode = true
        capturedPageCount = 0
        accumulatedText = ""
        capturedPageThumbnails = []
        capturedPageVisionImages = []
        pageTexts = []
        errorMessage = nil
        state = .scanning
    }

    /// Add the current capture to the multi-page session
    func addPageToSession() {
        guard let result = latestResult, result.hasText else { return }

        capturedPageCount += 1

        // Accumulate text with page separator
        if !accumulatedText.isEmpty {
            accumulatedText += "\n\n--- Page \(capturedPageCount) ---\n\n"
        }
        accumulatedText += result.extractedText
        pageTexts.append(result.extractedText)

        // Store thumbnail
        if let thumbnail = result.correctedImage {
            capturedPageThumbnails.append(thumbnail)
        }

        if let visionImage = result.visionImage {
            capturedPageVisionImages.append(visionImage)
        }

        // Play audio feedback for page capture
        voiceFeedback.pageCaptured(pageNumber: capturedPageCount)

        // Reset for next page but keep multi-page session active
        latestResult = nil
        state = .scanning

        // Reset auto-capture for next page
        if isAutoCaptureEnabled {
            resetAutoCapture()
        }
    }

    /// Finish multi-page session and prepare for summarization
    /// Returns the combined text from all pages
    func finishMultiPageSession() -> String {
        let combinedText = accumulatedText
        isMultiPageMode = false
        state = .complete

        // Announce completion
        voiceFeedback.multiPageScanComplete(pageCount: capturedPageCount)

        return combinedText
    }

    /// Reset multi-page session without finishing
    func resetMultiPageSession() {
        isMultiPageMode = false
        capturedPageCount = 0
        accumulatedText = ""
        capturedPageThumbnails = []
        capturedPageVisionImages = []
        pageTexts = []
    }

    /// Get total character count across all pages
    var totalCharacterCount: Int {
        accumulatedText.count
    }

    /// Get total line count across all pages
    var totalLineCount: Int {
        accumulatedText.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    // MARK: - Auto-Capture Methods

    /// Start auto-capture mode - continuously detects documents and auto-captures when stable
    func startAutoCapture() {
        guard !isAutoCaptureEnabled else { return }

        isAutoCaptureEnabled = true
        stableFrameCount = 0
        previousBoundary = nil
        stabilityProgress = 0
        isDocumentStable = false
        detectedBoundary = nil
        autoCaptureStatus = idlePrompt
        state = .scanning
        errorMessage = nil
    }

    /// Stop auto-capture mode
    func stopAutoCapture() {
        isAutoCaptureEnabled = false
        stableFrameCount = 0
        previousBoundary = nil
        stabilityProgress = 0
        isDocumentStable = false
        detectedBoundary = nil
        autoCaptureStatus = "Auto-capture disabled"
        shouldTriggerPhotoCapture = false
        hasPlayedDetectionSound = false
        lastStabilityLevel = 0
    }

    /// Process frame for auto-capture (lightweight document detection)
    func processFrameForAutoCapture(_ image: UIImage) {
        guard isAutoCaptureEnabled else { return }
        guard !isProcessing else { return }
        guard !isDetecting else { return }

        // Throttle detection to every Nth frame
        frameCounter += 1
        guard frameCounter % detectionFrameSkip == 0 else { return }

        // Barcodes take a different path entirely: Vision returns the payload
        // itself, so there is nothing to capture at high resolution and no model
        // round trip to make.
        if captureMode == .barcode {
            detectBarcode(in: image)
            return
        }

        latestFrame = image
        isDetecting = true

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let cgImage = image.cgImage else {
                Task { @MainActor in
                    self.isDetecting = false
                }
                return
            }

            // Lightweight document detection only
            self.detectDocument(cgImage: cgImage) { boundary in
                Task { @MainActor in
                    self.handleAutoCaptureDetection(boundary: boundary, image: image)
                    self.isDetecting = false
                }
            }
        }
    }

    /// Handle detection result for auto-capture
    private func handleAutoCaptureDetection(boundary: DocumentBoundary?, image: UIImage) {
        guard isAutoCaptureEnabled else { return }

        if let boundary = boundary {
            detectedBoundary = boundary

            // Play document detected sound on first detection
            if !hasPlayedDetectionSound {
                voiceFeedback.documentDetected()
                hasPlayedDetectionSound = true
            }

            // Check stability against previous boundary
            if let previous = previousBoundary {
                let movement = calculateBoundaryMovement(from: previous, to: boundary)

                if movement < stabilityThreshold {
                    // Document is stable
                    stableFrameCount += 1
                    stabilityProgress = Float(stableFrameCount) / Float(stableFramesRequired)

                    // Play stability tick at each 25% milestone
                    let currentLevel = Int(stabilityProgress * 4)
                    if currentLevel > lastStabilityLevel && currentLevel < 4 {
                        voiceFeedback.stabilityTick()
                        lastStabilityLevel = currentLevel
                    }

                    if stableFrameCount >= stableFramesRequired {
                        // Document is stable enough - trigger auto-capture
                        isDocumentStable = true
                        autoCaptureStatus = "Capturing..."
                        triggerAutoCapture(image)
                    } else {
                        autoCaptureStatus = "Hold steady..."
                        isDocumentStable = false
                    }
                } else {
                    // Document moved - reset stability
                    stableFrameCount = max(0, stableFrameCount - 2)
                    stabilityProgress = Float(stableFrameCount) / Float(stableFramesRequired)
                    isDocumentStable = false
                    autoCaptureStatus = "Hold steady..."
                    lastStabilityLevel = Int(stabilityProgress * 4)

                    // Play hold steady feedback if user was close to capturing
                    if stableFrameCount == 0 && lastStabilityLevel > 2 {
                        voiceFeedback.holdSteady()
                    }
                }
            } else {
                // First detection
                stableFrameCount = 1
                stabilityProgress = Float(stableFrameCount) / Float(stableFramesRequired)
                autoCaptureStatus = captureMode == .whiteboard
                    ? "Board detected - hold steady"
                    : "Document detected - hold steady"
                lastStabilityLevel = 0
            }

            previousBoundary = boundary
            state = .documentDetected

        } else {
            // No document detected - reset
            if hasPlayedDetectionSound {
                hasPlayedDetectionSound = false
            }
            detectedBoundary = nil
            previousBoundary = nil
            stableFrameCount = 0
            stabilityProgress = 0
            isDocumentStable = false
            autoCaptureStatus = idlePrompt
            state = .scanning
            lastStabilityLevel = 0
        }
    }

    // MARK: - Barcode Detection

    /// Payloads must repeat this many consecutive reads before being accepted.
    ///
    /// Vision occasionally misreads a partially-occluded or motion-blurred
    /// barcode, and a wrong ISBN silently creates the wrong deck. Requiring the
    /// same digits twice costs a fraction of a second and removes that class of
    /// error entirely.
    private let stableBarcodeFramesRequired = 2

    /// Read a barcode straight out of the live preview.
    private func detectBarcode(in image: UIImage) {
        guard recognizedBarcode == nil else { return }
        guard let cgImage = image.cgImage else { return }

        isDetecting = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isDetecting = false }

            var request = DetectBarcodesRequest()
            // Books only: EAN-13 carries ISBN-13, and the others are close enough
            // cousins to be worth accepting. Narrowing the set makes detection
            // faster and stops random product codes from matching.
            request.symbologies = [.ean13, .ean8, .upce]

            guard let observations = try? await request.perform(on: cgImage),
                  let best = observations.max(by: { $0.confidence < $1.confidence }),
                  let payload = best.payloadString,
                  !payload.isEmpty
            else {
                self.resetBarcodeStability()
                return
            }

            self.handleBarcodeRead(payload: payload, symbology: "\(best.symbology)")
        }
    }

    private func handleBarcodeRead(payload: String, symbology: String) {
        if payload == lastBarcodePayload {
            stableBarcodeCount += 1
        } else {
            lastBarcodePayload = payload
            stableBarcodeCount = 1
            autoCaptureStatus = "Reading barcode…"
        }

        guard stableBarcodeCount >= stableBarcodeFramesRequired else { return }

        recognizedBarcode = RecognizedBarcode(payload: payload, symbology: symbology)
        autoCaptureStatus = "Barcode found"
        voiceFeedback.captureSuccess()
        print("[DocumentReader] Barcode \(symbology): \(payload)")
    }

    private func resetBarcodeStability() {
        lastBarcodePayload = nil
        stableBarcodeCount = 0
    }

    /// Clear a read so scanning can resume — called once the deck sheet closes.
    func clearRecognizedBarcode() {
        recognizedBarcode = nil
        resetBarcodeStability()
        autoCaptureStatus = idlePrompt
    }

    /// Calculate movement between two boundaries (returns max corner movement)
    private func calculateBoundaryMovement(from: DocumentBoundary, to: DocumentBoundary) -> Float {
        let movements = [
            hypot(Float(to.topLeft.x - from.topLeft.x), Float(to.topLeft.y - from.topLeft.y)),
            hypot(Float(to.topRight.x - from.topRight.x), Float(to.topRight.y - from.topRight.y)),
            hypot(Float(to.bottomLeft.x - from.bottomLeft.x), Float(to.bottomLeft.y - from.bottomLeft.y)),
            hypot(Float(to.bottomRight.x - from.bottomRight.x), Float(to.bottomRight.y - from.bottomRight.y))
        ]
        return movements.max() ?? 0
    }

    /// Trigger photo capture when document is stable
    /// Instead of processing video frame, signals LibraryScannerView to capture high-res photo
    private func triggerAutoCapture(_ image: UIImage) {
        // Temporarily disable auto-capture during processing
        isAutoCaptureEnabled = false
        autoCaptureStatus = "Capturing photo..."

        // Signal that photo capture should be triggered
        // LibraryScannerView observes this and calls WearablesManager.captureDocumentPhoto()
        shouldTriggerPhotoCapture = true
    }

    /// Called after photo capture is complete to re-enable auto-capture if needed
    func autoCaptureDidComplete() {
        shouldTriggerPhotoCapture = false

        // Re-enable after a delay to allow user to see results
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            // Only re-enable if state indicates we should continue
            if self?.state == .complete {
                // Stay complete - user needs to save or discard
            } else {
                self?.resetAutoCapture()
            }
        }
    }

    /// Reset auto-capture state without disabling it
    func resetAutoCapture() {
        stableFrameCount = 0
        previousBoundary = nil
        stabilityProgress = 0
        isDocumentStable = false
        detectedBoundary = nil
        autoCaptureStatus = idlePrompt
        isAutoCaptureEnabled = true
        shouldTriggerPhotoCapture = false
        state = .scanning
        hasPlayedDetectionSound = false
        lastStabilityLevel = 0
    }

    /// Capture and process a single image (for on-demand scanning)
    func captureAndProcess(_ image: UIImage) {
        guard !isProcessing else { return }

        isProcessing = true
        state = .detectingDocument
        errorMessage = nil
        let startTime = Date()

        // Read the isolated configuration here, on the main actor, rather than
        // from inside the background closure.
        let mode = captureMode
        let ocrDimension = targetProcessingDimension
        let shouldPreprocess = preprocessImage

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let cgImage = image.cgImage else {
                Task { @MainActor in
                    self.isProcessing = false
                    self.state = .error("Failed to process image")
                    self.errorMessage = "Failed to process image"
                }
                return
            }

            // Step 1: Detect document boundaries
            self.detectDocument(cgImage: cgImage) { boundary in
                // A whiteboard on a light wall usually gives the segmentation
                // request no edge to lock onto. Rather than refuse the capture,
                // fall back to the uncropped frame — the model reads an
                // un-deskewed board far better than it reads nothing.
                if case .none = boundary, mode.requiresDocumentBoundary {
                    Task { @MainActor in
                        self.isProcessing = false
                        self.state = .idle
                        self.errorMessage = "No document detected"
                        self.latestResult = DocumentReadingResult(
                            documentBoundary: nil,
                            correctedImage: nil,
                            extractedText: "",
                            textBlocks: [],
                            timestamp: Date(),
                            processingTimeMs: Date().timeIntervalSince(startTime) * 1000
                        )
                        self.voiceFeedback.noDocumentDetected()
                    }
                    return
                }

                Task { @MainActor in
                    self.state = .processingDocument
                }

                // Step 2: Apply perspective correction when there is a boundary
                // to correct against; otherwise take the frame as shot.
                let correctedImage: CGImage
                let visionCGImage: CGImage?

                if let boundary {
                    guard let corrected = self.applyPerspectiveCorrection(
                        cgImage: cgImage,
                        boundary: boundary
                    ) else {
                        Task { @MainActor in
                            self.isProcessing = false
                            self.state = .error("Failed to correct perspective")
                            self.errorMessage = "Failed to correct perspective"
                        }
                        return
                    }
                    correctedImage = corrected

                    // Step 2b: Render a second copy for the language model — full
                    // color, no OCR preprocessing, and small enough to be a cheap
                    // attachment. Rendered from the original pixels rather than
                    // downscaled from `correctedImage`, which has already been
                    // flattened to grayscale.
                    visionCGImage = self.applyPerspectiveCorrection(
                        cgImage: cgImage,
                        boundary: boundary,
                        targetDimension: PageVisionImage.defaultMaxDimension,
                        preprocess: false
                    )
                } else {
                    correctedImage = self.scaledImage(
                        cgImage,
                        targetDimension: ocrDimension,
                        preprocess: shouldPreprocess
                    ) ?? cgImage
                    visionCGImage = self.scaledImage(
                        cgImage,
                        targetDimension: PageVisionImage.defaultMaxDimension,
                        preprocess: false
                    )
                }

                Task { @MainActor in
                    self.state = .readingText
                }

                // Step 3: Perform OCR on corrected image
                self.performOCR(on: correctedImage) { textBlocks, fullText in
                    Task { @MainActor in
                        let processingTime = Date().timeIntervalSince(startTime) * 1000
                        let result = DocumentReadingResult(
                            documentBoundary: boundary,
                            correctedImage: UIImage(cgImage: correctedImage),
                            visionImage: visionCGImage.map { UIImage(cgImage: $0) },
                            extractedText: fullText,
                            textBlocks: textBlocks,
                            timestamp: Date(),
                            processingTimeMs: processingTime
                        )

                        // Validate minimum text requirements
                        let lineCount = fullText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                        let charCount = fullText.count
                        let hasEnoughText = lineCount >= self.minimumTextLines || charCount >= self.minimumCharacters

                        let imageCanStandAlone = result.canStandOnImageAlone(in: mode)

                        self.latestResult = result
                        self.isProcessing = false

                        if !result.hasText && !imageCanStandAlone {
                            // No text at all
                            self.state = .idle
                            self.errorMessage = "No text found in document"
                            self.autoCaptureStatus = self.idlePrompt
                            self.voiceFeedback.captureFailedInsufficientText()
                        } else if !hasEnoughText && !imageCanStandAlone {
                            // Some text, but not enough
                            self.state = .idle
                            self.errorMessage = "Not enough text detected. Try moving closer."
                            self.autoCaptureStatus = self.idlePrompt
                            self.voiceFeedback.captureFailedInsufficientText()
                        } else {
                            // Success — enough text, or a whiteboard the model can read
                            self.state = .complete
                            // Clear the transient "Capturing photo..." text, which
                            // otherwise sticks because `autoCaptureDidComplete()`
                            // deliberately holds state when a capture succeeded.
                            self.autoCaptureStatus = "Captured"
                            self.voiceFeedback.captureSuccess()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Detect document boundaries using Vision
    private func detectDocument(cgImage: CGImage, completion: @escaping (DocumentBoundary?) -> Void) {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        let request = VNDetectDocumentSegmentationRequest { [weak self] request, error in
            guard let self = self else {
                completion(nil)
                return
            }

            if let error = error {
                print("[DocumentReader] Document detection error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let observations = request.results as? [VNRectangleObservation],
                  let bestObservation = observations.first,
                  bestObservation.confidence >= self.documentConfidenceThreshold else {
                completion(nil)
                return
            }

            let boundary = DocumentBoundary(
                topLeft: bestObservation.topLeft,
                topRight: bestObservation.topRight,
                bottomRight: bestObservation.bottomRight,
                bottomLeft: bestObservation.bottomLeft,
                confidence: bestObservation.confidence
            )

            completion(boundary)
        }

        do {
            try handler.perform([request])
        } catch {
            print("[DocumentReader] Failed to perform document detection: \(error)")
            completion(nil)
        }
    }

    /// Apply perspective correction to extract the document
    ///
    /// - Parameters:
    ///   - targetDimension: Longest-side dimension of the rendered output. Defaults
    ///     to `targetProcessingDimension`, the size Vision reads text best at.
    ///   - preprocess: Whether to apply the OCR preprocessing pass (grayscale and
    ///     contrast). Pass `false` for images destined for the language model —
    ///     that pass destroys the detail needed to interpret figures.
    private func applyPerspectiveCorrection(
        cgImage: CGImage,
        boundary: DocumentBoundary,
        targetDimension: CGFloat? = nil,
        preprocess: Bool? = nil
    ) -> CGImage? {
        let targetDimension = targetDimension ?? targetProcessingDimension
        let preprocess = preprocess ?? preprocessImage
        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size

        // Convert normalized coordinates to pixel coordinates
        let topLeft = CGPoint(
            x: boundary.topLeft.x * imageSize.width,
            y: boundary.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: boundary.topRight.x * imageSize.width,
            y: boundary.topRight.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: boundary.bottomRight.x * imageSize.width,
            y: boundary.bottomRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: boundary.bottomLeft.x * imageSize.width,
            y: boundary.bottomLeft.y * imageSize.height
        )

        // Calculate output size based on document dimensions
        let widthTop = hypot(topRight.x - topLeft.x, topRight.y - topLeft.y)
        let widthBottom = hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y)
        let heightLeft = hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y)
        let heightRight = hypot(topRight.x - bottomRight.x, topRight.y - bottomRight.y)

        let outputWidth = max(widthTop, widthBottom)
        let outputHeight = max(heightLeft, heightRight)

        // Apply perspective correction using CIPerspectiveCorrection
        guard let perspectiveFilter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        perspectiveFilter.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveFilter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        perspectiveFilter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        perspectiveFilter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")

        guard var processedImage = perspectiveFilter.outputImage else {
            return nil
        }

        // Scale to target dimension for optimal OCR
        // Vision works best with images around 2000-3000px on the longer side
        let maxDimension = max(outputWidth, outputHeight)
        if maxDimension > 0 {
            let scale = targetDimension / maxDimension
            if scale != 1.0 {
                // Use Lanczos for high-quality scaling
                if let lanczosFilter = CIFilter(name: "CILanczosScaleTransform") {
                    lanczosFilter.setValue(processedImage, forKey: kCIInputImageKey)
                    lanczosFilter.setValue(scale, forKey: kCIInputScaleKey)
                    lanczosFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
                    if let output = lanczosFilter.outputImage {
                        processedImage = output
                    }
                }
            }
        }

        // Apply preprocessing if enabled
        if preprocess {
            processedImage = preprocessForOCR(processedImage)
        }

        // Render to CGImage
        guard let result = ciContext.createCGImage(processedImage, from: processedImage.extent) else {
            return nil
        }

        print("[DocumentReader] Processed image size: \(result.width)x\(result.height)")
        return result
    }

    /// Scale (and optionally preprocess) a frame without cropping it.
    ///
    /// Used when no boundary was detected — whiteboard captures usually have no
    /// findable edge, so the whole frame is the subject.
    private func scaledImage(
        _ cgImage: CGImage,
        targetDimension: CGFloat,
        preprocess: Bool
    ) -> CGImage? {
        var image = CIImage(cgImage: cgImage)

        let maxDimension = max(image.extent.width, image.extent.height)
        if maxDimension > 0 {
            let scale = targetDimension / maxDimension
            if scale != 1.0, let lanczos = CIFilter(name: "CILanczosScaleTransform") {
                lanczos.setValue(image, forKey: kCIInputImageKey)
                lanczos.setValue(scale, forKey: kCIInputScaleKey)
                lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
                if let output = lanczos.outputImage {
                    image = output
                }
            }
        }

        if preprocess {
            image = preprocessForOCR(image)
        }

        return ciContext.createCGImage(image, from: image.extent)
    }

    /// Preprocess image for optimal OCR accuracy
    private func preprocessForOCR(_ image: CIImage) -> CIImage {
        var processedImage = image

        // Step 1: Convert to grayscale if enabled (reduces noise, focuses on text)
        if convertToGrayscale {
            if let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono") {
                grayscaleFilter.setValue(processedImage, forKey: kCIInputImageKey)
                if let output = grayscaleFilter.outputImage {
                    processedImage = output
                }
            }
        }

        // Step 2: Increase contrast to make text stand out (stronger for distance)
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(processedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.3, forKey: kCIInputContrastKey) // Stronger contrast for distance
            contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey)
            contrastFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = contrastFilter.outputImage {
                processedImage = output
            }
        }

        // Step 3: Apply adaptive threshold if enabled (binarization for cleaner text)
        // This can help with uneven lighting but may lose detail
        if useAdaptiveThreshold {
            // Unsharp mask to sharpen text edges blurred by distance
            if let unsharpFilter = CIFilter(name: "CIUnsharpMask") {
                unsharpFilter.setValue(processedImage, forKey: kCIInputImageKey)
                unsharpFilter.setValue(1.5, forKey: kCIInputRadiusKey)
                unsharpFilter.setValue(1.0, forKey: kCIInputIntensityKey)
                if let output = unsharpFilter.outputImage {
                    processedImage = output
                }
            }
        }

        return processedImage
    }

    /// Perform OCR on the corrected document image
    private func performOCR(on cgImage: CGImage, completion: @escaping ([RecognizedTextBlock], String) -> Void) {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else {
                completion([], "")
                return
            }

            if let error = error {
                print("[DocumentReader] OCR error: \(error.localizedDescription)")
                completion([], "")
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("[DocumentReader] No OCR results")
                completion([], "")
                return
            }

            print("[DocumentReader] OCR found \(observations.count) text observations")

            var textBlocks: [RecognizedTextBlock] = []

            for observation in observations {
                // Get top candidate with confidence check
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= self.textConfidenceThreshold else {
                    continue
                }

                let block = RecognizedTextBlock(
                    text: candidate.string,
                    boundingBox: observation.boundingBox,
                    confidence: candidate.confidence
                )
                textBlocks.append(block)
            }

            // Sort text blocks by position (top to bottom, left to right)
            // Vision coordinates: origin at bottom-left, y increases upward
            textBlocks.sort { block1, block2 in
                let y1 = block1.boundingBox.origin.y + block1.boundingBox.height
                let y2 = block2.boundingBox.origin.y + block2.boundingBox.height

                // If on roughly the same line (within 2% of image height)
                if abs(y1 - y2) < 0.02 {
                    return block1.boundingBox.origin.x < block2.boundingBox.origin.x
                }
                // Otherwise sort by y (higher y = earlier in document since origin is bottom-left)
                return y1 > y2
            }

            // Combine text in reading order
            let fullText = textBlocks.map { $0.text }.joined(separator: "\n")

            print("[DocumentReader] Recognized \(textBlocks.count) text blocks, \(fullText.count) characters")
            completion(textBlocks, fullText)
        }

        // Configure for maximum accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        // Detect small text that appears at distance
        request.minimumTextHeight = 0.01

        do {
            try handler.perform([request])
        } catch {
            print("[DocumentReader] Failed to perform OCR: \(error)")
            completion([], "")
        }
    }
}
