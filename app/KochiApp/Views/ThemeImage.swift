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
