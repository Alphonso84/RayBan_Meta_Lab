//
//  SearchMatchingTests.swift
//  Smart GlassesTests
//
//  Covers the fallback matching behind Siri and Spotlight lookups.
//
//  This runs when Siri hands over raw text instead of resolving an entity
//  through the semantic index, which is exactly when a spoken phrase arrives
//  intact — filler words and all.
//

import Testing
@testable import Smart_Glasses

struct SearchMatchingTests {

    // MARK: - Term extraction

    /// Siri passes whole spoken phrases. Matching the full string finds nothing;
    /// matching the meaningful words finds the card.
    @Test func fillerWordsAreDroppedFromSpokenPhrases() {
        let terms = StudyEntityStore.searchTerms(in: "the notes about photosynthesis")

        #expect(terms == ["photosynthesis"])
    }

    @Test func appNounsAreTreatedAsFiller() {
        let terms = StudyEntityStore.searchTerms(in: "read my card on mitochondria")

        #expect(terms == ["mitochondria"])
    }

    @Test func multipleMeaningfulTermsAreKept() {
        let terms = StudyEntityStore.searchTerms(in: "the deck about cellular respiration")

        #expect(terms == ["cellular", "respiration"])
    }

    /// Short tokens carry no signal and would match almost everything.
    @Test func shortTokensAreDropped() {
        #expect(StudyEntityStore.searchTerms(in: "a of in at").isEmpty)
        #expect(StudyEntityStore.searchTerms(in: "pH is up") == [])
    }

    @Test func punctuationSeparatesTerms() {
        let terms = StudyEntityStore.searchTerms(in: "photosynthesis, respiration; glycolysis")

        #expect(terms == ["photosynthesis", "respiration", "glycolysis"])
    }

    /// Digits are meaningful — "chapter 12" should still find chapter 12.
    @Test func numbersSurviveAsTerms() {
        let terms = StudyEntityStore.searchTerms(in: "chapter 1984 notes")

        #expect(terms.contains("1984"))
    }

    /// A query of nothing but filler must produce no terms, so the caller can
    /// bail out rather than matching every card in the library.
    @Test func aQueryOfPureFillerYieldsNothing() {
        #expect(StudyEntityStore.searchTerms(in: "show me the cards").isEmpty)
    }

    // MARK: - Matching

    /// The specific miss that made lookups fail most often: a plain lowercased
    /// `contains` will not match a term against its own inflected form.
    @Test func matchingFindsAPrefixInsideALongerWord() {
        let haystack = ["Mitochondrial respiration", "Cell biology"]

        #expect(StudyEntityStore.matches(terms: ["mitochondria"], in: haystack))
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(StudyEntityStore.matches(terms: ["PHOTOSYNTHESIS"], in: ["Photosynthesis basics"]))
    }

    /// `localizedStandardContains` folds diacritics, so a user who does not type
    /// accents still finds the card.
    @Test func matchingFoldsDiacritics() {
        #expect(StudyEntityStore.matches(terms: ["resume"], in: ["Résumé workshop"]))
    }

    /// Every term must appear — otherwise a two-word query is no narrower than
    /// a one-word query.
    @Test func allTermsMustMatch() {
        let haystack = ["Cellular respiration", "Photosynthesis"]

        #expect(StudyEntityStore.matches(terms: ["cellular", "respiration"], in: haystack))
        #expect(!StudyEntityStore.matches(terms: ["cellular", "mitosis"], in: haystack))
    }

    /// Terms may be satisfied by different entries — a card matches when one
    /// word is in its title and another is in its summary.
    @Test func termsMayMatchAcrossDifferentFields() {
        let haystack = ["Krebs cycle", "Takes place in the mitochondria"]

        #expect(StudyEntityStore.matches(terms: ["krebs", "mitochondria"], in: haystack))
    }

    @Test func noTermsMatchesEverythingSoCallersMustGuard() {
        // `allSatisfy` over an empty list is true by definition. This documents
        // why both query implementations bail out before calling `matches`.
        #expect(StudyEntityStore.matches(terms: [], in: ["anything"]))
    }

    @Test func emptyHaystackNeverMatches() {
        #expect(!StudyEntityStore.matches(terms: ["photosynthesis"], in: []))
    }
}
