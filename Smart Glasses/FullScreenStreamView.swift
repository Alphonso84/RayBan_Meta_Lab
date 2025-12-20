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
    @StateObject private var voiceFeedback = VoiceFeedbackManager.shared
    @StateObject private var externalDisplay = ExternalDisplayManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showMirroringInstructions = false

    var body: some View {
        ZStack {
            // Background + Video layer (ignores safe area)
            Color.black
                .ignoresSafeArea()

            // Video feed
            Group {
                if let frame = manager.latestFrameImage {
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
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
            .ignoresSafeArea()

            // Detection overlay (when in object detection mode)
            if manager.currentMode == .objectDetection {
                DetectionOverlayView(
                    result: manager.latestDetectionResult,
                    focusArea: .center,
                    showFocusArea: showControls
                )
                .ignoresSafeArea()
            }

            // AI Assistant overlay (when in AI Assistant mode)
            if manager.currentMode == .aiAssistant {
                AIAssistantOverlayView(
                    geminiManager: manager.geminiLiveManager,
                    wearablesManager: manager
                )
                .ignoresSafeArea()
            }

            // Processing indicator
            if manager.isDetectionProcessing && manager.currentMode == .objectDetection {
                VStack {
                    HStack {
                        Spacer()
                        ProcessingIndicator(isProcessing: true)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .padding(.top, 60)
            }

            // Controls overlay (respects safe area for proper touch handling)
            if showControls {
                VStack {
                    // Top bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())

                        // Screen Mirroring button
                        Button {
                            showMirroringInstructions = true
                        } label: {
                            Image(systemName: "tv")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                        }

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

                        // External display indicator
                        if externalDisplay.isExternalDisplayConnected {
                            Button {
                                externalDisplay.toggleOverlays()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "tv.fill")
                                        .font(.caption)
                                    Text("Projector")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.purple.opacity(0.8))
                                .clipShape(Capsule())
                            }
                        }

                        Spacer()

                        // Recording indicator or photo save status
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
                        } else if let photoStatus = manager.photoSaveStatus {
                            HStack(spacing: 6) {
                                Image(systemName: photoStatus.contains("Saved") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.caption)
                                Text(photoStatus)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(photoStatus.contains("Saved") ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                            .clipShape(Capsule())
                            .transition(.opacity.combined(with: .scale))
                        } else {
                            Color.clear.frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer()

                    // Describe button and audio status (only in object detection mode)
                    if manager.currentMode == .objectDetection {
                        VStack(spacing: 8) {
                            // Audio route indicator
                            HStack(spacing: 6) {
                                Image(systemName: voiceFeedback.isBluetoothConnected ? "airpodspro" : "speaker.wave.2")
                                    .font(.caption)
                                Text(voiceFeedback.audioOutputRoute)
                                    .font(.caption2)
                            }
                            .foregroundColor(voiceFeedback.isBluetoothConnected ? .green : .yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .onTapGesture {
                                // Test audio on tap
                                voiceFeedback.speak("Audio test")
                            }

                            DescribeButton(
                                result: manager.latestDetectionResult,
                                voiceFeedback: voiceFeedback,
                                isStreaming: manager.streamState == .streaming
                            )
                        }
                        .padding(.bottom, 16)
                    }

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
                    }
                    .padding()
                    .padding(.bottom, 8)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
                .transition(.opacity)
            }
        }
        .statusBar(hidden: !showControls)
        .onAppear {
            resetHideControlsTimer()
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .sheet(isPresented: $showMirroringInstructions) {
            ScreenMirroringInstructionsView()
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

// MARK: - Screen Mirroring Instructions
struct ScreenMirroringInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "tv.and.mediabox")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 20)

                Text("Mirror to Projector")
                    .font(.title)
                    .fontWeight(.bold)

                Text("To display video on your projector or TV, use Screen Mirroring from Control Center.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    InstructionStep(number: 1, text: "Swipe down from the top-right corner to open Control Center")
                    InstructionStep(number: 2, text: "Tap the Screen Mirroring button", icon: "rectangle.on.rectangle")
                    InstructionStep(number: 3, text: "Select your Apple TV or AirPlay device")
                    InstructionStep(number: 4, text: "Your entire screen will mirror to the display")
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()

                // Tip
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Tip: Use a Lightning/USB-C to HDMI adapter for a dedicated projector view with controls on your phone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                Button {
                    dismiss()
                } label: {
                    Text("Got It")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())

            HStack(spacing: 6) {
                Text(text)
                    .font(.subheadline)
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

#Preview {
    FullScreenStreamView(manager: WearablesManager.shared)
}
