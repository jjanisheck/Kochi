//  ThemeImage.swift
//  KochiApp
//
//  Resolves a named image from the active theme folder, falling back to the
//  asset catalog when the theme doesn't override it. Drop-in for Image("name").

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ThemeImage: View {
    @EnvironmentObject private var themeStore: ThemeStore
    private let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        if let themed = themedImage {
            themed.resizable()
        } else {
            Image(name)
                .resizable()
        }
    }

    /// The active theme's override for `name`, loaded off disk. Themes ship
    /// loose image files (not asset-catalog entries), so this goes through the
    /// platform image type rather than `Image(_:)`.
    private var themedImage: Image? {
        guard let url = themeStore.current.images[name] else { return nil }
        #if canImport(UIKit)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #endif
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
/// near-square art: an indefinite `maxWidth/maxHeight: .infinity` frame only
/// reliably fills when the image is far taller than its container, so art whose
/// ratio nearly matches the container (e.g. BRICKS) could otherwise under-fill
/// and leak the window's base colour out the bottom.
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
