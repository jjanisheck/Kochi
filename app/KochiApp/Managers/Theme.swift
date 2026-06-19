//  Theme.swift
//  KochiApp
//
//  Theme model: a palette + asset manifest decoded from a theme folder's
//  theme.json. See docs/superpowers/specs/2026-06-19-theme-system-design.md.

import SwiftUI

extension Color {
    /// Parse a `#RRGGBB` hex string into a Color. Returns nil if malformed.
    init?(themeHex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue:  Double(v & 0xFF) / 255
        )
    }
}

/// The 15 palette tokens that back `KColor`.
struct ThemePalette {
    let orange, orangeDeep, ink, inkSoft, paper, win, panel, panel2: Color
    let line, lineSoft, muted, muted2, good, deck, deckBorder: Color

    /// Ordered token names — used to decode/validate the `colors` map.
    static let tokenNames = ["orange","orangeDeep","ink","inkSoft","paper","win",
                             "panel","panel2","line","lineSoft","muted","muted2",
                             "good","deck","deckBorder"]

    /// Today's exact palette — the safety net if discovery ever finds nothing.
    static let fallback = ThemePalette(
        orange: Color(themeHex: "#F95800")!, orangeDeep: Color(themeHex: "#E14E00")!,
        ink: Color(themeHex: "#1C1B19")!, inkSoft: Color(themeHex: "#3B3A37")!,
        paper: Color(themeHex: "#FFFFFF")!, win: Color(themeHex: "#E9E8E4")!,
        panel: Color(themeHex: "#EFEEEA")!, panel2: Color(themeHex: "#E4E3DE")!,
        line: Color(themeHex: "#CDCCC6")!, lineSoft: Color(themeHex: "#DAD9D3")!,
        muted: Color(themeHex: "#8D8C86")!, muted2: Color(themeHex: "#A9A8A2")!,
        good: Color(themeHex: "#1F8A4C")!, deck: Color(themeHex: "#34332C")!,
        deckBorder: Color(themeHex: "#26251F")!
    )

    /// Build from a name→hex map. Returns nil if any token is missing/malformed.
    init?(colors: [String: String]) {
        func c(_ k: String) -> Color? { colors[k].flatMap { Color(themeHex: $0) } }
        guard let orange = c("orange"), let orangeDeep = c("orangeDeep"),
              let ink = c("ink"), let inkSoft = c("inkSoft"), let paper = c("paper"),
              let win = c("win"), let panel = c("panel"), let panel2 = c("panel2"),
              let line = c("line"), let lineSoft = c("lineSoft"), let muted = c("muted"),
              let muted2 = c("muted2"), let good = c("good"), let deck = c("deck"),
              let deckBorder = c("deckBorder") else { return nil }
        self.orange = orange; self.orangeDeep = orangeDeep; self.ink = ink
        self.inkSoft = inkSoft; self.paper = paper; self.win = win; self.panel = panel
        self.panel2 = panel2; self.line = line; self.lineSoft = lineSoft
        self.muted = muted; self.muted2 = muted2; self.good = good; self.deck = deck
        self.deckBorder = deckBorder
    }

    /// Memberwise init (used by `fallback`).
    init(orange: Color, orangeDeep: Color, ink: Color, inkSoft: Color, paper: Color,
         win: Color, panel: Color, panel2: Color, line: Color, lineSoft: Color,
         muted: Color, muted2: Color, good: Color, deck: Color, deckBorder: Color) {
        self.orange = orange; self.orangeDeep = orangeDeep; self.ink = ink
        self.inkSoft = inkSoft; self.paper = paper; self.win = win; self.panel = panel
        self.panel2 = panel2; self.line = line; self.lineSoft = lineSoft
        self.muted = muted; self.muted2 = muted2; self.good = good; self.deck = deck
        self.deckBorder = deckBorder
    }
}

/// Raw decode of theme.json.
struct ThemeManifest: Decodable {
    let displayName: String
    let colorScheme: String?
    let videoPrefix: String
    let colors: [String: String]
    let images: [String: String]?
}

/// A resolved theme: palette + asset URLs + identity.
struct Theme: Identifiable {
    let id: String            // folder name, e.g. "default"
    let displayName: String
    let colorScheme: ColorScheme?
    let videoPrefix: String
    let palette: ThemePalette
    let images: [String: URL] // logical name -> file URL inside the theme folder
    let folderURL: URL

    /// Subdirectory (relative to bundle resources) where this theme's videos live.
    var videoSubdirectory: String { "Themes/\(id)/videos" }

    /// Load a theme from a folder containing theme.json. Returns nil if the json
    /// is missing/unreadable or any color token is absent (surfaces authoring
    /// errors instead of shipping a half-themed look).
    static func load(folderURL: URL) -> Theme? {
        let jsonURL = folderURL.appendingPathComponent("theme.json")
        guard let data = try? Data(contentsOf: jsonURL),
              let m = try? JSONDecoder().decode(ThemeManifest.self, from: data),
              let palette = ThemePalette(colors: m.colors) else { return nil }
        var images: [String: URL] = [:]
        for (name, rel) in (m.images ?? [:]) {
            images[name] = folderURL.appendingPathComponent(rel)
        }
        let scheme: ColorScheme?
        switch m.colorScheme?.lowercased() {
        case "dark": scheme = .dark
        case "light": scheme = .light
        default: scheme = nil
        }
        return Theme(id: folderURL.lastPathComponent, displayName: m.displayName,
                     colorScheme: scheme, videoPrefix: m.videoPrefix,
                     palette: palette, images: images, folderURL: folderURL)
    }

    /// Guaranteed-valid default, used before discovery or if nothing is found.
    static let fallbackDefault: Theme = {
        let folder = Bundle.main.url(forResource: "Themes", withExtension: nil)?
            .appendingPathComponent("default")
            ?? URL(fileURLWithPath: "/dev/null")
        return Theme(id: "default", displayName: "DEFAULT", colorScheme: .light,
                     videoPrefix: "general", palette: .fallback, images: [:],
                     folderURL: folder)
    }()
}

/// Nonisolated mirror of the active theme's palette. `KColor` is a nonisolated
/// design-system enum read from many (non-`@MainActor`) view contexts, so it
/// cannot touch the `@MainActor` `ThemeStore`. `ThemeStore` is the sole writer
/// — on the main actor it pushes `current.palette` here whenever the theme
/// changes — and reads happen during main-actor rendering, so access is
/// effectively serialized.
enum ActivePalette {
    nonisolated(unsafe) static var current: ThemePalette = .fallback
}

/// Nonisolated mirror of the active theme's video lookup info, so the
/// (nonisolated) `VideoCoachingManager` can resolve clips without touching the
/// `@MainActor` `ThemeStore`. `ThemeStore` is the sole writer (on the main
/// actor), in `init` and `select`.
enum ActiveThemeVideo {
    nonisolated(unsafe) static var prefix: String = "general"
    nonisolated(unsafe) static var subdirectory: String = "Themes/default/videos"
}
