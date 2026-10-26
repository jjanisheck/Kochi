import SwiftUI

/// Three states of the companion, mirroring the design prototype.
enum MeetingPhase { case pre, live, ended }

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var llmManager: LLMManager
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var videoManager = VideoCoachingManager()
    @State private var showSettings = CommandLine.arguments.contains("--character-workshop")
    @State private var evaluationTimer: Timer?
    /// Length (in characters) of the transcript at the last goal evaluation.
    @State private var lastEvaluatedTranscriptLength = 0

    @State private var analysisTask: Task<Void, Never>?
    @State private var coachingSessionID = UUID()
    @State private var recentReactions: [String] = []
    @State private var isEndingMeeting = false

    private var phase: MeetingPhase {
        audioManager.isRecording ? .live : .pre
    }

    private var goalsHit: Int { goalManager.goals.prefix(3).filter { $0.isCompleted }.count }

    var body: some View {
        VStack(spacing: 0) {
            MeetingPanelsLayout(preferredPanelHeight: 200) {
                // Hidden (not removed) so the row still reserves its height and
                // the layout below doesn't shift up.
                BrandRow(phase: phase)
                    .opacity(ActiveChrome.hideBrandRow ? 0 : 1)
                CoachHero(videoManager: videoManager, captionText: coachLine)
                    .layoutValue(key: MeetingMediaPanelKey.self, value: true)
                goalsSection
                transcriptHeader
                LiveTranscriptPanel(
                    phase: phase,
                    transcript: audioManager.transcriptionText,
                    lines: audioManager.transcriptLines,
                    recordingFailure: audioManager.recordingFailure,
                    transcriptionStatus: audioManager.transcriptionStatus
                )
                .layoutValue(key: MeetingMediaPanelKey.self, value: true)
                .layoutValue(key: MeetingPanelGapKey.self, value: 7)
                TapeDeckPanel(elapsed: audioManager.recordingTime,
                              level: audioManager.audioLevel,
                              isLive: audioManager.isRecording,
                              height: 96, cornerRadius: 9)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)

            Toolbar(
                phase: phase,
                onStart: { startMeetingAndRecord() },
                onEnd: { stopRecordingAndEvaluate() },
                onInfo: { showSettings = true }
            )
        }
        // Halftone "window" background — attached as a background so it doesn't
        // inflate the content's intrinsic height (the panel sizes to the layout).
        // The GeometryReader hands the image a *definite* frame (the card's exact
        // size) so scaledToFill always covers edge-to-edge. An indefinite
        // maxWidth/maxHeight:.infinity frame only reliably fills when the image is
        // far taller than the card; a near-square theme image (e.g. BRICKS, whose
        // ratio nearly matches the card) could otherwise under-fill and leak the
        // window's white base out the bottom.
        .background(ThemeBackground("BackgroundImage"))
        // Settings sheet as an overlay so it's clamped to the card's bounds
        // rather than expanding the panel.
        .overlay {
            if showSettings {
                SettingsView(isPresented: $showSettings)
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            DispatchQueue.main.async { videoManager.setMeetingActive(audioManager.isRecording) }
        }
        .onDisappear {
            analysisTask?.cancel()
            analysisTask = nil
            coachingSessionID = UUID()
        }
        .onChange(of: audioManager.isRecording) { _, active in
            videoManager.setMeetingActive(active && !isEndingMeeting)
            if !active {
                cancelLiveAnalysis()
                if !isEndingMeeting, audioManager.recordingFailure != nil {
                    isEndingMeeting = true
                    goalManager.updateNotes(audioManager.transcriptionText)
                    goalManager.endCurrentMeeting()
                }
            }
        }
        .onReceive(audioManager.$transcriptionText) { newText in
            handleTranscriptUpdate(newText)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancelLiveAnalysis() }
            if phase == .active { handleTranscriptUpdate(audioManager.transcriptionText) }
        }
    }

    // MARK: - Sections

    private var goalsSection: some View {
        VStack(spacing: 7) {
            SlabLabel("Goals", tint: KColor.onBg) {
                Text(phase == .pre ? "set 3" : "\(goalsHit)/3 hit")
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.onBgFaint)
            }
            ForEach(Array(goalManager.goals.prefix(3).enumerated()), id: \.element.id) { index, goal in
                GoalRow(goal: goal, phase: phase, index: index)
            }
        }
    }

    private var transcriptHeader: some View {
        SlabLabel("Transcript", tint: KColor.onBg) {
            Text(phase == .live ? audioManager.transcriptionStatus.shortLabel : phase == .ended ? "final" : "ready")
                .font(KFont.mono(10))
                .foregroundColor(KColor.onBgFaint)
        }
    }

    /// Caption shown over the coach video. During a live meeting it surfaces the
    /// on-device coach's actual sentence (the canned line only for a goal-hit
    /// celebration); at rest it's the idle clip's ambient line.
    private var coachLine: String {
        if videoManager.usesAvatar { return videoManager.coachingText }
        if phase == .live {
            if videoManager.currentVideoLabel != .goal, !llmManager.coachingResponse.isEmpty {
                return llmManager.coachingResponse
            }
            if !videoManager.coachingText.isEmpty { return videoManager.coachingText }
            return "You're on. Set the tone early."
        }
        if !videoManager.coachingText.isEmpty { return videoManager.coachingText }
        switch phase {
        case .pre:  return "Breathe and prepare."
        case .live: return "You're on. Set the tone early."
        case .ended:
            switch goalsHit {
            case 3: return "Three for three. Textbook."
            case 2: return "Two of three — strong session."
            case 1: return "One down. Next time, two."
            default: return "Tough one — reset and run it back."
            }
        }
    }

    // MARK: - Recording Logic (unchanged behavior)

    private func startMeetingAndRecord() {
        cancelLiveAnalysis()
        isEndingMeeting = false
        recentReactions = []
        goalManager.startNewMeeting()
        // Hold coaching videos for the duration (no idle revert until we stop).
        videoManager.setMeetingActive(true)
        audioManager.transcriptionText = ""
        lastEvaluatedTranscriptLength = 0
        llmManager.resetSession()
        audioManager.startRecording()
        guard audioManager.isRecording else {
            videoManager.setMeetingActive(false)
            goalManager.currentMeeting = nil
            return
        }
        goalManager.attachAudioFolder(audioManager.activeMeetingFolderName)
        print("🎯 Recording started - capturing transcript only")
    }

    private func stopRecordingAndEvaluate() {
        isEndingMeeting = true
        cancelLiveAnalysis()
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        // Meeting over — freeze the coach back on the idle frame.
        videoManager.setMeetingActive(false)

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s to flush trailing transcript

            let fullTranscript = await MainActor.run { audioManager.transcriptionText }
            print("📝 FULL TRANSCRIPT CAPTURED (before stop): \(fullTranscript.count) characters")

            await MainActor.run { audioManager.stopRecording() }

            // Save the finished meeting to history.
            await MainActor.run {
                if !fullTranscript.isEmpty { goalManager.updateNotes(fullTranscript) }
                goalManager.endCurrentMeeting()
            }

            // Reset the panel to a clean START state: clear the live transcript,
            // uncheck goals, drop the coaching line. (handleTranscriptUpdate is
            // gated on isRecording, so clearing here won't touch the saved notes.)
            await MainActor.run {
                audioManager.transcriptionText = ""
                audioManager.transcriptLines = []
                audioManager.recordingTime = 0
                llmManager.coachingResponse = ""
                goalManager.resetGoals()
                lastEvaluatedTranscriptLength = 0
            }
        }
    }

    private func cancelLiveAnalysis() {
        coachingSessionID = UUID()
        analysisTask?.cancel()
        analysisTask = nil
        videoManager.setThinking(false)
    }

    /// One analysis at a time. Debounce partial speech, coalesce incoming text,
    /// and reject results from stopped/replaced sessions before changing UI or goals.
    private func handleTranscriptUpdate(_ newText: String) {
        guard audioManager.isRecording, !isEndingMeeting, scenePhase == .active else { return }
        goalManager.notes = newText
        // The current transcript is checkpointed to its meeting folder. Encoding
        // all prior meetings on every partial blocked the UI and overwrote the
        // previous meeting's notes with the current conversation.
        guard analysisTask == nil,
              newText.count - lastEvaluatedTranscriptLength >= 50 else { return }
        let sessionID = coachingSessionID
        analysisTask = Task { @MainActor in
            defer {
                if sessionID == coachingSessionID {
                    analysisTask = nil
                    videoManager.setThinking(false)
                    // Evaluate text that arrived during the previous model call.
                    if audioManager.isRecording, !isEndingMeeting {
                        handleTranscriptUpdate(audioManager.transcriptionText)
                    }
                }
            }
            do {
                try await Task.sleep(nanoseconds: 900_000_000)
                guard sessionID == coachingSessionID, audioManager.isRecording,
                      !isEndingMeeting, !Task.isCancelled else { return }
                let transcript = audioManager.transcriptionText
                lastEvaluatedTranscriptLength = transcript.count
                videoManager.setThinking(true)
                let evaluation = try await llmManager.evaluateFullTranscript(transcript, goals: goalManager.goals)
                guard sessionID == coachingSessionID, audioManager.isRecording,
                      !isEndingMeeting, !Task.isCancelled else { return }

                var achieved = false
                for (goalID, completed) in evaluation.evaluations where completed {
                    if let goal = goalManager.goals.first(where: { $0.id == goalID }), !goal.isCompleted {
                        goalManager.toggleGoalCompletion(goal)
                        achieved = true
                    }
                }
                if achieved {
                    videoManager.playVideo(label: .goal)
                    recentReactions.append("Verified goal achieved")
                } else {
                    let reaction = try await llmManager.generateCoachReaction(
                        for: transcript, goals: goalManager.goals, recentReactions: recentReactions)
                    guard sessionID == coachingSessionID, audioManager.isRecording,
                          !isEndingMeeting, !Task.isCancelled else { return }
                    llmManager.coachingResponse = reaction.caption
                    llmManager.streamingText = reaction.caption
                    videoManager.applyReaction(reaction)
                    recentReactions.append("\(reaction.intent.rawValue): \(reaction.caption)")
                }
                recentReactions = Array(recentReactions.suffix(3))
            } catch is CancellationError {
                // A stopped or replaced meeting must not receive this result.
            } catch {
                print("Live coaching unavailable: \(error)")
            }
        }
    }

}

/// The coach and transcript divide the remaining height equally after measuring
/// the brand, goals, transcript label, separate reel transport, and their spacing.
private nonisolated struct MeetingMediaPanelKey: LayoutValueKey {
    static let defaultValue = false
}

private nonisolated struct MeetingPanelGapKey: LayoutValueKey {
    static let defaultValue: CGFloat = 12
}

private struct MeetingPanelsLayout: Layout {
    let preferredPanelHeight: CGFloat

    private func fixedHeight(width: CGFloat, subviews: Subviews) -> CGFloat {
        subviews.indices.reduce(CGFloat.zero) { height, index in
            let view = subviews[index]
            let gap = index == 0 ? 0 : view[MeetingPanelGapKey.self]
            let content = view[MeetingMediaPanelKey.self] ? 0
                : view.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            return height + gap + content
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 408
        let fixed = fixedHeight(width: width, subviews: subviews)
        let panels = subviews.filter { $0[MeetingMediaPanelKey.self] }.count
        let idealHeight = fixed + CGFloat(panels) * preferredPanelHeight
        let height = proposal.height.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? idealHeight
        return CGSize(width: width, height: max(fixed, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fixed = fixedHeight(width: bounds.width, subviews: subviews)
        let panels = subviews.filter { $0[MeetingMediaPanelKey.self] }.count
        let panelHeight = max(0, (bounds.height - fixed) / CGFloat(max(1, panels)))
        var y = bounds.minY
        for index in subviews.indices {
            let view = subviews[index]
            if index > 0 { y += view[MeetingPanelGapKey.self] }
            let height = view[MeetingMediaPanelKey.self] ? panelHeight
                : view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height
        }
    }
}

// MARK: - Title bar

// MARK: - Brand row (logo + status)

private struct BrandRow: View {
    let phase: MeetingPhase
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ThemeImage("KochiLogo")
                .scaledToFit()
                .frame(height: 30)
                // The wordmark art is solid white on transparent; a theme can
                // recolor it by multiply (white × tint = tint). nil → .white = no-op.
                .colorMultiply(KColor.logoTint ?? .white)
            Text("MEETING COACH")
                .font(KFont.mono(9.5))
                .tracking(1.5)
                .foregroundColor(KColor.onBgFaint)
            Spacer()
            // READY / REC / ENDED sits on the far right of the logo row.
            HStack(spacing: 6) {
                if phase == .live {
                    Circle()
                        .fill(KColor.orange)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 1.0 : 0.7)
                        .opacity(pulse ? 1 : 0.5)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }
                }
                Text(statusText)
                    .font(KFont.mono(10))
                    .tracking(0.8)
                    .foregroundColor(KColor.onBgFaint)
            }
        }
    }

    private var statusText: String {
        switch phase {
        case .pre:   return "READY"
        case .live:  return "REC"
        case .ended: return "ENDED"
        }
    }
}

// MARK: - Coach hero (video + scanlines + caption)

private struct CoachHero: View {
    @ObservedObject var videoManager: VideoCoachingManager
    let captionText: String

    var body: some View {
        ZStack(alignment: .bottom) {
            // Base fill INSIDE the clip — otherwise its square corners show
            // behind the rounded video.
            Color(red: 91/255, green: 91/255, blue: 87/255)

            // Pass the radius so the AVPlayerLayer clips to the rounded corners
            // (SwiftUI's clipShape can't, which is why the video bled over them).
            CoachingVideoPlayerView(videoManager: videoManager, cornerRadius: 10)

            ScanlineOverlay()
                .allowsHitTesting(false)

            // Caption gradient + text
            HStack(alignment: .bottom, spacing: 9) {
                Text("COACH")
                    .font(KFont.mono(8.5))
                    .tracking(1.4)
                    .foregroundColor(KColor.orange)
                    .padding(.bottom, 2)
                Text(captionText)
                    .font(KFont.zilla(13, .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.top, 28)
            .padding(.bottom, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color(red: 15/255, green: 14/255, blue: 12/255).opacity(0.9)],
                    startPoint: .top, endPoint: .bottom)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // No hard border — the liquid-glass white→gray bevel defines the edge.
        .liquidGlass(10)
    }
}

/// Faint CRT scanlines over the coach video (design `.coach::after`).
private struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            let line = Path(CGRect(x: 0, y: 0, width: size.width, height: 1))
            while y < size.height {
                ctx.fill(line.applying(CGAffineTransform(translationX: 0, y: y)),
                         with: .color(.black.opacity(0.10)))
                y += 3
            }
        }
        .blendMode(.multiply)
        .opacity(0.35)
    }
}

// MARK: - Goal row

private struct GoalRow: View {
    let goal: Goal
    let phase: MeetingPhase
    let index: Int
    @EnvironmentObject var goalManager: GoalManager

    private var editing: Bool { phase == .pre }
    // Only show the "hit" orange styling once a meeting is underway — during
    // setup you're choosing goals, not achieving them.
    private var done: Bool { goal.isCompleted && phase != .pre }

    var body: some View {
        let bar = HStack(spacing: 11) {
            // Checkbox — white box w/ orange check on the orange bar when done.
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(done ? Color.white : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(done ? Color.white : KColor.goalUnmetInk, lineWidth: 2))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(KColor.orangeDeep)
                }
            }

            if editing {
                TextField("Type a goal…", text: Binding(
                    get: { goal.text },
                    set: { goalManager.updateGoalSlot(at: index, text: $0) }
                ))
                .textFieldStyle(.plain)
                .font(KFont.sans(13.5, .semibold))
                .foregroundColor(KColor.goalUnmetInk)
            } else {
                Text(goal.text)
                    .font(KFont.sans(13.5, .semibold))
                    .foregroundColor(done ? .white : KColor.goalUnmetInk)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // A hit goal turns the whole bar orange; an unmet goal stays a
                // plain row — no "in progress" / "missed" tag.
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(goalBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        // Make the WHOLE row a reliable tap target (the trailing Spacer would
        // otherwise leave a dead zone, so a row could feel unclickable).
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: done ? KColor.goalDoneLo.opacity(0.35) : .clear,
                radius: 4, x: 0, y: 2)

        // Manual override: once a meeting is underway, tap a goal to mark it hit
        // (or un-hit) yourself — in case the AI didn't catch it in the
        // conversation. During setup (.pre) the row stays an editable text field.
        if editing {
            bar
        } else {
            Button(action: { goalManager.toggleGoalCompletion(goal) }) { bar }
                .buttonStyle(.plain)
        }
    }

    /// A hit goal becomes a glossy orange key, just like the START button.
    @ViewBuilder private var goalBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if done {
            shape
                .fill(LinearGradient(colors: [KColor.goalDoneHi, KColor.goalDoneLo],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .black.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        } else if ActiveGoal.restBlur {
            // Frosted glass: blur the themed background behind the row, then lay
            // the (translucent) goalRestFill tint over it, then the border.
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(KColor.goalUnmetFill))
                .overlay(shape.strokeBorder(KColor.goalRestBorder, lineWidth: 1))
        } else {
            shape
                .fill(KColor.goalUnmetFill)
                .overlay(shape.strokeBorder(KColor.goalRestBorder, lineWidth: 1))
        }
    }

}

// MARK: - Live transcript

private struct LiveTranscriptPanel: View {
    let phase: MeetingPhase
    let transcript: String
    let lines: [TranscriptLine]
    let recordingFailure: String?
    let transcriptionStatus: LiveTranscriptionStatus
    var body: some View {
        stream
        .padding(.top, 5)
        .frame(maxHeight: .infinity)
        .clipped()
        .background {
            if let fill = KColor.liveTranscriptFill {
                fill
            } else {
                GeometryReader { geometry in
                    ThemeImage("BackgroundPlainImage")
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            LinearGradient(colors: [KColor.deckScrimTop, KColor.deckScrimBottom],
                                           startPoint: .top, endPoint: .bottom)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .liquidGlass(9)
    }

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let recordingFailure {
                        Text(recordingFailure)
                            .font(KFont.zilla(13, .medium))
                            .foregroundStyle(KColor.liveTranscriptInk)
                            .padding(.bottom, 6)
                    }
                    if phase == .live && (transcript.isEmpty || transcriptionStatus.isFailure) {
                        Text(transcriptionStatus.message)
                            .font(KFont.zilla(13, .medium))
                            .foregroundColor(KColor.liveTranscriptInk)
                            .shadow(color: KColor.liveTranscriptShadow, radius: 2, x: 0, y: 1)
                            .padding(transcriptionStatus.isFailure ? 8 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(transcriptionStatus.isFailure
                                ? (KColor.liveTranscriptFill ?? Color.black.opacity(0.8)) : Color.clear)
                    }
                    if !transcript.isEmpty {
                        LiveTranscriptText(lines: lines, isLive: phase == .live)
                            .equatable()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: transcript) {
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

}

/// Subtle dot texture for the recessed deck (design `.panel` background).
private struct DeckDots: View {
    var body: some View {
        Canvas { ctx, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1))
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(dot.applying(CGAffineTransform(translationX: x, y: y)),
                             with: .color(.white.opacity(0.035)))
                    x += 5
                }
                y += 5
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Toolbar (beveled physical keys)

private struct Toolbar: View {
    let phase: MeetingPhase
    let onStart: () -> Void
    let onEnd: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if phase == .live {
                key(icon: "●", title: "recording", variant: .light, action: {})
                    .disabled(true)
            } else {
                key(icon: phase == .ended ? "↺" : "▶",
                    title: phase == .ended ? "new" : "start",
                    variant: .primary, action: onStart)
            }
            key(icon: "■", title: "end", variant: .goal, action: onEnd)
                .disabled(phase != .live)
            key(icon: "ⓘ", title: "info", variant: .goal, action: onInfo)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 12)
        // No deck band — the keys sit on the card background like the logo row.
    }

    private func key(icon: String, title: String, variant: KeyVariant, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(icon).font(.system(size: 12))
                Text(title).font(KFont.zilla(14, .semibold))
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BeveledKeyStyle(variant: variant))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AudioManager())
            .environmentObject(GoalManager())
            .environmentObject(ThemeManager())
            .environmentObject(LLMManager())
            .environmentObject(CloudAnalysisManager())
    }
}
