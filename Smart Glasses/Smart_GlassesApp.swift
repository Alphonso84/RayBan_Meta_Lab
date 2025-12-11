//
//  Smart_GlassesApp.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI
import MWDATCore

@main
struct Smart_GlassesApp: App {
    init() {
        configureWearables()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        do {
                            _ = try await Wearables.shared.handleUrl(url)
                        } catch {
                            print("Wearables URL handling failed: \(error)")
                        }
                    }
                }
        }
    }
}
