//
//  PageVisionImageTests.swift
//  Smart GlassesTests
//
//  Covers the downscale applied before a page is attached to a model prompt.
//
//  The OCR pipeline renders at 2500px because Vision benefits from it; the
//  language model does not, and larger attachments cost proportionally more
//  tokens and latency.
//

import Testing
import UIKit
@testable import Smart_Glasses

@MainActor
struct PageVisionImageTests {

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }

    @Test func oversizedPagesAreScaledToTheLongestSide() {
        let prepared = PageVisionImage.prepare(image(width: 2500, height: 2000), maxDimension: 1024)

        #expect(prepared?.width == 1024)
        #expect(prepared?.height == 819)   // 2000 * (1024/2500), rounded
    }

    @Test func theLongestSideDrivesTheScaleInPortraitToo() {
        let prepared = PageVisionImage.prepare(image(width: 1000, height: 2000), maxDimension: 1024)

        #expect(prepared?.height == 1024)
        #expect(prepared?.width == 512)
    }

    /// Aspect ratio must survive: the model accepts any shape, and cropping or
    /// padding to a square would throw away part of the page.
    @Test func aspectRatioIsPreserved() {
        let prepared = PageVisionImage.prepare(image(width: 2000, height: 1000), maxDimension: 500)

        #expect(prepared != nil)
        let ratio = Double(prepared!.width) / Double(prepared!.height)
        #expect(abs(ratio - 2.0) < 0.01)
    }

    /// Interpolating a small source gains nothing and costs tokens.
    @Test func smallImagesAreNotUpscaled() {
        let prepared = PageVisionImage.prepare(image(width: 400, height: 300), maxDimension: 1024)

        #expect(prepared?.width == 400)
        #expect(prepared?.height == 300)
    }

    @Test func anImageExactlyAtTheLimitIsUnchanged() {
        let prepared = PageVisionImage.prepare(image(width: 1024, height: 768), maxDimension: 1024)

        #expect(prepared?.width == 1024)
        #expect(prepared?.height == 768)
    }

    /// A degenerate image must return nil rather than a zero-sized attachment
    /// the model would reject.
    @Test func aZeroSizedImageIsRejected() {
        #expect(PageVisionImage.prepare(UIImage()) == nil)
    }

    /// An extreme aspect ratio must not round a dimension down to zero.
    @Test func averyWideImageKeepsAtLeastOnePixelOfHeight() {
        let prepared = PageVisionImage.prepare(image(width: 2000, height: 2), maxDimension: 100)

        #expect(prepared != nil)
        #expect((prepared?.height ?? 0) >= 1)
    }

    @Test func theDefaultDimensionIsTheDocumentedOne() {
        #expect(PageVisionImage.defaultMaxDimension == 1024)
    }
}
