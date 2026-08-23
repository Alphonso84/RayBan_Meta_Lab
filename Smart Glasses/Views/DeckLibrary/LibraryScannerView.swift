//
//  LibraryScannerView.swift
//  Smart Glasses
//
//  Scanner view using Meta Smart Glasses camera
//

import MWDATCamera
import SwiftUI
import SwiftData
import AVFoundation

/// Standalone scanner view using Smart Glasses camera or phone camera fallback
struct LibraryScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var manager = WearablesManager.shared
    @StateObject private var processor = DocumentReaderProcessor()
    @StateObject private var summarizer = StreamingSummarizer()
    @StateObject private var phoneCamera = PhoneCameraManager()

    // User settings (persisted)
    @AppStorage("distanceModeEnabled") private var distanceModeEnabled = true
    @AppStorage("multiPageModeEnabled") private var isMultiPageMode = false  // Single-page (auto-summarize) by default
    @AppStorage("speakSummaries") private var speakSummaries = false

    @State private var showingDeckSelector = false
    @State private var pendingCard: SummaryCard?
    @State private var animationPhase: Double = 0
    @State private var isAutoCaptureOn = true  // Auto-capture enabled by default
    @State private var frameSize: CGSize = .zero
    @State private var showPageCapturedOptions = false  // Show options after page capture
    @State private var usingPhoneCamera = false

    @AppStorage("captureMode") private var captureModeRaw = CaptureMode.document.rawValue
    @StateObject private var barcodeScanner = BookBarcodeScanner()
    @State private var showingBookDeckSheet = false
    @State private var scannedBook: ScannedBookCode?

    private var captureMode: CaptureMode {
        CaptureMode(rawValue: captureModeRaw) ?? .document
    }

    /// Whether any camera source is actively providing frames
    private var isActivelyScanning: Bool {
        if manager.isGlassesConnected { return true }
        if usingPhoneCamera && phoneCamera.isRunning { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview (glasses or phone) or connection status
                cameraPreview

                // Document boundary overlay (only show during auto-capture scanning)
                if isActivelyScanning && isAutoCaptureOn && summarizer.state == .idle {
                    DocumentBoundaryOverlay(
                        boundary: processor.detectedBoundary,
                        stabilityProgress: processor.stabilityProgress,
                        isStable: processor.isDocumentStable,
                        statusText: processor.autoCaptureStatus,
                        frameSize: frameSize
                    )
                }

                // Overlay content
                VStack(spacing: 0) {
                    // Capture mode picker — document / whiteboard / book barcode
                    Picker("Mode", selection: $captureModeRaw) {
                        ForEach(CaptureMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .onChange(of: captureModeRaw) { _, _ in
                        // Barcode mode reads the preview itself and needs the
                        // detail; the others capture a still and cannot afford
                        // the bandwidth.
                        manager.matchPreviewQuality(to: captureMode)
                        handleCaptureModeChange()
                    }

                    // Top bar with title and mode toggles
                    HStack {
                        // Auto-capture toggle
                        Button {
                            isAutoCaptureOn.toggle()
                            if isAutoCaptureOn {
                                processor.startAutoCapture()
                            } else {
                                processor.stopAutoCapture()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isAutoCaptureOn ? "a.circle.fill" : "a.circle")
                                    .font(.system(size: 18))
                                Text("Auto")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(isAutoCaptureOn ? .green : .white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }

                        // Multi-page toggle
                        Button {
                            isMultiPageMode.toggle()
                            if isMultiPageMode {
                                processor.startMultiPageSession()
                            } else {
                                // If switching off multi-page, finish any current session
                                if processor.capturedPageCount > 0 {
                                    _ = processor.finishMultiPageSession()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isMultiPageMode ? "doc.on.doc.fill" : "doc.fill")
                                    .font(.system(size: 16))
                                Text(isMultiPageMode ? "Multi" : "Single")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(isMultiPageMode ? .blue : .white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }

                        Spacer()

                        // Source indicator
                        if isActivelyScanning {
                            HStack(spacing: 4) {
                                Image(systemName: usingPhoneCamera ? "camera.fill" : "eyeglasses")
                                    .font(.system(size: 14))
                                Text(usingPhoneCamera ? "Phone" : "Glasses")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }

                        // Page counter badge (when pages captured in multi-page mode)
                        if isMultiPageMode && processor.capturedPageCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc.fill")
                                    .font(.system(size: 14))
                                Text("\(processor.capturedPageCount)")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Spacer()

                    // Status and content area (hide default status when auto-capture is showing overlay)
                    VStack(spacing: 24) {
                        // Status indicator (only show when not in auto-capture scanning mode)
                        if !isAutoCaptureOn || summarizer.state != .idle || processor.state == .complete {
                            statusSection
                        }

                        // Content area (streaming summary)
                        if summarizer.state == .summarizing || summarizer.state == .complete {
                            summaryCard
                        }
                    }
                    .padding()

                    Spacer()

                    // Bottom controls
                    bottomControls
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDeckSelector) {
                if let card = pendingCard {
                    CardPreviewSheet(
                        card: card,
                        onSave: { deck in
                            saveCard(card, to: deck)
                            showingDeckSelector = false
                            pendingCard = nil
                        },
                        onDiscard: {
                            showingDeckSelector = false
                            pendingCard = nil
                            reset()
                        }
                    )
                }
            }
            .sheet(isPresented: $showingBookDeckSheet) {
                if let book = scannedBook {
                    BookDeckSheet(
                        book: book,
                        onCreate: { title in
                            createDeck(named: title, from: book)
                            showingBookDeckSheet = false
                            processor.clearRecognizedBarcode()
                        },
                        onCancel: {
                            showingBookDeckSheet = false
                            scannedBook = nil
                            barcodeScanner.reset()
                            processor.clearRecognizedBarcode()
                        }
                    )
                }
            }
            .onAppear {
                // Stream lifecycle is managed by MainTabView - don't start here
                manager.matchPreviewQuality(to: captureMode)
                configureProcessorForDistanceMode()
                if isAutoCaptureOn {
                    processor.startAutoCapture()
                }
                if isMultiPageMode {
                    processor.startMultiPageSession()
                }
            }
            .onChange(of: distanceModeEnabled) { _, _ in
                configureProcessorForDistanceMode()
            }
            .onChange(of: isMultiPageMode) { _, newValue in
                // When toggling multi-page mode, update processor state
                if newValue {
                    processor.startMultiPageSession()
                }
                // Note: Turning off is handled in the button action to properly finish session
            }
            .onDisappear {
                stopGlassesStream()
                phoneCamera.stopSession()
                usingPhoneCamera = false
                processor.stopAutoCapture()
            }
            .onChange(of: processor.latestResult) { _, newResult in
                // Uses the same rule the processor used to accept the capture —
                // a whiteboard with unreadable handwriting has no OCR text but
                // is still summarizable from the image.
                if let result = newResult, result.isSummarizable(in: captureMode) {
                    if isMultiPageMode {
                        // In multi-page mode, show options instead of immediately summarizing
                        showPageCapturedOptions = true
                    } else {
                        // Single page mode - summarize immediately
                        startSummarization(for: result)
                    }
                }
            }
            .onChange(of: processor.state) { _, newState in
                // Reset page captured options when going back to scanning
                if newState == .scanning || newState == .idle {
                    showPageCapturedOptions = false
                }
            }
            .onChange(of: manager.latestFrameImage) { _, newImage in
                // Feed frames to auto-capture processor for boundary detection
                // (uses low-res video for detection, but captures high-res photo when stable)
                if !usingPhoneCamera, let image = newImage, isAutoCaptureOn, summarizer.state == .idle {
                    processor.processFrameForAutoCapture(image)
                }
            }
            .onChange(of: phoneCamera.latestFrameImage) { _, newImage in
                // Feed phone camera frames to auto-capture processor
                if usingPhoneCamera, let image = newImage, isAutoCaptureOn, summarizer.state == .idle {
                    processor.processFrameForAutoCapture(image)
                }
            }
            .onChange(of: manager.isGlassesConnected) { _, connected in
                // Auto-switch to glasses when they connect
                if connected && usingPhoneCamera {
                    phoneCamera.stopSession()
                    usingPhoneCamera = false
                    VoiceFeedbackManager.shared.configureAudioRoute(forGlasses: true)
                }
            }
            .onChange(of: processor.shouldTriggerPhotoCapture) { _, shouldCapture in
                // When auto-capture detects stable document, trigger high-res photo capture
                if shouldCapture {
                    triggerHighResPhotoCapture()
                }
            }
            .onChange(of: processor.recognizedBarcode) { _, barcode in
                // Vision read the code straight from the preview — no capture,
                // no model round trip, so go directly to the deck sheet.
                guard let barcode else { return }
                scannedBook = ScannedBookCode(
                    code: barcode.payload,
                    isISBN: barcode.isISBN,
                    recognizedTitle: ""
                )
                showingBookDeckSheet = true
            }
        }
    }

    /// Trigger high-resolution photo capture for OCR
    private func triggerHighResPhotoCapture() {
        print("[LibraryScannerView] Triggering high-res photo capture for OCR")

        let captureHandler: (UIImage?) -> Void = { [weak processor] image in
            guard let processor = processor else { return }

            // Reset the trigger flag
            processor.shouldTriggerPhotoCapture = false

            if let image = image {
                print("[LibraryScannerView] Got high-res photo: \(image.size.width)x\(image.size.height)")
                handleCapturedPhoto(image)
                processor.autoCaptureDidComplete()
            } else {
                print("[LibraryScannerView] Photo capture failed")
                processor.errorMessage = "Photo capture failed"
                processor.autoCaptureDidComplete()
            }
        }

        if usingPhoneCamera {
            phoneCamera.capturePhoto(completion: captureHandler)
        } else {
            manager.capturePhoto(completion: captureHandler)
        }
    }

    // MARK: - Camera Preview

    private var cameraPreview: some View {
        GeometryReader { geometry in
            if let image = manager.latestFrameImage,
               manager.streamState == .streaming || manager.shouldHoldLastFrame {
                // Live feed from Smart Glasses — or the last frame held while the
                // camera is rebuilt after a capture, which reads as a continuous
                // preview instead of a stop and restart.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear {
                        frameSize = geometry.size
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        frameSize = newSize
                    }
            } else if usingPhoneCamera && phoneCamera.isRunning {
                // Live feed from phone camera
                PhoneCameraPreviewLayer(session: phoneCamera.captureSession)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .onAppear {
                        frameSize = geometry.size
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        frameSize = newSize
                    }
            } else {
                // Not connected or no stream
                Color.black
                    .overlay {
                        connectionStatus
                    }
            }
        }
        .ignoresSafeArea()
    }

    private var connectionStatus: some View {
        VStack(spacing: 20) {
            // Glasses icon
            Image(systemName: "eyeglasses")
                .font(.system(size: 64))
                .foregroundStyle(.gray)

            // Connection status
            VStack(spacing: 8) {
                Text(connectionStatusTitle)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(connectionStatusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Action buttons based on state. Permission comes first — neither
            // connecting nor starting a stream can succeed without it.
            if manager.needsCameraPermission {
                Button {
                    Task { await manager.requestCameraPermission() }
                } label: {
                    Label("Allow Camera Access", systemImage: "camera.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if !manager.isRegistered {
                Button {
                    manager.startRegistration()
                } label: {
                    Label("Connect Glasses", systemImage: "link")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else if manager.streamState != .streaming {
                Button {
                    startGlassesStream()
                } label: {
                    Label("Start Stream", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                // Streaming but no frame yet
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Waiting for video...")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            // Divider between glasses and phone camera options
            if manager.streamState != .streaming {
                HStack {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 40)

                // Phone camera fallback button
                Button {
                    usingPhoneCamera = true
                    phoneCamera.startSession()
                    VoiceFeedbackManager.shared.configureAudioRoute(forGlasses: false)
                } label: {
                    Label("Use Phone Camera", systemImage: "camera.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            // Settings hint
            if !manager.isRegistered {
                Text("Go to Settings tab to manage glasses connection")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.7))
                    .padding(.top, 8)
            }
        }
    }

    private var connectionStatusTitle: String {
        if manager.needsCameraPermission {
            return "Camera Access Needed"
        }
        switch manager.streamState {
        case .streaming:
            return "Connected"
        case .starting:
            return "Connecting..."
        case .stopping:
            return "Disconnecting..."
        case .waitingForDevice:
            return "Waiting for Glasses"
        case .paused:
            return "Paused"
        case .stopped:
            if manager.isRegistered {
                return "Glasses Ready"
            } else {
                return "Glasses Not Connected"
            }
        @unknown default:
            return "Unknown State"
        }
    }

    private var connectionStatusSubtitle: String {
        if manager.needsCameraPermission {
            return "Allow this app to use your glasses' camera, then scanning starts on its own"
        }
        switch manager.streamState {
        case .streaming:
            return "Receiving video from Smart Glasses"
        case .starting:
            return "Establishing connection..."
        case .stopping:
            return "Closing connection..."
        case .waitingForDevice:
            return "Looking for your glasses — make sure they are on and worn"
        case .paused:
            return "Streaming paused by the glasses — it resumes on its own"
        case .stopped:
            if manager.isRegistered {
                return "Tap Start Stream to begin scanning"
            } else {
                return "Connect your Meta Ray-Ban Smart Glasses to scan documents"
            }
        @unknown default:
            return ""
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 12) {
            // Animated status icon
            statusIcon
                .frame(width: 60, height: 60)

            // Status text
            Text(statusText)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            // Subtitle
            Text(statusSubtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch summarizer.state {
        case .idle:
            if processor.state == .idle {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color.blue, lineWidth: 3)
                        .rotationEffect(.degrees(animationPhase))
                }
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        animationPhase = 360
                    }
                }
            }

        case .preparing:
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)

        case .summarizing:
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                Circle()
                    .trim(from: 0, to: summarizer.progress)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse, options: .repeating)
            }

        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        // If no camera source is active, show that status
        if !isActivelyScanning {
            return "No Camera Active"
        }

        switch summarizer.state {
        case .idle:
            // Check for page captured state first
            if showPageCapturedOptions {
                return "Page Ready"
            }

            switch processor.state {
            case .idle, .scanning:
                if processor.capturedPageCount > 0 {
                    return "Scan Next Page"
                }
                return isAutoCaptureOn ? "Auto-Capture Active" : "Ready to Scan"
            case .detectingDocument: return "Detecting..."
            case .documentDetected: return "Document Found"
            case .processingDocument: return "Processing"
            case .readingText, .reading: return "Reading Text"
            case .complete: return "Page Captured"
            default: return "Processing..."
            }
        case .preparing: return "Preparing..."
        case .summarizing:
            if processor.capturedPageCount > 1 {
                return "Summarizing \(processor.capturedPageCount) Pages"
            }
            return "Summarizing"
        case .complete: return "Summary Ready"
        case .error: return "Error"
        }
    }

    private var statusSubtitle: String {
        // If no camera source is active, show that status
        if !isActivelyScanning {
            return "Connect glasses or use phone camera to scan"
        }

        switch summarizer.state {
        case .idle:
            // Check for page captured state first
            if showPageCapturedOptions {
                return "Add page, tap Done to summarize, or Skip"
            }

            switch processor.state {
            case .idle, .scanning:
                if processor.capturedPageCount > 0 {
                    return "Point at next page or tap Done to summarize"
                }
                return isAutoCaptureOn ? "Hold document steady to capture" : "Point at a document and tap capture"
            case .detectingDocument: return "Looking for document edges..."
            case .documentDetected: return "Hold steady..."
            case .processingDocument: return "Adjusting perspective..."
            case .readingText, .reading: return "Extracting text..."
            case .complete: return "Choose an action below"
            default: return "Processing..."
            }
        case .preparing: return "Getting ready..."
        case .summarizing: return summarizer.activeProvider.summarizingLabel
        case .complete: return "Tap Save to keep this card"
        case .error: return summarizer.errorMessage ?? "Try again"
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            if !summarizer.suggestedTitle.isEmpty {
                Text(summarizer.suggestedTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            // Document type badge
            if !summarizer.documentType.isEmpty {
                Text(summarizer.documentType)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.3))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }

            Divider()
                .background(.white.opacity(0.3))

            // Summary text (streams in)
            if !summarizer.streamingSummary.isEmpty {
                Text(summarizer.streamingSummary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(4)
            }

            // Key points (stream in)
            if !summarizer.streamingKeyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summarizer.streamingKeyPoints.prefix(3), id: \.self) { point in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)

                            Text(point)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Page info when in multi-page mode with captured pages
            if isMultiPageMode && processor.capturedPageCount > 0 {
                multiPageInfoBar
            }

            HStack(spacing: 16) {
                if summarizer.state == .complete {
                    // Summary complete - show save/discard
                    Button {
                        reset()
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button {
                        createCardAndShowSelector()
                    } label: {
                        Label("Save Card", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else if showPageCapturedOptions && isMultiPageMode {
                    // Page captured in multi-page mode - show options
                    multiPageCaptureOptions
                } else if isAutoCaptureOn {
                    // Auto-capture mode - show stability or manual capture
                    autoCaptureControls
                } else {
                    // Manual capture mode
                    manualCaptureButton
                }
            }
        }
    }

    // Multi-page info bar showing accumulated pages
    private var multiPageInfoBar: some View {
        HStack(spacing: 12) {
            // Page thumbnails (show up to 4)
            HStack(spacing: -8) {
                ForEach(Array(processor.capturedPageThumbnails.prefix(4).enumerated()), id: \.offset) { index, thumbnail in
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .zIndex(Double(4 - index))
                }
                if processor.capturedPageCount > 4 {
                    Text("+\(processor.capturedPageCount - 4)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 40)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(processor.capturedPageCount) \(processor.capturedPageCount == 1 ? "page" : "pages") captured")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)

                Text("\(processor.totalCharacterCount) characters")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Options shown after capturing a page in multi-page mode
    private var multiPageCaptureOptions: some View {
        HStack(spacing: 12) {
            // Add page and continue
            Button {
                addPageAndContinue()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.title2)
                    Text("Add Page")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Finish and summarize
            Button {
                finishAndSummarize()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                    Text("Done")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // Cancel current page
            Button {
                cancelCurrentPage()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.title2)
                    Text("Skip")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // Auto-capture controls
    private var autoCaptureControls: some View {
        Group {
            if processor.detectedBoundary != nil {
                HStack(spacing: 12) {
                    StabilityIndicator(
                        progress: processor.stabilityProgress,
                        isStable: processor.isDocumentStable
                    )

                    Text(processor.autoCaptureStatus)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Button {
                    captureDocument()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title2)
                        Text("Manual Capture")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                            )
                    )
                }
                .disabled(!canCapture)
            }
        }
    }

    // Manual capture button
    private var manualCaptureButton: some View {
        Button {
            captureDocument()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                Text("Capture")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canCapture ? Color.blue : Color.gray)
            )
        }
        .disabled(!canCapture)
    }

    private var canCapture: Bool {
        let hasSource = (manager.streamState == .streaming && manager.latestFrameImage != nil) ||
                        (usingPhoneCamera && phoneCamera.isRunning)
        return hasSource &&
            (processor.state == .idle || processor.state == .scanning || processor.state == .complete) &&
            !showPageCapturedOptions
    }

    // MARK: - Configuration

    /// Configure processor settings based on distance mode
    private func configureProcessorForDistanceMode() {
        processor.captureMode = captureMode

        // Whiteboards need the opposite of the OCR profile. Grayscale throws away
        // marker colour, which on a board is meaningful ("the red boxes are the
        // constraints"), and boosting contrast on a glossy surface amplifies
        // overhead-light glare rather than sharpening the writing. The model gets
        // the un-preprocessed `visionImage` either way, so this only governs OCR —
        // but the preprocessed copy is also what the user sees as the thumbnail.
        if captureMode == .whiteboard {
            processor.targetProcessingDimension = 3000
            processor.preprocessImage = false
            processor.convertToGrayscale = false
            processor.useAdaptiveThreshold = false
            processor.textConfidenceThreshold = 0.15   // marker handwriting scores low
            processor.documentConfidenceThreshold = 0.25
            processor.minimumTextLines = 1
            processor.minimumCharacters = 1
            // Standing back from a board, the same head movement sweeps far more
            // of the scene than it does over a page held at arm's length.
            processor.stabilityThreshold = 0.05
            processor.stableFramesRequired = 10
            return
        }

        processor.stabilityThreshold = 0.03
        processor.stableFramesRequired = 8

        if distanceModeEnabled {
            // Distance mode: Optimized for far distance scanning
            // Aggressive upscale so Vision has more pixels after perspective crop
            processor.targetProcessingDimension = 3500
            processor.preprocessImage = true
            processor.convertToGrayscale = true         // Improves OCR accuracy
            processor.useAdaptiveThreshold = true       // Sharpen text edges at distance
            processor.textConfidenceThreshold = 0.2     // Accept lower-confidence text
            processor.documentConfidenceThreshold = 0.35 // Detect documents at distance
            processor.minimumTextLines = 1
            processor.minimumCharacters = 15
        } else {
            // Close-up mode: Faster processing
            processor.targetProcessingDimension = 2000
            processor.preprocessImage = false
            processor.convertToGrayscale = false
            processor.useAdaptiveThreshold = false
            processor.textConfidenceThreshold = 0.4
            processor.minimumTextLines = 3
            processor.minimumCharacters = 50
        }
    }

    // MARK: - Glasses Stream Control

    private func startGlassesStream() {
        if manager.streamState == .stopped {
            manager.startStream()
        }
    }

    private func stopGlassesStream() {
        // Stream lifecycle is managed by MainTabView based on tab selection
        // Stream stops when leaving Scan tab, starts when entering Scan tab
        // This saves battery when the glasses camera is not needed
    }

    // MARK: - Actions

    /// Capture a high-resolution photo and process for OCR
    /// Uses the photo capture API for 12MP images instead of 720p video frames
    private func captureDocument() {
        if usingPhoneCamera {
            phoneCamera.capturePhoto { image in
                if let image = image {
                    handleCapturedPhoto(image)
                }
            }
        } else {
            manager.captureDocumentPhoto()
        }
    }

    /// Route a captured photo to the pipeline for the current mode.
    ///
    /// Barcode mode bypasses OCR and summarization entirely — the model's
    /// barcode tool reads the code directly off the image.
    private func handleCapturedPhoto(_ image: UIImage) {
        guard captureMode == .barcode else {
            processor.captureAndProcess(image)
            return
        }

        Task {
            if let scanned = await barcodeScanner.scan(image) {
                scannedBook = scanned
                showingBookDeckSheet = true
                VoiceFeedbackManager.shared.captureSuccess()
            } else {
                VoiceFeedbackManager.shared.captureFailedInsufficientText()
            }
        }
    }

    /// Reset capture state when switching modes, so a half-finished session in
    /// one mode does not leak into the next.
    private func handleCaptureModeChange() {
        processor.captureMode = captureMode
        configureProcessorForDistanceMode()

        barcodeScanner.reset()
        summarizer.reset()
        processor.latestResult = nil
        processor.clearRecognizedBarcode()
        showPageCapturedOptions = false

        // Barcode mode still runs the frame loop — it just detects barcodes with
        // Vision rather than looking for a document rectangle.
        if isAutoCaptureOn {
            processor.resetAutoCapture()
        }
    }

    /// Create a deck from a scanned book barcode.
    private func createDeck(named title: String, from book: ScannedBookCode) {
        let deck = SummaryDeck(
            title: title,
            colorHex: SummaryDeck.randomColor
        )
        deck.deckDescription = book.isISBN ? "ISBN \(book.code)" : "Barcode \(book.code)"
        modelContext.insert(deck)

        do {
            try modelContext.save()
        } catch {
            print("[LibraryScannerView] Failed to save deck: \(error)")
        }

        scannedBook = nil
        barcodeScanner.reset()
    }

    private func startSummarization(for result: DocumentReadingResult) {
        Task {
            let output = await summarizer.summarize(
                result.extractedText,
                pageImage: result.visionImage,
                mode: captureMode
            )
            if speakSummaries, let output = output {
                VoiceFeedbackManager.shared.speakSummary(output.summary)
            }
        }
    }

    // MARK: - Multi-Page Actions

    /// Add current page to session and continue scanning
    private func addPageAndContinue() {
        processor.addPageToSession()
        showPageCapturedOptions = false
        manager.resumeVideoIfStalled()

        // Re-enable auto-capture for next page
        if isAutoCaptureOn {
            processor.startAutoCapture()
        }
    }

    /// Finish multi-page session and start summarization
    private func finishAndSummarize() {
        // Add current page first if not already added
        if processor.latestResult != nil {
            processor.addPageToSession()
        }

        // Get combined text and summarize
        let firstPageImage = processor.capturedPageVisionImages.first
        let combinedText = processor.finishMultiPageSession()
        showPageCapturedOptions = false

        // Summarize all pages together. Only the first page is attached — the
        // combined OCR text still covers every page, and attaching N images
        // multiplies token cost. See FOUNDATION_MODELS_UPGRADES.md item 1
        // ("Follow-on work") for per-page attachments via ImageReference.
        Task {
            let output = await summarizer.summarize(
                combinedText,
                pageImage: firstPageImage,
                mode: captureMode
            )
            if speakSummaries, let output = output {
                VoiceFeedbackManager.shared.speakSummary(output.summary)
            }
        }
    }

    /// Skip current page without adding it
    private func cancelCurrentPage() {
        processor.latestResult = nil
        showPageCapturedOptions = false
        manager.resumeVideoIfStalled()

        // Reset for next capture
        if isAutoCaptureOn {
            processor.resetAutoCapture()
        } else {
            processor.state = .idle
        }
    }

    private func createCardAndShowSelector() {
        // Get source text - either from multi-page session or single capture
        let sourceText: String
        if processor.capturedPageCount > 0 {
            sourceText = processor.accumulatedText
        } else if let result = processor.latestResult {
            sourceText = result.extractedText
        } else {
            return
        }

        // Create thumbnail from first page or latest result
        var thumbnailData: Data?
        let thumbnailImage = processor.capturedPageThumbnails.first ?? processor.latestResult?.correctedImage

        if let image = thumbnailImage {
            let maxSize: CGFloat = 200
            let scale = min(maxSize / image.size.width, maxSize / image.size.height)
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)
        }

        // Add page count to title if multi-page
        var title = summarizer.suggestedTitle.isEmpty ? "Untitled" : summarizer.suggestedTitle
        if processor.capturedPageCount > 1 {
            title += " (\(processor.capturedPageCount) pages)"
        }

        let visualDescription = summarizer.streamingVisualDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let card = SummaryCard(
            title: title,
            summary: summarizer.streamingSummary,
            keyPoints: summarizer.streamingKeyPoints,
            sourceText: sourceText,
            visualDescription: visualDescription.isEmpty ? nil : visualDescription,
            thumbnailData: thumbnailData
        )

        pendingCard = card
        showingDeckSelector = true
    }

    private func saveCard(_ card: SummaryCard, to deck: SummaryDeck?) {
        if let deck = deck {
            card.deck = deck
            deck.cards.append(card)
            deck.markAccessed()
        }

        modelContext.insert(card)

        do {
            try modelContext.save()
        } catch {
            print("[LibraryScannerView] Failed to save card: \(error)")
        }

        reset()
    }

    private func reset() {
        summarizer.reset()
        processor.reset()
        animationPhase = 0

        // A still capture stops video on the glasses. Nothing needed the live
        // preview while the summary was up, but scanning does.
        manager.resumeVideoIfStalled()

        // Re-enable auto-capture if it was on
        if isAutoCaptureOn {
            processor.startAutoCapture()
        }
    }
}

#Preview {
    LibraryScannerView()
        .modelContainer(for: [SummaryCard.self, SummaryDeck.self], inMemory: true)
}
