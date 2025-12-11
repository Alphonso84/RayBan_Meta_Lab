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
                    Text("Stream state: \(String(describing: manager.streamState))")
                    Button("Start stream") {
                        manager.startStream()
                    }
                    Button("Stop stream") {
                        manager.stopStream()
                    }
                    if let frame = manager.latestFrameImage {
                        Image(uiImage: frame)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                    }
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
        }
    }
}

#Preview {
    ContentView()
}
