//  ThemeImage.swift
//  KochiApp
//
//  Resolves a named image from the active theme folder, falling back to the
//  asset catalog when the theme doesn't override it. Drop-in for Image("name").

import SwiftUI

struct ThemeImage: View {
    @EnvironmentObject private var themeStore: ThemeStore
    private let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        if let url = themeStore.current.images[name],
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
        } else {
            Image(name)
                .resizable()
        }
    }
}

/// Full-window themed background. Defaults to `scaledToFill` (the image bleeds
/// edge-to-edge, cropping as needed). When the active theme sets
/// `backgroundStretch`, the image is shown *whole* and undistorted (`scaledToFit`)
/// so a decorative *framed* page (e.g. HERO's 1776 border) is fully visible —
/// fit to width, with any leftover band above/below filled by a `scaledToFill`
/// copy of the same art underneath. Because both layers are the identical
/// parchment, the band reads as a seamless extension rather than a gray gap.
/// The `GeometryReader` hands a definite frame so fill is reliable even for
/// near-square art (see ContentView's note).
struct ThemeBackground: View {
    @EnvironmentObject private var themeStore: ThemeStore
    private let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        GeometryReader { geo in
            if themeStore.current.backgroundStretch {
                ZStack {
                    // Underlay: same art filled edge-to-edge so the letterbox
                    // band carries the parchment, never the window's gray base.
                    ThemeImage(name)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    // Overlay: the whole framed page, undistorted, fit to width.
                    ThemeImage(name)
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            } else {
                ThemeImage(name)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }
}
