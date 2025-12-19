//
//  AirPlayButton.swift
//  Smart Glasses
//
//  Created by Alphonso Sensley II on 12/9/25.
//

import SwiftUI
import AVKit

/// SwiftUI wrapper for AVRoutePickerView to enable AirPlay device selection
struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .white
    var activeTintColor: UIColor = .systemBlue

    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = tintColor
        routePicker.activeTintColor = activeTintColor
        routePicker.prioritizesVideoDevices = true

        // Make background transparent
        routePicker.backgroundColor = .clear

        return routePicker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}

/// Styled AirPlay button for the full-screen view
struct StyledAirPlayButton: View {
    var isCompact: Bool = false

    var body: some View {
        if isCompact {
            AirPlayButton(tintColor: .white, activeTintColor: .systemBlue)
                .frame(width: 44, height: 44)
        } else {
            HStack(spacing: 8) {
                AirPlayButton(tintColor: .white, activeTintColor: .systemBlue)
                    .frame(width: 24, height: 24)
                Text("AirPlay")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            StyledAirPlayButton()
            StyledAirPlayButton(isCompact: true)
        }
    }
}
