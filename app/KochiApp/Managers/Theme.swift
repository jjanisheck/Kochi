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

// MARK: - Colour maths

/// sRGB components and HSB conversion for palette colours, used to derive the
/// live-transcript tones from whatever accent a theme already declares. Every
/// palette colour originates as a hex string, so this round-trips exactly.
enum ThemeColorMath {
    static func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(AppKit)
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (Double(c.redComponent), Double(c.greenComponent),
                Double(c.blueComponent), Double(c.alphaComponent))
        #else
        return nil
        #endif
    }

    static func hsb(_ color: Color) -> (h: Double, s: Double, b: Double, a: Double)? {
        guard let (r, g, b, a) = rgba(color) else { return nil }
        let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
        var h = 0.0
        if delta > 0 {
            if maxV == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxV == 0 ? 0 : delta / maxV, maxV, a)
    }

    static func color(h: Double, s: Double, b: Double, a: Double = 1) -> Color {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        let (r, g, bl): (Double, Double, Double)
        switch i {
        case 0: (r, g, bl) = (b, t, p)
        case 1: (r, g, bl) = (q, b, p)
        case 2: (r, g, bl) = (p, b, t)
        case 3: (r, g, bl) = (p, q, b)
        case 4: (r, g, bl) = (t, p, b)
        default: (r, g, bl) = (b, p, q)
        }
        return Color(.sRGB, red: r, green: g, blue: bl, opacity: a)
    }

    /// True when the palette is a dark one — judged by its own body ink being
    /// light, which is the only signal `ThemePalette` has without the scheme.
    static func isDark(ink: Color) -> Bool { (hsb(ink)?.b ?? 0) > 0.5 }

    /// The counterpart hue for the far side of a conversation: the accent rotated
    /// most of the way round the wheel. Stops short of a true 180° complement,
    /// which lands on the eye-jarring exact opposite; 165° reads as clearly
    /// "a different speaker" while still sitting in the same family.
    ///
    /// A near-neutral accent (NOIR's grey) has no meaningful hue to rotate, so it
    /// falls back to a calm blue-grey rather than producing another grey that
    /// would be indistinguishable from the ME side.
    static func counterpart(of accent: Color) -> Color {
        // Brightness is deliberately dropped: the counterpart is pinned to a fixed
        // depth below so a pale accent cannot yield a washed-out THEM bubble.
        guard let (h, s, _, _) = hsb(accent), s >= 0.15 else {
            return Color(.sRGB, red: 0.42, green: 0.50, blue: 0.60, opacity: 1)
        }
        let rotated = (h + 165.0 / 360.0).truncatingRemainder(dividingBy: 1)
        // Clamp both ways: a neon accent must not produce a neon counterpart, and
        // a muddy one must still be distinguishable.
        return color(h: rotated, s: min(max(s, 0.45), 0.75), b: 0.62)
    }

    /// Relative luminance, WCAG 2.1.
    static func luminance(_ color: Color) -> Double {
        guard let (r, g, b, _) = rgba(color) else { return 0 }
        func f(_ u: Double) -> Double { u <= 0.03928 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    /// WCAG contrast ratio. 4.5 is the pass mark for body text.
    static func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func mix(_ a: Color, _ b: Color) -> Color {
        guard let x = rgba(a), let y = rgba(b) else { return a }
        return Color(.sRGB, red: (x.r + y.r) / 2, green: (x.g + y.g) / 2,
                     blue: (x.b + y.b) / 2, opacity: 1)
    }

    /// The darker stop for a bubble gradient, mirroring how `buttonLo` sits under
    /// `buttonHi` on the physical keys.
    static func gradientLo(of hi: Color) -> Color {
        guard let (h, s, b, _) = hsb(hi) else { return hi }
        return color(h: h, s: s, b: max(b * 0.76, 0.12))
    }

    /// Body text for a filled bubble.
    ///
    /// White, to match the RECORD key — the bubble *is* that key, and a transcript
    /// that switched ink colour theme by theme read as five different components.
    /// White on the shipped accents lands at 2.8–10.7 against the gradient's mid
    /// tone; the key itself ships white at 3.1, and the bubbles carry the same
    /// text shadow and a medium weight to hold it up at 11.5pt.
    ///
    /// The floor is a safety net for a future theme with a genuinely pale key
    /// (a lemon or off-white accent), where white would vanish rather than merely
    /// soften. Only then does the fill's own hue, driven deep, take over. Set
    /// `transcriptMeInk` / `transcriptThemInk` to override either way.
    static func legibleInk(on fill: Color) -> Color {
        if contrast(.white, fill) >= 2.5 { return .white }
        guard let (h, s, _, _) = hsb(fill) else { return .black }
        for b in [0.20, 0.17, 0.14, 0.11, 0.08] {
            let candidate = color(h: h, s: min(s * 1.05, 1), b: b)
            if contrast(candidate, fill) >= 4.5 { return candidate }
        }
        return contrast(.black, fill) >= contrast(.white, fill) ? .black : .white
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
    /// NOTE: these are *also* the live transcript bubble's fill/ink (KochiDeviceStyle),
    /// so to recolor only the goal rows use `goalUnmetFill`/`goalUnmetInk` below.
    let goalRestFill, goalRestInk: Color
    /// Fill + text/checkbox ink for an *unachieved goal row*, specifically (not the
    /// transcript bubble). Optional; default to `goalRestFill`/`goalRestInk` so a
    /// theme that doesn't set them looks unchanged. A theme overrides these to give
    /// resting goals a distinct chip (e.g. BRICKS' orange) without touching the
    /// transcript. Pair a saturated fill with a light ink for legibility.
    let goalUnmetFill, goalUnmetInk: Color
    /// Solid face fill for goal-styled toolbar keys (end/info). Optional; defaults
    /// to `goalUnmetFill`. The keys are always opaque, so when a theme's goal rows
    /// are translucent-over-background (e.g. HERO's frosted parchment), set this to
    /// the solid tone the rows read as, so the keys match without flattening the rows.
    let goalKeyFill: Color
    /// Background fill for a saved-transcript list row. Optional; defaults to
    /// `paper`. A dark theme can set this (e.g. NOIR's black) so the transcript
    /// rows read distinct from the other (lighter) cards.
    let transcriptRowFill: Color
    /// Border stroked around an unachieved goal row. Optional; defaults to clear
    /// (no visible border) so themes opt in. Use an 8-digit `#RRGGBBAA` hex to
    /// control opacity.
    let goalRestBorder: Color
    /// Gradient stops for a *hit* (done/selected) goal row. Optional; default to
    /// `buttonHi`/`buttonLo` so a hit goal matches the primary key — themes that
    /// want a distinct hit color (e.g. HERO's patriotic red) override these
    /// without disturbing the buttons.
    let goalDoneHi, goalDoneLo: Color
    /// Gradient stops for the audio meter's filled volume bars. Optional; default
    /// to `buttonHi`/`buttonLo` so the meter matches the primary key — themes can
    /// override for a distinct meter color (e.g. HERO's patriotic blue).
    let meterHi, meterLo: Color
    /// Face fill for the neutral toolbar keys — the `.light` variant (info) and
    /// any disabled key (end, when not live). Optional; `nil` keeps the default
    /// light-gray bevel gradients, so themes opt in to a tinted key.
    let neutralKeyFill: Color?
    /// Multiply tint for the brand wordmark image. The logo art is a solid white
    /// glyph on transparent, so `colorMultiply(logoTint)` recolors it (white ×
    /// tint = tint) while leaving transparency intact. Optional; `nil` = no tint
    /// (`colorMultiply(.white)`), preserving each theme's original logo.
    let logoTint: Color?
    /// Hairline rule drawn in a `SlabLabel` section header (the line across
    /// "GOALS ——— set 3" / "TRANSCRIPT ——— ready"). Optional; defaults to `line`.
    let slabRule: Color
    /// Text/labels that sit directly on the themed window background (brand row,
    /// section headers) + their fainter secondary variant (counts, status).
    /// Optional; default to `inkSoft`/`muted`.
    let onBg, onBgFaint: Color
    /// Gradient scrim over the tape-deck background image (top→bottom). Use
    /// 8-digit `#RRGGBBAA` hex to control opacity. Optional; default to the
    /// black 0.45 → 0.7 deck darkening. A near-clear scrim lets the image's
    /// real colors show through.
    let deckScrimTop, deckScrimBottom: Color
    /// Live-transcript recess: a translucent tint laid over a blur of the theme
    /// background, so the panel sits *in* the theme instead of on top of it as a
    /// solid white slab. Use 8-digit `#RRGGBBAA` hex — the alpha is the point.
    /// Optional; defaults to the theme's own `paper`/`panel` at ~22–30% — a wash,
    /// not a fill, so the background art stays legible through it.
    let transcriptFill: Color
    /// The two speakers' bubbles, drawn as gradients exactly like the physical
    /// keys. ME *is* the RECORD key: `buttonHi` → `buttonLo`. THEM is that accent
    /// rotated 165° round the wheel and darkened to the same depth, so the far
    /// side reads as a different voice on matching hardware. The `Ink` tokens are
    /// chosen for legibility — white where it clears WCAG AA (as on the key),
    /// otherwise the fill's own hue driven deep. All six are optional.
    let transcriptMeFill, transcriptMeLo, transcriptMeInk: Color
    let transcriptThemFill, transcriptThemLo, transcriptThemInk: Color

    /// Ordered token names — used to decode/validate the `colors` map.
    static let tokenNames = ["orange","orangeDeep","ink","inkSoft","paper","win",
                             "panel","panel2","line","lineSoft","muted","muted2",
                             "good","deck","deckBorder","buttonHi","buttonLo",
                             "goalRestFill","goalRestInk",
                             "goalUnmetFill","goalUnmetInk","goalKeyFill","transcriptRowFill","goalRestBorder",
                             "goalDoneHi","goalDoneLo","meterHi","meterLo",
                             "neutralKeyFill","logoTint","slabRule","onBg","onBgFaint",
                             "deckScrimTop","deckScrimBottom",
                             "transcriptFill",
                             "transcriptMeFill","transcriptMeLo","transcriptMeInk",
                             "transcriptThemFill","transcriptThemLo","transcriptThemInk"]

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
        goalUnmetFill: Color(themeHex: "#FFFFFF")!, goalUnmetInk: Color(themeHex: "#1C1B19")!,
        goalKeyFill: Color(themeHex: "#FFFFFF")!,
        transcriptRowFill: Color(themeHex: "#FFFFFF")!,
        goalRestBorder: .clear,
        goalDoneHi: Color(themeHex: "#FF7A36")!, goalDoneLo: Color(themeHex: "#EC5000")!,
        meterHi: Color(themeHex: "#FF7A36")!, meterLo: Color(themeHex: "#EC5000")!,
        neutralKeyFill: nil, logoTint: nil,
        slabRule: Color(themeHex: "#CDCCC6")!,
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
        self.goalUnmetFill = c("goalUnmetFill") ?? self.goalRestFill
        self.goalUnmetInk = c("goalUnmetInk") ?? self.goalRestInk
        self.goalKeyFill = c("goalKeyFill") ?? self.goalUnmetFill
        self.transcriptRowFill = c("transcriptRowFill") ?? self.paper
        self.goalRestBorder = c("goalRestBorder") ?? .clear
        self.goalDoneHi = c("goalDoneHi") ?? self.buttonHi
        self.goalDoneLo = c("goalDoneLo") ?? self.buttonLo
        self.meterHi = c("meterHi") ?? self.buttonHi
        self.meterLo = c("meterLo") ?? self.buttonLo
        self.neutralKeyFill = c("neutralKeyFill")
        self.logoTint = c("logoTint")
        self.slabRule = c("slabRule") ?? line
        self.onBg = c("onBg") ?? inkSoft
        self.onBgFaint = c("onBgFaint") ?? muted
        self.deckScrimTop = c("deckScrimTop") ?? Color.black.opacity(0.45)
        self.deckScrimBottom = c("deckScrimBottom") ?? Color.black.opacity(0.7)

        // Live transcript. Derived from what the theme already declares, so every
        // theme — including ones written later — gets a legible, on-palette
        // transcript for free, and any of the five can still be overridden.
        let dark = ThemeColorMath.isDark(ink: ink)
        let me = self.buttonHi
        let them = ThemeColorMath.counterpart(of: me)
        self.transcriptFill = c("transcriptFill")
            ?? (dark ? panel.opacity(0.30) : paper.opacity(0.22))
        self.transcriptMeFill = c("transcriptMeFill") ?? me
        self.transcriptMeLo = c("transcriptMeLo") ?? self.buttonLo
        self.transcriptThemFill = c("transcriptThemFill") ?? them
        self.transcriptThemLo = c("transcriptThemLo") ?? ThemeColorMath.gradientLo(of: them)
        self.transcriptMeInk = c("transcriptMeInk")
            ?? ThemeColorMath.legibleInk(on: ThemeColorMath.mix(self.transcriptMeFill, self.transcriptMeLo))
        self.transcriptThemInk = c("transcriptThemInk")
            ?? ThemeColorMath.legibleInk(on: ThemeColorMath.mix(self.transcriptThemFill, self.transcriptThemLo))
    }

    /// Memberwise init (used by `fallback`).
    init(orange: Color, orangeDeep: Color, ink: Color, inkSoft: Color, paper: Color,
         win: Color, panel: Color, panel2: Color, line: Color, lineSoft: Color,
         muted: Color, muted2: Color, good: Color, deck: Color, deckBorder: Color,
         buttonHi: Color, buttonLo: Color, goalRestFill: Color, goalRestInk: Color,
         goalUnmetFill: Color, goalUnmetInk: Color, goalKeyFill: Color,
         transcriptRowFill: Color,
         goalRestBorder: Color, goalDoneHi: Color, goalDoneLo: Color,
         meterHi: Color, meterLo: Color,
         neutralKeyFill: Color?, logoTint: Color?,
         slabRule: Color,
         onBg: Color, onBgFaint: Color, deckScrimTop: Color, deckScrimBottom: Color) {
        self.orange = orange; self.orangeDeep = orangeDeep; self.ink = ink
        self.inkSoft = inkSoft; self.paper = paper; self.win = win; self.panel = panel
        self.panel2 = panel2; self.line = line; self.lineSoft = lineSoft
        self.muted = muted; self.muted2 = muted2; self.good = good; self.deck = deck
        self.deckBorder = deckBorder
        self.buttonHi = buttonHi; self.buttonLo = buttonLo
        self.goalRestFill = goalRestFill; self.goalRestInk = goalRestInk
        self.goalUnmetFill = goalUnmetFill; self.goalUnmetInk = goalUnmetInk
        self.goalKeyFill = goalKeyFill
        self.transcriptRowFill = transcriptRowFill
        self.goalRestBorder = goalRestBorder
        self.goalDoneHi = goalDoneHi; self.goalDoneLo = goalDoneLo
        self.meterHi = meterHi; self.meterLo = meterLo
        self.neutralKeyFill = neutralKeyFill
        self.logoTint = logoTint; self.slabRule = slabRule
        self.onBg = onBg; self.onBgFaint = onBgFaint
        self.deckScrimTop = deckScrimTop; self.deckScrimBottom = deckScrimBottom
        // Derived here too, so the memberwise init (and `fallback`) stay in step
        // with the JSON path without repeating five more parameters.
        let dark = ThemeColorMath.isDark(ink: ink)
        let them = ThemeColorMath.counterpart(of: buttonHi)
        self.transcriptFill = dark ? panel.opacity(0.30) : paper.opacity(0.22)
        self.transcriptMeFill = buttonHi
        self.transcriptMeLo = buttonLo
        self.transcriptThemFill = them
        self.transcriptThemLo = ThemeColorMath.gradientLo(of: them)
        self.transcriptMeInk = ThemeColorMath.legibleInk(on: ThemeColorMath.mix(buttonHi, buttonLo))
        self.transcriptThemInk = ThemeColorMath.legibleInk(
            on: ThemeColorMath.mix(them, ThemeColorMath.gradientLo(of: them)))
    }
}

/// Raw decode of theme.json.
struct ThemeManifest: Decodable {
    let displayName: String
    let colorScheme: String?
    let colors: [String: String]
    let images: [String: String]?
    /// Tape-deck reel treatment. `deckReelGrayscale` 0…1 (1 = fully gray),
    /// `deckReelBrightness` -1…1. Optional; default to 1 / -0.15 (the original
    /// dimmed-gray reel). Set grayscale 0 to show the reel's real colors.
    let deckReelGrayscale: Double?
    let deckReelBrightness: Double?
    /// When true, the background image is scaled to fill the window exactly
    /// (frame hugs all four edges) instead of the default `scaledToFill` crop.
    /// Use for a decorative *framed* background that must be seen whole (e.g.
    /// HERO's ornate 1776 page). Optional; default false.
    let backgroundStretch: Bool?
    /// When true, an unachieved goal row renders a frosted blur (ultraThinMaterial)
    /// behind its `goalRestFill` tint, so a translucent fill reads as glass over
    /// the themed background. Optional; default false.
    let goalRestBlur: Bool?
    /// The MEETING DETAILS header floats on the themed background image and the
    /// tab bar carries the theme's primary key gradient (`buttonHi`→`buttonLo`).
    /// The header label reads with `onBg`; the tab labels read white (matching the
    /// primary key's face text). Optional; default true. Set false to fall back to
    /// the legacy gray "device chrome".
    let chromeOnBackground: Bool?
    /// When true, the top brand row (KŌCHI logo + "MEETING COACH" + READY/REC
    /// status) is hidden on the home screen, letting a theme that supplies its own
    /// titling in the background art stand alone. Optional; default false.
    let hideBrandRow: Bool?
}

/// A resolved theme: palette + asset URLs + identity.
struct Theme: Identifiable {
    let id: String            // folder name, e.g. "default"
    let displayName: String
    let colorScheme: ColorScheme?
    let palette: ThemePalette
    let images: [String: URL] // logical name -> file URL inside the theme folder
    let folderURL: URL
    let deckReelGrayscale: Double
    let deckReelBrightness: Double
    /// Scale the background image to fill the window exactly (vs `scaledToFill`).
    let backgroundStretch: Bool
    /// Frost an unachieved goal row's fill with a blur material.
    let goalRestBlur: Bool
    /// Settings header + tab bar float transparently on the themed background
    /// (vs the default gray device chrome).
    let chromeOnBackground: Bool
    /// Hide the home-screen brand row (logo + "MEETING COACH" + status).
    let hideBrandRow: Bool

    /// Subdirectory (relative to bundle resources) where this theme's videos live.
    var videoSubdirectory: String { "Themes/\(id)/videos" }

    /// Optional `images/theme.png` used as this theme's chip in the Themes picker.
    /// Resolved by convention (it need not be listed in theme.json's `images`);
    /// nil when absent, so the picker falls back to the theme's key gradient.
    var swatchImageURL: URL? {
        let url = folderURL.appendingPathComponent("images/theme.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

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
                     colorScheme: scheme,
                     palette: palette, images: images, folderURL: folderURL,
                     deckReelGrayscale: m.deckReelGrayscale ?? 1.0,
                     deckReelBrightness: m.deckReelBrightness ?? -0.15,
                     backgroundStretch: m.backgroundStretch ?? false,
                     goalRestBlur: m.goalRestBlur ?? false,
                     chromeOnBackground: m.chromeOnBackground ?? true,
                     hideBrandRow: m.hideBrandRow ?? false)
    }

    /// Guaranteed-valid default, used before discovery or if nothing is found.
    static let fallbackDefault: Theme = {
        let folder = Bundle.main.url(forResource: "Themes", withExtension: nil)?
            .appendingPathComponent("default")
            ?? URL(fileURLWithPath: "/dev/null")
        return Theme(id: "default", displayName: "DEFAULT", colorScheme: .light,
                     palette: .fallback, images: [:],
                     folderURL: folder, deckReelGrayscale: 1.0, deckReelBrightness: -0.15,
                     backgroundStretch: false, goalRestBlur: false,
                     chromeOnBackground: true, hideBrandRow: false)
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
    nonisolated(unsafe) static var subdirectory: String = "Themes/default/videos"
}

/// Nonisolated mirror of the active theme's tape-deck reel treatment, read by
/// the deck view. Written by `ThemeStore` on the main actor.
enum ActiveDeck {
    nonisolated(unsafe) static var reelGrayscale: Double = 1.0
    nonisolated(unsafe) static var reelBrightness: Double = -0.15
}

/// Nonisolated mirror of goal-row treatment flags, read by `GoalRow` (which uses
/// the nonisolated `KColor`/mirror pattern rather than an `@EnvironmentObject`).
/// Written by `ThemeStore` on the main actor.
enum ActiveGoal {
    nonisolated(unsafe) static var restBlur: Bool = false
}

/// Nonisolated mirror of home-screen chrome flags (read by `KochiMC1View`, which
/// uses the `KColor`/mirror pattern rather than an `@EnvironmentObject`).
/// Written by `ThemeStore` on the main actor.
enum ActiveChrome {
    nonisolated(unsafe) static var hideBrandRow: Bool = false
}
