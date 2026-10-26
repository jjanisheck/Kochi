//  ThemeImage.swift
//  KochiApp
//
//  Resolves a named image from the active theme folder, falling back to the
//  asset catalog when the theme doesn't override it. Drop-in for Image("name").

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ThemeImage: View {
    @EnvironmentObject private var themeStore: ThemeStore
    private let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        if let url = themeStore.current.images[name], let img = Self.loadImage(url) {
            img.resizable()
        } else {
            Image(name)
                .resizable()
        }
    }

    private static func loadImage(_ url: URL) -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }
}

/// Use the same edge-to-edge phone artwork on Mac and iOS, including framed
/// themes. A definite canvas keeps borders and texture scaling consistent.
struct ThemeBackground: View {
    private let name: String
    /// Which screen edges the art bleeds under. Defaults to every edge (the
    /// original behavior), including the phone's status bar and Dynamic Island.
    private let ignoredEdges: Edge.Set

    init(_ name: String, ignoresSafeAreaEdges: Edge.Set = .all) {
        self.name = name
        self.ignoredEdges = ignoresSafeAreaEdges
    }

    var body: some View {
        GeometryReader { geo in
            ThemeImage(name)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(edges: ignoredEdges)
    }
}
