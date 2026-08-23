//
//  PhoneCameraPreviewLayer.swift
//  Smart Glasses
//
//  UIViewRepresentable wrapping AVCaptureVideoPreviewLayer for smooth camera preview
//

import SwiftUI
import AVFoundation

/// Displays a live camera preview from an AVCaptureSession
struct PhoneCameraPreviewLayer: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    /// UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer
    class PreviewView: UIView {

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

/// Renders black: an `AVCaptureSession` that was never started has no frames to
/// show, and previews have no camera to start it with. Useful for checking
/// layout and sizing around the preview layer, not the image itself.
#Preview {
    PhoneCameraPreviewLayer(session: AVCaptureSession())
        .frame(width: 320, height: 480)
        .background(.black)
}
