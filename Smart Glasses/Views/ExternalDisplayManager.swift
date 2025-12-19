//
//  ExternalDisplayManager.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import Combine
import SwiftUI
import UIKit
import MWDATCamera

/// Manages external display (AirPlay, HDMI) connections and rendering
@MainActor
class ExternalDisplayManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ExternalDisplayManager()

    // MARK: - Published Properties

    /// Whether an external display is connected
    @Published var isExternalDisplayConnected: Bool = false

    /// Name of the connected display
    @Published var displayName: String = ""

    /// Whether to show detection overlays on external display
    @Published var showOverlaysOnExternal: Bool = true

    // MARK: - Private Properties

    private var externalWindow: UIWindow?
    private var hostingController: UIHostingController<AnyView>?

    // MARK: - Initialization

    private init() {
        setupNotifications()
        checkForExternalDisplay()
    }

    // MARK: - Setup

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect),
            name: UIScreen.didConnectNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
    }

    private func checkForExternalDisplay() {
        if UIScreen.screens.count > 1 {
            if let externalScreen = UIScreen.screens.last, externalScreen != UIScreen.main {
                setupExternalDisplay(screen: externalScreen)
            }
        }
    }

    // MARK: - Screen Notifications

    @objc private func screenDidConnect(_ notification: Notification) {
        guard let screen = notification.object as? UIScreen else { return }
        print("[ExternalDisplay] Screen connected: \(screen)")
        setupExternalDisplay(screen: screen)
    }

    @objc private func screenDidDisconnect(_ notification: Notification) {
        print("[ExternalDisplay] Screen disconnected")
        tearDownExternalDisplay()
    }

    // MARK: - External Display Management

    private func setupExternalDisplay(screen: UIScreen) {
        // Create window for external display
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen

        // Create the external display view
        let externalView = ExternalDisplayView()
        let hostingController = UIHostingController(rootView: AnyView(externalView))
        hostingController.view.backgroundColor = .black

        window.rootViewController = hostingController
        window.isHidden = false

        self.externalWindow = window
        self.hostingController = hostingController
        self.isExternalDisplayConnected = true
        self.displayName = "External Display"

        print("[ExternalDisplay] External display configured: \(screen.bounds)")
    }

    private func tearDownExternalDisplay() {
        externalWindow?.isHidden = true
        externalWindow = nil
        hostingController = nil
        isExternalDisplayConnected = false
        displayName = ""
    }

    // MARK: - Public Methods

    /// Toggle overlay visibility on external display
    func toggleOverlays() {
        showOverlaysOnExternal.toggle()
    }
}

// MARK: - External Display View
/// The view shown on the external display (projector/TV)
struct ExternalDisplayView: View {
    @StateObject private var manager = WearablesManager.shared
    @StateObject private var displayManager = ExternalDisplayManager.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black

                // Video feed - full screen
                if let frame = manager.latestFrameImage {
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Waiting for stream
                    VStack(spacing: 20) {
                        Image(systemName: "rays")
                            .font(.system(size: 80))
                            .foregroundColor(.white.opacity(0.3))

                        Text("Smart Glasses")
                            .font(.largeTitle)
                            .fontWeight(.light)
                            .foregroundColor(.white.opacity(0.5))

                        Text("Waiting for video stream...")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                // Detection overlay (optional)
                if displayManager.showOverlaysOnExternal && manager.currentMode == .objectDetection {
                    DetectionOverlayView(
                        result: manager.latestDetectionResult,
                        focusArea: .center,
                        showFocusArea: true
                    )
                }

                // Status bar at bottom
                VStack {
                    Spacer()

                    HStack {
                        // Mode indicator
                        HStack(spacing: 8) {
                            Image(systemName: manager.currentMode.icon)
                            Text(manager.currentMode.rawValue)
                        }
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        // Stream status
                        if manager.streamState == .streaming {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 10, height: 10)
                                Text("LIVE")
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.green)
                        }

                        // Recording indicator
                        if manager.isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                Text("REC")
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.red)
                            .padding(.leading, 16)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ExternalDisplayView()
}
