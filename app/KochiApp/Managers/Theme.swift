//  Theme.swift
//  KochiApp
//
//  Theme model: a palette + asset manifest decoded from a theme folder's
//  theme.json. See docs/superpowers/specs/2026-06-19-theme-system-design.md.

import SwiftUI

extension Color {
    /// Parse a `#RRGGBB` or `#RRGGBBAA` hex string into a Color. Returns nil if
    /// malformed. The 8-digit form carries an alpha channel (for scrims/overlays).
    init?(themeHex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 6 {
            self = Color(
                red:   Double((v >> 16) & 0xFF) / 255,
                green: Double((v >> 8) & 0xFF) / 255,
                blue:  Double(v & 0xFF) / 255
            )
        } else if s.count == 8 {
            self = Color(.sRGB,
                red:     Double((v >> 24) & 0xFF) / 255,
                green:   Double((v >> 16) & 0xFF) / 255,
                blue:    Double((v >> 8) & 0xFF) / 255,
                opacity: Double(v & 0xFF) / 255
            )
        } else {
            return nil
        }
    }
}

/// The palette tokens that back `KColor`. `buttonHi`/`buttonLo` are the primary
/// (glossy "key") button + hit-goal gradient stops; a theme may omit them in its
/// JSON, in which case they default to `orange`/`orangeDeep`.
struct ThemePalette {
    let orange, orangeDeep, ink, inkSoft, paper, win, panel, panel2: Color
    let line, lineSoft, muted, muted2, good, deck, deckBorder: Color
    let buttonHi, buttonLo: Color
    /// Unachieved goal-row fill + its text/checkbox ink. Optional; default to
    /// `paper`/`ink` (an achieved goal uses the `buttonHi`/`buttonLo` gradient).
    let goalRestFill, goalRestInk: Color
    /// Text/labels that sit directly on the themed window background (brand row,
    /// section headers) + their fainter secondary variant (counts, status).
    /// Optional; default to `inkSoft`/`muted`.
    let onBg, onBgFaint: Color
    /// Gradient scrim over the tape-deck background image (top→bottom). Use
    /// 8-digit `#RRGGBBAA` hex to control opacity. Optional; default to the
    /// black 0.45 → 0.7 deck darkening. A near-clear scrim lets the image's
    /// real colors show through.
    let deckScrimTop, deckScrimBottom: Color

    /// Ordered token names — used to decode/validate the `colors` map.
    static let tokenNames = ["orange","orangeDeep","ink","inkSoft","paper","win",
                             "panel","panel2","line","lineSoft","muted","muted2",
                             "good","deck","deckBorder","buttonHi","buttonLo",
                             "goalRestFill","goalRestInk","onBg","onBgFaint",
                             "deckScrimTop","deckScrimBottom"]

    /// Today's exact palette — the safety net if discovery ever finds nothing.
    static let fallback = ThemePalette(
        orange: Color(themeHex: "#F95800")!, orangeDeep: Color(themeHex: "#E14E00")!,
        ink: Color(themeHex: "#1C1B19")!, inkSoft: Color(themeHex: "#3B3A37")!,
        paper: Color(themeHex: "#FFFFFF")!, win: Color(themeHex: "#E9E8E4")!,
        panel: Color(themeHex: "#EFEEEA")!, panel2: Color(themeHex: "#E4E3DE")!,
        line: Color(themeHex: "#CDCCC6")!, lineSoft: Color(themeHex: "#DAD9D3")!,
        muted: Color(themeHex: "#8D8C86")!, muted2: Color(themeHex: "#A9A8A2")!,
        good: Color(themeHex: "#1F8A4C")!, deck: Color(themeHex: "#34332C")!,
        deckBorder: Color(themeHex: "#26251F")!,
        buttonHi: Color(themeHex: "#FF7A36")!, buttonLo: Color(themeHex: "#EC5000")!,
        goalRestFill: Color(themeHex: "#FFFFFF")!, goalRestInk: Color(themeHex: "#1C1B19")!,
        onBg: Color(themeHex: "#3B3A37")!, onBgFaint: Color(themeHex: "#8D8C86")!,
        deckScrimTop: Color.black.opacity(0.45), deckScrimBottom: Color.black.opacity(0.7)
    )

    /// Build from a name→hex map. Returns nil if any required token is
    /// missing/malformed. `buttonHi`/`buttonLo` are optional and fall back to
    /// `orange`/`orangeDeep`.
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
        self.buttonHi = c("buttonHi") ?? orange
        self.buttonLo = c("buttonLo") ?? orangeDeep
        self.goalRestFill = c("goalRestFill") ?? paper
        self.goalRestInk = c("goalRestInk") ?? ink
        self.onBg = c("onBg") ?? inkSoft
        self.onBgFaint = c("onBgFaint") ?? muted
        self.deckScrimTop = c("deckScrimTop") ?? Color.black.opacity(0.45)
        self.deckScrimBottom = c("deckScrimBottom") ?? Color.black.opacity(0.7)
    }

    /// Memberwise init (used by `fallback`).
    init(orange: Color, orangeDeep: Color, ink: Color, inkSoft: Color, paper: Color,
         win: Color, panel: Color, panel2: Color, line: Color, lineSoft: Color,
         muted: Color, muted2: Color, good: Color, deck: Color, deckBorder: Color,
         buttonHi: Color, buttonLo: Color, goalRestFill: Color, goalRestInk: Color,
         onBg: Color, onBgFaint: Color, deckScrimTop: Color, deckScrimBottom: Color) {
        self.orange = orange; self.orangeDeep = orangeDeep; self.ink = ink
        self.inkSoft = inkSoft; self.paper = paper; self.win = win; self.panel = panel
        self.panel2 = panel2; self.line = line; self.lineSoft = lineSoft
        self.muted = muted; self.muted2 = muted2; self.good = good; self.deck = deck
        self.deckBorder = deckBorder
        self.buttonHi = buttonHi; self.buttonLo = buttonLo
        self.goalRestFill = goalRestFill; self.goalRestInk = goalRestInk
        self.onBg = onBg; self.onBgFaint = onBgFaint
        self.deckScrimTop = deckScrimTop; self.deckScrimBottom = deckScrimBottom
    }
}

/// Raw decode of theme.json.
struct ThemeManifest: Decodable {
    let displayName: String
    let colorScheme: String?
    let videoPrefix: String
    let colors: [String: String]
    let images: [String: String]?
    /// Tape-deck reel treatment. `deckReelGrayscale` 0…1 (1 = fully gray),
    /// `deckReelBrightness` -1…1. Optional; default to 1 / -0.15 (the original
    /// dimmed-gray reel). Set grayscale 0 to show the reel's real colors.
    let deckReelGrayscale: Double?
    let deckReelBrightness: Double?
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
    let deckReelGrayscale: Double
    let deckReelBrightness: Double

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
                     palette: palette, images: images, folderURL: folderURL,
                     deckReelGrayscale: m.deckReelGrayscale ?? 1.0,
                     deckReelBrightness: m.deckReelBrightness ?? -0.15)
    }

    /// Guaranteed-valid default, used before discovery or if nothing is found.
    static let fallbackDefault: Theme = {
        let folder = Bundle.main.url(forResource: "Themes", withExtension: nil)?
            .appendingPathComponent("default")
            ?? URL(fileURLWithPath: "/dev/null")
        return Theme(id: "default", displayName: "DEFAULT", colorScheme: .light,
                     videoPrefix: "general", palette: .fallback, images: [:],
                     folderURL: folder, deckReelGrayscale: 1.0, deckReelBrightness: -0.15)
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

/// Nonisolated mirror of the active theme's tape-deck reel treatment, read by
/// the deck view. Written by `ThemeStore` on the main actor.
enum ActiveDeck {
    nonisolated(unsafe) static var reelGrayscale: Double = 1.0
    nonisolated(unsafe) static var reelBrightness: Double = -0.15
}
