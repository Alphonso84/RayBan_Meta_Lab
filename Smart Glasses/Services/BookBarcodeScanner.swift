//
//  BookBarcodeScanner.swift
//  Smart Glasses
//
//  Reads a book barcode through the glasses using the Vision-backed
//  BarcodeReaderTool, so a textbook can become a deck without typing.
//
//  `BarcodeReaderTool` lives in the _Vision_FoundationModels cross-import
//  overlay — it appears by importing both Vision and FoundationModels, and
//  there is no module of its own to import.
//
//  That overlay ships in the device SDK only; it is absent from the iOS
//  Simulator SDK. Compiling this path unconditionally therefore breaks any
//  simulator build, including the unit test bundle, so the tool-backed scan is
//  guarded on the overlay being present. Vision reads barcodes directly in
//  `DocumentReaderProcessor` and is unaffected — this fallback is what the
//  simulator loses.
//

import Combine
import Foundation
import UIKit
import FoundationModels
import Vision


// MARK: - Output

#if canImport(FoundationModels)

@Generable
struct ScannedBookCode: Sendable {
    @Guide(description: "The barcode digits exactly as read, with no spaces or dashes. Empty string if no barcode is visible.")
    var code: String

    @Guide(description: "True only when the code is a 10- or 13-digit ISBN, which identifies a book.")
    var isISBN: Bool

    @Guide(description: "The book's title, but only if you recognize this specific ISBN with confidence. Empty string otherwise — never guess a title from the number.")
    var recognizedTitle: String
}

#else

struct ScannedBookCode: Sendable {
    var code: String
    var isISBN: Bool
    var recognizedTitle: String
}

#endif

extension ScannedBookCode {
    /// Whether anything usable came back.
    var hasCode: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Deck title to pre-fill. Falls back to the bare ISBN, which is at least
    /// something the user can recognize and rename.
    var suggestedDeckTitle: String {
        let title = recognizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return isISBN ? "ISBN \(code)" : code
    }
}

// MARK: - Scanner

@MainActor
final class BookBarcodeScanner: ObservableObject {

    enum ScanState: Equatable {
        case idle
        case scanning
        case complete
        case error(String)
    }

    @Published var state: ScanState = .idle
    @Published var result: ScannedBookCode?

    /// Barcodes are small in a head-worn frame and need finer detail than page
    /// text does, so this runs higher than `PageVisionImage.defaultMaxDimension`.
    private let barcodeImageDimension: CGFloat = 1_536

    private static let instructions = """
        You read barcodes from photographs. Use the barcode reading tool to get the
        exact digits — never transcribe them by eye from the image, and never invent
        a code when none is readable.

        Only claim to recognize a book title if you genuinely know that specific ISBN.
        A wrong title is worse than no title, because it silently mislabels the user's
        study material.
        """

    func reset() {
        state = .idle
        result = nil
    }

    /// Read a book barcode from a captured photo.
    @discardableResult
    func scan(_ image: UIImage) async -> ScannedBookCode? {
        state = .scanning
        result = nil

        #if canImport(FoundationModels) && canImport(_Vision_FoundationModels)
        guard PageVisionPrompt.isVisionSupported else {
            state = .error("This device's model cannot read images.")
            return nil
        }

        guard let cgImage = PageVisionImage.prepare(image, maxDimension: barcodeImageDimension) else {
            state = .error("Could not prepare the photo.")
            return nil
        }

        let session = LanguageModelSession(
            tools: [BarcodeReaderTool()],
            instructions: Self.instructions
        )

        // The attachment is labeled so the model can name it when calling the
        // tool — the tool resolves an ImageReference back to this attachment.
        let prompt = Prompt {
            "Read the barcode in the photo below and report what it says."
            Attachment(cgImage).label("barcode-photo")
        }

        do {
            let scanned = try await session.respond(
                to: prompt,
                generating: ScannedBookCode.self
            ).content

            guard scanned.hasCode else {
                state = .error("No barcode found. Move closer and hold steady.")
                return nil
            }

            result = scanned
            state = .complete
            print("[BookBarcodeScanner] Read \(scanned.code) (ISBN: \(scanned.isISBN))")
            return scanned

        } catch {
            print("[BookBarcodeScanner] Error: \(error)")
            state = .error(error.localizedDescription)
            return nil
        }
        #elseif canImport(FoundationModels)
        // Simulator: the barcode tool is unavailable, so this fallback cannot run.
        state = .error("Model-assisted barcode reading is unavailable in the Simulator.")
        return nil
        #else
        state = .error("Barcode scanning requires iOS 27.")
        return nil
        #endif
    }
}
