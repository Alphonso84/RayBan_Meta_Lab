//
//  DetectionConfiguration.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Foundation
import CoreGraphics

// MARK: - Focus Area
/// Defines a rectangular region of interest within the video frame
/// All coordinates are normalized (0-1) where (0,0) is top-left
struct FocusArea: Equatable {
    let origin: CGPoint      // Top-left corner (normalized 0-1)
    let size: CGSize         // Width and height (normalized 0-1)

    /// Center region of the frame (middle 50%)
    static let center = FocusArea(
        origin: CGPoint(x: 0.25, y: 0.25),
        size: CGSize(width: 0.5, height: 0.5)
    )

    /// Entire frame
    static let fullFrame = FocusArea(
        origin: .zero,
        size: CGSize(width: 1.0, height: 1.0)
    )

    /// Left-biased region (for left-mounted camera on glasses)
    static let leftBias = FocusArea(
        origin: CGPoint(x: 0.1, y: 0.25),
        size: CGSize(width: 0.5, height: 0.5)
    )

    /// Convert to CGRect for intersection testing
    var rect: CGRect {
        CGRect(origin: origin, size: size)
    }

    /// Check if a bounding box intersects with this focus area
    /// - Parameter boundingBox: Normalized bounding box from Vision (bottom-left origin)
    /// - Returns: True if the bounding box intersects the focus area
    func contains(_ boundingBox: CGRect) -> Bool {
        // Vision uses bottom-left origin, convert to top-left
        let convertedBox = CGRect(
            x: boundingBox.origin.x,
            y: 1 - boundingBox.origin.y - boundingBox.height,
            width: boundingBox.width,
            height: boundingBox.height
        )
        return rect.intersects(convertedBox)
    }
}

// MARK: - Detection Configuration
/// Configuration options for object detection processing
struct DetectionConfiguration {
    /// The focus area to prioritize for detection
    var focusArea: FocusArea = .center

    /// Number of frames to skip between processing (1 = process every frame)
    /// Default of 5 means process every 5th frame (6fps at 30fps input)
    var frameSkipCount: Int = 5

    /// Minimum confidence threshold for detections (0-1)
    var confidenceThreshold: Float = 0.5

    /// Maximum number of detections to report
    var maxDetections: Int = 5

    /// Whether to include detections outside the focus area
    var includeOutOfFocusDetections: Bool = true

    /// Default configuration
    static let `default` = DetectionConfiguration()

    /// Performance-optimized configuration (less frequent processing)
    static let lowPower = DetectionConfiguration(
        frameSkipCount: 10,
        confidenceThreshold: 0.6,
        maxDetections: 3
    )
}

// MARK: - Detection Configurable Protocol
/// Protocol for objects that can be configured with detection settings
protocol DetectionConfigurable {
    var configuration: DetectionConfiguration { get set }
}
