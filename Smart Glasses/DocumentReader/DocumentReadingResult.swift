//
//  DocumentReadingResult.swift
//  Smart Glasses
//
//  Created by Claude on 1/20/26.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - Recognized Text Block

/// Represents a single recognized text region
struct RecognizedTextBlock: Identifiable, Equatable {
    let id: UUID
    let text: String
    let boundingBox: CGRect  // Vision coordinates (0-1, bottom-left origin)
    let confidence: Float

    init(id: UUID = UUID(), text: String, boundingBox: CGRect, confidence: Float) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

// MARK: - Document Boundary
/// Represents the detected document boundary in the frame
struct DocumentBoundary: Equatable {
    /// The four corners of the document in Vision coordinates (0-1, bottom-left origin)
    /// Order: top-left, top-right, bottom-right, bottom-left
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    /// Confidence of the document detection (0-1)
    let confidence: Float

    /// Convert to a path for drawing
    func path(in size: CGSize) -> [CGPoint] {
        // Convert Vision coordinates to SwiftUI coordinates
        return [
            CGPoint(x: topLeft.x * size.width, y: (1 - topLeft.y) * size.height),
            CGPoint(x: topRight.x * size.width, y: (1 - topRight.y) * size.height),
            CGPoint(x: bottomRight.x * size.width, y: (1 - bottomRight.y) * size.height),
            CGPoint(x: bottomLeft.x * size.width, y: (1 - bottomLeft.y) * size.height)
        ]
    }

    /// Bounding rect containing the document
    var boundingRect: CGRect {
        let minX = min(topLeft.x, bottomLeft.x)
        let maxX = max(topRight.x, bottomRight.x)
        let minY = min(bottomLeft.y, bottomRight.y)
        let maxY = max(topLeft.y, topRight.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Document Reading Result
/// Contains the result of document detection and OCR
struct DocumentReadingResult: Equatable {
    static func == (lhs: DocumentReadingResult, rhs: DocumentReadingResult) -> Bool {
        lhs.documentBoundary == rhs.documentBoundary &&
        lhs.extractedText == rhs.extractedText &&
        lhs.textBlocks == rhs.textBlocks &&
        lhs.timestamp == rhs.timestamp
    }

    /// The detected document boundary (nil if no document detected)
    let documentBoundary: DocumentBoundary?

    /// The perspective-corrected document image, preprocessed for OCR
    /// (grayscale and contrast-boosted when `preprocessImage` is enabled)
    let correctedImage: UIImage?

    /// The perspective-corrected page rendered for the language model: full color,
    /// no OCR preprocessing, downscaled to `PageVisionImage.defaultMaxDimension`.
    ///
    /// Kept separate from `correctedImage` because the grayscale + contrast pass
    /// that helps Vision read text actively destroys the detail a vision model
    /// needs to interpret diagrams and charts.
    let visionImage: UIImage?

    /// The extracted text from the document
    let extractedText: String

    /// Individual text blocks with positions (relative to corrected image)
    let textBlocks: [RecognizedTextBlock]

    /// Timestamp when this reading was performed
    let timestamp: Date

    /// Time taken to process in milliseconds
    let processingTimeMs: Double

    init(
        documentBoundary: DocumentBoundary?,
        correctedImage: UIImage?,
        visionImage: UIImage? = nil,
        extractedText: String,
        textBlocks: [RecognizedTextBlock],
        timestamp: Date,
        processingTimeMs: Double
    ) {
        self.documentBoundary = documentBoundary
        self.correctedImage = correctedImage
        self.visionImage = visionImage
        self.extractedText = extractedText
        self.textBlocks = textBlocks
        self.timestamp = timestamp
        self.processingTimeMs = processingTimeMs
    }

    /// Whether a document was detected
    var hasDocument: Bool {
        documentBoundary != nil
    }

    /// Whether any text was extracted
    var hasText: Bool {
        !extractedText.isEmpty
    }

    /// Number of text blocks
    var textBlockCount: Int {
        textBlocks.count
    }

    /// Whether the picture alone is enough, with no usable OCR text.
    ///
    /// True only for whiteboards: marker handwriting is where
    /// `VNRecognizeTextRequest` is weakest, so a board holding a diagram and
    /// four words routinely yields no text at all — yet it is exactly what the
    /// user meant to capture, and the model can read it from the image.
    ///
    /// `visionSupported` defaults to asking the model and exists so tests can pin
    /// it: the real value depends on the on-device model variant, which differs
    /// between devices on the same OS.
    func canStandOnImageAlone(
        in mode: CaptureMode,
        visionSupported: Bool = PageVisionPrompt.isVisionSupported
    ) -> Bool {
        mode == .whiteboard && visionImage != nil && visionSupported
    }

    /// Whether this capture is worth sending to the summarizer.
    ///
    /// The single source of truth for that decision. It previously lived in two
    /// places — the processor's acceptance check and the scanner view's
    /// summarization trigger — which drifted apart and left image-only
    /// whiteboard captures accepted but never summarized.
    func isSummarizable(
        in mode: CaptureMode,
        visionSupported: Bool = PageVisionPrompt.isVisionSupported
    ) -> Bool {
        hasText || canStandOnImageAlone(in: mode, visionSupported: visionSupported)
    }

    /// Empty result (no document detected)
    static let empty = DocumentReadingResult(
        documentBoundary: nil,
        correctedImage: nil,
        extractedText: "",
        textBlocks: [],
        timestamp: Date(),
        processingTimeMs: 0
    )

    /// Check if text has changed significantly from another result
    func hasTextChanged(from other: DocumentReadingResult?) -> Bool {
        guard let other = other else { return hasText }

        // Simple comparison - could be made more sophisticated
        let currentNormalized = extractedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let otherNormalized = other.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Consider changed if more than 10% different
        if currentNormalized.isEmpty && otherNormalized.isEmpty {
            return false
        }

        if currentNormalized.isEmpty || otherNormalized.isEmpty {
            return true
        }

        // Simple length-based change detection
        let lengthDiff = abs(currentNormalized.count - otherNormalized.count)
        let maxLength = max(currentNormalized.count, otherNormalized.count)
        let changeRatio = Double(lengthDiff) / Double(maxLength)

        return changeRatio > 0.1 || currentNormalized != otherNormalized
    }
}

// MARK: - Capture Mode

/// What the user is pointing the glasses at.
///
/// This is not cosmetic: each mode wants different image preprocessing, a
/// different tolerance for failed boundary detection, and a different prompt.
enum CaptureMode: String, CaseIterable, Identifiable {
    /// A page or printed document. Rectangular, high contrast, boundary reliably
    /// detected, OCR does most of the work.
    case document

    /// A whiteboard or flip chart. Often frameless against a light wall, so the
    /// document detector usually finds nothing; marker colour carries meaning and
    /// must survive to the model; handwriting means the image matters more than
    /// the OCR text.
    case whiteboard

    /// A book barcode. Read by the model's barcode tool, not by the OCR pipeline.
    case barcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .document: return "Document"
        case .whiteboard: return "Whiteboard"
        case .barcode: return "Book"
        }
    }

    var symbolName: String {
        switch self {
        case .document: return "doc.text"
        case .whiteboard: return "rectangle.on.rectangle"
        case .barcode: return "barcode.viewfinder"
        }
    }

    /// Whether a detected rectangle is required before a capture can proceed.
    ///
    /// Whiteboards frequently have no detectable edge — a frameless board on a
    /// white wall gives the segmentation request nothing to lock onto — so a
    /// missing boundary must not block the capture.
    var requiresDocumentBoundary: Bool {
        self == .document
    }

    /// Whether this mode runs the OCR + summarization pipeline at all.
    var usesTextPipeline: Bool {
        self != .barcode
    }
}

// MARK: - Recognized Barcode

/// A barcode read directly by Vision.
///
/// Vision returns the payload itself, so the digits never depend on the
/// language model — this works offline and on devices whose model variant has
/// no vision capability.
struct RecognizedBarcode: Equatable {
    let payload: String
    let symbology: String

    /// Whether this is a book barcode.
    ///
    /// ISBN-13 is carried as an EAN-13 whose Bookland prefix is 978 or 979.
    /// Anything else scanned off a product is a real barcode but not a book.
    var isISBN: Bool {
        symbology == "ean13" && (payload.hasPrefix("978") || payload.hasPrefix("979"))
    }
}

// MARK: - Document Reader State
/// State of the document reader
enum DocumentReaderState: Equatable {
    case idle
    case scanning
    case detectingDocument
    case processingDocument
    case documentDetected
    case readingText
    case reading
    case complete
    case error(String)

    var description: String {
        switch self {
        case .idle:
            return "Ready"
        case .scanning:
            return "Scanning..."
        case .detectingDocument:
            return "Detecting..."
        case .processingDocument:
            return "Processing..."
        case .documentDetected:
            return "Document Found"
        case .readingText:
            return "Reading Text..."
        case .reading:
            return "Reading..."
        case .complete:
            return "Complete"
        case .error(let message):
            return message
        }
    }
}
