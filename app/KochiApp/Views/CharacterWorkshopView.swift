import SwiftUI
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated enum CoachWorkshopAction: String, CaseIterable, Identifiable {
    case idle = "Rest", listening = "Listen", thinking = "Think", salute = "Salute"
    case wave = "Wave", point = "Point", openHand = "Open palm", checkWatch = "Watch"
    case nod = "Nod", tilt = "Tilt"
    var id: String { rawValue }

    func reaction(expression: CoachExpression) -> CoachReaction {
        let intent: CoachIntent
        let gesture: CoachGesture
        switch self {
        case .idle: intent = .idle; gesture = .none
        case .listening: intent = .listen; gesture = .none
        case .thinking: intent = .thinking; gesture = .none
        case .salute: intent = .goal; gesture = .salute
        case .wave: intent = .wrap; gesture = .wave
        case .point: intent = .focus; gesture = .point
        case .openHand: intent = .prompt; gesture = .openHand
        case .checkWatch: intent = .timing; gesture = .checkWatch
        case .nod: intent = .steady; gesture = .nod
        case .tilt: intent = .listen; gesture = .tilt
        }
        return CoachReaction(intent: intent, expression: expression, gesture: gesture, intensity: 0.65)
    }
}

@MainActor
final class CoachWorkshopModel: ObservableObject {
    enum Framing: String, CaseIterable { case card = "App card", portrait = "Full portrait" }
    @Published var action: CoachWorkshopAction = .salute { didSet { refreshReaction() } }
    @Published var expression: CoachExpression = .pleased { didSet { refreshReaction() } }
    @Published var draft: CoachCharacterTuning { didSet { invalidate(); notice = "" } }
    @Published var reaction = CoachWorkshopAction.salute.reaction(expression: .pleased)
    @Published var playhead: Double = 1.4
    @Published var playing = false
    @Published var speed: Double = 1
    @Published var joints = true
    @Published var grid = false
    @Published var framing: Framing = .card { didSet { invalidate() } }
    @Published private(set) var seekID = UUID()
    @Published private(set) var jointGap: CGFloat = 0
    @Published private(set) var targetOffset: CGFloat = 0
    @Published var notice = ""
    private var requestedSeekTime: Double = 1.4
    private let settings: CoachCharacterSettings

    init(settings: CoachCharacterSettings? = nil) {
        let resolved = settings ?? .shared
        self.settings = resolved
        draft = resolved.tuning
    }

    var control: CoachPreviewControl {
        CoachPreviewControl(reaction: reaction, thinking: action == .thinking, seekID: seekID,
            seekTime: requestedSeekTime, playing: playing, speed: speed, joints: joints, grid: grid)
    }

    private func refreshReaction() {
        reaction = action.reaction(expression: expression)
        invalidate()
    }

    private func invalidate() {
        playing = false
        requestedSeekTime = playhead
        seekID = UUID()
    }

    func seek(_ time: Double) {
        playhead = min(5, max(0, time))
        invalidate()
    }

    func replay() {
        seek(0)
        playing = true
    }

    func receiveFrame(time: Double, gap: CGFloat, offset: CGFloat, requestID: UUID) {
        guard requestID == seekID else { return }
        if abs(playhead - time) > 0.005 { playhead = time }
        if abs(jointGap - gap) > 0.001 { jointGap = gap }
        if abs(targetOffset - offset) > 0.01 { targetOffset = offset }
    }

    func apply() {
        settings.apply(draft)
        notice = "Saved. The live coach now uses these proportions."
    }

    func reset() { draft = .standard }

    func load(_ json: String) {
        guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(CoachCharacterTuning.self, from: data) else {
            notice = "Couldn't load that preset. Paste a JSON object with numeric character settings."
            return
        }
        draft = value.sanitized
        notice = "Preset loaded into the preview. Apply it when ready."
    }

    func copySettings() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft.json(), forType: .string)
        #else
        UIPasteboard.general.string = draft.json()
        #endif
        notice = "Settings copied. Paste them into our conversation to share this setup."
    }
}

struct PortraitCharacterWorkshopView: View {
    @StateObject private var studio = CoachWorkshopModel()
    @State private var presetJSON = ""

    private var artworkFolder: URL? {
        Bundle.main.url(forResource: "Themes", withExtension: nil)?.appendingPathComponent("default/avatar")
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            playback
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Preview gestures and tune proportions. No meeting or microphone needed.")
                        .font(KFont.sans(12, .regular))
                        .foregroundColor(KColor.inkSoft)
                    actionControls
                    proportions
                    debugControls
                    DisclosureGroup("Arm fit") {
                        VStack(spacing: 14) {
                            tuningSlider("Sleeve width", value: $studio.draft.armWidth, range: 0.65...1.6, suffix: "×")
                            tuningSlider("Upper arm", value: $studio.draft.upperArmLength, range: 110...210, suffix: "px", decimals: 0)
                            tuningSlider("Forearm", value: $studio.draft.forearmLength, range: 110...210, suffix: "px", decimals: 0)
                            tuningSlider("Shoulder spread", value: $studio.draft.shoulderSpread, range: -30...30, suffix: "px", decimals: 0)
                            tuningSlider("Shoulder height", value: $studio.draft.shoulderLift, range: -20...20, suffix: "px", decimals: 0)
                        }
                        .padding(.top, 12)
                    }
                    DisclosureGroup("Breathing and framing") {
                        VStack(spacing: 14) {
                            tuningSlider("Breathing amount", value: $studio.draft.breathAmplitude, range: 0...24, suffix: "px", decimals: 0)
                            tuningSlider("Breathing cycle", value: $studio.draft.breathPeriod, range: 2.5...8, suffix: "s", decimals: 1)
                            tuningSlider("Camera framing", value: $studio.draft.framingHeight, range: 440...540, suffix: "px", decimals: 0)
                            Text("Camera stays fixed during every gesture.")
                                .font(KFont.sans(11, .regular))
                                .foregroundColor(KColor.inkSoft)
                        }
                        .padding(.top, 12)
                    }
                    DisclosureGroup("Share or load settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button("Copy current settings") { studio.copySettings() }
                            TextEditor(text: $presetJSON)
                                .font(KFont.mono(10))
                                .frame(height: 110)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(KColor.line))
                                .accessibilityLabel("Preset JSON")
                            Button("Load pasted preset") { studio.load(presetJSON) }
                                .disabled(presetJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("Loading changes the preview. Apply saves it to the live coach.")
                                .font(KFont.sans(11, .regular))
                                .foregroundColor(KColor.inkSoft)
                        }
                        .padding(.top, 10)
                    }
                }
                .font(KFont.sans(12, .medium))
                .padding(14)
            }
            .background(KColor.paper.opacity(0.97))
            footer
        }
        .tint(KColor.orange)
        .accessibilityIdentifier("character-workshop")
    }

    private var preview: some View {
        VStack(spacing: 6) {
            HStack {
                Text(studio.action.rawValue.uppercased())
                    .font(KFont.mono(10, .medium))
                    .tracking(1)
                Spacer()
                Picker("Preview framing", selection: $studio.framing) {
                    ForEach(CoachWorkshopModel.Framing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            .foregroundColor(KColor.ink)
            if let folder = artworkFolder {
                GeometryReader { geometry in
                    let width = studio.framing == .portrait ? min(geometry.size.width, 270 * 664 / 540) : geometry.size.width
                    let requestID = studio.seekID
                    CoachSceneSurface(folder: folder, reaction: studio.reaction,
                        meetingActive: studio.action != .idle, thinking: studio.action == .thinking,
                        reduceMotion: false, paused: false, tuning: studio.draft,
                        preview: studio.control, onPreviewFrame: { [model = studio] time, gap, offset in
                            model.receiveFrame(time: time, gap: gap, offset: offset, requestID: requestID)
                        })
                        .frame(width: width, height: geometry.size.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .frame(height: studio.framing == .portrait ? 270 : 174)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
            } else {
                Text("Character artwork couldn't be loaded.").frame(height: 174)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(KColor.paper.opacity(0.98))
    }

    private var playback: some View {
        VStack(spacing: 5) {
            HStack(spacing: 14) {
                Button { studio.playing.toggle() } label: {
                    Label(studio.playing ? "Pause" : "Play", systemImage: studio.playing ? "pause.fill" : "play.fill")
                }
                .accessibilityIdentifier("workshop-play")
                Button { studio.replay() } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Replay gesture")
                Spacer()
                Picker("Playback speed", selection: $studio.speed) {
                    Text("¼×").tag(0.25)
                    Text("½×").tag(0.5)
                    Text("1×").tag(1.0)
                }
                .labelsHidden()
                .frame(width: 75)
                Text(String(format: "%.2f / 5s", studio.playhead))
                    .font(KFont.mono(10))
                    .monospacedDigit()
                    .frame(width: 78, alignment: .trailing)
            }
            Slider(value: Binding(get: { studio.playhead }, set: { studio.seek($0) }), in: 0...5)
                .accessibilityLabel("Gesture time")
                .accessibilityIdentifier("workshop-timeline")
            HStack {
                Button("Start") { studio.seek(0) }
                Spacer()
                Button("Hold pose") { studio.seek(1.4) }
                Spacer()
                Button("End") { studio.seek(4.8) }
            }
            .font(KFont.sans(11, .medium))
        }
        .font(KFont.sans(12, .semibold))
        .foregroundColor(KColor.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(KColor.panel)
    }

    private var actionControls: some View {
        HStack(spacing: 12) {
            Picker("Pose", selection: $studio.action) {
                ForEach(CoachWorkshopAction.allCases) { action in Text(action.rawValue).tag(action) }
            }
            .accessibilityIdentifier("workshop-pose")
            Picker("Face", selection: $studio.expression) {
                ForEach(CoachExpression.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
        .pickerStyle(.menu)
    }

    private var proportions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HAND PROPORTIONS").font(KFont.mono(10, .medium)).tracking(1)
            tuningSlider("Hand size", value: $studio.draft.handScale, range: 0.8...3, suffix: "×")
                .accessibilityIdentifier("workshop-hand-size")
            tuningSlider("Hand width", value: $studio.draft.handWidth, range: 0.65...1.6, suffix: "×")
        }
    }

    private var debugControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Joints", isOn: $studio.joints)
                Toggle("Grid", isOn: $studio.grid)
            }
            Text("S shoulder · E elbow · W wrist · orange target")
                .font(KFont.mono(9))
                .foregroundColor(KColor.inkSoft)
            Text(String(format: "Joint gap %.2f px · target offset %.1f px", Double(studio.jointGap), Double(studio.targetOffset)))
                .font(KFont.mono(9))
                .foregroundColor(studio.targetOffset > 1 ? KColor.orangeDeep : KColor.inkSoft)
        }
    }

    private func tuningSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                              suffix: String, decimals: Int = 2) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.*f %@", decimals, value.wrappedValue, suffix))
                    .font(KFont.mono(10))
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if !studio.notice.isEmpty {
                Text(studio.notice)
                    .font(KFont.sans(11, .medium))
                    .foregroundColor(KColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Reset preview") { studio.reset() }
                    .font(KFont.sans(12, .medium))
                Spacer()
                Button { studio.apply() } label: {
                    Text("Apply to coach")
                        .font(KFont.zilla(13, .bold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                }
                .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 6))
                .accessibilityIdentifier("workshop-apply")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(KColor.panel)
    }
}
