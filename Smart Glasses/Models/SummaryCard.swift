//
//  SummaryCard.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import Foundation
import SwiftData

/// A single summary card representing a scanned document page/section
@Model
final class SummaryCard {
    /// Unique identifier
    var id: UUID

    /// Card title (e.g., "Chapter 3: Functions" or auto-generated)
    var title: String

    /// Main summary text
    var summary: String

    /// Key points extracted from the document
    var keyPoints: [String]

    /// Original OCR text for reference
    var sourceText: String

    /// Description of diagrams, charts, tables or equations on the scanned page.
    /// Nil for cards created before vision summarization, and empty for pages
    /// that are text only.
    var visualDescription: String?

    /// Optional page number or section reference
    var pageNumber: Int?

    /// Small thumbnail image of the scanned document (JPEG data)
    @Attribute(.externalStorage)
    var thumbnailData: Data?

    /// When the card was created
    var createdAt: Date

    /// The deck this card belongs to (optional - can be unsorted)
    var deck: SummaryDeck?

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        keyPoints: [String] = [],
        sourceText: String,
        visualDescription: String? = nil,
        pageNumber: Int? = nil,
        thumbnailData: Data? = nil,
        createdAt: Date = Date(),
        deck: SummaryDeck? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.keyPoints = keyPoints
        self.sourceText = sourceText
        self.visualDescription = visualDescription
        self.pageNumber = pageNumber
        self.thumbnailData = thumbnailData
        self.createdAt = createdAt
        self.deck = deck
    }
}

// MARK: - Convenience Extensions
extension SummaryCard {
    /// Formatted creation date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    /// Preview text (truncated summary)
    var previewText: String {
        if summary.count <= 100 {
            return summary
        }
        return String(summary.prefix(100)) + "..."
    }

    /// Whether the page carried a diagram, chart, table or equation
    var hasVisualDescription: Bool {
        guard let visualDescription else { return false }
        return !visualDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Full text for TTS (summary + key points + any figure description)
    var textForSpeech: String {
        var text = summary
        if !keyPoints.isEmpty {
            text += ". Key points: "
            text += keyPoints.joined(separator: ". ")
        }
        if hasVisualDescription, let visualDescription {
            text += ". On the page: "
            text += visualDescription
        }
        return text
    }

    /// Word count of the summary
    var wordCount: Int {
        summary.split(separator: " ").count
    }
}
