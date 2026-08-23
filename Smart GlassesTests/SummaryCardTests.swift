//
//  SummaryCardTests.swift
//  Smart GlassesTests
//
//  Covers the derived text on a card: what gets spoken aloud and what gets
//  shown in a preview.
//

import Testing
import SwiftData
@testable import Smart_Glasses

@MainActor
struct SummaryCardTests {

    private func card(
        summary: String = "A summary.",
        keyPoints: [String] = [],
        visualDescription: String? = nil
    ) -> SummaryCard {
        SummaryCard(
            title: "Title",
            summary: summary,
            keyPoints: keyPoints,
            sourceText: "raw ocr",
            visualDescription: visualDescription
        )
    }

    // MARK: - Speech

    /// Speech order matters: the summary orients the listener before details.
    @Test func speechCombinesSummaryKeyPointsAndFigures() {
        let c = card(
            summary: "Cells make energy",
            keyPoints: ["Glycolysis", "Krebs cycle"],
            visualDescription: "A cycle diagram"
        )

        #expect(c.textForSpeech == "Cells make energy. Key points: Glycolysis. Krebs cycle. On the page: A cycle diagram")
    }

    /// A text-only page must not have a dangling "On the page:" read out.
    @Test func speechOmitsFiguresWhenThereAreNone() {
        let c = card(summary: "Cells make energy", keyPoints: ["Glycolysis"])

        #expect(c.textForSpeech == "Cells make energy. Key points: Glycolysis")
    }

    @Test func speechOmitsKeyPointsWhenThereAreNone() {
        #expect(card(summary: "Just this").textForSpeech == "Just this")
    }

    // MARK: - Visual description

    /// The model returns an empty string for text-only pages rather than nil,
    /// so emptiness has to be checked, not just nil-ness.
    @Test func whitespaceOnlyFiguresCountAsAbsent() {
        #expect(!card(visualDescription: "").hasVisualDescription)
        #expect(!card(visualDescription: "   \n ").hasVisualDescription)
        #expect(card(visualDescription: "A bar chart").hasVisualDescription)
        #expect(!card(visualDescription: nil).hasVisualDescription)
    }

    @Test func speechOmitsAWhitespaceOnlyFigureDescription() {
        let c = card(summary: "Body", visualDescription: "   ")

        #expect(c.textForSpeech == "Body")
    }

    // MARK: - Preview

    @Test func shortSummariesArePreviewedWhole() {
        let c = card(summary: "Short one")

        #expect(c.previewText == "Short one")
    }

    @Test func longSummariesAreTruncatedWithAnEllipsis() {
        let c = card(summary: String(repeating: "x", count: 250))

        #expect(c.previewText.hasSuffix("..."))
        #expect(c.previewText.count == 103)
    }

    /// Exactly at the limit is not truncated.
    @Test func aSummaryOfExactlyTheLimitIsNotTruncated() {
        let c = card(summary: String(repeating: "x", count: 100))

        #expect(c.previewText.count == 100)
        #expect(!c.previewText.hasSuffix("..."))
    }

    // MARK: - Word count

    @Test func wordCountCountsWordsNotCharacters() {
        #expect(card(summary: "one two three").wordCount == 3)
        #expect(card(summary: "").wordCount == 0)
    }
}
