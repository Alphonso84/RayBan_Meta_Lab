//
//  CaptureRulesTests.swift
//  Smart GlassesTests
//
//  Covers the rules that decide whether a capture is worth summarizing.
//
//  These shipped broken once: the processor was taught to accept image-only
//  whiteboard captures while the scanner view still required OCR text, so a
//  whiteboard capture was accepted and then silently never summarized — the UI
//  sat on "Capturing Photo" forever. The rule now lives in one place, and this
//  suite is what keeps it there.
//

import Testing
import UIKit
@testable import Smart_Glasses

@MainActor
struct CaptureRulesTests {

    // MARK: - Helpers

    private func result(text: String, hasVisionImage: Bool) -> DocumentReadingResult {
        DocumentReadingResult(
            documentBoundary: nil,
            correctedImage: nil,
            visionImage: hasVisionImage ? UIImage() : nil,
            extractedText: text,
            textBlocks: [],
            timestamp: Date(),
            processingTimeMs: 0
        )
    }

    // MARK: - The regression

    /// The exact case that hung: a whiteboard photo whose marker handwriting
    /// produced no OCR text at all.
    @Test func whiteboardWithNoTextIsStillSummarizable() {
        let capture = result(text: "", hasVisionImage: true)

        #expect(capture.isSummarizable(in: .whiteboard, visionSupported: true))
    }

    /// The same capture in document mode is *not* summarizable — a page with no
    /// text and no readable image is a failed scan, not a diagram.
    @Test func documentWithNoTextIsNotSummarizable() {
        let capture = result(text: "", hasVisionImage: true)

        #expect(!capture.isSummarizable(in: .document, visionSupported: true))
    }

    /// Falling back to OCR-only is what happens on a device whose model variant
    /// has no vision capability, so an image alone cannot carry the capture.
    @Test func whiteboardNeedsVisionSupportToStandOnImageAlone() {
        let capture = result(text: "", hasVisionImage: true)

        #expect(!capture.isSummarizable(in: .whiteboard, visionSupported: false))
    }

    @Test func whiteboardWithoutImageIsNotSummarizable() {
        let capture = result(text: "", hasVisionImage: false)

        #expect(!capture.isSummarizable(in: .whiteboard, visionSupported: true))
    }

    /// Text alone is always enough, in every mode and regardless of vision.
    @Test(arguments: [CaptureMode.document, .whiteboard, .barcode])
    func anyTextIsSummarizable(mode: CaptureMode) {
        let capture = result(text: "Mitochondria are the powerhouse", hasVisionImage: false)

        #expect(capture.isSummarizable(in: mode, visionSupported: false))
    }

    // MARK: - Mode configuration

    /// Whiteboards routinely have no detectable edge — a frameless board on a
    /// white wall gives the segmentation request nothing to lock onto — so
    /// requiring a boundary would block the capture entirely.
    @Test func onlyDocumentModeRequiresABoundary() {
        #expect(CaptureMode.document.requiresDocumentBoundary)
        #expect(!CaptureMode.whiteboard.requiresDocumentBoundary)
        #expect(!CaptureMode.barcode.requiresDocumentBoundary)
    }

    @Test func barcodeModeSkipsTheTextPipeline() {
        #expect(CaptureMode.document.usesTextPipeline)
        #expect(CaptureMode.whiteboard.usesTextPipeline)
        #expect(!CaptureMode.barcode.usesTextPipeline)
    }

    /// The raw values are persisted in `@AppStorage("captureMode")`. Renaming one
    /// silently resets the user's selected mode on next launch, so pin them.
    @Test func rawValuesArePersistedAndMustNotChange() {
        #expect(CaptureMode.document.rawValue == "document")
        #expect(CaptureMode.whiteboard.rawValue == "whiteboard")
        #expect(CaptureMode.barcode.rawValue == "barcode")
        #expect(CaptureMode.allCases.count == 3)
    }

    // MARK: - Barcode classification

    /// ISBN-13 rides on EAN-13 with a Bookland prefix of 978 or 979.
    @Test func booklandPrefixesAreRecognizedAsISBN() {
        #expect(RecognizedBarcode(payload: "9780306406157", symbology: "ean13").isISBN)
        #expect(RecognizedBarcode(payload: "9790306406157", symbology: "ean13").isISBN)
    }

    /// A real barcode, but off a cereal box rather than a book.
    @Test func nonBooklandEAN13IsNotISBN() {
        #expect(!RecognizedBarcode(payload: "0123456789012", symbology: "ean13").isISBN)
    }

    /// The prefix alone is not enough — the symbology has to be EAN-13.
    @Test func booklandPrefixOnAnotherSymbologyIsNotISBN() {
        #expect(!RecognizedBarcode(payload: "9780306406157", symbology: "code128").isISBN)
        #expect(!RecognizedBarcode(payload: "97803064", symbology: "ean8").isISBN)
    }
}
