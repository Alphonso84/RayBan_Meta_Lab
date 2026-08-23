//
//  DocumentBoundaryOverlay.swift
//  Smart Glasses
//
//  Visual overlay showing detected document boundary and capture stability
//

import SwiftUI

/// Overlay showing document boundary detection and auto-capture progress
struct DocumentBoundaryOverlay: View {
    let boundary: DocumentBoundary?
    let stabilityProgress: Float
    let isStable: Bool
    let statusText: String
    let frameSize: CGSize

    var body: some View {
        ZStack {
            // Document boundary outline
            if let boundary = boundary {
                DocumentBoundaryShape(boundary: boundary, frameSize: frameSize)
                    .stroke(
                        boundaryColor,
                        style: StrokeStyle(
                            lineWidth: isStable ? 4 : 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .animation(.easeInOut(duration: 0.2), value: isStable)

                // Corner indicators
                ForEach(cornerPoints(for: boundary), id: \.self) { point in
                    Circle()
                        .fill(boundaryColor)
                        .frame(width: isStable ? 14 : 10, height: isStable ? 14 : 10)
                        .position(point)
                        .animation(.easeInOut(duration: 0.2), value: isStable)
                }
            }

            // Status indicator at bottom
            VStack {
                Spacer()

                VStack(spacing: 12) {
                    // Stability progress ring
                    if boundary != nil {
                        ZStack {
                            // Background ring
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                                .frame(width: 50, height: 50)

                            // Progress ring
                            Circle()
                                .trim(from: 0, to: CGFloat(stabilityProgress))
                                .stroke(
                                    boundaryColor,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .frame(width: 50, height: 50)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.15), value: stabilityProgress)

                            // Center icon
                            Image(systemName: isStable ? "checkmark" : "viewfinder")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(boundaryColor)
                        }
                    }

                    // Status text
                    Text(statusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 120) // Above the capture button
            }
        }
    }

    private var boundaryColor: Color {
        if isStable {
            return .green
        } else if stabilityProgress > 0.5 {
            return .yellow
        } else if boundary != nil {
            return .cyan
        } else {
            return .white.opacity(0.5)
        }
    }

    private func cornerPoints(for boundary: DocumentBoundary) -> [CGPoint] {
        boundary.path(in: frameSize)
    }
}

/// Shape that draws the document boundary polygon
struct DocumentBoundaryShape: Shape {
    let boundary: DocumentBoundary
    let frameSize: CGSize

    func path(in rect: CGRect) -> Path {
        let points = boundary.path(in: frameSize)
        guard points.count == 4 else { return Path() }

        var path = Path()
        path.move(to: points[0])
        path.addLine(to: points[1])
        path.addLine(to: points[2])
        path.addLine(to: points[3])
        path.closeSubpath()

        return path
    }
}

/// Compact stability indicator for inline use
struct StabilityIndicator: View {
    let progress: Float
    let isStable: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        isStable ? Color.green : Color.cyan,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 20, height: 20)

            // Status text
            Text(isStable ? "Ready" : "\(Int(progress * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isStable ? .green : .secondary)
        }
        .animation(.easeInOut(duration: 0.15), value: progress)
    }
}

#Preview {
    ZStack {
        Color.black

        DocumentBoundaryOverlay(
            boundary: DocumentBoundary(
                topLeft: CGPoint(x: 0.1, y: 0.85),
                topRight: CGPoint(x: 0.9, y: 0.85),
                bottomRight: CGPoint(x: 0.90, y: 0.2),
                bottomLeft: CGPoint(x: 0.10, y: 0.2),
                confidence: 0.95
            ),
            stabilityProgress: 0.6,
            isStable: false,
            statusText: "Hold steady...",
            frameSize: CGSize(width: 390, height: 844)
        )
    }
}

#Preview("Stability indicator") {
    HStack(spacing: 32) {
        StabilityIndicator(progress: 0.0, isStable: false)
        StabilityIndicator(progress: 0.55, isStable: false)
        StabilityIndicator(progress: 1.0, isStable: true)
    }
    .padding()
    .background(.black)
}

#Preview("No document") {
    ZStack {
        Color.black

        DocumentBoundaryOverlay(
            boundary: nil,
            stabilityProgress: 0,
            isStable: false,
            statusText: "Point at a document",
            frameSize: CGSize(width: 390, height: 844)
        )
    }
}

#Preview("Ready to capture") {
    ZStack {
        Color.black

        DocumentBoundaryOverlay(
            boundary: PreviewSamples.documentBoundary,
            stabilityProgress: 1.0,
            isStable: true,
            statusText: "Captured",
            frameSize: CGSize(width: 390, height: 844)
        )
    }
}
