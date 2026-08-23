//
//  DocumentBoundaryTests.swift
//  Smart GlassesTests
//
//  Covers the conversion from Vision's coordinate space to SwiftUI's.
//
//  Vision reports normalized points with a bottom-left origin; SwiftUI draws
//  from the top left. Getting that flip wrong renders the boundary overlay
//  upside down over the live preview, which is easy to miss in code review and
//  obvious the moment it ships.
//

import Testing
import CoreGraphics
@testable import Smart_Glasses

struct DocumentBoundaryTests {

    /// A boundary occupying the upper-left quadrant in Vision's space.
    private let boundary = DocumentBoundary(
        topLeft: CGPoint(x: 0.1, y: 0.9),
        topRight: CGPoint(x: 0.5, y: 0.9),
        bottomRight: CGPoint(x: 0.5, y: 0.6),
        bottomLeft: CGPoint(x: 0.1, y: 0.6),
        confidence: 0.9
    )

    private let canvas = CGSize(width: 200, height: 100)

    // MARK: - Coordinate conversion

    @Test func pathFlipsTheVerticalAxis() {
        let points = boundary.path(in: canvas)

        // y = 0.9 in Vision is near the top, so it must map near y = 0 in SwiftUI.
        #expect(points[0].y.isApproximately(10))   // (1 - 0.9) * 100
        #expect(points[3].y.isApproximately(40))   // (1 - 0.6) * 100
    }

    @Test func pathScalesHorizontallyWithoutFlipping() {
        let points = boundary.path(in: canvas)

        #expect(points[0].x.isApproximately(20))    // 0.1 * 200
        #expect(points[1].x.isApproximately(100))   // 0.5 * 200
    }

    /// The corners come back in draw order, so the polygon closes correctly.
    @Test func pathReturnsFourCornersClockwiseFromTopLeft() {
        let points = boundary.path(in: canvas)

        #expect(points.count == 4)
        #expect(points[0].isApproximately(CGPoint(x: 20, y: 10)))    // top left
        #expect(points[1].isApproximately(CGPoint(x: 100, y: 10)))   // top right
        #expect(points[2].isApproximately(CGPoint(x: 100, y: 40)))   // bottom right
        #expect(points[3].isApproximately(CGPoint(x: 20, y: 40)))    // bottom left
    }

    /// The top edge must stay above the bottom edge once converted — the single
    /// assertion that catches an inverted flip.
    @Test func convertedTopEdgeIsAboveTheBottomEdge() {
        let points = boundary.path(in: canvas)

        #expect(points[0].y < points[3].y)
        #expect(points[1].y < points[2].y)
    }

    // MARK: - Bounding rect

    @Test func boundingRectSpansAllFourCorners() {
        let rect = boundary.boundingRect

        #expect(rect.minX == 0.1)
        #expect(rect.minY == 0.6)
        #expect(rect.width.isApproximately(0.4))
        #expect(rect.height.isApproximately(0.3))
    }

    /// A page photographed at an angle has no axis-aligned corners, so the rect
    /// has to take the outermost of each pair rather than trusting one corner.
    @Test func boundingRectHandlesASkewedQuadrilateral() {
        let skewed = DocumentBoundary(
            topLeft: CGPoint(x: 0.2, y: 0.8),
            topRight: CGPoint(x: 0.9, y: 0.95),
            bottomRight: CGPoint(x: 0.85, y: 0.3),
            bottomLeft: CGPoint(x: 0.1, y: 0.25),
            confidence: 0.7
        )

        let rect = skewed.boundingRect

        #expect(rect.minX == 0.1)    // bottomLeft is further left than topLeft
        #expect(rect.maxX.isApproximately(0.9))
        #expect(rect.minY.isApproximately(0.25))
        #expect(rect.maxY.isApproximately(0.95))
    }
}

/// Vision's normalized coordinates are binary fractions, so conversions carry
/// rounding noise — `(1 - 0.9) * 100` is 9.999999999999998, not 10. Exact
/// equality would fail on arithmetic that is entirely correct.
private extension CGFloat {
    func isApproximately(_ other: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
        abs(self - other) < tolerance
    }
}

private extension CGPoint {
    func isApproximately(_ other: CGPoint, tolerance: CGFloat = 1e-9) -> Bool {
        x.isApproximately(other.x, tolerance: tolerance)
            && y.isApproximately(other.y, tolerance: tolerance)
    }
}
