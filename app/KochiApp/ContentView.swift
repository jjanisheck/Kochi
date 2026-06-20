import SwiftUI

/// Three states of the companion, mirroring the design prototype.
enum MeetingPhase { case pre, live, ended }

struct ContentView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var llmManager: LLMManager
    @StateObject private var videoManager = VideoCoachingManager()
    @State private var showSettings = false
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "HasCompletedOnboarding")
    @State private var evaluationTimer: Timer?
    /// Length (in characters) of the transcript at the last goal evaluation.
    @State private var lastEvaluatedTranscriptLength = 0

    private var phase: MeetingPhase {
        audioManager.isRecording ? .live : .pre
    }

    private var goalsHit: Int { goalManager.goals.prefix(3).filter { $0.isCompleted }.count }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                BrandRow(phase: phase)
                CoachHero(videoManager: videoManager, captionText: coachLine)
                    .frame(height: 166)
                goalsSection
                transcriptSection
            }
            .padding(.horizontal, 14)
            // Snug the logo row up under the macOS traffic lights.
            .padding(.top, 8)
            .padding(.bottom, 13)

            Toolbar(
                phase: phase,
                onStart: { startMeetingAndRecord() },
                onEnd: { stopRecordingAndEvaluate() },
                onInfo: { showSettings = true }
            )
        }
        // Halftone "window" background — attached as a background so it doesn't
        // inflate the content's intrinsic height (the panel sizes to the layout).
        .background(
            ThemeImage("BackgroundImage")
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
        )
        // Settings sheet as an overlay so it's clamped to the card's bounds
        // rather than expanding the panel.
        .overlay {
            if showSettings {
                SettingsView(isPresented: $showSettings)
                    .transition(.move(edge: .bottom))
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            DispatchQueue.main.async { videoManager.playVideo(label: .idle) }
        }
        .fullScreenCoverCompat(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .onReceive(audioManager.$transcriptionText) { newText in
            handleTranscriptUpdate(newText)
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

    private var transcriptSection: some View {
        VStack(spacing: 7) {
            SlabLabel("Transcript", tint: KColor.onBg) {
                HStack(spacing: 8) {
                    Text(phase == .live ? "live" : phase == .ended ? "final" : "ready")
                        .font(KFont.mono(10))
                        .foregroundColor(KColor.onBgFaint)
                    Text(fmtTime(audioManager.recordingTime))
                        .font(KFont.mono(11, .medium))
                        .foregroundColor(KColor.onBg)
                }
            }
            TapeDeck(
                phase: phase,
                transcript: audioManager.transcriptionText,
                isRecording: audioManager.isRecording,
                audioLevel: audioManager.audioLevel
            )
        }
    }

    /// Caption shown over the coach video. During a live meeting it surfaces the
    /// on-device coach's actual sentence (the canned line only for a goal-hit
    /// celebration); at rest it's the idle clip's ambient line.
    private var coachLine: String {
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
        goalManager.startNewMeeting()
        // Hold coaching videos for the duration (no idle revert until we stop).
        videoManager.setMeetingActive(true)
        audioManager.transcriptionText = ""
        lastEvaluatedTranscriptLength = 0
        llmManager.resetSession()
        audioManager.startRecording()
        goalManager.attachAudioFolder(audioManager.activeMeetingFolderName)
        print("🎯 Recording started - capturing transcript only")
    }

    private func stopRecordingAndEvaluate() {
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
                audioManager.recordingTime = 0
                llmManager.coachingResponse = ""
                goalManager.resetGoals()
                lastEvaluatedTranscriptLength = 0
            }
        }
    }

    /// Live transcript → notes + history sync, plus growth-throttled on-device
    /// goal evaluation and coach-video selection (behavior preserved from before).
    private func handleTranscriptUpdate(_ newText: String) {
        // Only sync notes / evaluate while actually recording. Once a meeting
        // ends and we clear the live transcript, this must not run — otherwise
        // it would overwrite the just-saved meeting's notes with empty text.
        guard audioManager.isRecording else { return }

        DispatchQueue.main.async {
            goalManager.notes = newText
            if !goalManager.meetingHistory.isEmpty {
                goalManager.meetingHistory[0].notes = newText
                goalManager.saveMeetingHistory()
            }
        }

        let currentLength = newText.count
        let evaluationGrowthThreshold = 50  // re-check goals after ~a sentence of speech
        guard currentLength - lastEvaluatedTranscriptLength >= evaluationGrowthThreshold else { return }

        let fullTranscript = newText
        print("🎯 TRANSCRIPT GREW to \(currentLength) chars: Evaluating FULL transcript against goals")

        guard !fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastEvaluatedTranscriptLength = currentLength
            return
        }
        lastEvaluatedTranscriptLength = currentLength

        Task {
            do {
                let evaluation = try await llmManager.evaluateFullTranscript(
                    fullTranscript, goals: goalManager.goals)
                print("📊 Evaluation complete: \(evaluation.evaluations.count) goals evaluated")

                await MainActor.run {
                    var anyGoalAchieved = false
                    for (goalId, achieved) in evaluation.evaluations {
                        if let goalIndex = goalManager.goals.firstIndex(where: { $0.id == goalId }),
                           achieved && !goalManager.goals[goalIndex].isCompleted {
                            let goal = goalManager.goals[goalIndex]
                            print("✅ GOAL ACHIEVED: \(goal.text)")
                            goalManager.toggleGoalCompletion(goal)
                            anyGoalAchieved = true
                        }
                    }

                    if anyGoalAchieved {
                        videoManager.playVideo(label: .goal)
                    } else {
                        Task {
                            do {
                                try await llmManager.generateCoachingResponse(
                                    for: fullTranscript, goals: goalManager.goals)
                                videoManager.playForCoaching(response: llmManager.coachingResponse)
                            } catch {
                                videoManager.playForGoalProgress(goals: goalManager.goals, evaluation: evaluation)
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

private func fmtTime(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%02d:%02d", s / 60, s % 60)
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
                        .strokeBorder(done ? Color.white : KColor.goalRestInk, lineWidth: 2))
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
                .foregroundColor(KColor.goalRestInk)
            } else {
                Text(goal.text)
                    .font(KFont.sans(13.5, .semibold))
                    .foregroundColor(done ? .white : KColor.goalRestInk)
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
        .shadow(color: done ? Color(red: 140/255, green: 55/255, blue: 0).opacity(0.35) : .clear,
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
                .fill(LinearGradient(colors: [KColor.buttonHi, KColor.buttonLo],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .black.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        } else {
            shape
                .fill(KColor.goalRestFill)
                .overlay(shape.strokeBorder(KColor.line, lineWidth: 1))
        }
    }

}

// MARK: - Tape-deck transcript

private struct TapeDeck: View {
    let phase: MeetingPhase
    let transcript: String
    let isRecording: Bool
    let audioLevel: Float
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // 5px top inset so scrolling text clips a little below the deck's
            // top edge instead of butting right against it.
            stream
                .padding(.top, 5)
                .frame(height: 124)
                .clipped()

            tape
        }
        // Spinning reel spans the WHOLE deck (behind the meter too) so it shows
        // through the gaps between the volume bars.
        .background(
            GeometryReader { geo in
                ThemeImage("FilmReel")
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.width)
                    .grayscale(ActiveDeck.reelGrayscale)
                    .brightness(ActiveDeck.reelBrightness) // dim so transcript text stays readable (themeable)
                    .rotationEffect(.degrees(rotation))
                    .position(x: geo.size.width / 2, y: geo.size.height)
            }
            .allowsHitTesting(false)
        )
        .background(
            // Dark camo deck with a top-to-bottom gradient for depth.
            ThemeImage("BackgroundPlainImage")
                .scaledToFill()
                .overlay(
                    LinearGradient(colors: [KColor.deckScrimTop, KColor.deckScrimBottom],
                                   startPoint: .top, endPoint: .bottom)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // No hard border — the liquid-glass white→gray bevel defines the edge.
        .liquidGlass(9)
        .onChange(of: isRecording) { _, rec in
            if rec { startSpin() } else { stopSpin() }
        }
        .onAppear { if isRecording { startSpin() } }
    }

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if transcript.isEmpty {
                        // No pre-meeting blurb — the big START button is self-explanatory.
                        // While recording, a quiet "Listening…" stands in until words arrive.
                        if phase == .live {
                            Text("Listening…")
                                .font(KFont.mono(11))
                                .foregroundColor(Color(red: 226/255, green: 224/255, blue: 216/255))
                                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        }
                    } else {
                        // Me (mic) left, Them (system) right — chat-style.
                        // Light text reads crisply on the darker camo deck.
                        ChatTranscriptView(turns: parseTranscript(transcript), onDark: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .onChange(of: transcript) {
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private var tape: some View {
        // Just the volume rectangles — no deck band behind them.
        HStack(spacing: 4) {
            ForEach(0..<14, id: \.self) { i in
                let filled = tapeFilled
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < filled
                          ? AnyShapeStyle(LinearGradient(colors: [KColor.buttonHi, KColor.buttonLo],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.black.opacity(0.18)))
                    .frame(height: 9)
                    .shadow(color: (i == filled - 1 && phase == .live) ? KColor.buttonHi.opacity(0.85) : .clear,
                            radius: 4)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }

    private var tapeFilled: Int {
        switch phase {
        case .pre:   return 0
        case .live:  return max(1, min(14, Int(audioLevel * 14)))
        case .ended: return 14
        }
    }

    private func startSpin() {
        rotation = 0
        withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) { rotation = 360 }
    }
    private func stopSpin() {
        withAnimation(.linear(duration: 0.2)) { rotation = 0 }
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
            key(icon: "■", title: "end", variant: .primary, action: onEnd)
                .disabled(phase != .live)
            key(icon: "ⓘ", title: "info", variant: .light, action: onInfo)
        }
        .padding(.horizontal, 11)
        .padding(.top, 9)
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
