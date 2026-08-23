//
//  StudyIntents.swift
//  Smart Glasses
//
//  Hands-free study actions. These deliberately do not open the app: the point
//  of asking while wearing glasses is to keep your hands and eyes where they
//  are, so each one answers out loud and returns.
//

import AppIntents
import Foundation
import SwiftData

// MARK: - Read a Card

struct ReadCardIntent: AppIntent {

    static let title: LocalizedStringResource = "Read a Card"
    static let description = IntentDescription(
        "Reads a study card's summary and key points aloud.",
        categoryName: "Study"
    )

    /// Answers aloud without taking over the screen.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Card")
    var card: SummaryCardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Read \(\.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // With no card named, fall back to the most recent one — "read me my
        // last card" is the common case and should not require naming it.
        let target: SummaryCardEntity
        if let card {
            target = card
        } else if let latest = try StudyEntityStore.recentCards(limit: 1).first {
            target = latest
        } else {
            return .result(value: "", dialog: "You don't have any cards yet.")
        }

        let spoken = "\(target.title). \(target.spokenText)"
        return .result(value: spoken, dialog: "\(spoken)")
    }
}

// MARK: - Summarize a Deck

struct SummarizeDeckIntent: AppIntent {

    static let title: LocalizedStringResource = "Summarize a Deck"
    static let description = IntentDescription(
        "Reads a deck's overall summary aloud, generating one if it doesn't exist yet.",
        categoryName: "Study"
    )

    static let openAppWhenRun: Bool = false

    @Parameter(title: "Deck")
    var deck: SummaryDeckEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$deck)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // Prefer the stored summary — regenerating on every ask would be slow
        // and would burn context for no benefit.
        if let existing = deck.deckSummary, !existing.isEmpty {
            return .result(value: existing, dialog: "\(spokenSummary(existing, themes: deck.deckKeyPoints))")
        }

        guard let storedDeck = try StudyEntityStore.deck(for: deck.id), !storedDeck.cards.isEmpty else {
            return .result(value: "", dialog: "That deck is empty.")
        }

        let summarizer = StreamingSummarizer()
        await summarizer.checkAvailability()

        guard let output = await summarizer.summarizeDeck(
            cardSummaries: storedDeck.combinedCardSummaries,
            cardCount: storedDeck.cards.count,
            deckTitle: storedDeck.title
        ) else {
            return .result(value: "", dialog: "I couldn't summarize that deck.")
        }

        // Persist so the next ask is instant.
        storedDeck.deckSummary = output.summary
        storedDeck.deckKeyPoints = output.keyThemes
        try? SharedModelContainer.context.save()

        await StudyEntityIndexer.reindexAll()

        return .result(
            value: output.summary,
            dialog: "\(spokenSummary(output.summary, themes: output.keyThemes))"
        )
    }

    private func spokenSummary(_ summary: String, themes: [String]?) -> String {
        guard let themes, !themes.isEmpty else { return summary }
        return summary + ". Key themes: " + themes.joined(separator: ". ")
    }
}
