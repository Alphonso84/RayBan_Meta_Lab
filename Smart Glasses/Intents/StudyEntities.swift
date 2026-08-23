//
//  StudyEntities.swift
//  Smart Glasses
//
//  Cards and decks described as App Entities so Siri can find and reason about
//  them — "what did I read about mitochondria?" — rather than treating the app
//  as a black box.
//
//  Both conform to `IndexedEntity`, which puts them in the system semantic
//  index. That is what turns exact-name matching into meaning-based search, and
//  it is also what gives the app Spotlight integration without a separate
//  CoreSpotlight layer.
//

import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

// MARK: - Card Entity

struct SummaryCardEntity: AppEntity, IndexedEntity {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Study Card"
    static let defaultQuery = SummaryCardEntityQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Summary")
    var summary: String

    @Property(title: "Deck")
    var deckTitle: String

    @Property(title: "Created")
    var createdAt: Date

    var keyPoints: [String]
    var visualDescription: String?
    var thumbnailData: Data?

    init(card: SummaryCard) {
        self.id = card.id
        self.keyPoints = card.keyPoints
        self.visualDescription = card.visualDescription
        self.thumbnailData = card.thumbnailData
        self.title = card.title.isEmpty ? "Untitled" : card.title
        self.summary = card.summary
        self.deckTitle = card.deck?.title ?? "Unsorted"
        self.createdAt = card.createdAt
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(deckTitle)"
        )
    }

    /// Everything worth speaking aloud, in the order a listener wants it.
    var spokenText: String {
        var text = summary
        if !keyPoints.isEmpty {
            text += ". Key points: " + keyPoints.joined(separator: ". ")
        }
        if let visualDescription, !visualDescription.isEmpty {
            text += ". On the page: " + visualDescription
        }
        return text
    }

    /// What Spotlight and the semantic index see.
    ///
    /// Deliberately excludes `sourceText`: raw OCR is noisy — misread words,
    /// merged lines — and indexing it pollutes retrieval with terms the user
    /// never actually read.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = title
        set.displayName = title
        set.subject = title
        set.contentDescription = summary
        set.keywords = keyPoints
        set.contentCreationDate = createdAt

        // Shows as the result's type in Spotlight, so a card is distinguishable
        // from a deck at a glance.
        set.kind = "Study Card"

        // Spotlight renders these as the result's container, which surfaces the
        // deck a card belongs to without the user opening anything.
        set.containerTitle = deckTitle
        set.containerDisplayName = deckTitle

        // The scanned page itself, so results are visually recognizable — far
        // easier to pick out than a wall of model-generated titles.
        set.thumbnailData = thumbnailData

        // Everything searchable in one field. `sourceText` is deliberately
        // excluded: raw OCR is noisy and would match words the user never read.
        var body = [summary]
        body.append(contentsOf: keyPoints)
        if let visualDescription, !visualDescription.isEmpty {
            body.append(visualDescription)
        }
        body.append(deckTitle)
        set.textContent = body.joined(separator: "\n")

        return set
    }
}

// MARK: - Deck Entity

struct SummaryDeckEntity: AppEntity, IndexedEntity {

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Deck"
    static let defaultQuery = SummaryDeckEntityQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Cards")
    var cardCount: Int

    var deckDescription: String?
    var deckSummary: String?
    var deckKeyPoints: [String]?
    var cardTitles: [String]
    var thumbnailData: Data?
    var lastAccessedAt: Date

    init(deck: SummaryDeck) {
        self.id = deck.id
        self.deckDescription = deck.deckDescription
        self.deckSummary = deck.deckSummary
        self.deckKeyPoints = deck.deckKeyPoints
        self.cardTitles = deck.sortedCards.map(\.title)
        self.thumbnailData = deck.sortedCards.first?.thumbnailData
        self.lastAccessedAt = deck.lastAccessedAt
        self.title = deck.title
        self.cardCount = deck.cards.count
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(cardCount) cards"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = title
        set.displayName = title
        set.subject = title
        set.contentDescription = deckSummary ?? deckDescription ?? "\(cardCount) cards"
        set.kind = "Deck"
        set.contentModificationDate = lastAccessedAt
        set.thumbnailData = thumbnailData

        var keywords = deckKeyPoints ?? []
        // Card titles make a deck findable by what is *in* it, which is usually
        // how people remember a deck they named months ago.
        keywords.append(contentsOf: cardTitles)
        set.keywords = keywords

        var body: [String] = []
        if let deckSummary { body.append(deckSummary) }
        if let deckDescription { body.append(deckDescription) }
        if let deckKeyPoints { body.append(contentsOf: deckKeyPoints) }
        body.append(contentsOf: cardTitles)
        set.textContent = body.joined(separator: "\n")

        return set
    }
}

// MARK: - Queries

struct SummaryCardEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [SummaryCardEntity] {
        try await StudyEntityStore.cards { card in
            identifiers.contains(card.id)
        }
    }

    /// Fallback matching for when Siri hands over raw text rather than resolving
    /// through the semantic index.
    func entities(matching string: String) async throws -> [SummaryCardEntity] {
        let terms = StudyEntityStore.searchTerms(in: string)
        guard !terms.isEmpty else { return [] }

        return try await StudyEntityStore.cards { card in
            var haystack = [card.title, card.summary, card.deck?.title ?? ""]
            haystack.append(contentsOf: card.keyPoints)
            if let visual = card.visualDescription { haystack.append(visual) }
            return StudyEntityStore.matches(terms: terms, in: haystack)
        }
    }

    /// Most recent cards, shown when Siri or Shortcuts needs something to offer.
    func suggestedEntities() async throws -> [SummaryCardEntity] {
        try await StudyEntityStore.recentCards(limit: 10)
    }
}

struct SummaryDeckEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [SummaryDeckEntity] {
        try await StudyEntityStore.decks { deck in
            identifiers.contains(deck.id)
        }
    }

    func entities(matching string: String) async throws -> [SummaryDeckEntity] {
        let terms = StudyEntityStore.searchTerms(in: string)
        guard !terms.isEmpty else { return [] }

        return try await StudyEntityStore.decks { deck in
            var haystack = [deck.title, deck.deckDescription ?? "", deck.deckSummary ?? ""]
            haystack.append(contentsOf: deck.deckKeyPoints ?? [])
            // Findable by what the deck contains, not only by its name.
            haystack.append(contentsOf: deck.cards.map(\.title))
            return StudyEntityStore.matches(terms: terms, in: haystack)
        }
    }

    func suggestedEntities() async throws -> [SummaryDeckEntity] {
        try await StudyEntityStore.decks { _ in true }
    }
}

// MARK: - Store

/// SwiftData reads for the entity queries.
///
/// Filtering happens in Swift rather than in a `#Predicate` because the
/// matching rules reach across relationships and into arrays, which the
/// predicate compiler does not handle. Deck sizes here are small enough that
/// fetching and filtering in memory is not worth optimizing.
enum StudyEntityStore {

    // MARK: Matching

    /// Words worth matching on, with filler dropped.
    ///
    /// Siri passes through whole spoken phrases, so "the notes about photosynthesis"
    /// arrives intact. Matching the full string finds nothing; matching the
    /// meaningful words finds the card.
    nonisolated static func searchTerms(in query: String) -> [String] {
        let noise: Set<String> = [
            "the", "a", "an", "my", "about", "on", "for", "of", "in", "with",
            "notes", "note", "card", "cards", "deck", "decks", "read", "show", "find"
        ]
        return query
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !noise.contains($0.lowercased()) }
    }

    /// Whether every term appears somewhere in the haystack.
    ///
    /// `localizedStandardContains` is the important part: it folds case *and*
    /// diacritics and does the right thing for prefixes, so "mitochondria"
    /// matches "Mitochondrial respiration" where a plain lowercased `contains`
    /// would not.
    nonisolated static func matches(terms: [String], in haystack: [String]) -> Bool {
        terms.allSatisfy { term in
            haystack.contains { $0.localizedStandardContains(term) }
        }
    }


    @MainActor
    static func cards(matching isIncluded: (SummaryCard) -> Bool) throws -> [SummaryCardEntity] {
        let descriptor = FetchDescriptor<SummaryCard>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try SharedModelContainer.context
            .fetch(descriptor)
            .filter(isIncluded)
            .map(SummaryCardEntity.init)
    }

    @MainActor
    static func recentCards(limit: Int) throws -> [SummaryCardEntity] {
        var descriptor = FetchDescriptor<SummaryCard>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try SharedModelContainer.context
            .fetch(descriptor)
            .map(SummaryCardEntity.init)
    }

    @MainActor
    static func decks(matching isIncluded: (SummaryDeck) -> Bool) throws -> [SummaryDeckEntity] {
        let descriptor = FetchDescriptor<SummaryDeck>(
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        return try SharedModelContainer.context
            .fetch(descriptor)
            .filter(isIncluded)
            .map(SummaryDeckEntity.init)
    }

    /// The SwiftData deck behind an entity, for intents that need to mutate it.
    @MainActor
    static func deck(for id: UUID) throws -> SummaryDeck? {
        let descriptor = FetchDescriptor<SummaryDeck>()
        return try SharedModelContainer.context.fetch(descriptor).first { $0.id == id }
    }
}
