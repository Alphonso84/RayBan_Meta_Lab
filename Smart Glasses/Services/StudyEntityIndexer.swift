//
//  StudyEntityIndexer.swift
//  Smart Glasses
//
//  Pushes cards and decks into the system semantic index so Siri and Spotlight
//  can find them by meaning rather than by exact title.
//

import AppIntents
import CoreSpotlight
import Foundation
import SwiftData

enum StudyEntityIndexer {

    // MARK: - Change Tracking

    private static var saveObserver: NSObjectProtocol?
    private static var pendingReindex: Task<Void, Never>?

    /// Reindex whenever SwiftData saves.
    ///
    /// `ModelContext.didSave` is the one choke point every mutation passes
    /// through — card creation, deck creation, deck-summary writes, and both
    /// delete paths including the deck cascade. Hooking it here means a new card
    /// is searchable immediately instead of only after the next launch, and
    /// there is no list of call sites to keep in sync.
    static func startObservingChanges() {
        guard saveObserver == nil else { return }

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { scheduleReindex() }
        }

        print("[StudyEntityIndexer] Observing SwiftData saves")
    }

    /// Coalesce bursts of saves into one reindex.
    ///
    /// PDF import saves once per page, so a 40-page document would otherwise
    /// trigger 40 full reindexes.
    private static func scheduleReindex() {
        pendingReindex?.cancel()
        pendingReindex = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await reindexAll()
        }
    }


    /// Reindex everything.
    ///
    /// A full reindex is fine at this scale — a heavy user has hundreds of
    /// cards, not millions — and it avoids having to track deltas across a
    /// SwiftData model that several views can mutate. Cheap and always correct
    /// beats incremental and occasionally stale.
    static func reindexAll() async {
        do {
            let cards = try StudyEntityStore.cards { _ in true }
            let decks = try StudyEntityStore.decks { _ in true }

            let index = CSSearchableIndex.default()

            // Clear first, then rebuild. `indexAppEntities` adds and updates but
            // never removes, so without this a deleted card keeps showing up in
            // Spotlight and Siri keeps offering it — a stale hit that opens
            // nothing is worse than no hit at all. Clearing makes the index a
            // mirror of the database instead of an append-only log, and at a few
            // hundred items the gap is imperceptible.
            try await index.deleteAppEntities(ofType: SummaryCardEntity.self)
            try await index.deleteAppEntities(ofType: SummaryDeckEntity.self)

            try await index.indexAppEntities(cards)
            try await index.indexAppEntities(decks)

            print("[StudyEntityIndexer] Indexed \(cards.count) cards, \(decks.count) decks")
        } catch {
            // Indexing is an enhancement, never a blocker — a failure here costs
            // Siri search, not the app.
            print("[StudyEntityIndexer] Indexing failed: \(error)")
        }
    }
}
