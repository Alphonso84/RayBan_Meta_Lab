//
//  FullScreenStreamView.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI
import MWDATCamera

struct FullScreenStreamView: View {
    @ObservedObject var manager: WearablesManager
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                // Video feed (tap this area to toggle controls)
                Group {
                    if let frame = manager.latestFrameImage {
                        Image(uiImage: frame)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("No video feed")
                                .font(.headline)
                                .foregroundColor(.gray)
                            if manager.streamState == .stopped {
                                Text("Start streaming to see video")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                    resetHideControlsTimer()
                }

                // Controls overlay
                if showControls {
                    VStack {
                        // Top bar
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                                    .shadow(radius: 4)
                            }
                            .frame(width: 44, height: 44)

                            Spacer()

                            // Stream state indicator
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(streamStateColor)
                                    .frame(width: 10, height: 10)
                                Text(streamStateText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                            Spacer()

                            // Recording indicator (or placeholder for alignment)
                            if manager.isRecording {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 10, height: 10)
                                    Text("REC")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.red.opacity(0.3))
                                .clipShape(Capsule())
                            } else {
                                Color.clear.frame(width: 44, height: 44)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, geometry.safeAreaInsets.top + 8)

                        Spacer()

                        // Bottom controls
                        VStack(spacing: 16) {
                            // Mode picker
                            ModePicker(selectedMode: $manager.currentMode)
                                .padding(.horizontal)

                            // Action buttons
                            HStack(spacing: 40) {
                                // Capture photo
                                ActionButton(
                                    icon: "camera.fill",
                                    label: "Photo",
                                    disabled: manager.streamState != .streaming
                                ) {
                                    manager.capturePhoto()
                                }

                                // Start/Stop stream
                                ActionButton(
                                    icon: manager.streamState == .streaming ? "stop.fill" : "play.fill",
                                    label: manager.streamState == .streaming ? "Stop" : "Start",
                                    isActive: manager.streamState == .streaming
                                ) {
                                    if manager.streamState == .streaming {
                                        manager.stopStream()
                                    } else {
                                        manager.startStream()
                                    }
                                }

                                // Record video
                                ActionButton(
                                    icon: manager.isRecording ? "record.circle.fill" : "record.circle",
                                    label: manager.isRecording ? "Stop Rec" : "Record",
                                    isActive: manager.isRecording,
                                    disabled: manager.streamState != .streaming
                                ) {
                                    if manager.isRecording {
                                        manager.stopRecording()
                                    } else {
                                        manager.startRecording()
                                    }
                                }
                            }
                            .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 16)
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .statusBar(hidden: !showControls)
        .onAppear {
            resetHideControlsTimer()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

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

    private func resetHideControlsTimer() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = false
                    }
                }
            }
        }
    }
}

// MARK: - Mode Picker Component
struct ModePicker: View {
    @Binding var selectedMode: StreamingMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StreamingMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 18))
                        Text(mode.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(selectedMode == mode ? .white : .gray)
                    .background(
                        selectedMode == mode
                            ? Color.blue.opacity(0.8)
                            : Color.clear
                    )
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Action Button Component
struct ActionButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isActive ? .red : .white.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isActive ? .white : (disabled ? .gray : .white))
                }

                Text(label)
                    .font(.caption)
                    .foregroundColor(disabled ? .gray : .white)
            }
        }
        .disabled(disabled)
    }
}

#Preview {
    FullScreenStreamView(manager: WearablesManager.shared)
}
