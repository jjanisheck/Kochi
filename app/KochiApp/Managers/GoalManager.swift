import Foundation
import Combine

class GoalManager: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var notes: String = ""
    @Published var goalPresets: [GoalPreset] = []
    @Published var meetingHistory: [MeetingSession] = []
    @Published var currentMeeting: MeetingSession?

    private let userDefaults = UserDefaults.standard
    private let goalsKey = "savedGoals"
    private let notesKey = "savedNotes"
    private let presetsKey = "goalPresets"
    private let historyKey = "meetingHistory"

    init() {
        // Defer loading to avoid "Publishing changes from within view updates"
        Task { @MainActor [weak self] in
            self?.loadGoals()
            self?.loadNotes()
            self?.loadPresets()
            self?.loadMeetingHistory()
        }
    }
    
    // MARK: - Goal Management
    func loadGoals() {
        if let data = userDefaults.data(forKey: goalsKey),
           let decodedGoals = try? JSONDecoder().decode([Goal].self, from: data) {
            goals = decodedGoals
        } else {
            // Initialize with default goals
            goals = [
                Goal(text: "Practice active listening", isCompleted: false),
                Goal(text: "Speak more clearly", isCompleted: false),
                Goal(text: "Reduce filler words", isCompleted: false)
            ]
            saveGoals()
        }
    }
    
    func saveGoals() {
        if let encoded = try? JSONEncoder().encode(goals) {
            userDefaults.set(encoded, forKey: goalsKey)
        }
    }
    
    func addGoal(_ text: String) {
        let newGoal = Goal(text: text, isCompleted: false)
        goals.append(newGoal)
        saveGoals()
    }
    
    func updateGoal(_ goal: Goal) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
            saveGoals()
        }
    }
    
    func deleteGoal(_ goal: Goal) {
        goals.removeAll { $0.id == goal.id }
        saveGoals()
    }

    func updateGoalSlot(at index: Int, text: String) {
        // Ensure we always have exactly 3 goal slots
        while goals.count < 3 {
            goals.append(Goal(text: "", isCompleted: false))
        }

        // Update the text while preserving completion status
        let wasCompleted = goals[index].isCompleted
        goals[index] = Goal(text: text, isCompleted: wasCompleted)
        saveGoals()
    }

    func toggleGoalCompletion(_ goal: Goal) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let index = self.goals.firstIndex(where: { $0.id == goal.id }) {
                self.goals[index].isCompleted.toggle()
                self.saveGoals()

                // Check if all goals are completed
                if self.goals.allSatisfy({ $0.isCompleted }) {
                    self.celebrateCompletion()
                }
            }
        }
    }
    
    func resetGoals() {
        for index in goals.indices {
            goals[index].isCompleted = false
        }
        saveGoals()
    }

    // MARK: - Meeting Session Management
    func startNewMeeting(withGoals goals: [Goal]? = nil) {
        // Save current session if exists
        if let current = currentMeeting {
            saveMeetingToHistory(current)
        }

        // Create new meeting session
        let newMeeting = MeetingSession(
            id: UUID(),
            startTime: Date(),
            goals: goals ?? self.goals,
            notes: ""
        )

        currentMeeting = newMeeting

        // Set goals for new meeting
        if let newGoals = goals {
            self.goals = newGoals
        } else {
            resetGoals()
        }

        // Clear notes for new session
        notes = ""
        saveNotes()
        saveGoals()
    }

    /// Link the in-progress meeting to its on-disk audio folder so the UI can
    /// share/export the recording later.
    func attachAudioFolder(_ name: String?) {
        guard let name = name else { return }
        currentMeeting?.audioFolderName = name
    }

    func endCurrentMeeting() {
        guard var meeting = currentMeeting else { return }

        meeting.endTime = Date()
        meeting.goals = goals
        meeting.notes = notes

        saveMeetingToHistory(meeting)
        currentMeeting = nil
    }

    private func saveMeetingToHistory(_ meeting: MeetingSession) {
        meetingHistory.insert(meeting, at: 0)

        // Keep only last 50 meetings
        if meetingHistory.count > 50 {
            meetingHistory = Array(meetingHistory.prefix(50))
        }

        saveMeetingHistory()
    }

    func loadMeetingHistory() {
        if let data = userDefaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([MeetingSession].self, from: data) {
            meetingHistory = decoded
        }
    }

    func saveMeetingHistory() {
        if let encoded = try? JSONEncoder().encode(meetingHistory) {
            userDefaults.set(encoded, forKey: historyKey)
        }
    }

    func deleteMeeting(_ meeting: MeetingSession) {
        meetingHistory.removeAll { $0.id == meeting.id }
        saveMeetingHistory()
    }

    /// Replaces the transcript text for a saved meeting (e.g. after a higher-accuracy
    /// on-device re-transcription) and persists the change.
    func updateMeetingNotes(_ meeting: MeetingSession, notes: String) {
        guard let index = meetingHistory.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetingHistory[index].notes = notes
        saveMeetingHistory()
    }

    /// Saves a cloud-LLM analysis onto a meeting in history and persists it.
    func updateMeetingAnalysis(_ meeting: MeetingSession, analysis: MeetingAnalysis, folderName: String? = nil) {
        guard let index = meetingHistory.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetingHistory[index].analysis = analysis
        // Link the on-disk folder if this meeting didn't have one (e.g. legacy
        // meetings whose analysis.md we just created).
        if meetingHistory[index].audioFolderName == nil, let folderName {
            meetingHistory[index].audioFolderName = folderName
        }
        saveMeetingHistory()
    }

    /// Sets (or clears, when nil) a meeting's custom name and persists it.
    func updateMeetingName(_ meeting: MeetingSession, name: String?) {
        guard let index = meetingHistory.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetingHistory[index].name = name
        saveMeetingHistory()
    }

    func loadGoalsFromMeeting(_ meeting: MeetingSession) {
        goals = meeting.goals.map { goal in
            Goal(text: goal.text, isCompleted: false)
        }
        saveGoals()
    }

    // MARK: - Goal Presets
    func loadPresets() {
        if let data = userDefaults.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([GoalPreset].self, from: data) {
            goalPresets = decoded
        } else {
            // Initialize with default presets
            goalPresets = [
                GoalPreset(
                    name: "Team Stand-up",
                    icon: "person.3.fill",
                    goals: [
                        "Keep updates under 2 minutes",
                        "Focus on blockers and progress",
                        "Ask clarifying questions"
                    ]
                ),
                GoalPreset(
                    name: "Client Meeting",
                    icon: "briefcase.fill",
                    goals: [
                        "Practice active listening",
                        "Speak clearly and confidently",
                        "Reduce filler words"
                    ]
                ),
                GoalPreset(
                    name: "1-on-1",
                    icon: "person.2.fill",
                    goals: [
                        "Be an active listener",
                        "Ask thoughtful questions",
                        "Provide constructive feedback"
                    ]
                ),
                GoalPreset(
                    name: "Presentation",
                    icon: "chart.bar.fill",
                    goals: [
                        "Maintain steady pace",
                        "Use clear examples",
                        "Engage the audience"
                    ]
                )
            ]
            savePresets()
        }
    }

    func savePresets() {
        if let encoded = try? JSONEncoder().encode(goalPresets) {
            userDefaults.set(encoded, forKey: presetsKey)
        }
    }

    func addPreset(name: String, icon: String, goals: [String]) {
        let preset = GoalPreset(name: name, icon: icon, goals: goals)
        goalPresets.append(preset)
        savePresets()
    }

    func deletePreset(_ preset: GoalPreset) {
        goalPresets.removeAll { $0.id == preset.id }
        savePresets()
    }

    func loadGoalsFromPreset(_ preset: GoalPreset) {
        goals = preset.goals.map { Goal(text: $0, isCompleted: false) }
        saveGoals()
    }

    func saveCurrentAsPreset(name: String, icon: String) {
        let goalTexts = goals.map { $0.text }
        addPreset(name: name, icon: icon, goals: goalTexts)
    }
    
    // MARK: - Notes Management
    func loadNotes() {
        notes = userDefaults.string(forKey: notesKey) ?? ""
    }
    
    func saveNotes() {
        userDefaults.set(notes, forKey: notesKey)
    }
    
    func updateNotes(_ newNotes: String) {
        notes = newNotes
        saveNotes()
    }
    
    func appendToNotes(_ text: String) {
        if !notes.isEmpty {
            notes += "\n\n"
        }
        notes += text
        saveNotes()
    }
    
    // MARK: - Helpers
    private func celebrateCompletion() {
        // Trigger celebration animation or notification
        NotificationCenter.default.post(name: .goalsCompleted, object: nil)
    }
}

// MARK: - Goal Model
struct Goal: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isCompleted: Bool

    init(text: String, isCompleted: Bool) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
    }
}

// MARK: - Goal Preset Model
struct GoalPreset: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let icon: String
    let goals: [String]

    init(name: String, icon: String, goals: [String]) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.goals = goals
    }
}

// MARK: - Meeting Session Model
struct MeetingSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var goals: [Goal]
    var notes: String
    /// Name of the MeetingFileManager folder holding this meeting's audio.m4a
    /// (optional — nil for meetings recorded before audio linking existed).
    var audioFolderName: String? = nil
    /// Cloud-LLM analysis (summary, action items, effectiveness), if the user has
    /// run "Run AI Analysis" on this meeting. Optional → old saved meetings decode
    /// unchanged.
    var analysis: MeetingAnalysis? = nil
    /// Custom or AI-suggested meeting name. Optional → old meetings decode unchanged.
    var name: String? = nil

    var duration: TimeInterval {
        if let end = endTime {
            return end.timeIntervalSince(startTime)
        }
        return Date().timeIntervalSince(startTime)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let goalsCompleted = Notification.Name("goalsCompleted")
    static let newMeetingStarted = Notification.Name("newMeetingStarted")
}