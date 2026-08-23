//
//  PageVisionSupport.swift
//  Smart Glasses
//
//  Vision-assisted summarization: prepares page images for the language model
//  and holds the text + image prompt wording.
//
//  All iOS 27 image-attachment API usage in the app is isolated to this file
//  and to the one branch in StreamingSummarizer.summarize(_:pageImage:).
//

import Foundation
import UIKit
import CoreGraphics

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Image Preparation

/// Prepares perspective-corrected page images for use as language model attachments.
enum PageVisionImage {

    /// Longest-side dimension for images handed to the language model.
    ///
    /// The OCR pipeline renders at `DocumentReaderProcessor.targetProcessingDimension`
    /// (2500px) because Vision benefits from the extra resolution. The language model
    /// does not — larger images cost proportionally more tokens and latency. 1024 is
    /// enough to read figures, headings and layout while keeping the attachment cheap.
    ///
    /// The model accepts any size and aspect ratio, so never crop or pad to a square.
    static let defaultMaxDimension: CGFloat = 1024

    /// Downscale a page image and normalize its orientation for attachment.
    ///
    /// Redrawing rather than reading `.cgImage` directly bakes in any
    /// `UIImage.imageOrientation`, so the attachment never needs a separate
    /// orientation argument.
    ///
    /// - Returns: `nil` if the image is degenerate or rendering fails.
    static func prepare(_ image: UIImage, maxDimension: CGFloat = defaultMaxDimension) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        // Never upscale — a small source image gains nothing from interpolation.
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let target = CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }
}

// MARK: - Prompt Construction

#if canImport(FoundationModels)

/// Summarization prompt wording, with the vision and text-only variants kept
/// side by side so they stay in sync.
enum PageVisionPrompt {

    /// Whether image attachments are supported at runtime.
    ///
    /// Asks the model rather than assuming: `capabilities` reflects the actual
    /// on-device model variant, which can differ between devices on the same OS.
    /// Callers use this to skip image preparation entirely rather than doing the
    /// work and discarding it.
    static var isVisionSupported: Bool {
        SystemLanguageModel.default.capabilities.contains(.vision)
    }

    /// Prompt used when no page image is available, or on iOS 26.
    static func textOnly(documentText: String) -> Prompt {
        Prompt("""
        Summarize the following document text:

        ---
        \(documentText)
        ---

        Provide:
        1. A concise summary as if taking notes in college (1-3 sentences)
        2. Key points that would be useful to learning the topic (3-5 bullet points)
        3. A suggested title
        4. The document type
        5. Leave the visual description empty — no page image was provided.
        """)
    }

    /// Leading half of the whiteboard prompt, placed *before* the attachment.
    ///
    /// Deliberately does not mention reading order or "the page": a board is
    /// laid out spatially, not linearly, and the arrows and groupings are often
    /// the actual content. OCR is demoted to a hint because marker handwriting
    /// is exactly where `VNRecognizeTextRequest` is weakest.
    static let whiteboardHeader = """
    You are given a photograph of a whiteboard, followed by whatever text an OCR \
    engine managed to extract from it.

    The photo was taken with a head-worn camera, usually from across a room and \
    often at an angle, and the writing is handwritten in marker. Expect the OCR \
    text to be badly mangled or nearly empty — read the board yourself from the \
    image and treat what you see as the truth.

    A whiteboard is laid out spatially rather than in reading order. Pay attention \
    to how the content is arranged: what is boxed or circled, what arrows connect \
    to what and in which direction, what is grouped in a column or list, what is \
    starred or underlined for emphasis, and what different marker colours are being \
    used to distinguish.

    Whiteboard photo:
    """

    /// Trailing half of the whiteboard prompt, placed *after* the attachment.
    static func whiteboardBody(documentText: String) -> String {
        """

        OCR text from that board (likely unreliable — prefer the image):
        ---
        \(documentText)
        ---

        Provide:
        1. A concise summary of what this board is working through (1-3 sentences)
        2. Key points a student would want in their notes (3-5 bullets), following \
        the board's own structure rather than inventing one
        3. A suggested title, using the board's heading if it has one
        4. The document type — say "whiteboard"
        5. A description of the board's diagram or layout: the boxes, arrows, \
        groupings and what they connect. This is read aloud, so describe it as you \
        would to someone who cannot see the board. If the board is only writing with \
        no structure worth describing, leave this empty.
        """
    }

    /// Leading half of the vision prompt, placed *before* the image attachment.
    ///
    /// The OCR-repair framing is the point of this whole feature: glasses capture
    /// is often at a distance, so `textConfidenceThreshold` is set as low as 0.2
    /// and the resulting text is noisy. Telling the model the image outranks the
    /// text is what lets it fix those errors.
    static let visionHeader = """
    You are given a photograph of a document page, followed by the text an OCR \
    engine extracted from it.

    The photo was taken with a head-worn camera, often at a distance, so the OCR \
    text frequently contains errors: misread characters, dropped words, merged \
    lines, and garbled formulas. Read the page image yourself and treat it as the \
    source of truth. Use the OCR text only as a hint, and silently correct it \
    wherever the image disagrees.

    Page image:
    """

    /// Trailing half of the vision prompt, placed *after* the image attachment.
    static func visionBody(documentText: String) -> String {
        """

        OCR text extracted from that page (may contain errors):
        ---
        \(documentText)
        ---

        Provide:
        1. A concise summary as if taking notes in college (1-3 sentences)
        2. Key points that would be useful to learning the topic (3-5 bullet points)
        3. A suggested title, using the page's actual heading when one is visible
        4. The document type
        5. A visual description of any diagram, chart, table, equation or figure on \
        the page — what it shows and what it means, not merely that it is present. \
        This is read aloud to the user, so write plain prose. If the page is text \
        only, leave this empty.
        """
    }
}

#endif
