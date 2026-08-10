//
//  KochiMC1View.swift
//  KochiApp
//
//  The app's one and only layout, on iPhone and on the Mac — "KŌCHI MC—1,
//  the desk unit".
//
//  The organising idea is instrument modules, not page sections: every module
//  is a fixed, hairline-bordered panel on a strict grid, so height is allocated
//  rather than filled. Coach screen 150, three 49pt goal rows, 96pt tape deck.
//  Only the transcript flexes.
//
//  Two deltas from the design doc, both requested:
//    • the tape deck uses the app's own reel art (`FilmReel`) rather than the
//      doc's CSS reel, and runs *two* reels — supply and take-up;
//    • the coach screen and the tape deck keep the app's liquid-glass overlay.
//

import SwiftUI

// MARK: - Chassis palette
//
// Geometry only. Every colour on this screen now comes from `KColor` — the same
// nonisolated theme mirror `ThemeStore` publishes — so a theme swap
// retints the instrument instead of leaving it a fixed cool-grey slab. The
// literal palette that used to live here is gone; it was the reason BRICKS and
// friends had no effect on the phone.
private enum MC1 {
    /// The module grid: 10pt corner, 6pt of background showing around whatever
    /// the module contains.
    static let moduleRadius: CGFloat = 10
    static let modulePad: CGFloat = 6
    /// Screens and recesses inside a module carry the tighter 5pt corner.
    static let screenRadius: CGFloat = 5

    static let coachHeight: CGFloat = 150
    static let deckHeight: CGFloat = 96
    static let transportHeight: CGFloat = 56
}

// MARK: - Root

struct KochiMC1View: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var llmManager: LLMManager
    /// Observed so a theme switch re-evaluates this body. `KColor` reads a
    /// nonisolated static mirror rather than a published property, so without a
    /// dependency on the store nothing here would know the palette moved.
    @EnvironmentObject var themeStore: ThemeStore
    @StateObject private var videoManager = VideoCoachingManager()

    @State private var showSettings = false
    @State private var lastEvaluatedTranscriptLength = 0
    /// Recording time at which each goal flipped to hit, so a completed row can
    /// wear the timestamp the design shows. The `Goal` model has no timestamp
    /// of its own and this is presentation-only, so it lives here.
    @State private var goalHitAt: [UUID: TimeInterval] = [:]

    private var isLive: Bool { audioManager.isRecording }
    private var goals: [Goal] { Array(goalManager.goals.prefix(3)) }
    private var goalsHit: Int { goals.filter(\.isCompleted).count }

    var body: some View {
        VStack(spacing: 8) {
            topBar
            coachModule
            goalsModule
            transcriptModule
            tapeDeckModule
            transportRow
        }
        .padding(.horizontal, 14)
        // The one deliberate platform difference, and it is window chrome rather
        // than layout: iOS gets the safe area for free, while the desktop window
        // is `.hiddenTitleBar`, so the traffic lights would otherwise sit on top
        // of the wordmark. Everything below this row is identical on both.
        #if os(macOS)
        .padding(.top, 28)
        #else
        .padding(.top, 8)
        #endif
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The active theme's art. The module wrapper paints nothing, so this
        // shows through the whole instrument — only the coach screen, deck
        // plate, transcript recess and goal rows carry a surface of their own.
        .background(ThemeBackground("BackgroundImage"))
        // Rebuild the instrument whenever the theme changes. Every colour on it
        // comes from `KColor`, which reads `ActivePalette` — a plain static, so
        // SwiftUI sees no dependency and would leave each control painted in the
        // old theme until something else happened to invalidate it. That is why
        // `ThemeStore.select` bumps `themeVersion`; this is what consumes it.
        //
        // Deliberately applied here rather than at the app root: the settings
        // panel is where you pick a theme, and re-identifying it would tear the
        // picker down on every tap. It is added by `.overlay` below, so it sits
        // outside this identity and survives the swap.
        .id(themeStore.themeVersion)
        .animation(.easeInOut(duration: 0.3), value: themeStore.themeVersion)
        // Themes declare their own scheme (NOIR is dark); this used to be a
        // hardcoded `.light`, which silently overrode them.
        .preferredColorScheme(themeStore.current.colorScheme)
        .overlay {
            if showSettings {
                SettingsView(isPresented: $showSettings)
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            DispatchQueue.main.async { videoManager.playVideo(label: .idle) }
        }
        .onReceive(audioManager.$transcriptionText) { handleTranscriptUpdate($0) }
        .onChange(of: goalManager.goals) { _, updated in
            stampNewlyHitGoals(updated)
        }
        // AudioManager rolls back its own half of a failed start (file, timers,
        // meeting folder); this unwinds the half the view owns. Without it the
        // coach would stay in meeting mode and an empty session would sit in
        // history for a recording that never captured a thing.
        .onChange(of: audioManager.recordingFailure) { _, failure in
            guard failure != nil else { return }
            videoManager.setMeetingActive(false)
            videoManager.playVideo(label: .idle)
            goalManager.discardCurrentMeeting()
            lastEvaluatedTranscriptLength = 0
            goalHitAt = [:]
        }
        .alert("Recording didn't start",
               isPresented: Binding(get: { audioManager.recordingFailure != nil },
                                    set: { if !$0 { audioManager.recordingFailure = nil } })) {
            Button("OK", role: .cancel) { audioManager.recordingFailure = nil }
        } message: {
            Text(audioManager.recordingFailure ?? "")
        }
    }

    // MARK: Top bar
    //
    // All the state the design stripped off the module labels lives here:
    // where inference runs, how many goals are hit, and whether tape is rolling.

    private var topBar: some View {
        HStack(spacing: 9) {
            // The wordmark art is solid white on transparent, so a theme
            // retints it by multiply.
            ThemeImage("KochiLogo")
                .scaledToFit()
                .frame(height: 26)
                .colorMultiply(KColor.logoTint ?? .white)
                // Themes that bake the wordmark into their own background art
                // hide it here. Only the mark goes — the rest of the row is the
                // only live state on screen, so it always stays.
                .opacity(ActiveChrome.hideBrandRow ? 0 : 1)

            Spacer(minLength: 8)

            // Session state.
            Text(isLive ? "live" : "ready")
                .font(KFont.mono(10))
                .tracking(1.8)
                .foregroundColor(KColor.onBgFaint)
            // No clock here — the meeting clock is the tape counter in the deck
            // window, between the two reels. Removing `.blendMode(.screen)` from
            // the reels is what made it readable again.
            Text("\(goalsHit)/3")
                .font(KFont.mono(10))
                .tracking(1.8)
                .foregroundColor(isLive ? KColor.orange : KColor.onBgFaint)
            RecordLamp(isLive: isLive)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: Coach module
    //
    // A real letterboxed screen with a bezel: fixed at 150pt so the animation
    // reads without the portrait ever ballooning to half the phone. The coach's
    // line sits in the lower third like a subtitle, not in a card of its own.

    private var coachModule: some View {
        Module {
            ZStack(alignment: .bottom) {
                Color.black
                CoachingVideoPlayerView(videoManager: videoManager,
                                        cornerRadius: MC1.screenRadius)
                MC1Scanlines()
                    .allowsHitTesting(false)

                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("COACH")
                        .font(KFont.mono(9))
                        .tracking(1.8)
                        .foregroundColor(KColor.orange)
                    Text(coachLine)
                        .font(KFont.sans(15, .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 26)
                .padding(.bottom, 10)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.88)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .frame(height: MC1.coachHeight)
            .clipShape(RoundedRectangle(cornerRadius: MC1.screenRadius, style: .continuous))
            // Glass on the screen.
            .liquidGlass(MC1.screenRadius, inset: 3)
        }
    }

    // MARK: Goals module
    //
    // Three lamps, not three cards. Before a session the rows are editable
    // fields; once tape is rolling a hit row fills with record-orange and the
    // rows still in play carry a hairline orange outline.

    private var goalsModule: some View {
        Module {
            VStack(spacing: 5) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    MC1GoalRow(goal: goal,
                               index: index,
                               isLive: isLive,
                               hitAt: goalHitAt[goal.id])
                }
            }
        }
    }

    // MARK: Transcript module
    //
    // The only module that flexes. Reads as chat — them left, you right — so
    // speaker changes register without a label on every line.

    private var transcriptModule: some View {
        Module {
            ZStack(alignment: .bottom) {
                transcriptBody
                // Bottom fade, so the newest line runs under the module floor
                // instead of stopping dead against it.
                LinearGradient(colors: [KColor.transcriptRowFill, KColor.transcriptRowFill.opacity(0)],
                               startPoint: .bottom, endPoint: .top)
                    .frame(height: 24)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KColor.transcriptRowFill)
            .clipShape(RoundedRectangle(cornerRadius: MC1.screenRadius, style: .continuous))
        }
        .frame(minHeight: MC1.deckHeight + 2 * MC1.modulePad)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var transcriptBody: some View {
        if audioManager.transcriptionText.isEmpty {
            Text(isLive
                 ? "Listening…"
                 : "Transcription starts on record. Nothing leaves this iPhone.")
                .font(KFont.sans(14))
                .foregroundColor(KColor.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ChatTranscriptView(turns: parseTranscript(audioManager.transcriptionText))
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(10)
                }
                .onChange(of: audioManager.transcriptionText) {
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Tape deck module
    //
    // The instrument, not wallpaper: two reels on the outer thirds, cropped in
    // half by the 96pt module floor, with the counter and VU meter in a
    // recessed window over the centre third. Stopped at standby; turning at
    // different rates while recording — take-up faster than supply, like tape.

    private var tapeDeckModule: some View {
        Module {
            TapeDeckPanel(elapsed: audioManager.recordingTime,
                          level: audioManager.audioLevel,
                          isLive: isLive,
                          height: MC1.deckHeight,
                          cornerRadius: MC1.screenRadius)
        }
    }

    // MARK: Transport
    //
    // Three keys that never move. Slot 1 is the wide primary, slot 2 is always
    // stop, slot 3 is always info, so muscle memory holds across states.

    private var transportRow: some View {
        HStack(spacing: 10) {
            // The design's slot 1 toggles RECORD → PAUSE. This build has no
            // pause in AudioManager, so while tape is rolling the key becomes an
            // inert REC lamp and slot 2 (stop) is the live control — same
            // geometry, no invented behaviour. `.primary` to start, `.light`
            // for the disabled recording lamp, `.goal` for stop and info.
            transportKey(label: isLive ? "● REC" : "● RECORD",
                         variant: isLive ? .light : .primary,
                         wide: true,
                         action: startMeetingAndRecord)
                .disabled(isLive)

            transportKey(label: "■", variant: .goal, wide: false,
                         action: stopRecordingAndEvaluate)
                .disabled(!isLive)

            transportKey(label: "i", variant: .goal, wide: false) {
                showSettings = true
            }
        }
        .frame(height: MC1.transportHeight)
    }

    /// One transport key. `BeveledKeyStyle` owns every colour — face gradient,
    /// text, border, shadow and the disabled treatment — so the transport reads
    /// as the same hardware as every other key in the app, under every theme.
    private func transportKey(label: String, variant: KeyVariant, wide: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(KFont.mono(14, .semibold))
                .tracking(wide ? 2.5 : 0)
                .frame(maxWidth: wide ? .infinity : nil, maxHeight: .infinity)
                .frame(width: wide ? nil : MC1.transportHeight)
        }
        .buttonStyle(BeveledKeyStyle(variant: variant))
    }

    // MARK: - Coach copy

    private var coachLine: String {
        if isLive {
            if videoManager.currentVideoLabel != .goal, !llmManager.coachingResponse.isEmpty {
                return llmManager.coachingResponse
            }
            if !videoManager.coachingText.isEmpty { return videoManager.coachingText }
            return "You're on. Set the tone early."
        }
        if !videoManager.coachingText.isEmpty { return videoManager.coachingText }
        return "Breathe and prepare."
    }

    // MARK: - Session control

    private func startMeetingAndRecord() {
        goalManager.startNewMeeting()
        videoManager.setMeetingActive(true)
        audioManager.transcriptionText = ""
        lastEvaluatedTranscriptLength = 0
        goalHitAt = [:]
        llmManager.resetSession()
        audioManager.startRecording()
        goalManager.attachAudioFolder(audioManager.activeMeetingFolderName)
    }

    private func stopRecordingAndEvaluate() {
        videoManager.setMeetingActive(false)

        Task {
            // Let the trailing partial transcript land before tearing down.
            try? await Task.sleep(nanoseconds: 500_000_000)
            let fullTranscript = await MainActor.run { audioManager.transcriptionText }
            await MainActor.run { audioManager.stopRecording() }

            await MainActor.run {
                if !fullTranscript.isEmpty { goalManager.updateNotes(fullTranscript) }
                goalManager.endCurrentMeeting()
            }

            await MainActor.run {
                audioManager.transcriptionText = ""
                audioManager.recordingTime = 0
                llmManager.coachingResponse = ""
                goalManager.resetGoals()
                lastEvaluatedTranscriptLength = 0
                goalHitAt = [:]
            }
        }
    }

    /// Note the clock reading for any goal that just flipped to hit, so its row
    /// can show when it landed.
    private func stampNewlyHitGoals(_ updated: [Goal]) {
        for goal in updated.prefix(3) where goal.isCompleted && goalHitAt[goal.id] == nil {
            goalHitAt[goal.id] = audioManager.recordingTime
        }
    }

    private func handleTranscriptUpdate(_ newText: String) {
        guard audioManager.isRecording else { return }

        DispatchQueue.main.async {
            goalManager.notes = newText
            if !goalManager.meetingHistory.isEmpty {
                goalManager.meetingHistory[0].notes = newText
                goalManager.saveMeetingHistory()
            }
        }

        // Re-evaluate only after roughly a sentence of new speech.
        let currentLength = newText.count
        guard currentLength - lastEvaluatedTranscriptLength >= 50 else { return }
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastEvaluatedTranscriptLength = currentLength
            return
        }
        lastEvaluatedTranscriptLength = currentLength

        Task {
            do {
                let evaluation = try await llmManager.evaluateFullTranscript(
                    newText, goals: goalManager.goals)

                await MainActor.run {
                    var anyGoalAchieved = false
                    for (goalId, achieved) in evaluation.evaluations {
                        if let index = goalManager.goals.firstIndex(where: { $0.id == goalId }),
                           achieved && !goalManager.goals[index].isCompleted {
                            goalManager.toggleGoalCompletion(goalManager.goals[index])
                            anyGoalAchieved = true
                        }
                    }

                    if anyGoalAchieved {
                        videoManager.playVideo(label: .goal)
                    } else {
                        Task {
                            do {
                                try await llmManager.generateCoachingResponse(
                                    for: newText, goals: goalManager.goals)
                                videoManager.playForCoaching(response: llmManager.coachingResponse)
                            } catch {
                                videoManager.playForGoalProgress(goals: goalManager.goals,
                                                                 evaluation: evaluation)
                            }
                        }
                    }
                }
            } catch {
                print("❌ Goal evaluation failed: \(error)")
            }
        }
    }
}

// MARK: - Module chrome

/// One instrument module: hairline border, 10pt corner, and 6pt of chassis
/// showing around its contents. Every panel on the unit is one of these.
/// Spacing only. No panel sits behind a module — sections rest straight on the
/// theme's `BackgroundImage`, and each control carries its own themed fill, so
/// the module chrome never paints an opaque slab over the theme art. Everything
/// that still needs a surface (the coach screen, the deck plate, the transcript
/// recess, the goal rows) supplies its own.
private struct Module<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.padding(MC1.modulePad)
    }
}

// MARK: - Record lamp

private struct RecordLamp: View {
    let isLive: Bool
    @State private var dim = false

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isLive ? KColor.orange : KColor.onBgFaint)
                .frame(width: 7, height: 7)
                .opacity(isLive && dim ? 0.25 : 1)
            Text(isLive ? "REC" : "STANDBY")
                .font(KFont.mono(10))
                .tracking(1.8)
                .foregroundColor(isLive ? KColor.orange : KColor.onBgFaint)
        }
        .onChange(of: isLive) { _, live in
            if live {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    dim = true
                }
            } else {
                withAnimation(.linear(duration: 0.1)) { dim = false }
            }
        }
    }
}

// MARK: - Scanlines

/// Faint CRT scanlines over the coach screen.
private struct MC1Scanlines: View {
    var body: some View {
        Canvas { ctx, size in
            let line = Path(CGRect(x: 0, y: 0, width: size.width, height: 1))
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(line.applying(CGAffineTransform(translationX: 0, y: y)),
                         with: .color(.black.opacity(0.16)))
                y += 3
            }
        }
        .blendMode(.multiply)
    }
}

// MARK: - Goal row

private struct MC1GoalRow: View {
    let goal: Goal
    let index: Int
    let isLive: Bool
    let hitAt: TimeInterval?
    @EnvironmentObject var goalManager: GoalManager

    /// A goal only reads as "hit" once a session is underway — before that
    /// you're choosing goals, not achieving them.
    private var done: Bool { goal.isCompleted && isLive }
    /// Rows still in play during a session carry the hairline orange outline.
    private var inPlay: Bool { isLive && !goal.isCompleted }

    var body: some View {
        let row = HStack(spacing: 12) {
            // The indicator lamp: a clear box with a themed stroke at rest,
            // solid white with an orangeDeep tick once hit.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(done ? Color.white : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(done ? Color.white : KColor.goalUnmetInk, lineWidth: 2))
                .frame(width: 16, height: 16)
                .overlay {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(KColor.orangeDeep)
                    }
                }

            if isLive {
                Text(goal.text.isEmpty ? "—" : goal.text)
                    .font(KFont.sans(16.5, .semibold))
                    .foregroundColor(done ? .white : KColor.goalUnmetInk)
                    .lineLimit(1)
            } else {
                TextField("Type a goal…", text: Binding(
                    get: { goal.text },
                    set: { goalManager.updateGoalSlot(at: index, text: $0) }
                ))
                .textFieldStyle(.plain)
                .font(KFont.sans(16.5, .semibold))
                .foregroundColor(KColor.goalUnmetInk)
            }

            Spacer(minLength: 6)

            if done, let hitAt {
                Text(deckTime(hitAt))
                    .font(KFont.mono(10))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 49)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

        // Once a session is running, tapping a row marks the goal hit (or
        // un-hit) by hand, in case the coach missed it in conversation.
        if isLive {
            Button(action: { goalManager.toggleGoalCompletion(goal) }) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if done {
            shape
                .fill(LinearGradient(colors: [KColor.goalDoneHi, KColor.goalDoneLo],
                                     startPoint: .top, endPoint: .bottom))
                // The 2pt lip that gives every lit key on the unit its depth.
                .overlay(alignment: .bottom) {
                    Rectangle().fill(KColor.orangeDeep).frame(height: 2)
                }
        } else if ActiveGoal.restBlur {
            // Frosted glass: blur the theme art behind the row, then the
            // translucent rest tint, then the border.
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(KColor.goalUnmetFill))
                .overlay(shape.strokeBorder(inPlay ? KColor.orange : KColor.goalRestBorder,
                                            lineWidth: inPlay ? 1.5 : 1))
        } else {
            shape
                .fill(KColor.goalUnmetFill)
                .overlay(shape.strokeBorder(inPlay ? KColor.orange : KColor.goalRestBorder,
                                            lineWidth: inPlay ? 1.5 : 1))
        }
    }
}

// MARK: - Preview

#Preview("MC—1 · standby") {
    KochiMC1View()
        .environmentObject(AudioManager())
        .environmentObject(GoalManager())
        .environmentObject(LLMManager())
        .environmentObject(ThemeStore.shared)
        .frame(width: 393, height: 852)
}
