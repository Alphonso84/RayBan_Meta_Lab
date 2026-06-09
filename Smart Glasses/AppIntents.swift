//
//  AppIntents.swift
//  Smart Glasses
//
//  App Intents for Siri Shortcuts integration
//  Document scanning shortcuts
//

import AppIntents
import MWDATCamera
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Scan Document Intent

/// Intent to scan a document with smart glasses, extract text, and summarize it
struct ScanDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Document"
    static var description = IntentDescription("Scans a document using your smart glasses, extracts text, and generates an AI summary.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let manager = WearablesManager.shared
        let processor = manager.documentReaderProcessor

        // Reset any previous state
        processor.reset()

        // Navigate to Scan tab - this triggers MainTabView's stream management
        NavigationState.shared.selectedTab = .scan

        // Give the tab switch a moment to process
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Start streaming if not already streaming (MainTabView should handle this, but ensure it)
        if manager.streamState == .stopped {
            manager.startStream()
        }

        // Wait for stream to become active (up to 5 seconds)
        var attempts = 0
        while manager.streamState != .streaming && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        guard manager.streamState == .streaming else {
            throw ScanError.connectionFailed
        }

        // Wait for a frame to be available
        attempts = 0
        while manager.latestFrameImage == nil && attempts < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        guard let frame = manager.latestFrameImage else {
            throw ScanError.noFrame
        }

        // Capture and process the document
        processor.captureAndProcess(frame)

        // Wait for processing to complete (up to 15 seconds)
        attempts = 0
        while processor.state != .complete && processor.state != .idle && attempts < 150 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        // Check OCR results
        guard let result = processor.latestResult, result.hasText else {
            if processor.latestResult?.hasDocument == true {
                return .result(value: "", dialog: "Document detected but no text found.")
            } else {
                return .result(value: "", dialog: "No document detected. Point at a document and try again.")
            }
        }

        let extractedText = result.extractedText

        // Summarize the document using AI (respects provider setting)
        let summarizer = StreamingSummarizer()
        await summarizer.checkAvailability()
        // Provider selection is read from @AppStorage automatically

        guard let summaryOutput = await summarizer.summarize(extractedText) else {
            // Fallback to raw text if summarization fails
            let preview = extractedText.count > 200 ? String(extractedText.prefix(200)) + "..." : extractedText
            return .result(value: extractedText, dialog: "Scanned: \(preview)")
        }

        // Build the output string with summary and key points
        var outputText = summaryOutput.summary
        if !summaryOutput.keyPoints.isEmpty {
            outputText += "\n\nKey Points:\n"
            for point in summaryOutput.keyPoints {
                outputText += "• \(point)\n"
            }
        }

        // Create a spoken dialog with the title and summary
        let dialogText = "\(summaryOutput.suggestedTitle): \(summaryOutput.summary)"

        return .result(value: outputText, dialog: "\(dialogText)")
    }
}

// MARK: - Capture Photo Intent

/// Intent to capture a high-resolution photo with the glasses and return it as a
/// file. Shortcuts can then pass the returned image to any other action — save to
/// Photos, share, upload, run through another app, etc.
struct CaptureGlassesPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Photo with Glasses"
    static var description = IntentDescription("Takes a high-resolution photo using your smart glasses and returns the image to your shortcut.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let manager = WearablesManager.shared

        // Navigate to the Scan tab so MainTabView starts the stream. The glasses
        // require the app to be in the foreground to stream, hence openAppWhenRun.
        NavigationState.shared.selectedTab = .scan
        try? await Task.sleep(nanoseconds: 200_000_000)

        if manager.streamState == .stopped {
            manager.startStream()
        }

        // Wait for the stream to become active (up to 5 seconds).
        var attempts = 0
        while manager.streamState != .streaming && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        guard manager.streamState == .streaming else {
            throw ScanError.connectionFailed
        }

        // Wait until at least one frame has arrived, signalling the session is ready
        // to service a high-resolution photo capture.
        attempts = 0
        while manager.latestFrameImage == nil && attempts < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        // Capture a high-resolution still (capturePhotoAsync times out rather than
        // hanging the shortcut if the capture is dropped).
        guard let image = await manager.capturePhotoAsync(),
              let data = image.jpegData(compressionQuality: 0.9) else {
            throw ScanError.noFrame
        }

        // Stop the stream now that we have the photo, and return to the Library tab
        // so the live scanner preview isn't left running (saves battery and avoids
        // leaving the glasses streaming after a one-shot capture).
        manager.stopStream()
        NavigationState.shared.selectedTab = .library

        let file = IntentFile(data: data, filename: "glasses-photo.jpg", type: .jpeg)
        return .result(value: file, dialog: "Photo captured.")
    }
}

/// Errors for scanning intents
enum ScanError: Error, CustomLocalizedStringResourceConvertible {
    case connectionFailed
    case noFrame
    case processingFailed
    case summarizationFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .connectionFailed:
            return "Unable to connect to smart glasses. Make sure they're connected."
        case .noFrame:
            return "Could not get an image. Please try again."
        case .processingFailed:
            return "Failed to process the document."
        case .summarizationFailed:
            return "Failed to summarize the document."
        }
    }
}

// MARK: - App Shortcuts Provider

/// Provides shortcuts that appear in Siri and Shortcuts app
struct SmartGlassesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanDocumentIntent(),
            phrases: [
                "Scan this with \(.applicationName)",
                "Scan document with \(.applicationName)",
                "Scan with \(.applicationName)",
                "\(.applicationName) scan this",
                "\(.applicationName) scan document",
                "Read this with \(.applicationName)",
                "Read document with \(.applicationName)",
                "Capture document with \(.applicationName)",
                "Summarize this with \(.applicationName)",
                "Summarize document with \(.applicationName)"
            ],
            shortTitle: "Scan Document",
            systemImageName: "doc.viewfinder"
        )
        AppShortcut(
            intent: CaptureGlassesPhotoIntent(),
            phrases: [
                "Take a photo with \(.applicationName)",
                "Take a picture with \(.applicationName)",
                "Capture a photo with \(.applicationName)",
                "\(.applicationName) take a photo",
                "\(.applicationName) capture a photo"
            ],
            shortTitle: "Capture Photo",
            systemImageName: "camera.fill"
        )
    }
}
