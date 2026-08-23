//
//  MainTabView.swift
//  Smart Glasses
//
//  Main tab navigation for the document study app
//

import Combine
import MWDATCamera
import SwiftUI

/// Tab identifiers
enum AppTab: Int {
    case library = 0
    case scan = 1
    case settings = 2
}

/// Shared navigation state for programmatic tab changes (e.g., from Siri intents)
@MainActor
final class NavigationState: ObservableObject {
    static let shared = NavigationState()
    @Published var selectedTab: AppTab = .library
    private init() {}
}

/// Main tab-based navigation
struct MainTabView: View {
    @StateObject private var navigationState = NavigationState.shared
    @ObservedObject private var manager = WearablesManager.shared

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { navigationState.selectedTab },
            set: { navigationState.selectedTab = $0 }
        )
    }

    var body: some View {
        TabView(selection: selectedTab) {
            // Library Tab - Decks and Cards (Landing Page)
            DeckLibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .tag(AppTab.library)

            // Scan Tab - Document Scanner
            LibraryScannerView()
                .tabItem {
                    Label("Scan", systemImage: "doc.viewfinder")
                }
                .tag(AppTab.scan)

            // Settings Tab - Glasses connection & preferences
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .task(id: navigationState.selectedTab) {
            // This task runs when selectedTab changes and cancels when it changes again
            await handleStreamForTab(navigationState.selectedTab)
        }
        .onChange(of: navigationState.selectedTab) { _, _ in
            // Speech outlives the view that started it: both the synthesizer and
            // the OpenAI audio player belong to a singleton, so leaving a screen
            // does not stop it.
            //
            // Handled here rather than in each view's `onDisappear` because that
            // fires inconsistently for a view sitting inside an inactive tab's
            // navigation stack, and because a per-view list is one more thing to
            // forget — `LibraryScannerView` had already forgotten it, which is
            // what left a summary reading aloud after switching tabs.
            //
            // Deliberately not tied to backgrounding: the app declares the
            // `audio` background mode so summaries can keep playing through the
            // glasses with the phone pocketed.
            VoiceFeedbackManager.shared.stopSpeaking()
        }
    }

    /// Manage stream based on current tab
    @MainActor
    private func handleStreamForTab(_ tab: AppTab) async {
        if tab == .scan {
            // On Scan tab - start stream if needed
            print("[MainTabView] On Scan tab - ensuring stream is running")
            if manager.streamState == .stopped {
                manager.startStream()
            }

            // Keep this task alive while on Scan tab
            // When tab changes, this task gets cancelled and a new one starts
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }

            // Task was cancelled = we left the Scan tab
            print("[MainTabView] Left Scan tab - stopping stream")
            manager.stopStream()
        }
        // For other tabs, do nothing (stream stays stopped or was stopped above)
    }
}

#Preview {
    MainTabView()
}
