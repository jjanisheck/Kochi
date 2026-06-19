import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @State private var selectedTab = 0
    @State private var showGoals = false
    /// The transcript being viewed. Non-nil shows the detail as a full-panel
    /// overlay (covering the header + tab bar) rather than a nav push beneath them.
    @State private var selectedMeeting: MeetingSession?
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var cloudAnalysisManager: CloudAnalysisManager

    var body: some View {
        VStack(spacing: 0) {
                    // Header — MEETING DETAILS + beveled Done key
                    HStack {
                        Text("MEETING DETAILS")
                            .font(KFont.mono(11))
                            .tracking(1.6)
                            .foregroundColor(KColor.inkSoft)
                        Spacer()
                        Button(action: { isPresented = false }) {
                            Text("Done")
                                .font(KFont.zilla(12.5, .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle()) // whole key is the tap target
                        }
                        .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // Snug under the macOS traffic lights / clear the iOS status bar.
                    .padding(.top, 8)
                    .background(
                        LinearGradient(colors: [Color(red: 243/255, green: 242/255, blue: 239/255),
                                                Color(red: 233/255, green: 232/255, blue: 227/255)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(Rectangle().fill(KColor.line).frame(height: 1), alignment: .bottom)

                    // Beveled tab bar — 5 tabs
                    HStack(spacing: 5) {
                        TabButton(title: "Transcripts", icon: "doc.text.fill", isSelected: selectedTab == 0) {
                            withAnimation { selectedTab = 0 }
                        }
                        TabButton(title: "Search", icon: "magnifyingglass", isSelected: selectedTab == 1) {
                            withAnimation { selectedTab = 1 }
                        }
                        TabButton(title: "Goals", icon: "target", isSelected: selectedTab == 2) {
                            withAnimation { selectedTab = 2 }
                        }
                        TabButton(title: "AI", icon: "sparkles", isSelected: selectedTab == 3) {
                            withAnimation { selectedTab = 3 }
                        }
                        TabButton(title: "About", icon: "info.circle", isSelected: selectedTab == 4) {
                            withAnimation { selectedTab = 4 }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [Color(red: 220/255, green: 218/255, blue: 212/255),
                                                Color(red: 205/255, green: 203/255, blue: 196/255)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(Rectangle().fill(Color(red: 184/255, green: 182/255, blue: 175/255)).frame(height: 1), alignment: .bottom)

                    // Tab Content. Transcript → detail is presented as a
                    // full-panel overlay (see below), so no NavigationStack /
                    // push is needed — that avoids the duplicated header + tab
                    // bar that sat above the pushed detail.
                    Group {
                        switch selectedTab {
                        case 0:
                            TranscriptsTab(onSelect: { selectedMeeting = $0 })
                        case 1:
                            SearchTab(onSelect: { selectedMeeting = $0 })
                        case 2:
                            GoalsTab(showGoals: $showGoals)
                        case 3:
                            AITab()
                        case 4:
                            AboutTab()
                        default:
                            TranscriptsTab(onSelect: { selectedMeeting = $0 })
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        // Fill the card top-aligned (no centering ZStack — that was clipping the
        // header), with the halftone as a non-inflating background.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            ThemeImage("BackgroundImage")
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showGoals) {
            GoalsManagementView(isPresented: $showGoals)
        }
        // Transcript detail covers the whole panel (header + tab bar included),
        // so its own Back key is the only chrome at the top.
        .overlay {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting, onBack: { selectedMeeting = nil })
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.22), value: selectedMeeting?.id)
    }
}

// MARK: - Custom Tab Button
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title.uppercased())
                    .font(KFont.mono(8.5))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .foregroundColor(isSelected ? KColor.orangeDeep : KColor.muted)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [.white, Color(red: 241/255, green: 239/255, blue: 233/255)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                            .shadow(color: .black.opacity(0.14), radius: 2, x: 0, y: 1)
                    }
                }
            )
            // Make the ENTIRE button frame tappable, not just the icon/text
            // glyphs (transparent areas aren't hit-tested by default).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transcripts Tab
struct TranscriptsTab: View {
    /// Open a transcript's detail (presented as a full-panel overlay upstream).
    let onSelect: (MeetingSession) -> Void
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TabHeader(
                    icon: "doc.text.fill",
                    title: "Transcripts",
                    subtitle: "Your recorded meetings and their transcripts."
                )

                if goalManager.meetingHistory.isEmpty {
                    Text("No transcripts yet. Start a recording to see history here.")
                        .font(.body)
                        .foregroundColor(.black.opacity(0.6))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(KColor.paper.opacity(0.92))
                        .cornerRadius(10)
                        .padding(.horizontal)
                } else {
                    ForEach(goalManager.meetingHistory) { meeting in
                        TranscriptRow(meeting: meeting, onTap: {
                            onSelect(meeting)
                        }, onDelete: {
                            goalManager.deleteMeeting(meeting)
                        })
                    }
                }
            }
            .padding(.bottom)
        }
    }
}

// MARK: - Transcript Row with Delete
struct TranscriptRow: View {
    let meeting: MeetingSession
    let onTap: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showDeleteAlert = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    // Show the meeting name when set, with the timestamp kept visible but small.
                    if let name = meeting.name, !name.isEmpty {
                        Text(name)
                            .font(KFont.zilla(14, .bold))
                            .foregroundColor(KColor.ink)
                        Text(formatDate(meeting.startTime))
                            .font(KFont.mono(9))
                            .foregroundColor(KColor.muted)
                    } else {
                        Text(formatDate(meeting.startTime))
                            .font(KFont.zilla(14, .bold))
                            .foregroundColor(KColor.ink)
                    }

                    let completedCount = meeting.goals.filter { $0.isCompleted }.count
                    Text("\(completedCount)/\(meeting.goals.count) goals")
                        .font(KFont.mono(10))
                        .tracking(0.5)
                        .foregroundColor(completedCount == meeting.goals.count && completedCount > 0 ? KColor.good : KColor.orangeDeep)

                    if !meeting.notes.isEmpty {
                        Text(meeting.notes)
                            .font(KFont.mono(11))
                            .foregroundColor(KColor.muted)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                // Delete button
                Button(action: { showDeleteAlert = true }) {
                    Image(systemName: "trash.fill")
                        .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
                        .font(.system(size: 18))
                        .padding(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(KColor.paper.opacity(0.92))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .alert("Delete Transcript", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this transcript? This cannot be undone.")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Search Tab
/// One transcript that matches the query, with a context snippet + hit count.
private struct SearchHit: Identifiable {
    let id: UUID
    let meeting: MeetingSession
    let count: Int
    let snippet: AttributedString
}

/// Full-text search across every saved transcript. Results open the same
/// MeetingDetailView overlay as the Transcripts tab.
struct SearchTab: View {
    /// Open a transcript's detail (presented as a full-panel overlay upstream).
    let onSelect: (MeetingSession) -> Void
    @EnvironmentObject var goalManager: GoalManager
    @State private var query = ""

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hits: [SearchHit] {
        let q = trimmed
        guard q.count >= 2 else { return [] }
        return goalManager.meetingHistory.compactMap { meeting in
            let count = Self.occurrences(of: q, in: meeting.notes)
            guard count > 0 else { return nil }
            return SearchHit(id: meeting.id, meeting: meeting, count: count,
                             snippet: Self.snippet(of: q, in: meeting.notes))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TabHeader(
                    icon: "magnifyingglass",
                    title: "Search",
                    subtitle: "Find a word or phrase across your transcripts."
                )

                searchField

                if trimmed.count < 2 {
                    hintCard("Type at least two characters to search your saved transcripts.")
                } else if hits.isEmpty {
                    hintCard("No transcripts mention “\(trimmed)”.")
                } else {
                    HStack {
                        Text("\(hits.count) transcript\(hits.count == 1 ? "" : "s")")
                            .font(KFont.mono(10))
                            .tracking(0.5)
                            .foregroundColor(KColor.muted)
                        Spacer()
                    }
                    .padding(.horizontal)

                    ForEach(hits) { hit in
                        SearchResultRow(hit: hit, onTap: { onSelect(hit.meeting) })
                    }
                }
            }
            .padding(.bottom)
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(KColor.muted)
            TextField("Search transcripts…", text: $query)
                .textFieldStyle(.plain)
                .font(KFont.sans(13.5, .medium))
                .foregroundColor(KColor.ink)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(KColor.muted2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(KColor.paper)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(KColor.line, lineWidth: 1))
        )
        .padding(.horizontal)
    }

    private func hintCard(_ text: String) -> some View {
        Text(text)
            .font(KFont.mono(11))
            .foregroundColor(KColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(KColor.paper.opacity(0.92))
            .cornerRadius(10)
            .padding(.horizontal)
    }

    // MARK: Search helpers

    /// Case-insensitive occurrence count.
    static func occurrences(of query: String, in text: String) -> Int {
        guard !query.isEmpty else { return 0 }
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let r = text.range(of: query, options: .caseInsensitive, range: range) {
            count += 1
            range = r.upperBound..<text.endIndex
        }
        return count
    }

    /// A single-line context window around the first match, with every match
    /// highlighted in orange.
    static func snippet(of query: String, in text: String) -> AttributedString {
        let flat = text.replacingOccurrences(of: "\n", with: "  ")
        guard let first = flat.range(of: query, options: .caseInsensitive) else {
            return AttributedString(String(flat.prefix(120)))
        }
        let lead = flat.index(first.lowerBound, offsetBy: -40, limitedBy: flat.startIndex) ?? flat.startIndex
        let tail = flat.index(first.upperBound, offsetBy: 70, limitedBy: flat.endIndex) ?? flat.endIndex
        var window = String(flat[lead..<tail])
        if lead > flat.startIndex { window = "…" + window }
        if tail < flat.endIndex { window += "…" }

        var attr = AttributedString(window)
        attr.font = KFont.mono(11)
        attr.foregroundColor = KColor.inkSoft
        var search = attr.startIndex..<attr.endIndex
        while let m = attr[search].range(of: query, options: .caseInsensitive) {
            attr[m].foregroundColor = KColor.orangeDeep
            attr[m].font = KFont.mono(11, .bold)
            search = m.upperBound..<attr.endIndex
        }
        return attr
    }
}

// MARK: - Search Result Row
private struct SearchResultRow: View {
    let hit: SearchHit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(formatDate(hit.meeting.startTime))
                        .font(KFont.zilla(14, .bold))
                        .foregroundColor(KColor.ink)
                    Spacer()
                    Text("\(hit.count)×")
                        .font(KFont.mono(10, .medium))
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(KColor.orange))
                }
                Text(hit.snippet)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KColor.paper.opacity(0.92))
            .cornerRadius(10)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Goals Tab
struct GoalsTab: View {
    @Binding var showGoals: Bool
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var llmManager: LLMManager
    @StateObject private var dictation = GoalDictationService()
    @State private var goalTexts: [String] = ["", "", ""]
    @State private var isParsing = false
    @State private var goalSpeechError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TabHeader(
                    icon: "target",
                    title: "Goals",
                    subtitle: "Set up to three goals to track during meetings."
                )

                // Running tally across all saved meetings
                HStack(spacing: 9) {
                    StatTile(value: goalManager.meetingHistory.count, label: "meetings")
                    StatTile(value: goalManager.meetingHistory.reduce(0) { $0 + $1.goals.filter { $0.isCompleted }.count }, label: "goals hit")
                    StatTile(value: goalManager.meetingHistory.filter { !$0.goals.isEmpty && $0.goals.allSatisfy { $0.isCompleted } }.count, label: "perfect")
                }
                .padding(.horizontal)

                speakGoalsButton

                // Three fixed goal slots
                ForEach(0..<3, id: \.self) { index in
                    GoalSlotRow(
                        index: index,
                        text: bindingForGoal(at: index),
                        isCompleted: goalManager.goals.count > index ? goalManager.goals[index].isCompleted : false
                    )
                }
            }
            .padding(.bottom)
        }
        .onAppear {
            loadGoalTexts()
        }
    }

    private func bindingForGoal(at index: Int) -> Binding<String> {
        Binding(
            get: {
                if index < goalManager.goals.count {
                    return goalManager.goals[index].text
                }
                return ""
            },
            set: { newValue in
                goalManager.updateGoalSlot(at: index, text: newValue)
            }
        )
    }

    private func loadGoalTexts() {
        for i in 0..<3 {
            if i < goalManager.goals.count {
                goalTexts[i] = goalManager.goals[i].text
            }
        }
    }

    // MARK: - Speak new goals

    @ViewBuilder
    private var speakGoalsButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleDictation) {
                HStack(spacing: 8) {
                    if isParsing {
                        ProgressView().controlSize(.small)
                        Text("PARSING\u{2026}")
                    } else if dictation.isListening {
                        Image(systemName: "stop.fill")
                        Text("LISTENING\u{2026} TAP TO STOP")
                    } else {
                        Image(systemName: "mic.fill")
                        Text("SPEAK NEW GOALS")
                    }
                }
                .font(KFont.zilla(12.5, .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(BeveledKeyStyle(variant: dictation.isListening ? .light : .primary, radius: 8))
            .disabled(isParsing)

            if dictation.isListening, !dictation.transcript.isEmpty {
                Text(dictation.transcript)
                    .font(KFont.sans(12, .regular))
                    .foregroundColor(KColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let goalSpeechError {
                Text(goalSpeechError)
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.orangeDeep)
            }
        }
        .padding(.horizontal)
    }

    private func toggleDictation() {
        goalSpeechError = nil
        if dictation.isListening {
            Task {
                let spoken = await dictation.stop()
                guard !spoken.isEmpty else {
                    goalSpeechError = "Didn\u{2019}t catch any speech. Try again."
                    return
                }
                isParsing = true
                let parsed = (try? await llmManager.parseGoalsFromSpeech(spoken)) ?? []
                isParsing = false
                guard !parsed.isEmpty else {
                    goalSpeechError = "Couldn\u{2019}t turn that into goals. Try again."
                    return
                }
                goalManager.setGoals(parsed)
                loadGoalTexts()
            }
        } else {
            dictation.start()
            if !dictation.isListening {
                goalSpeechError = "Couldn\u{2019}t start the microphone. Check Microphone & Speech permissions in System Settings."
            }
        }
    }
}

// MARK: - Stat tile (Goals tab)
struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(KFont.zilla(25, .bold))
                .foregroundColor(KColor.orange)
            Text(label.uppercased())
                .font(KFont.mono(8.5))
                .tracking(0.6)
                .foregroundColor(KColor.muted)
        }
        .frame(maxWidth: .infinity)
        .kCard(radius: 9, padding: 11)
    }
}

// MARK: - Goal Slot Row
struct GoalSlotRow: View {
    let index: Int
    @Binding var text: String
    let isCompleted: Bool
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    private func commit() {
        text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? KColor.good : KColor.muted2)

            if isEditing {
                TextField("Goal \(index + 1)", text: $editText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(KFont.sans(14, .semibold))
                    .foregroundColor(KColor.ink)
                    .tint(KColor.orange)              // visible blinking caret
                    .focused($fieldFocused)
                    .onSubmit { commit() }          // Enter saves
                    .onAppear { fieldFocused = true } // focus immediately on Edit
                    // Recessed white input box with a neutral border (no colored
                    // ring) — the blinking cursor signals it's editable.
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(KColor.line, lineWidth: 1))
                    )

                Button(action: commit) {
                    Text("Save")
                        .font(KFont.zilla(12.5, .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
            } else {
                Text(text.isEmpty ? "Goal \(index + 1)" : text)
                    .font(KFont.sans(14, .semibold))
                    .foregroundColor(text.isEmpty ? KColor.muted2 : KColor.ink)

                Spacer()

                Button(action: {
                    editText = text
                    isEditing = true
                }) {
                    Text("Edit")
                        .font(KFont.zilla(12.5, .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(BeveledKeyStyle(variant: .light, radius: 7))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(KColor.paper.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(KColor.line, lineWidth: 1))
        )
        .padding(.horizontal)
    }
}

// MARK: - About Tab
struct AboutTab: View {
    @AppStorage("kochiTheme") private var theme: KochiTheme = .default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TabHeader(
                    icon: "info.circle.fill",
                    title: "About",
                    subtitle: "How Kōchi works and handles your data."
                )

                themesCard

                // Main description
                VStack(alignment: .leading, spacing: 16) {
                    Text("Kochi transcribes your meetings entirely on-device with Apple Speech, and evaluates your goals and coaching using Apple's on-device Foundation model. Your audio never leaves your device.")
                        .font(.body)
                        .foregroundColor(.black.opacity(0.8))

                    Divider()
                        .background(.black.opacity(0.3))

                    Text("How It Works")
                        .font(.headline)
                        .foregroundColor(.black)

                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyFeatureRow(icon: "waveform", text: "Audio transcribed on-device with Apple Speech")
                        PrivacyFeatureRow(icon: "brain", text: "Goal evaluation runs on Apple's on-device model")
                        PrivacyFeatureRow(icon: "folder", text: "Transcripts stored locally on your device")
                    }

                    Divider()
                        .background(.black.opacity(0.3))

                    Text("Private by Design")
                        .font(.headline)
                        .foregroundColor(.black)

                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyFeatureRow(icon: "wifi.slash", text: "Works without an internet connection")
                        PrivacyFeatureRow(icon: "key.slash", text: "No API keys or accounts required")
                        PrivacyFeatureRow(icon: "person.2.wave.2", text: "Dual-channel speaker separation (Me / Them)")
                    }

                    Divider()
                        .background(.black.opacity(0.3))

                    Text("Privacy Note")
                        .font(.headline)
                        .foregroundColor(.black)

                    Text("K\u{014D}chi runs entirely on your device by default \u{2014} audio, transcription, and coaching all happen locally with no account or API key. The optional AI Analysis feature (Settings \u{2192} AI) is the one exception: if you add your own API key and tap Run AI Analysis on a meeting, that meeting\u{2019}s transcript is sent to your chosen provider. Your audio, transcripts, and goals stay stored locally on your device.")
                        .font(.body)
                        .foregroundColor(.black.opacity(0.8))
                }
                .padding()
                .background(KColor.paper.opacity(0.92))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
    }

    // Theme picker — currently just DEFAULT; more looks plug in via KochiTheme.
    private var themesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("Themes") { EmptyView() }
            Picker("", selection: $theme) {
                ForEach(KochiTheme.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(KFont.sans(13, .medium))
            .tint(KColor.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
        .padding(.horizontal)
    }
}

// MARK: - Tab Header (shared section header — matches Settings styling)
struct TabHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(KColor.orange)
                Text(title)
                    .font(KFont.zilla(22, .bold))
                    .foregroundColor(KColor.ink)
            }
            Text(subtitle)
                .font(KFont.mono(11))
                .foregroundColor(KColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 18)
    }
}

// MARK: - Privacy Feature Row
struct PrivacyFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.black)
        }
    }
}

// MARK: - Meeting History Compact Row
struct MeetingHistoryCompactRow: View {
    let meeting: MeetingSession
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(meeting.startTime))
                    .font(.headline)
                    .foregroundColor(Color.black)
                Spacer()
                let completedCount = meeting.goals.filter { $0.isCompleted }.count
                Text("\(completedCount)/\(meeting.goals.count) goals")
                    .font(.caption)
                    .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.black.opacity(0.3))
            }

            if !meeting.notes.isEmpty {
                Text(meeting.notes)
                    .font(.caption)
                    .foregroundColor(Color.black.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding()
        .background(KColor.paper.opacity(0.92))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Meeting Detail View
struct MeetingDetailView: View {
    let meeting: MeetingSession
    /// Called when the Back key is tapped. The detail is presented as a
    /// full-panel overlay (not a nav push), so dismissal is an explicit closure.
    var onBack: () -> Void = {}
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var cloudAnalysisManager: CloudAnalysisManager
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    /// The analysis to display — seeded from the saved meeting, updated on re-run.
    @State private var analysis: MeetingAnalysis?
    /// Whether to feed the meeting's goals into the analysis prompt (checkbox).
    @State private var includeGoals = true
    @State private var showDeleteAlert = false
    @State private var didCopy = false
    @State private var showAudioShare = false
    /// Presents the system share sheet with the meeting's text (same content as Copy).
    @State private var showTextShare = false
    /// Transcript is collapsed by default so the analysis is visible first.
    @State private var transcriptExpanded = false
    /// Display name (custom or AI-suggested); seeded from the meeting on appear.
    @State private var meetingName: String?
    @State private var isEditingName = false
    @State private var nameDraft = ""

    private let fileManager = MeetingFileManager()
    /// The saved mixed mic + system-audio recording for this meeting, if present.
    private var audioURL: URL? {
        meeting.audioFolderName.flatMap { fileManager.audioURL(forFolderName: $0) }
    }
    /// The saved (speaker-separated) transcript for this meeting.
    private var displayedNotes: String { meeting.notes }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Back bar — the borderless panel has no native nav bar, so
            // this explicit Back key stays put while the detail scrolls.
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                            .font(KFont.zilla(12.5, .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle()) // whole key is the tap target
                }
                .buttonStyle(BeveledKeyStyle(variant: .light, radius: 7))
                Spacer()
                // Copy the whole meeting (session, goals, transcript) to the
                // clipboard. Lives top-right, opposite the Back key.
                if hasCopyableContent {
                    // Share the meeting text (name, goals, transcript, analysis) to
                    // Notes / Mail / Messages / etc. — never the audio file.
                    Button(action: { showTextShare = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .bold))
                            Text("Share")
                                .font(KFont.zilla(12.5, .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BeveledKeyStyle(variant: .light, radius: 7))

                    Button(action: copyMeeting) {
                        HStack(spacing: 4) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .bold))
                            Text(didCopy ? "Copied" : "Copy")
                                .font(KFont.zilla(12.5, .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
                }
            }
            .padding(.horizontal, 14)
            // Snug under the macOS traffic lights / clear the iOS status bar.
            .padding(.top, 2)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sessionCard
                    goalsCard
                    transcriptCard
                    if cloudAnalysisManager.isConfigured || analysis != nil {
                        analysisCard
                    }
                    if let audioURL = audioURL { audioCard(audioURL) }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            // Uniform pixel-grid camo so the top bar matches the rest of the page
            // (the gradient BackgroundImage read plainer up top).
            ThemeImage("BackgroundPlainImage")
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showAudioShare) {
            ShareSheet(items: [audioURL].compactMap { $0 })
        }
        .sheet(isPresented: $showTextShare) {
            ShareSheet(items: [meetingPlainText()])
        }
        .onAppear { analysis = meeting.analysis; meetingName = meeting.name }
    }

    // MARK: - Sections (device-card design system)

    /// When + how long, as a slab-labelled white card.
    private var hasName: Bool { !(meetingName ?? "").isEmpty }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SlabLabel("Session") {
                if let end = meeting.endTime {
                    Text(formatDuration(end.timeIntervalSince(meeting.startTime)))
                        .font(KFont.mono(10, .medium))
                        .foregroundColor(KColor.inkSoft)
                }
            }

            if isEditingName {
                HStack(spacing: 8) {
                    TextField("Meeting name", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(KFont.zilla(16.5, .bold))
                        .foregroundColor(KColor.ink)
                        .tint(KColor.orange)
                        .onSubmit { saveName() }
                    Button(action: saveName) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(KColor.good)
                    }
                    .buttonStyle(.plain)
                    Button(action: { isEditingName = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(KColor.muted)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hasName ? (meetingName ?? "") : formatDate(meeting.startTime))
                        .font(KFont.zilla(16.5, .bold))
                        .foregroundColor(KColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // Discrete inline rename control.
                    Button(action: beginEditName) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(KColor.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Rename meeting")
                }
            }

            // Once a name is shown (or being edited), keep the timestamp visible but small.
            if hasName || isEditingName {
                Text(formatDate(meeting.startTime))
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 12, padding: 13)
    }

    private func beginEditName() {
        nameDraft = meetingName ?? ""
        isEditingName = true
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingName = trimmed.isEmpty ? nil : trimmed
        goalManager.updateMeetingName(meeting, name: meetingName)
        isEditingName = false
    }

    /// Every goal, with hit goals rendered as the app's glossy orange key.
    private var goalsCard: some View {
        let completed = meeting.goals.filter { $0.isCompleted }
        return VStack(alignment: .leading, spacing: 8) {
            SlabLabel("Goals") {
                Text("\(completed.count)/\(meeting.goals.count) hit")
                    .font(KFont.mono(10))
                    .foregroundColor(completed.count == meeting.goals.count && !completed.isEmpty
                                     ? KColor.good : KColor.muted)
            }
            if meeting.goals.isEmpty {
                emptyLine("No goals were set")
            } else {
                ForEach(meeting.goals) { goal in
                    MeetingGoalRow(goal: goal)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 12, padding: 13)
    }

    /// The Me/Them conversation, kept as chat bubbles inside a white card.
    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tappable header — toggles the transcript open/closed.
            Button(action: { withAnimation(.easeOut(duration: 0.2)) { transcriptExpanded.toggle() } }) {
                SlabLabel("Transcript") {
                    Image(systemName: transcriptExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(KColor.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if transcriptExpanded {
                if displayedNotes.isEmpty {
                    emptyLine("No transcript available")
                } else {
                    ChatTranscriptView(turns: parseTranscript(displayedNotes), onDark: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 12, padding: 13)
    }

    private func audioCard(_ audioURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("Audio")
            HStack(spacing: 9) {
                AudioActionButton(icon: "folder", label: "Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                }
                AudioActionButton(icon: "square.and.arrow.up", label: "Share") {
                    showAudioShare = true
                }
                AudioActionButton(icon: "square.and.arrow.down", label: "Export") {
                    exportAudio(audioURL)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 12, padding: 13)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(KFont.mono(11))
            .foregroundColor(KColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Copy the recording to a user-chosen location via the sandbox-safe save panel.
    private func exportAudio(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(meeting.audioFolderName ?? "meeting")-audio.m4a"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }

    /// True when there's anything worth copying (goals and/or a transcript).
    private var hasCopyableContent: Bool {
        !meeting.goals.isEmpty || !displayedNotes.isEmpty || analysis != nil
    }

    /// Builds a plain-text export of the meeting — session, goals, transcript —
    /// matching the on-screen sections.
    private func meetingPlainText() -> String {
        var lines: [String] = []

        if hasName {
            lines.append(meetingName ?? "")
            lines.append("")
        }
        lines.append("SESSION")
        lines.append(formatDate(meeting.startTime))
        if let end = meeting.endTime {
            lines.append("Duration: \(formatDuration(end.timeIntervalSince(meeting.startTime)))")
        }

        lines.append("")
        lines.append("GOALS")
        if meeting.goals.isEmpty {
            lines.append("(none)")
        } else {
            for goal in meeting.goals {
                lines.append("\(goal.isCompleted ? "✓" : "✗") \(goal.text)")
            }
        }

        lines.append("")
        lines.append("TRANSCRIPT")
        lines.append(displayedNotes.isEmpty ? "(no transcript)" : displayedNotes)

        if let analysis {
            lines.append("")
            lines.append(analysis.plainText())
        }

        return lines.joined(separator: "\n")
    }

    /// Copies the full meeting to the clipboard and briefly flips the key to a
    /// "Copied" confirmation.
    private func copyMeeting() {
        let text = meetingPlainText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    // MARK: - AI analysis

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("AI Analysis") {
                if let analysis {
                    Text(analysis.provider)
                        .font(KFont.mono(9))
                        .foregroundColor(KColor.muted)
                }
            }

            if let analysis {
                analysisContent(analysis)
            } else {
                Text("Summarize this meeting into tasks and a professional-effectiveness review.")
                    .font(KFont.sans(12, .regular))
                    .foregroundColor(KColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let analysisError {
                Text(analysisError)
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.orangeDeep)
            }

            if cloudAnalysisManager.isConfigured {
                HStack(spacing: 12) {
                    Toggle("Include goals", isOn: $includeGoals)
                        .toggleStyle(.checkbox)
                        .font(KFont.sans(12, .medium))
                        .foregroundColor(KColor.inkSoft)
                        .tint(KColor.orange)
                        .disabled(isAnalyzing)
                    Spacer()
                    Button(action: runAnalysis) {
                        HStack(spacing: 6) {
                            if isAnalyzing { ProgressView().controlSize(.small) }
                            Text(isAnalyzing ? "Analyzing\u{2026}"
                                 : (analysis == nil ? "Run AI Analysis" : "Re-run"))
                                .font(KFont.zilla(12.5, .bold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
                    .disabled(isAnalyzing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 12, padding: 13)
    }

    @ViewBuilder
    private func analysisContent(_ a: MeetingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(a.summary)
                .font(KFont.sans(13, .medium))
                .foregroundColor(KColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !a.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ACTION ITEMS")
                        .font(KFont.mono(9, .medium)).tracking(1.0).foregroundColor(KColor.muted)
                    ForEach(Array(a.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\u{2022}").foregroundColor(KColor.orange)
                            Text(item.owner.map { "\(item.task) \u{2014} \($0)" } ?? item.task)
                                .font(KFont.sans(12.5, .regular))
                                .foregroundColor(KColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("EFFECTIVENESS")
                    .font(KFont.mono(9, .medium)).tracking(1.0).foregroundColor(KColor.muted)
                gradeRow("Communication", a.effectiveness.communication)
                gradeRow("Focus", a.effectiveness.focus)
                gradeRow("Professionalism", a.effectiveness.professionalism)
            }

            Text(a.overallCoaching)
                .font(KFont.sans(12.5, .regular))
                .foregroundColor(KColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let usage = a.usage {
                let cost = usage.estimatedCostUSD.map { String(format: "~$%.4f", $0) } ?? "cost n/a"
                Text("\(usage.inputTokens) in \u{00B7} \(usage.outputTokens) out \u{00B7} \(cost)")
                    .font(KFont.mono(9))
                    .foregroundColor(KColor.muted)
            }
        }
    }

    private func gradeRow(_ title: String, _ d: Dimension) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(d.grade)
                .font(KFont.zilla(14, .bold))
                .foregroundColor(KColor.orangeDeep)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KFont.sans(12, .semibold))
                    .foregroundColor(KColor.ink)
                Text(d.note)
                    .font(KFont.sans(11.5, .regular))
                    .foregroundColor(KColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runAnalysis() {
        isAnalyzing = true
        analysisError = nil
        Task {
            do {
                let result = try await cloudAnalysisManager.analyze(meeting: meeting, includeGoals: includeGoals)
                let folder = fileManager.writeAnalysisMarkdown(result.markdown(),
                                                               folderName: meeting.audioFolderName,
                                                               startTime: meeting.startTime)
                goalManager.updateMeetingAnalysis(meeting, analysis: result, folderName: folder)
                analysis = result
                // Auto-apply the AI's suggested name if the user hasn't named it yet.
                if !hasName,
                   let suggested = result.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !suggested.isEmpty {
                    meetingName = suggested
                    goalManager.updateMeetingName(meeting, name: suggested)
                }
            } catch let e as CloudLLMError {
                analysisError = message(for: e)
            } catch {
                analysisError = "Analysis failed. Please try again."
            }
            isAnalyzing = false
        }
    }

    private func message(for error: CloudLLMError) -> String {
        switch error {
        case .missingKey:   return "No API key set. Add one in Settings \u{2192} AI."
        case .auth:         return "The API key was rejected. Check it in Settings \u{2192} AI."
        case .rateLimited:  return "Rate limited by the provider. Try again shortly."
        case .refusal:      return "The model declined to analyze this transcript."
        case .truncated:    return "The analysis was too long to finish. Try a shorter meeting and re-run."
        case .badResponse:  return "The provider returned an unexpected response."
        case .http(let s):  return "Request failed (HTTP \(s))."
        case .network:      return "Network error. Check your connection and try again."
        }
    }
}

// MARK: - Meeting Goal Row
/// A goal as it reads in the recap: a hit goal becomes the app's glossy orange
/// key (white check, white text); an unmet goal stays a plain white row.
/// Mirrors ContentView's GoalRow.
private struct MeetingGoalRow: View {
    let goal: Goal
    private var done: Bool { goal.isCompleted }

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(done ? Color.white : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(done ? Color.white : KColor.line, lineWidth: 2))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(KColor.orangeDeep)
                }
            }

            Text(goal.text)
                .font(KFont.sans(13.5, .semibold))
                .foregroundColor(done ? .white : KColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 42)
        .background(goalBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: done ? Color(red: 140/255, green: 55/255, blue: 0).opacity(0.30) : .clear,
                radius: 4, x: 0, y: 2)
    }

    @ViewBuilder private var goalBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if done {
            shape
                .fill(LinearGradient(colors: [Color(red: 255/255, green: 122/255, blue: 54/255),
                                              Color(red: 236/255, green: 80/255, blue: 0)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05), .black.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        } else {
            shape
                .fill(KColor.paper)
                .overlay(shape.strokeBorder(KColor.line, lineWidth: 1))
        }
    }
}

// MARK: - Settings Tab (transcription & model settings)
/// Standalone tab hosting the transcription/model settings, styled to match the
/// other tabs (black text / white cards over the shared light background image).
struct SettingsTab: View {
    var body: some View {
        TranscriptionSettingsView()
    }
}

// MARK: - Share Sheet
struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Present the macOS sharing picker once the view is in the window hierarchy.
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Audio Action Button
struct AudioActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(KColor.orange)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recording Row
struct RecordingRow: View {
    let recording: RecordingMetadata
    let onTap: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDate(recording.date))
                        .font(.headline)
                        .foregroundColor(Color.black)

                    Text("Duration: \(formatDuration(recording.duration))")
                        .font(.caption)
                        .foregroundColor(Color.black.opacity(0.7))
                    
                    if !recording.transcription.isEmpty {
                        Text(recording.transcription)
                            .font(.caption)
                            .foregroundColor(Color.black.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
            }
            .padding()
            .background(KColor.paper.opacity(0.92))
            .cornerRadius(10)
            .padding(.horizontal)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}


// MARK: - About AI Tab
struct AboutAITab: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "apple.logo")
                            .font(.title)
                            .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))

                        Text("Apple Foundation Models")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color.black)
                    }

                    Text("100% On-Device AI • No Downloads Required")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KColor.paper.opacity(0.92))
                .cornerRadius(10)
                .padding(.horizontal)

                // What's Included
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Capabilities")
                        .font(.headline)
                        .foregroundColor(Color.black)
                        .padding(.horizontal)

                    AICapabilityCard(
                        icon: "mic.fill",
                        title: "Speech Recognition",
                        description: "Apple's SFSpeechRecognizer for transcription",
                        framework: "Speech.framework"
                    )

                    AICapabilityCard(
                        icon: "brain",
                        title: "Semantic AI",
                        description: "NLEmbedding for goal matching",
                        framework: "NaturalLanguage.framework"
                    )

                    AICapabilityCard(
                        icon: "chart.bar",
                        title: "Sentiment Analysis",
                        description: "Real-time emotion detection",
                        framework: "NaturalLanguage.framework"
                    )

                    AICapabilityCard(
                        icon: "sparkles",
                        title: "Topic Extraction",
                        description: "Automatic key phrase identification",
                        framework: "NaturalLanguage.framework"
                    )
                }

                // Privacy Benefits
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy & Security")
                        .font(.headline)
                        .foregroundColor(Color.black)
                        .padding(.horizontal)

                    PrivacyBenefitRow(
                        icon: "iphone",
                        text: "100% on-device processing"
                    )

                    PrivacyBenefitRow(
                        icon: "wifi.slash",
                        text: "No internet connection required"
                    )

                    PrivacyBenefitRow(
                        icon: "lock",
                        text: "Zero data sent to servers"
                    )

                    PrivacyBenefitRow(
                        icon: "shield.checkmark",
                        text: "Apple's privacy standards"
                    )
                }
                .padding()
                .background(KColor.paper.opacity(0.92))
                .cornerRadius(10)
                .padding(.horizontal)

                // System Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Requirements")
                        .font(.headline)
                        .foregroundColor(Color.black)

                    HStack {
                        Text("macOS Version")
                            .foregroundColor(Color.black.opacity(0.7))
                        Spacer()
                        Text("27.0+")
                            .fontWeight(.medium)
                            .foregroundColor(Color.black)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Storage Required")
                            .foregroundColor(Color.black.opacity(0.7))
                        Spacer()
                        Text("0 MB (built-in)")
                            .fontWeight(.medium)
                            .foregroundColor(Color.black)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Status")
                            .foregroundColor(Color.black.opacity(0.7))
                        Spacer()
                        Text("Active & Ready")
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(KColor.paper.opacity(0.92))
                .cornerRadius(10)
                .padding(.horizontal)

                // Footer
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                    Text("No downloads, no setup, always ready!")
                        .font(.caption)
                        .foregroundColor(Color.black.opacity(0.6))
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical)
        }
    }
}

// MARK: - AI Capability Card
struct AICapabilityCard: View {
    let icon: String
    let title: String
    let description: String
    let framework: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color.black)

                Text(description)
                    .font(.caption)
                    .foregroundColor(Color.black.opacity(0.6))

                Text(framework)
                    .font(.caption2)
                    .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0).opacity(0.7))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(KColor.paper.opacity(0.92))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

// MARK: - Privacy Benefit Row
struct PrivacyBenefitRow: View {
    let icon: String
    let text: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 249/255, green: 81/255, blue: 0))
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundColor(Color.black)

            Spacer()
        }
    }
}

// MARK: - AI / API Key tab

/// Manages the optional cloud-LLM API key that unlocks post-meeting analysis.
struct AITab: View {
    @EnvironmentObject var cloudAnalysisManager: CloudAnalysisManager
    @State private var keyInput = ""
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TabHeader(
                    icon: "sparkles",
                    title: "AI",
                    subtitle: "Bring your own key for optional cloud analysis."
                )

                VStack(alignment: .leading, spacing: 15) {
                    providerCard
                    keyCard
                    disclosureCard
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("Provider") { EmptyView() }
            Picker("", selection: Binding(
                get: { cloudAnalysisManager.provider },
                set: { cloudAnalysisManager.selectProvider($0); keyInput = ""; saveError = nil }
            )) {
                ForEach(CloudProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 9) {
                Text("MODEL")
                    .font(KFont.mono(9, .medium))
                    .tracking(1.0)
                    .foregroundColor(KColor.muted)
                TextField(cloudAnalysisManager.provider.defaultModel, text: Binding(
                    get: { cloudAnalysisManager.model },
                    set: { cloudAnalysisManager.setModel($0) }
                ))
                .textFieldStyle(.plain)
                .font(KFont.sans(13, .medium))
                .foregroundColor(KColor.ink)
                .tint(KColor.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KColor.paper)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(KColor.line, lineWidth: 1))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("API Key") {
                Text(cloudAnalysisManager.hasKey ? "✓ Key saved" : "No key set")
                    .font(KFont.mono(10))
                    .foregroundColor(cloudAnalysisManager.hasKey ? KColor.good : KColor.muted)
            }
            SecureField("Paste your \(cloudAnalysisManager.provider.displayName) API key",
                        text: $keyInput)
                .textFieldStyle(.plain)
                .font(KFont.sans(13, .medium))
                .foregroundColor(KColor.ink)
                .tint(KColor.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KColor.paper)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(KColor.line, lineWidth: 1))
                )

            if let saveError {
                Text(saveError)
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.orangeDeep)
            }

            HStack(spacing: 8) {
                Button(action: saveKey) {
                    Text("Save")
                        .font(KFont.zilla(12.5, .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if cloudAnalysisManager.hasKey {
                    Button(action: { cloudAnalysisManager.removeKey(); keyInput = "" }) {
                        Text("Remove key")
                            .font(KFont.zilla(12.5, .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BeveledKeyStyle(variant: .light, radius: 7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SlabLabel("Privacy") { EmptyView() }
            Text("Kōchi is on-device by default. With a personal API key, the meeting "
                 + "transcript you choose to analyze is sent to your selected provider "
                 + "(Anthropic or OpenAI). This is the only feature that leaves your device, "
                 + "and it only runs when you tap \u{201C}Run AI Analysis\u{201D} on a meeting.")
                .font(KFont.sans(12, .regular))
                .foregroundColor(KColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
    }

    private func saveKey() {
        do {
            try cloudAnalysisManager.saveKey(keyInput)
            keyInput = ""
            saveError = nil
        } catch {
            saveError = "Could not save the key to the Keychain."
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(isPresented: .constant(true))
            .environmentObject(AudioManager())
            .environmentObject(ThemeManager())
            .environmentObject(GoalManager())
            .environmentObject(CloudAnalysisManager())
    }
}