//
//  DeckTests.swift
//  Smart GlassesTests
//
//  Covers deck aggregation and the two caches hanging off a deck: the generated
//  deck summary and the generated flashcards.
//
//  Both caches are expensive to rebuild — each is a model round trip — so the
//  staleness rules decide how often the user waits.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Smart_Glasses

@MainActor
struct DeckTests {

    /// An in-memory store, so tests never touch the user's library.
    private let context: ModelContext

    init() throws {
        let schema = Schema([SummaryCard.self, SummaryDeck.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    // MARK: - Fixtures

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDeck(title: String = "Biology") -> SummaryDeck {
        let deck = SummaryDeck(title: title)
        context.insert(deck)
        return deck
    }

    @discardableResult
    private func addCard(
        to deck: SummaryDeck,
        title: String,
        summary: String = "Summary",
        keyPoints: [String] = [],
        createdAt: Date
    ) -> SummaryCard {
        let card = SummaryCard(
            title: title,
            summary: summary,
            keyPoints: keyPoints,
            sourceText: "source of \(title)",
            createdAt: createdAt,
            deck: deck
        )
        context.insert(card)
        return card
    }

    // MARK: - Ordering

    @Test func cardsSortNewestFirst() {
        let deck = makeDeck()
        addCard(to: deck, title: "Oldest", createdAt: Self.epoch)
        addCard(to: deck, title: "Newest", createdAt: Self.epoch.addingTimeInterval(200))
        addCard(to: deck, title: "Middle", createdAt: Self.epoch.addingTimeInterval(100))

        #expect(deck.sortedCards.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    // MARK: - Summary staleness

    /// A deck that has never been summarized is outdated by definition, so the
    /// first request always generates.
    @Test func aDeckWithNoSummaryIsOutdated() {
        let deck = makeDeck()
        addCard(to: deck, title: "One", createdAt: Self.epoch)

        #expect(deck.isSummaryOutdated)
        #expect(deck.cardsAddedSinceSummary == 1)
    }

    @Test func aSummaryCoveringEveryCardIsCurrent() {
        let deck = makeDeck()
        addCard(to: deck, title: "One", createdAt: Self.epoch)
        deck.deckSummary = "All about cells"
        deck.summaryGeneratedAt = Self.epoch.addingTimeInterval(60)

        #expect(!deck.isSummaryOutdated)
        #expect(deck.cardsAddedSinceSummary == 0)
        #expect(deck.hasDeckSummary)
    }

    @Test func aCardAddedAfterGenerationMakesTheSummaryOutdated() {
        let deck = makeDeck()
        addCard(to: deck, title: "One", createdAt: Self.epoch)
        deck.summaryGeneratedAt = Self.epoch.addingTimeInterval(60)
        addCard(to: deck, title: "Two", createdAt: Self.epoch.addingTimeInterval(120))

        #expect(deck.isSummaryOutdated)
        #expect(deck.cardsAddedSinceSummary == 1)
    }

    /// An empty string is not a usable summary and must not suppress generation.
    @Test func anEmptySummaryDoesNotCountAsHavingOne() {
        let deck = makeDeck()
        deck.deckSummary = ""

        #expect(!deck.hasDeckSummary)
    }

    @Test func clearingResetsEveryPartOfTheSummary() {
        let deck = makeDeck()
        deck.deckSummary = "Something"
        deck.deckKeyPoints = ["A", "B"]
        deck.summaryGeneratedAt = Self.epoch

        deck.clearDeckSummary()

        #expect(deck.deckSummary == nil)
        #expect(deck.deckKeyPoints == nil)
        #expect(deck.summaryGeneratedAt == nil)
        #expect(deck.isSummaryOutdated)
    }

    // MARK: - Flashcard cache

    @Test func flashcardsSurviveAnEncodeDecodeRoundTrip() {
        let deck = makeDeck()
        let flashcards = [
            Flashcard(front: "ATP", back: "Energy currency", sourceCardTitle: "Metabolism"),
            Flashcard(front: "Krebs", back: "Citric acid cycle", sourceCardTitle: "Metabolism", category: "Cycles")
        ]

        deck.saveFlashcards(flashcards)

        #expect(deck.hasFlashcards)
        let restored = deck.cachedFlashcards
        #expect(restored?.count == 2)
        #expect(restored?.first?.front == "ATP")
        #expect(restored?.last?.category == "Cycles")
        #expect(restored?.map(\.id) == flashcards.map(\.id))
    }

    @Test func aDeckWithNoFlashcardsHasNoCache() {
        let deck = makeDeck()

        #expect(!deck.hasFlashcards)
        #expect(deck.cachedFlashcards == nil)
        #expect(deck.areFlashcardsOutdated)
    }

    @Test func clearingRemovesTheFlashcardCache() {
        let deck = makeDeck()
        deck.saveFlashcards([Flashcard(front: "A", back: "B", sourceCardTitle: "T")])

        deck.clearFlashcards()

        #expect(!deck.hasFlashcards)
        #expect(deck.cachedFlashcards == nil)
    }

    @Test func aCardAddedAfterGenerationMakesFlashcardsOutdated() {
        let deck = makeDeck()
        addCard(to: deck, title: "One", createdAt: Self.epoch)
        deck.flashcardsGeneratedAt = Self.epoch.addingTimeInterval(60)

        #expect(!deck.areFlashcardsOutdated)

        addCard(to: deck, title: "Two", createdAt: Self.epoch.addingTimeInterval(120))

        #expect(deck.areFlashcardsOutdated)
        #expect(deck.cardsAddedSinceFlashcards == 1)
    }

    // MARK: - Aggregated text

    /// What gets sent to the model for a deck summary. It is numbered and
    /// titled so the model can attribute themes back to individual cards.
    @Test func combinedSummariesAreNumberedInDisplayOrder() {
        let deck = makeDeck()
        addCard(to: deck, title: "Older", summary: "First body", keyPoints: ["a"], createdAt: Self.epoch)
        addCard(to: deck, title: "Newer", summary: "Second body", keyPoints: ["b", "c"],
                createdAt: Self.epoch.addingTimeInterval(100))

        let combined = deck.combinedCardSummaries

        #expect(combined == """
        Card 1 - Newer:
        Second body
        Key Points: b; c

        Card 2 - Older:
        First body
        Key Points: a
        """)
    }

    @Test func combinedSourceTextCarriesEveryCard() {
        let deck = makeDeck()
        addCard(to: deck, title: "One", createdAt: Self.epoch)
        addCard(to: deck, title: "Two", createdAt: Self.epoch.addingTimeInterval(100))

        let combined = deck.combinedSourceText

        #expect(combined.contains("source of One"))
        #expect(combined.contains("source of Two"))
        #expect(deck.totalSourceTextLength == "source of One".count + "source of Two".count)
    }

    @Test func anEmptyDeckAggregatesToNothing() {
        let deck = makeDeck()

        #expect(deck.cardCount == 0)
        #expect(deck.combinedCardSummaries.isEmpty)
        #expect(deck.combinedSourceText.isEmpty)
        #expect(deck.totalSourceTextLength == 0)
    }

    // MARK: - Colors

    /// `SummaryDeck.color` falls back to blue, so an unparsable hex must not
    /// crash or render as clear.
    @Test func presetColorsAreAllSixDigitHex() {
        for hex in SummaryDeck.presetColors {
            // Evaluated outside the macro: `allSatisfy` is `rethrows`, which the
            // #expect expansion cannot prove non-throwing.
            let isHex = hex.allSatisfy { $0.isHexDigit }
            #expect(hex.count == 6, "\(hex) is not 6 digits")
            #expect(isHex, "\(hex) is not hex")
        }
    }

    @Test func hexParsingRejectsWrongLengthsAndStripsTheHash() {
        #expect(Color(hex: "007AFF") != nil)
        #expect(Color(hex: "#007AFF") != nil)
        #expect(Color(hex: " 007AFF ") != nil)
        #expect(Color(hex: "007AF") == nil)
        #expect(Color(hex: "007AFFF") == nil)
        #expect(Color(hex: "") == nil)
    }
}
