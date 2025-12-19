//
//  DetectionResult.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import CoreGraphics

// MARK: - Detected Object
/// Represents a single detected object in a video frame
struct DetectedObject: Identifiable, Equatable {
    let id = UUID()

    /// The classification label (e.g., "cat", "person", "cup")
    let label: String

    /// Confidence score from 0-1
    let confidence: Float

    /// Bounding box in normalized coordinates (0-1)
    /// Note: Vision uses bottom-left origin, this is stored as-is
    let boundingBox: CGRect

    /// Whether this object is within the focus area
    let isInFocusArea: Bool

    /// Display-friendly label with confidence percentage
    var displayLabel: String {
        "\(label) (\(Int(confidence * 100))%)"
    }

    /// Confidence as a percentage string
    var confidencePercent: String {
        "\(Int(confidence * 100))%"
    }

    static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Detection Result
/// Contains all detection results for a single frame
struct DetectionResult {
    /// All detected objects in the frame
    let objects: [DetectedObject]

    /// Timestamp when this detection was performed
    let timestamp: Date

    /// Time taken to process the frame in milliseconds
    let processingTimeMs: Double

    /// Objects that are within the focus area, sorted by confidence
    var focusedObjects: [DetectedObject] {
        objects
            .filter { $0.isInFocusArea }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Objects outside the focus area
    var unfocusedObjects: [DetectedObject] {
        objects.filter { !$0.isInFocusArea }
    }

    /// The primary (highest confidence) object in the focus area
    var primaryObject: DetectedObject? {
        focusedObjects.first
    }

    /// Whether any objects were detected in the focus area
    var hasFocusedObjects: Bool {
        !focusedObjects.isEmpty
    }

    /// Total number of detections
    var count: Int {
        objects.count
    }

    /// Empty result
    static let empty = DetectionResult(
        objects: [],
        timestamp: Date(),
        processingTimeMs: 0
    )
}

// MARK: - Detection Result Description
extension DetectionResult {
    /// Generate a natural language description of what was detected
    func generateDescription() -> String {
        let focused = focusedObjects

        if focused.isEmpty {
            return "No objects detected in focus area"
        }

        if focused.count == 1 {
            return "I see a \(focused[0].label)"
        }

        if focused.count == 2 {
            return "I see a \(focused[0].label) and a \(focused[1].label)"
        }

        // For 3+ objects, list first few and summarize
        let labels = focused.prefix(3).map { $0.label }
        let lastLabel = labels.last!
        let otherLabels = labels.dropLast().joined(separator: ", ")

        if focused.count > 3 {
            return "I see \(otherLabels), \(lastLabel), and \(focused.count - 3) more objects"
        }

        return "I see \(otherLabels), and \(lastLabel)"
    }
}
