//
//  KochiDeviceStyle.swift
//  KochiApp
//
//  Shared "physical device" design system for the KŌCHI Meeting Companion,
//  ported from the Claude Design prototype (KOCHI Meeting Companion.html /
//  app.jsx). Palette, bundled-font helpers, beveled physical-key button style,
//  and the mono section label are reused by KochiMC1View and SettingsView.
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
    static var goalUnmetFill: Color { p.goalUnmetFill }
    static var goalUnmetInk: Color  { p.goalUnmetInk }
    static var goalKeyFill: Color   { p.goalKeyFill }
    static var transcriptRowFill: Color { p.transcriptRowFill }
    static var goalRestBorder: Color { p.goalRestBorder }
    static var goalDoneHi: Color { p.goalDoneHi }
    static var goalDoneLo: Color { p.goalDoneLo }
    static var meterHi: Color { p.meterHi }
    static var meterLo: Color { p.meterLo }
    static var neutralKeyFill: Color? { p.neutralKeyFill }
    static var logoTint: Color? { p.logoTint }
    static var slabRule: Color { p.slabRule }
    static var onBg: Color         { p.onBg }
    static var onBgFaint: Color    { p.onBgFaint }
    static var deckScrimTop: Color    { p.deckScrimTop }
    static var deckScrimBottom: Color { p.deckScrimBottom }
    static var transcriptFill: Color      { p.transcriptFill }
    static var transcriptMeFill: Color    { p.transcriptMeFill }
    static var transcriptMeLo: Color      { p.transcriptMeLo }
    static var transcriptMeInk: Color     { p.transcriptMeInk }
    static var transcriptThemFill: Color  { p.transcriptThemFill }
    static var transcriptThemLo: Color    { p.transcriptThemLo }
    static var transcriptThemInk: Color   { p.transcriptThemInk }
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

enum KeyVariant { case primary, light, goal }

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
                        // Border: the `.goal` key mirrors the unfinished-goal row's
                        // `goalRestBorder`; other keys get the raised top highlight.
                        if variant == .goal {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(KColor.goalRestBorder, lineWidth: 1)
                        } else {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(colors: [Color.white.opacity(variant == .primary ? 0.45 : 0.9),
                                                            Color.clear],
                                                   startPoint: .top, endPoint: .bottom),
                                    lineWidth: 1)
                        }
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
            // The `.goal` key always wears the unfinished-goal color (even when
            // disabled). It uses `goalKeyFill` (defaults to goalUnmetFill) so a
            // theme whose goal rows are translucent-over-background can give the
            // opaque keys the solid tone the rows read as. Clamp opacity (×100) so
            // any residual alpha saturates to a fully solid key.
            if variant == .goal {
                let solid = KColor.goalKeyFill.opacity(100)
                return LinearGradient(colors: [solid, solid], startPoint: .top, endPoint: .bottom)
            }
            // A theme may tint the neutral keys (light variant + any disabled key)
            // with a single fill; the bevel still reads via the highlight + shadow.
            if let tint = KColor.neutralKeyFill, !isEnabled || variant == .light {
                return LinearGradient(colors: [tint, tint], startPoint: .top, endPoint: .bottom)
            }
            if !isEnabled {
                return LinearGradient(colors: [Color(red: 231/255, green: 229/255, blue: 223/255),
                                               Color(red: 220/255, green: 218/255, blue: 211/255)],
                                      startPoint: .top, endPoint: .bottom)
            }
            switch variant {
            case .primary:
                return LinearGradient(colors: [KColor.buttonHi, KColor.buttonLo],
                                      startPoint: .top, endPoint: .bottom)
            case .light, .goal:
                return LinearGradient(colors: [Color(red: 251/255, green: 250/255, blue: 248/255),
                                               Color(red: 222/255, green: 220/255, blue: 213/255)],
                                      startPoint: .top, endPoint: .bottom)
            }
        }
        private var faceText: Color {
            if variant == .goal { return KColor.goalUnmetInk }
            if !isEnabled { return KColor.muted2 }
            return variant == .primary ? .white : KColor.inkSoft
        }
        private var shadowColor: Color {
            // The goal key reads flat like the goal rows — no raised key shadow.
            if variant == .goal { return .clear }
            guard isEnabled else { return .clear }
            // Primary key glow derives from the theme's own deep button color
            // (was a hardcoded orange that glowed orange on every theme).
            return variant == .primary ? KColor.buttonLo.opacity(0.4)
                                       : Color.black.opacity(0.22)
        }
    }
}

// MARK: - Mono section label ("GOALS ——— set 3")

/// The design's `.slab` row: a small uppercase mono label, a hairline rule, and
/// an optional trailing accessory (count / status / timer).
struct SlabLabel<Trailing: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder var trailing: Trailing

    init(_ title: String, tint: Color = KColor.inkSoft, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(KFont.mono(10, .medium))
                .tracking(1.3)
                .foregroundColor(tint)
            Rectangle().fill(KColor.slabRule).frame(height: 1)
            trailing
        }
    }
}

extension SlabLabel where Trailing == EmptyView {
    init(_ title: String, tint: Color = KColor.inkSoft) { self.init(title, tint: tint) { EmptyView() } }
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
                .foregroundColor(ink(turn.speaker))
                // The same lift the primary key gives its label.
                .shadow(color: .black.opacity(turn.speaker == .other ? 0 : 0.18),
                        radius: 0.5, x: 0, y: 1)
                .multilineTextAlignment(rightAligned ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(bubbleBackground(turn.speaker))
    }

    @ViewBuilder private func bubbleBackground(_ s: TranscriptSpeaker) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if s == .other {
            // Unattributed lines stay a neutral wash — they are not a speaker.
            shape
                .fill(onDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                .overlay(shape.strokeBorder(strokeColor(s), lineWidth: 1))
        } else {
            // A bubble is a key: the same top-to-bottom gradient and top highlight
            // the RECORD button wears, so a line of transcript reads as the same
            // piece of hardware. ME literally *is* the RECORD key's gradient.
            shape
                .fill(LinearGradient(colors: [fill(s), fillLo(s)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.45), Color.clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
        }
    }

    // Mic ("Me") and system ("Them") come from the palette: ME is the theme's own
    // RECORD-key gradient (`buttonHi` → `buttonLo`); THEM is that accent rotated
    // round the wheel to the same depth. Both are overridable per theme. They used
    // to be two hardcoded RGB literals, which is why the transcript looked the
    // same under every theme.

    private func fill(_ s: TranscriptSpeaker) -> Color {
        s == .them ? KColor.transcriptThemFill : KColor.transcriptMeFill
    }

    private func fillLo(_ s: TranscriptSpeaker) -> Color {
        s == .them ? KColor.transcriptThemLo : KColor.transcriptMeLo
    }

    private func ink(_ s: TranscriptSpeaker) -> Color {
        switch s {
        case .me:    return KColor.transcriptMeInk
        case .them:  return KColor.transcriptThemInk
        case .other: return onDark ? KColor.goalRestInk : KColor.ink
        }
    }

    private func labelColor(_ s: TranscriptSpeaker) -> Color {
        // The speaker tag is the bubble's own ink at reduced weight, so ME and
        // THEM are labelled in the colour they are written in.
        ink(s).opacity(0.75)
    }

    private func strokeColor(_ s: TranscriptSpeaker) -> Color {
        onDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}


// MARK: - Tape deck
//
// The transport of a real deck: two reels — supply and take-up — with a
// recessed counter/VU window between them, over the theme's own plate art.
// Shared so the desktop and the phone render one deck, not two that drift.

/// mm:ss, the tape counter's format.
func deckTime(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

/// One tape reel, drawn from the app's own reel art over the themed deck plate,
/// with the per-theme grayscale/brightness treatment from `ActiveDeck`. No blend
/// mode: `.screen` only works while the plate is a literal near-black, and washes
/// the deck out once the plate is theme art.
struct TapeReel: View {
    let isSpinning: Bool
    /// Seconds per revolution. The take-up reel runs faster than the supply
    /// reel, the way real tape does.
    let revolutionSeconds: Double
    let size: CGFloat

    @State private var angle: Double = 0

    var body: some View {
        ThemeImage("FilmReel")
            .scaledToFit()
            .frame(width: size, height: size)
            .grayscale(ActiveDeck.reelGrayscale)
            .brightness(ActiveDeck.reelBrightness)
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
            .onChange(of: isSpinning) { _, spinning in
                if spinning { spin() } else { halt() }
            }
            .onAppear { if isSpinning { spin() } }
    }

    private func spin() {
        angle = 0
        withAnimation(.linear(duration: revolutionSeconds).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }

    private func halt() {
        withAnimation(.easeOut(duration: 0.35)) { angle = 0 }
    }
}

/// The recessed window between the reels: tape counter over an 8-segment VU
/// meter, the way the transport of a real deck reads.
struct DeckCounterWindow: View {
    let elapsed: TimeInterval
    let level: Float
    let isLive: Bool

    private static let segments = 8

    var body: some View {
        VStack(spacing: 7) {
            Text(deckTime(elapsed))
                .font(KFont.mono(21, .medium))
                .tracking(0.4)
                .foregroundColor(isLive ? KColor.orange : KColor.muted2)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<Self.segments, id: \.self) { i in
                    Rectangle()
                        .fill(i < lit
                              ? AnyShapeStyle(LinearGradient(colors: [KColor.meterHi, KColor.meterLo],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(KColor.deckBorder))
                        .frame(width: 3, height: 13)
                        // Segments fall away from full height as the level drops,
                        // so the meter reads as a needle, not a bar.
                        .scaleEffect(y: i < lit ? 1 : 0.35, anchor: .bottom)
                }
            }
            .frame(height: 13, alignment: .bottom)
            .animation(.easeOut(duration: 0.12), value: lit)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(KColor.deck)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var lit: Int {
        guard isLive else { return 0 }
        return max(1, min(Self.segments, Int(level * Float(Self.segments))))
    }
}

/// The whole deck: themed plate, two reels cropped in half by the deck floor,
/// and the counter window centred between them.
struct TapeDeckPanel: View {
    let elapsed: TimeInterval
    let level: Float
    let isLive: Bool
    var height: CGFloat = 96
    var cornerRadius: CGFloat = 5

    /// Reels are twice the deck's height, so the floor crops them in half and
    /// only their top halves are on show.
    private var reelSize: CGFloat { height * 2 }
    /// Inset of each reel's centre from its edge, scaled off the reel so the
    /// pair always leaves the counter window clear in the middle.
    private var reelInset: CGFloat { reelSize * 0.3 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base tone, so a theme with no plate art never flashes white.
                KColor.deck

                // The plate needs a definite frame, exactly as `ThemeBackground`
                // gives its art. A bare `scaledToFill()` keeps the image's own
                // (much larger) size, which inflates the ZStack — and since a
                // GeometryReader pins its content to the top-leading corner, the
                // centred counter then sits well below the visible deck.
                ThemeImage("BackgroundPlainImage")
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // The themed deck scrim. This is what makes the deck read like
                // the coach screen: that module lays its caption gradient over a
                // black base, so the liquid-glass sheen — which is pure white —
                // has something dark to catch on. Straight onto bright plate art
                // the same sheen all but disappears and the deck goes flat.
                //
                // `deckScrimTop`/`deckScrimBottom` are first-class palette tokens
                // (BRICKS and HERO already tune them; everything else takes the
                // black 0.45 → 0.7 default) that nothing was reading. Sitting
                // under the reels, the scrim also restores the dark field the
                // silver-on-black reel art was drawn for.
                LinearGradient(colors: [KColor.deckScrimTop, KColor.deckScrimBottom],
                               startPoint: .top, endPoint: .bottom)

                // Reels hang half below the floor: centred on the deck's bottom
                // edge, so only their top halves show.
                TapeReel(isSpinning: isLive, revolutionSeconds: 2.4, size: reelSize)
                    .position(x: reelInset, y: geo.size.height)
                TapeReel(isSpinning: isLive, revolutionSeconds: 3.6, size: reelSize)
                    .position(x: geo.size.width - reelInset, y: geo.size.height)

                // Dead centre of the deck, between the two reels.
                DeckCounterWindow(elapsed: elapsed, level: level, isLive: isLive)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .liquidGlass(cornerRadius, inset: 3)
    }
}
