//
//  KochiDeviceStyle.swift
//  KochiApp
//
//  Shared "physical device" design system for the KŌCHI Meeting Companion,
//  ported from the Claude Design prototype (KOCHI Meeting Companion.html /
//  app.jsx). Palette, bundled-font helpers, beveled physical-key button style,
//  and the mono section label are reused by ContentView and SettingsView.
//

import SwiftUI
import CoreText

// MARK: - Palette (from the design's :root custom properties)

enum KColor {
    private static var p: ThemePalette { ActivePalette.current }
    static var orange: Color     { p.orange }
    static var orangeDeep: Color { p.orangeDeep }
    static var ink: Color        { p.ink }
    static var inkSoft: Color     { p.inkSoft }
    static var paper: Color      { p.paper }
    static var win: Color        { p.win }
    static var panel: Color      { p.panel }
    static var panel2: Color     { p.panel2 }
    static var line: Color       { p.line }
    static var lineSoft: Color   { p.lineSoft }
    static var muted: Color      { p.muted }
    static var muted2: Color     { p.muted2 }
    static var good: Color       { p.good }
    static var deck: Color       { p.deck }
    static var deckBorder: Color { p.deckBorder }
    static var buttonHi: Color   { p.buttonHi }
    static var buttonLo: Color   { p.buttonLo }
    static var goalRestFill: Color { p.goalRestFill }
    static var goalRestInk: Color  { p.goalRestInk }
}

// MARK: - Bundled fonts

enum KFont {
    /// Register every bundled .ttf with CoreText once, so `Font.custom` resolves
    /// the family names. Cross-platform (no Info.plist UIAppFonts needed).
    static func register() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Zilla Slab — display / UI / buttons / big numbers. Uses the exact
    /// PostScript face per weight for reliable rendering.
    static func zilla(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:        name = "ZillaSlab-Bold"
        case .semibold:                     name = "ZillaSlab-SemiBold"
        case .medium:                       name = "ZillaSlab-Medium"
        default:                            name = "ZillaSlab-Regular"
        }
        return .custom(name, fixedSize: size)
    }

    /// JetBrains Mono — status labels, transcript, metadata, tags (variable font).
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", fixedSize: size).weight(weight)
    }

    /// Hanken Grotesk — goal labels (variable font).
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Hanken Grotesk", fixedSize: size).weight(weight)
    }
}

// MARK: - Beveled physical key (toolbar + Done key)

enum KeyVariant { case primary, light }

/// A pressable hardware-style key: raised gradient face, top highlight, drop
/// shadow, and a 2px pressed-down inset state. Mirrors the design's `.btn`.
struct BeveledKeyStyle: ButtonStyle {
    var variant: KeyVariant = .light
    var radius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(variant: variant, radius: radius, configuration: configuration)
    }

    private struct KeyBody: View {
        let variant: KeyVariant
        let radius: CGFloat
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .foregroundColor(faceText)
                // Only the enabled orange key gets the drop shadow on its text;
                // a disabled (grey) key with a grey shadow looks muddy.
                .shadow(color: (variant == .primary && isEnabled) ? Color.black.opacity(0.25) : .clear,
                        radius: 0.5, x: 0, y: 1)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(faceGradient)
                        // top highlight
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(variant == .primary ? 0.45 : 0.9),
                                                        Color.clear],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                        if pressed {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Color.black.opacity(0.18))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: shadowColor, radius: pressed ? 1 : 4,
                        x: 0, y: pressed ? 0 : 2)
                .offset(y: pressed ? 2 : 0)
                .opacity(isEnabled ? 1 : 1) // disabled visuals handled by gradient below
                .animation(.easeOut(duration: 0.08), value: pressed)
        }

        private var faceGradient: LinearGradient {
            if !isEnabled {
                return LinearGradient(colors: [Color(red: 231/255, green: 229/255, blue: 223/255),
                                               Color(red: 220/255, green: 218/255, blue: 211/255)],
                                      startPoint: .top, endPoint: .bottom)
            }
            switch variant {
            case .primary:
                return LinearGradient(colors: [KColor.buttonHi, KColor.buttonLo],
                                      startPoint: .top, endPoint: .bottom)
            case .light:
                return LinearGradient(colors: [Color(red: 251/255, green: 250/255, blue: 248/255),
                                               Color(red: 222/255, green: 220/255, blue: 213/255)],
                                      startPoint: .top, endPoint: .bottom)
            }
        }
        private var faceText: Color {
            if !isEnabled { return KColor.muted2 }
            return variant == .primary ? .white : KColor.inkSoft
        }
        private var shadowColor: Color {
            guard isEnabled else { return .clear }
            return variant == .primary ? Color(red: 140/255, green: 55/255, blue: 0).opacity(0.4)
                                       : Color.black.opacity(0.22)
        }
    }
}

// MARK: - Mono section label ("GOALS ——— set 3")

/// The design's `.slab` row: a small uppercase mono label, a hairline rule, and
/// an optional trailing accessory (count / status / timer).
struct SlabLabel<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(KFont.mono(10, .medium))
                .tracking(1.3)
                .foregroundColor(KColor.inkSoft)
            Rectangle().fill(KColor.line).frame(height: 1)
            trailing
        }
    }
}

extension SlabLabel where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

// MARK: - Liquid-glass bevel

/// A glossy "liquid glass" treatment that hugs the edge: a white-gradient
/// reflection across the surface (bright at the top, clear through the middle,
/// a faint reflection returning at the bottom) plus a bright bevel rim snug
/// against the border, with a soft glow so it pops. Non-interactive.
struct LiquidGlass: View {
    var cornerRadius: CGFloat
    var inset: CGFloat = 5

    var body: some View {
        let innerRadius = max(4, cornerRadius - inset * 0.4)
        let pane = RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
        ZStack {
            // 1. Glossy sheen raking from the top-left of the inset pane.
            pane.fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.30), location: 0.0),
                    .init(color: .white.opacity(0.08), location: 0.18),
                    .init(color: .clear,               location: 0.5),
                    .init(color: .black.opacity(0.12), location: 1.0),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )

            // 2. THE GLASS REFLECTION: white gradient down the pane — bright top,
            //    clear mid, a faint reflection wrapping back at the very bottom.
            //    No edge stroke — just the soft gradient sheen.
            pane.fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.42), location: 0.0),
                    .init(color: .white.opacity(0.18), location: 0.16),
                    .init(color: .white.opacity(0.04), location: 0.34),
                    .init(color: .clear,               location: 0.52),
                    .init(color: .white.opacity(0.03), location: 0.84),
                    .init(color: .white.opacity(0.14), location: 1.0),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .padding(inset) // clear buffer between the edge and the glass pane
        .allowsHitTesting(false)
        .compositingGroup()
    }
}

extension View {
    /// Overlay the glossy liquid-glass treatment as an inset pane.
    func liquidGlass(_ cornerRadius: CGFloat, inset: CGFloat = 5) -> some View {
        overlay(LiquidGlass(cornerRadius: cornerRadius, inset: inset))
    }
}

// MARK: - Device card container

extension View {
    /// Paper card with the design's hairline border + soft shadow.
    func kCard(radius: CGFloat = 9, padding: CGFloat = 11) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KColor.paper)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(KColor.line, lineWidth: 1))
            )
            .shadow(color: Color.black.opacity(0.05), radius: 1.5, x: 0, y: 1)
    }
}

// MARK: - Chat-style transcript

enum TranscriptSpeaker { case me, them, other }

struct TranscriptTurn: Identifiable {
    let id = UUID()
    let speaker: TranscriptSpeaker
    let text: String
}

/// Parse a "Me: …\nThem: …" transcript into speaker turns. Lines without a
/// speaker prefix are treated as a continuation of the previous turn (or a
/// neutral turn when there's no prefix at all, e.g. a flattened transcript).
func parseTranscript(_ raw: String) -> [TranscriptTurn] {
    var turns: [TranscriptTurn] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
        let s = String(line)
        if s.hasPrefix("Me: ") {
            turns.append(TranscriptTurn(speaker: .me, text: String(s.dropFirst(4))))
        } else if s.hasPrefix("Them: ") {
            turns.append(TranscriptTurn(speaker: .them, text: String(s.dropFirst(6))))
        } else {
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if let last = turns.popLast() {
                turns.append(TranscriptTurn(speaker: last.speaker, text: last.text + " " + t))
            } else {
                turns.append(TranscriptTurn(speaker: .other, text: t))
            }
        }
    }
    return turns
}

/// Renders transcript turns as chat bubbles — "Me" (mic) on the left, "Them"
/// (system audio) on the right — so the two inputs read as a conversation.
struct ChatTranscriptView: View {
    let turns: [TranscriptTurn]
    var onDark: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ForEach(turns) { turn in
                HStack(spacing: 0) {
                    if turn.speaker == .them { Spacer(minLength: 34) }
                    bubble(turn)
                    if turn.speaker != .them { Spacer(minLength: 34) }
                }
            }
        }
    }

    private func bubble(_ turn: TranscriptTurn) -> some View {
        let rightAligned = turn.speaker == .them
        return VStack(alignment: rightAligned ? .trailing : .leading, spacing: 2) {
            if turn.speaker != .other {
                Text(turn.speaker == .them ? "THEM" : "ME")
                    .font(KFont.mono(8))
                    .tracking(0.6)
                    .foregroundColor(labelColor(turn.speaker))
            }
            Text(turn.text)
                .font(KFont.mono(11.5))
                .foregroundColor(textColor)
                .multilineTextAlignment(rightAligned ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(bubbleColor(turn.speaker))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(strokeColor(turn.speaker), lineWidth: 1))
        )
    }

    // Mic ("Me") = orange, System ("Them") = steel blue. Tuned per background.
    private var meHue: Color { Color(red: 255/255, green: 138/255, blue: 77/255) }
    private var themHue: Color { Color(red: 120/255, green: 158/255, blue: 200/255) }

    private var textColor: Color {
        onDark ? Color(red: 230/255, green: 228/255, blue: 220/255) : KColor.ink
    }
    private func labelColor(_ s: TranscriptSpeaker) -> Color {
        switch s {
        case .them: return themHue
        default:    return onDark ? meHue : KColor.orangeDeep
        }
    }
    private func bubbleColor(_ s: TranscriptSpeaker) -> Color {
        if s == .other { return onDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04) }
        let hue = s == .them ? themHue : meHue
        return onDark ? hue.opacity(0.16) : hue.opacity(0.10)
    }
    private func strokeColor(_ s: TranscriptSpeaker) -> Color {
        if s == .other { return onDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
        let hue = s == .them ? themHue : meHue
        return onDark ? hue.opacity(0.30) : hue.opacity(0.25)
    }
}

