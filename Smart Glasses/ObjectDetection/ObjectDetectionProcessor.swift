//
//  ObjectDetectionProcessor.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import Vision
import CoreImage
import AVFoundation
import Combine

/// Processes video frames using Apple's Vision framework for object detection
@MainActor
class ObjectDetectionProcessor: ObservableObject, DetectionConfigurable {

    // MARK: - Published Properties

    /// Latest detection result for UI binding
    @Published var latestResult: DetectionResult?

    /// Whether a frame is currently being processed
    @Published var isProcessing: Bool = false

    /// Error message if processing fails
    @Published var errorMessage: String?

    // MARK: - Configuration

    /// Detection configuration settings
    var configuration = DetectionConfiguration.default

    // MARK: - Private Properties

    /// Frame counter for skip logic
    private var frameCounter: Int = 0

    /// Dedicated queue for Vision processing
    private let processingQueue = DispatchQueue(
        label: "com.smartglasses.objectdetection",
        qos: .userInitiated
    )

    /// Temporary storage for classification results
    private var pendingClassifications: [VNClassificationObservation] = []

    // MARK: - Vision Requests

    /// Image classification request
    private lazy var classificationRequest: VNClassifyImageRequest = {
        let request = VNClassifyImageRequest { [weak self] request, error in
            if let error = error {
                print("Classification error: \(error.localizedDescription)")
                return
            }
            self?.handleClassificationResults(request)
        }
        // Use the latest revision for best accuracy
        if #available(iOS 17.0, *) {
            request.revision = VNClassifyImageRequestRevision2
        }
        return request
    }()

    // MARK: - Public Methods

    /// Process a video frame for object detection
    /// - Parameter sampleBuffer: The CMSampleBuffer from the video stream
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        frameCounter += 1

        // Skip frames based on configuration
        guard frameCounter % configuration.frameSkipCount == 0 else { return }

        // Don't start new processing if still working on previous frame
        guard !isProcessing else { return }

        isProcessing = true
        let startTime = Date()

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Extract pixel buffer from sample buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                Task { @MainActor in
                    self.isProcessing = false
                    self.errorMessage = "Failed to get pixel buffer"
                }
                return
            }

            // Create Vision request handler
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )

            do {
                // Perform classification
                try handler.perform([self.classificationRequest])

                // Process and publish results
                Task { @MainActor in
                    self.publishResults(startTime: startTime)
                    self.isProcessing = false
                    self.errorMessage = nil
                }
            } catch {
                print("Vision processing error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Reset the processor state
    func reset() {
        frameCounter = 0
        latestResult = nil
        isProcessing = false
        errorMessage = nil
        pendingClassifications = []
    }

    // MARK: - Private Methods

    /// Handle classification results from Vision
    private func handleClassificationResults(_ request: VNRequest) {
        guard let observations = request.results as? [VNClassificationObservation] else {
            return
        }
        pendingClassifications = observations
    }

    /// Process Vision results and publish to UI
    private func publishResults(startTime: Date) {
        let processingTime = Date().timeIntervalSince(startTime) * 1000

        // Filter by confidence threshold and limit count
        let filteredClassifications = pendingClassifications
            .filter { $0.confidence >= configuration.confidenceThreshold }
            .prefix(configuration.maxDetections)

        // Convert to DetectedObject array
        // Note: VNClassifyImageRequest doesn't provide bounding boxes,
        // so we create a center bounding box for classification results
        let objects = filteredClassifications.map { observation -> DetectedObject in
            // For classification (no bounding box), assume center of frame
            let centerBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

            // Format the label nicely
            let label = formatLabel(observation.identifier)

            return DetectedObject(
                label: label,
                confidence: observation.confidence,
                boundingBox: centerBox,
                isInFocusArea: true // Classifications are considered in-focus
            )
        }

        // Create and publish result
        let result = DetectionResult(
            objects: Array(objects),
            timestamp: Date(),
            processingTimeMs: processingTime
        )

        latestResult = result
        pendingClassifications = []
    }

    /// Format Vision classifier labels for display
    /// - Parameter identifier: Raw identifier from Vision (e.g., "golden_retriever")
    /// - Returns: Human-readable label (e.g., "Golden Retriever")
    private func formatLabel(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Object Detection with Bounding Boxes (Alternative)
extension ObjectDetectionProcessor {

    /// Process frame using object detection (provides bounding boxes)
    /// This uses VNRecognizeAnimalsRequest for animals and could be extended
    /// Note: For more general object detection with bounding boxes,
    /// consider using a CoreML model like YOLOv8
    func processFrameWithBoundingBoxes(_ sampleBuffer: CMSampleBuffer) {
        frameCounter += 1

        guard frameCounter % configuration.frameSkipCount == 0 else { return }
        guard !isProcessing else { return }

        isProcessing = true
        let startTime = Date()

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                Task { @MainActor in
                    self.isProcessing = false
                }
                return
            }

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )

            // Animal recognition request (has bounding boxes)
            let animalRequest = VNRecognizeAnimalsRequest { [weak self] request, error in
                guard let self = self else { return }

                if let error = error {
                    print("Animal recognition error: \(error)")
                    return
                }

                guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                    return
                }

                let objects = observations.compactMap { observation -> DetectedObject? in
                    guard let label = observation.labels.first else { return nil }
                    guard label.confidence >= self.configuration.confidenceThreshold else { return nil }

                    let isInFocus = self.configuration.focusArea.contains(observation.boundingBox)

                    return DetectedObject(
                        label: self.formatLabel(label.identifier),
                        confidence: label.confidence,
                        boundingBox: observation.boundingBox,
                        isInFocusArea: isInFocus
                    )
                }

                Task { @MainActor in
                    let processingTime = Date().timeIntervalSince(startTime) * 1000
                    self.latestResult = DetectionResult(
                        objects: objects,
                        timestamp: Date(),
                        processingTimeMs: processingTime
                    )
                    self.isProcessing = false
                }
            }

            do {
                try handler.perform([animalRequest])
            } catch {
                print("Animal detection error: \(error)")
                Task { @MainActor in
                    self.isProcessing = false
                }
            }
        }
    }
}
