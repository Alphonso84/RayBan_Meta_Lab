//
//  StudyEntityTests.swift
//  Smart GlassesTests
//
//  Covers what Siri and Spotlight are given for a card or a deck.
//
//  These attributes are the entire input to the system's semantic index, so an
//  omission here shows up as "Siri can't find my notes" rather than as a
//  compile error.
//

import Testing
import CoreSpotlight
import Foundation
import SwiftData
@testable import Smart_Glasses

@MainActor
struct StudyEntityTests {

    private let context: ModelContext

    init() throws {
        let schema = Schema([SummaryCard.self, SummaryDeck.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    private func makeCard(
        title: String = "Photosynthesis",
        summary: String = "Plants convert light to sugar",
        keyPoints: [String] = ["Chloroplasts", "Light reactions"],
        sourceText: String = "PHOTOSYNTHES1S rnisread OCR junk",
        visualDescription: String? = "A leaf cross-section",
        deck: SummaryDeck? = nil
    ) -> SummaryCard {
        let card = SummaryCard(
            title: title,
            summary: summary,
            keyPoints: keyPoints,
            sourceText: sourceText,
            visualDescription: visualDescription,
            deck: deck
        )
        context.insert(card)
        return card
    }

    // MARK: - Card attributes

    @Test func cardIndexesTitleSummaryAndKeyPoints() {
        let attributes = SummaryCardEntity(card: makeCard()).attributeSet

        #expect(attributes.title == "Photosynthesis")
        #expect(attributes.displayName == "Photosynthesis")
        #expect(attributes.contentDescription == "Plants convert light to sugar")
        #expect(attributes.keywords == ["Chloroplasts", "Light reactions"])
        #expect(attributes.kind == "Study Card")
    }

    /// Raw OCR is noisy — misread words, merged lines — and indexing it pollutes
    /// retrieval with terms the user never actually read. This is a deliberate
    /// exclusion, so it gets a test rather than only a comment.
    @Test func rawOCRTextIsNeverIndexed() {
        let attributes = SummaryCardEntity(card: makeCard()).attributeSet

        #expect(attributes.textContent?.contains("rnisread") != true)
        #expect(attributes.textContent?.contains("junk") != true)
    }

    @Test func indexedTextCoversEverythingWorthSearching() {
        let deck = SummaryDeck(title: "Biology")
        context.insert(deck)
        let attributes = SummaryCardEntity(card: makeCard(deck: deck)).attributeSet
        let text = attributes.textContent ?? ""

        #expect(text.contains("Plants convert light to sugar"))
        #expect(text.contains("Chloroplasts"))
        #expect(text.contains("A leaf cross-section"))
        #expect(text.contains("Biology"))
    }

    /// Spotlight renders this as the result's container, which tells the user
    /// which deck a card is in without opening anything.
    @Test func cardReportsItsDeckAsTheContainer() {
        let deck = SummaryDeck(title: "Biology")
        context.insert(deck)
        let attributes = SummaryCardEntity(card: makeCard(deck: deck)).attributeSet

        #expect(attributes.containerTitle == "Biology")
        #expect(attributes.containerDisplayName == "Biology")
    }

    @Test func aCardWithNoDeckIsLabelledUnsorted() {
        let entity = SummaryCardEntity(card: makeCard(deck: nil))

        #expect(entity.deckTitle == "Unsorted")
        #expect(entity.attributeSet.containerTitle == "Unsorted")
    }

    /// An untitled card would otherwise show as a blank Spotlight row.
    @Test func anEmptyTitleFallsBackToAPlaceholder() {
        #expect(SummaryCardEntity(card: makeCard(title: "")).title == "Untitled")
    }

    @Test func spokenTextMatchesWhatTheCardWouldReadAloud() {
        let card = makeCard()
        let entity = SummaryCardEntity(card: card)

        #expect(entity.spokenText == card.textForSpeech)
    }

    @Test func spokenTextOmitsAnAbsentFigureDescription() {
        let entity = SummaryCardEntity(card: makeCard(keyPoints: [], visualDescription: nil))

        #expect(entity.spokenText == "Plants convert light to sugar")
    }

    // MARK: - Deck attributes

    /// People remember a deck by what is in it, not by a name they chose months
    /// ago, so card titles have to be searchable on the deck itself.
    @Test func deckIsFindableByTheTitlesOfItsCards() {
        let deck = SummaryDeck(title: "Semester One")
        context.insert(deck)
        makeCard(title: "Photosynthesis", deck: deck)
        makeCard(title: "Mitosis", deck: deck)

        let attributes = SummaryDeckEntity(deck: deck).attributeSet

        #expect(attributes.keywords?.contains("Photosynthesis") == true)
        #expect(attributes.keywords?.contains("Mitosis") == true)
        #expect(attributes.textContent?.contains("Mitosis") == true)
        #expect(attributes.kind == "Deck")
    }

    @Test func deckDescriptionPrefersTheGeneratedSummary() {
        let deck = SummaryDeck(title: "Biology", deckDescription: "Typed by hand")
        context.insert(deck)
        deck.deckSummary = "Generated overview"

        #expect(SummaryDeckEntity(deck: deck).attributeSet.contentDescription == "Generated overview")
    }

    @Test func deckDescriptionFallsBackToTheCardCount() {
        let deck = SummaryDeck(title: "Biology")
        context.insert(deck)
        makeCard(deck: deck)

        #expect(SummaryDeckEntity(deck: deck).attributeSet.contentDescription == "1 cards")
    }

    @Test func deckCountsItsCards() {
        let deck = SummaryDeck(title: "Biology")
        context.insert(deck)
        makeCard(title: "One", deck: deck)
        makeCard(title: "Two", deck: deck)

        #expect(SummaryDeckEntity(deck: deck).cardCount == 2)
    }
}
