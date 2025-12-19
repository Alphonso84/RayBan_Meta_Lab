//
//  DetectionOverlayView.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI

/// Overlay view that displays detection results on top of the video feed
struct DetectionOverlayView: View {
    let result: DetectionResult?
    let focusArea: FocusArea
    let showFocusArea: Bool

    init(
        result: DetectionResult?,
        focusArea: FocusArea = .center,
        showFocusArea: Bool = true
    ) {
        self.result = result
        self.focusArea = focusArea
        self.showFocusArea = showFocusArea
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Focus area indicator
                if showFocusArea {
                    FocusAreaOverlay(
                        focusArea: focusArea,
                        size: geometry.size
                    )
                }

                // Bounding boxes for detected objects
                if let result = result {
                    ForEach(result.objects) { object in
                        BoundingBoxView(
                            object: object,
                            containerSize: geometry.size
                        )
                    }

                    // Detection count badge
                    if result.hasFocusedObjects {
                        DetectionBadge(count: result.focusedObjects.count)
                            .position(
                                x: geometry.size.width - 50,
                                y: 30
                            )
                    }
                }
            }
        }
        .allowsHitTesting(false) // Pass through touches
    }
}

// MARK: - Focus Area Overlay
/// Displays the focus area rectangle
struct FocusAreaOverlay: View {
    let focusArea: FocusArea
    let size: CGSize

    private var rect: CGRect {
        CGRect(
            x: focusArea.origin.x * size.width,
            y: focusArea.origin.y * size.height,
            width: focusArea.size.width * size.width,
            height: focusArea.size.height * size.height
        )
    }

    var body: some View {
        ZStack {
            // Corner brackets instead of full rectangle
            FocusCorners(rect: rect)

            // "FOCUS" label
            Text("FOCUS")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.yellow.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .position(x: rect.midX, y: rect.minY - 12)
        }
    }
}

/// Corner brackets for focus area
struct FocusCorners: View {
    let rect: CGRect
    let cornerLength: CGFloat = 20
    let lineWidth: CGFloat = 2

    var body: some View {
        let color = Color.yellow.opacity(0.8)

        ZStack {
            // Top-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
            }
            .stroke(color, lineWidth: lineWidth)

            // Top-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
            }
            .stroke(color, lineWidth: lineWidth)

            // Bottom-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
            }
            .stroke(color, lineWidth: lineWidth)
        }
    }
}

// MARK: - Bounding Box View
/// Displays a bounding box around a detected object
struct BoundingBoxView: View {
    let object: DetectedObject
    let containerSize: CGSize

    /// Convert Vision coordinates (bottom-left origin) to SwiftUI (top-left origin)
    private var displayRect: CGRect {
        let box = object.boundingBox
        return CGRect(
            x: box.origin.x * containerSize.width,
            y: (1 - box.origin.y - box.height) * containerSize.height,
            width: box.width * containerSize.width,
            height: box.height * containerSize.height
        )
    }

    private var boxColor: Color {
        object.isInFocusArea ? .green : .blue.opacity(0.6)
    }

    private var lineWidth: CGFloat {
        object.isInFocusArea ? 3 : 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            RoundedRectangle(cornerRadius: 4)
                .stroke(boxColor, lineWidth: lineWidth)
                .frame(width: displayRect.width, height: displayRect.height)

            // Label tag
            HStack(spacing: 4) {
                Text(object.label)
                    .font(.caption2)
                    .fontWeight(.semibold)

                Text(object.confidencePercent)
                    .font(.caption2)
                    .opacity(0.8)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(boxColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(y: -24)
        }
        .position(x: displayRect.midX, y: displayRect.midY)
    }
}

// MARK: - Detection Badge
/// Shows count of detected objects
struct DetectionBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "viewfinder")
                .font(.caption)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.8))
        .clipShape(Capsule())
    }
}

// MARK: - Describe Button
/// Button to trigger voice description of detected objects
struct DescribeButton: View {
    let result: DetectionResult?
    @ObservedObject var voiceFeedback: VoiceFeedbackManager
    let isStreaming: Bool

    private var isEnabled: Bool {
        isStreaming && result != nil
    }

    private var buttonColor: Color {
        if voiceFeedback.isSpeaking {
            return .orange
        }
        if result?.hasFocusedObjects == true {
            return .green
        }
        return .blue
    }

    private var buttonIcon: String {
        if voiceFeedback.isSpeaking {
            return "speaker.wave.3.fill"
        }
        return "speaker.wave.2"
    }

    private var buttonText: String {
        if voiceFeedback.isSpeaking {
            return "Speaking..."
        }
        return "Describe"
    }

    var body: some View {
        Button {
            if voiceFeedback.isSpeaking {
                voiceFeedback.stopSpeaking()
            } else if let result = result {
                voiceFeedback.describe(result)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: buttonIcon)
                    .font(.title2)
                    .symbolEffect(.pulse, isActive: voiceFeedback.isSpeaking)

                Text(buttonText)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(buttonColor)
            )
            .shadow(color: buttonColor.opacity(0.5), radius: 8, y: 4)
        }
        .disabled(!isEnabled && !voiceFeedback.isSpeaking)
        .opacity(isEnabled || voiceFeedback.isSpeaking ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: voiceFeedback.isSpeaking)
    }
}

// MARK: - Processing Indicator
/// Shows when object detection is processing
struct ProcessingIndicator: View {
    let isProcessing: Bool

    var body: some View {
        if isProcessing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                Text("Analyzing...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black

        DetectionOverlayView(
            result: DetectionResult(
                objects: [
                    DetectedObject(
                        label: "Cat",
                        confidence: 0.92,
                        boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
                        isInFocusArea: true
                    ),
                    DetectedObject(
                        label: "Couch",
                        confidence: 0.78,
                        boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.2),
                        isInFocusArea: false
                    )
                ],
                timestamp: Date(),
                processingTimeMs: 45
            ),
            focusArea: .center
        )
    }
}
