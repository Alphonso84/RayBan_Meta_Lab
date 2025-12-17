//
//  ContentView.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI
import MWDATCamera

struct ContentView: View {
    @StateObject private var manager = WearablesManager.shared
    @State private var showFullScreen = false

    var body: some View {
        NavigationView {
            List {
                Section("Registration") {
                    Text("State: \(manager.registrationStateDescription)")
                    Text("Device: \(manager.deviceStatus)")
                    Button("Start registration") {
                        manager.startRegistration()
                    }
                    Button("Unregister") {
                        manager.startUnregistration()
                    }
                }

                Section("Camera") {
                    Text("Camera status: \(manager.cameraStatus ?? "Unknown")")
                    Button("Check status") {
                        Task {
                            await manager.refreshCameraPermissionStatus()
                        }
                    }
                    Button("Request camera permission") {
                        Task {
                            await manager.requestCameraPermission()
                        }
                    }
                }

                Section("Streaming") {
                    // Stream controls
                    HStack {
                        Text("Stream state:")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(streamStateColor)
                                .frame(width: 8, height: 8)
                            Text(streamStateText)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: { manager.startStream() }) {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .disabled(manager.streamState == .streaming)

                        Button(action: { manager.stopStream() }) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(manager.streamState == .stopped)
                    }

                    // Video preview with tap to expand
                    if let frame = manager.latestFrameImage {
                        Button(action: { showFullScreen = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: frame)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption)
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .padding(8)
                            }
                        }
                        .buttonStyle(.plain)
                    } else if manager.streamState == .streaming {
                        HStack {
                            Spacer()
                            ProgressView()
                                .frame(height: 100)
                            Spacer()
                        }
                    }

                    // Full screen button
                    Button(action: { showFullScreen = true }) {
                        Label("Open Full Screen View", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }

                // Mode Selection
                Section {
                    Picker("Processing Mode", selection: $manager.currentMode) {
                        ForEach(StreamingMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    // Mode description
                    HStack {
                        Image(systemName: manager.currentMode.icon)
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        Text(manager.currentMode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Mode")
                } footer: {
                    Text("Select a processing mode for the video feed. Additional modes will process frames using Vision or AI.")
                }

                Section("Photos") {
                    Button("Capture photo") {
                        manager.capturePhoto()
                    }
                    if let photo = manager.lastCapturedPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                    }
                }

                Section("Video Recording") {
                    Text("Recording: \(manager.isRecording ? "Yes" : "No")")
                    Button("Start Recording") {
                        manager.startRecording()
                    }
                    .disabled(manager.streamState != .streaming || manager.isRecording)

                    Button("Stop Recording") {
                        manager.stopRecording()
                    }
                    .disabled(!manager.isRecording)

                    if let videoURL = manager.lastRecordedVideoURL {
                        Text("Last video: \(videoURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Meta Glasses Lab")
            .fullScreenCover(isPresented: $showFullScreen) {
                FullScreenStreamView(manager: manager)
            }
        }
    }

    // MARK: - Computed Properties
    private var streamStateColor: Color {
        switch manager.streamState {
        case .streaming: return .green
        case .paused: return .yellow
        case .stopped: return .red
        @unknown default: return .gray
        }
    }

    private var streamStateText: String {
        switch manager.streamState {
        case .streaming: return "Live"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    ContentView()
}
