//
//  SharedModelContainer.swift
//  Smart Glasses
//
//  One SwiftData container shared by the app and by App Intents.
//
//  Intents can run outside the app's process, so they cannot reach the
//  container the `App` struct builds. Both sides resolve to this instead.
//

import Foundation
import SwiftData

enum SharedModelContainer {

    static let shared: ModelContainer = {
        do {
            let schema = Schema([SummaryCard.self, SummaryDeck.self])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }()

    /// A context for one-off reads from an intent.
    @MainActor
    static var context: ModelContext {
        shared.mainContext
    }
}
