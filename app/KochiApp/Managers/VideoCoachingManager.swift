import Foundation
import AVFoundation
import AVKit
import SwiftUI
import Combine

// MARK: - Video Label
// Maps to desktop app's video categories
enum VideoLabel: String, CaseIterable {
    case idle = "idle"
    case goal = "goal"
    case timing = "timing"
    case pause = "pause"
    case listen = "listen"
    case prompt = "prompt"
    case mute = "mute"
    case focus = "focus"
    case check = "check"
    case steady = "steady"
    case wrap = "wrap"

    var description: String {
        switch self {
        case .idle: return "Idle breathing animation"
        case .goal: return "Goal achievement celebration"
        case .timing: return "Time management reminder"
        case .pause: return "Take a pause"
        case .listen: return "Active listening prompt"
        case .prompt: return "Ask questions"
        case .mute: return "Reduce talking"
        case .focus: return "Focus and concentration"
        case .check: return "Check progress"
        case .steady: return "Maintain good pace"
        case .wrap: return "Wrap up the meeting"
        }
    }

    /// Short coaching text to display with this video
    var coachingText: [String] {
        switch self {
        case .idle:
            return ["Ready when you are.", "Take your time.", "Breathe and prepare."]
        case .goal:
            return ["Goal achieved! Keep it up!", "Excellent work!", "That's progress!", "You're crushing it!"]
        case .timing:
            return ["Watch your pace.", "Time check - stay on track.", "Keep moving forward."]
        case .pause:
            return ["Take a breath.", "Pause and reflect.", "A moment of clarity."]
        case .listen:
            return ["Listen actively.", "Focus on what's being said.", "Hear them out.", "Stay present."]
        case .prompt:
            return ["Speak clearly.", "Make your point.", "Be direct.", "Your voice matters."]
        case .mute:
            return ["Less is more.", "Cut the filler.", "Be concise.", "Quality over quantity."]
        case .focus:
            return ["Stay focused.", "Eyes on the goal.", "You've got this.", "Concentrate."]
        case .check:
            return ["How are you doing?", "Check your progress.", "Review your goals.", "Stay on target."]
        case .steady:
            return ["Keep this pace.", "You're doing well.", "Steady progress.", "Almost there!"]
        case .wrap:
            return ["Great session!", "Wrapping up strong.", "Mission accomplished.", "Well done!"]
        }
    }

    /// Get a random coaching text for variety
    var randomCoachingText: String {
        coachingText.randomElement() ?? ""
    }
}

// MARK: - Video Coaching Manager
// Manages video playback for Army General coaching feedback
class VideoCoachingManager: ObservableObject {
    @Published var currentVideoLabel: VideoLabel = .idle
    @Published var isPlaying: Bool = false
    @Published var player: AVPlayer?
    @Published var videoTheme: String = "general" // "general" or "zen"
    @Published var coachingText: String = "" // Short text displayed with video

    private var currentPlayerItem: AVPlayerItem?
    private var idleTimer: Timer?
    private let IDLE_TIMEOUT: TimeInterval = 5.0
    /// True while a meeting is being recorded. During a meeting the coaching
    /// video reflects how the conversation is going and should NOT auto-revert
    /// to the idle clip between reads; idle is only for when no meeting is active.
    private var isMeetingActive = false
    private var playerObserver: Any?
    private var statusObserver: AnyCancellable?

    // Video cache - don't cache to allow variations
    private var videoCache: [VideoLabel: AVPlayerItem] = [:]

    init() {
        setupNotifications()

        // Start idle video on main thread after a short delay
        // to ensure the view is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.preloadVideos()
        }
    }

    deinit {
        cleanupObservers()
        idleTimer?.invalidate()
        statusObserver?.cancel()
    }

    // MARK: - Setup
    private func setupNotifications() {
        // Listen for goal completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGoalCompleted),
            name: .goalsCompleted,
            object: nil
        )

        // Listen for recording stopped
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingStopped),
            name: .recordingStopped,
            object: nil
        )
    }

    private func preloadVideos() {
        print("🎬 VideoCoachingManager: Preloading videos...")
        print("📂 Bundle path: \(Bundle.main.bundlePath)")
        print("📂 Resource path: \(Bundle.main.resourcePath ?? "none")")

        // List ALL files in bundle root
        if let resourcePath = Bundle.main.resourcePath {
            print("📂 Listing bundle contents:")
            if let allFiles = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                let videoFiles = allFiles.filter { $0.hasSuffix(".mp4") }
                print("📹 Found \(videoFiles.count) .mp4 files in bundle root")
                print("📹 First 10 videos: \(videoFiles.prefix(10).joined(separator: ", "))")

                // Also check subdirectories
                let subdirs = allFiles.filter { item in
                    var isDir: ObjCBool = false
                    let fullPath = (resourcePath as NSString).appendingPathComponent(item)
                    FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
                    return isDir.boolValue
                }
                print("📁 Subdirectories in bundle: \(subdirs.joined(separator: ", "))")

                // Check for Videos subdirectory
                if subdirs.contains("Videos") {
                    let videosPath = (resourcePath as NSString).appendingPathComponent("Videos")
                    if let videosContent = try? FileManager.default.contentsOfDirectory(atPath: videosPath) {
                        let vids = videosContent.filter { $0.hasSuffix(".mp4") }
                        print("📹 Found \(vids.count) .mp4 files in Videos subdirectory")
                        print("📹 First 10 in Videos/: \(vids.prefix(10).joined(separator: ", "))")
                    }
                }
            }
        }

        // Try to load idle video with all methods
        print("🎬 Testing idle video load...")
        if let item = createPlayerItem(for: .idle) {
            videoCache[.idle] = item
            print("✅ Idle video loaded successfully")
        } else {
            print("❌ Failed to load idle video - trying debug load...")
            // Try to manually find ANY mp4 file
            if let resourcePath = Bundle.main.resourcePath,
               let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath),
               let firstVideo = files.first(where: { $0.hasSuffix(".mp4") }) {
                print("🔍 Found first .mp4 in bundle: \(firstVideo)")
                let url = URL(fileURLWithPath: (resourcePath as NSString).appendingPathComponent(firstVideo))
                let testItem = AVPlayerItem(url: url)
                videoCache[.idle] = testItem
                print("✅ Loaded test video as fallback: \(firstVideo)")
            }
        }

        // Start with idle video
        print("🎬 Starting idle video playback...")
        playVideo(label: .idle)
    }

    // MARK: - Video Playback
    func playVideo(label requestedLabel: VideoLabel) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // The coach only animates during an active meeting. Any non-idle clip
            // requested while no meeting is running collapses to the calm idle loop —
            // so stray async coaching results, goal toggles, or wrap clips never
            // animate when you're not in a meeting.
            let label = (requestedLabel == .idle || self.isMeetingActive) ? requestedLabel : .idle

            print("🎬 Playing video: \(label.rawValue)")

            // Set coaching text for this video (instant, no API call)
            self.coachingText = label.randomCoachingText
            print("💬 Coaching: \(self.coachingText)")

            // Cancel idle timer
            self.idleTimer?.invalidate()

            // Skip if already playing this video AND player exists and is playing
            if self.currentVideoLabel == label && self.player != nil && self.isPlaying {
                print("🎬 Video already playing: \(label.rawValue)")
                return
            }

            self.currentVideoLabel = label

            // Get or create player item
            let item = self.videoCache[label] ?? self.createPlayerItem(for: label)

            if let item = item {
                // Create new player if needed
                if self.player == nil {
                    self.player = AVPlayer(playerItem: item)
                    self.player?.isMuted = true // Silent videos
                    self.player?.actionAtItemEnd = .none // Don't pause at end
                    self.setupPlayerObserver()
                } else {
                    self.player?.replaceCurrentItem(with: item)
                }

                self.currentPlayerItem = item

                // Observe player item status and play when ready
                self.statusObserver?.cancel()
                self.statusObserver = item.publisher(for: \.status)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] status in
                        guard let self = self else { return }

                        print("📺 Player item status changed: \(status.rawValue)")

                        if status == .readyToPlay {
                            self.startOrFreeze(label: label)
                        } else if status == .failed {
                            print("❌ Player item failed: \(item.error?.localizedDescription ?? "unknown error")")
                        }
                    }

                // Also try playing immediately in case item is already ready
                if item.status == .readyToPlay {
                    self.startOrFreeze(label: label)
                }

                print("✅ Player status: \(self.player?.status.rawValue ?? -1), rate: \(self.player?.rate ?? 0)")
                print("✅ Player item status: \(item.status.rawValue)")

                // Set timer to return to idle (except for idle itself)
                if label != .idle {
                    self.startIdleTimer()
                }
            } else {
                print("⚠️ No video found for label: \(label.rawValue)")
                // Fall back to idle if video not found
                if label != .idle {
                    self.playVideo(label: .idle)
                }
            }
        }
    }

    /// Animate during a meeting; at rest, drift slowly through the idle clips
    /// (quarter speed) so the coach feels alive instead of frozen.
    private func startOrFreeze(label: VideoLabel) {
        player?.seek(to: .zero)
        if label == .idle && !isMeetingActive {
            // Slow, calm idle motion. Each clip advances to a random next one on end
            // (see setupPlayerObserver / advanceIdleVideo).
            player?.playImmediately(atRate: idleRate)
            isPlaying = true
        } else {
            player?.play()
            isPlaying = true
        }
    }

    private func createPlayerItem(for label: VideoLabel, variation: Int? = nil) -> AVPlayerItem? {
        // Try to find video in Resources/Videos folder
        // Videos are named like: general-idle-1.mp4, zen-goal-2.mp4, etc.

        // Use configured theme (general or zen)
        let theme = videoTheme

        // Use the requested variation, or randomly select one (1-4 available).
        let variation = variation ?? Int.random(in: 1...4)
        let videoName = "\(theme)-\(label.rawValue)-\(variation)"

        print("🎬 Looking for video: \(videoName).mp4")

        // Method 1: Try Bundle.main.url (most reliable for bundled resources)
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            print("✅ Found video in main bundle: \(videoName).mp4")
            let item = AVPlayerItem(url: url)
            return item
        }

        // Method 2: Try with subdirectory
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "Videos") {
            print("✅ Found video in Videos subdirectory: \(videoName).mp4")
            let item = AVPlayerItem(url: url)
            return item
        }

        // Method 3: Try with Resources/Videos subdirectory (full path)
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "Resources/Videos") {
            print("✅ Found video in Resources/Videos subdirectory: \(videoName).mp4")
            let item = AVPlayerItem(url: url)
            return item
        }

        // Method 4: Try resourcePath method
        if let resourcesPath = Bundle.main.resourcePath {
            let videoPath = (resourcesPath as NSString)
                .appendingPathComponent("\(videoName).mp4")

            if FileManager.default.fileExists(atPath: videoPath) {
                print("✅ Found video in resources: \(videoName).mp4")
                let url = URL(fileURLWithPath: videoPath)
                let item = AVPlayerItem(url: url)
                return item
            } else {
                print("⚠️ Video not found at: \(videoPath)")
            }

            // Also try Resources/Videos subdirectory
            let videosSubPath = (resourcesPath as NSString)
                .appendingPathComponent("Resources/Videos/\(videoName).mp4")

            if FileManager.default.fileExists(atPath: videosSubPath) {
                print("✅ Found video in Resources/Videos: \(videoName).mp4")
                let url = URL(fileURLWithPath: videosSubPath)
                let item = AVPlayerItem(url: url)
                return item
            }

            // Also try just Videos subdirectory
            let videosPath = (resourcesPath as NSString)
                .appendingPathComponent("Videos/\(videoName).mp4")

            if FileManager.default.fileExists(atPath: videosPath) {
                print("✅ Found video in Videos: \(videoName).mp4")
                let url = URL(fileURLWithPath: videosPath)
                let item = AVPlayerItem(url: url)
                return item
            }
        }

        // Video not found - this is okay, app will show placeholder
        print("❌ No video found for: \(videoName).mp4 (label: \(label.rawValue), theme: \(theme), variation: \(variation))")
        print("📂 Bundle path: \(Bundle.main.bundlePath)")
        return nil
    }

    /// Idle playback speed — slow drift so the resting coach isn't static.
    private let idleRate: Float = 0.5
    /// Last idle variation shown, to avoid playing the same clip twice in a row.
    private var lastIdleVariation = 0

    private func setupPlayerObserver() {
        // When a clip ends: at rest, advance to a different random idle clip
        // (slow loop through the four). During a meeting, loop the current clip.
        playerObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, // Observe all items
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let item = notification.object as? AVPlayerItem,
                  item == self.player?.currentItem else { return }

            if self.currentVideoLabel == .idle && !self.isMeetingActive {
                self.advanceIdleVideo()
            } else {
                print("🔄 Video ended, looping...")
                self.player?.seek(to: .zero)
                self.player?.play()
            }
        }
    }

    /// Swap in a different random idle clip and play it slowly. Keeps the resting
    /// coach drifting through the four idle videos instead of freezing.
    private func advanceIdleVideo() {
        var variation = Int.random(in: 1...4)
        if variation == lastIdleVariation { variation = (variation % 4) + 1 }
        lastIdleVariation = variation

        guard let item = createPlayerItem(for: .idle, variation: variation) else {
            // No alternate clip — just loop the current one slowly.
            player?.seek(to: .zero)
            player?.playImmediately(atRate: idleRate)
            return
        }
        currentPlayerItem = item
        player?.replaceCurrentItem(with: item)

        // Play at quarter speed once the new clip is ready.
        statusObserver?.cancel()
        statusObserver = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self, status == .readyToPlay else { return }
                self.player?.seek(to: .zero)
                self.player?.playImmediately(atRate: self.idleRate)
                self.isPlaying = true
            }
        if item.status == .readyToPlay {
            player?.seek(to: .zero)
            player?.playImmediately(atRate: idleRate)
            isPlaying = true
        }
    }

    private func cleanupObservers() {
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Meeting State
    /// Called when recording starts/stops. While a meeting is active we hold the
    /// coaching video (looping) until the next read; when it ends we ease back to
    /// the idle loop.
    func setMeetingActive(_ active: Bool) {
        isMeetingActive = active
        idleTimer?.invalidate()
        if active {
            // Coach comes alive when the meeting starts — kick off an animated
            // clip; the live transcript then cycles through the coaching clips.
            playVideo(label: .focus)
        } else {
            // Meeting over — ease back into the slow idle loop (no wrap clip,
            // no lingering coaching video).
            playVideo(label: .idle)
        }
    }

    // MARK: - Timer Management
    private func startIdleTimer() {
        idleTimer?.invalidate()
        // Never auto-revert to idle mid-meeting — the coaching video should
        // persist (and loop) until the next read replaces it.
        guard !isMeetingActive else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: IDLE_TIMEOUT, repeats: false) { [weak self] _ in
            print("🎬 Idle timeout - returning to idle video")
            self?.playVideo(label: .idle)
        }
    }

    // MARK: - Event Handlers
    @objc private func handleGoalCompleted(_ notification: Notification) {
        print("🎯 Goal completed - triggering goal video")
        playVideo(label: .goal)
    }

    @objc private func handleRecordingStopped(_ notification: Notification) {
        print("🎬 Recording stopped - playing wrap video")
        playVideo(label: .wrap)
    }

    // MARK: - Public Methods

    /// Play video based on goal progress - encourages user toward completing goals
    func playForGoalProgress(goals: [Goal], evaluation: GoalEvaluation) {
        let completedCount = goals.filter { $0.isCompleted }.count
        let totalCount = goals.count
        let progressRatio = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0

        print("🎬 Video selection: \(completedCount)/\(totalCount) goals complete (\(Int(progressRatio * 100))%)")

        if progressRatio >= 1.0 {
            // All goals complete - celebrate!
            playVideo(label: .goal)
        } else if progressRatio >= 0.66 {
            // 2/3 done - almost there, keep steady
            playVideo(label: .steady)
        } else if progressRatio >= 0.33 {
            // 1/3 done - making progress, check in
            playVideo(label: .check)
        } else {
            // Just starting - focus and listen
            let encouragementVideos: [VideoLabel] = [.focus, .listen, .prompt, .steady]
            let selected = encouragementVideos.randomElement() ?? .focus
            playVideo(label: selected)
        }
    }

    /// Play video based on specific goal type being worked on
    func playForGoalType(_ goalText: String) {
        let goalLower = goalText.lowercased()

        if goalLower.contains("listen") {
            playVideo(label: .listen)
        } else if goalLower.contains("speak") || goalLower.contains("clear") {
            playVideo(label: .prompt)
        } else if goalLower.contains("filler") || goalLower.contains("reduce") {
            playVideo(label: .mute)
        } else if goalLower.contains("focus") || goalLower.contains("attention") {
            playVideo(label: .focus)
        } else if goalLower.contains("time") || goalLower.contains("pace") {
            playVideo(label: .timing)
        } else if goalLower.contains("question") || goalLower.contains("ask") {
            playVideo(label: .prompt)
        } else {
            // Default to encouraging videos
            let defaultVideos: [VideoLabel] = [.focus, .steady, .check]
            playVideo(label: defaultVideos.randomElement() ?? .focus)
        }
    }

    func playForCoaching(response: String) {
        // Analyze coaching response to determine video
        let responseLower = response.lowercased()

        // Priority 1: Goal achievement keywords
        if responseLower.contains("achieved") || responseLower.contains("complete") || responseLower.contains("great") || responseLower.contains("excellent") {
            playVideo(label: .goal)
            return
        }

        // Priority 2: Progress keywords
        if responseLower.contains("progress") || responseLower.contains("solid") || responseLower.contains("good") || responseLower.contains("keep") {
            playVideo(label: .steady)
            return
        }

        // Priority 3: Specific coaching areas
        if responseLower.contains("listen") || responseLower.contains("hear") || responseLower.contains("attention") {
            playVideo(label: .listen)
        } else if responseLower.contains("speak") || responseLower.contains("voice") || responseLower.contains("clear") {
            playVideo(label: .prompt)
        } else if responseLower.contains("filler") || responseLower.contains("um") || responseLower.contains("uh") || responseLower.contains("less") {
            playVideo(label: .mute)
        } else if responseLower.contains("time") || responseLower.contains("hurry") || responseLower.contains("pace") || responseLower.contains("faster") {
            playVideo(label: .timing)
        } else if responseLower.contains("focus") || responseLower.contains("concentrate") {
            playVideo(label: .focus)
        } else if responseLower.contains("wrap") || responseLower.contains("conclude") || responseLower.contains("finish") {
            playVideo(label: .wrap)
        } else if responseLower.contains("check") || responseLower.contains("review") {
            playVideo(label: .check)
        } else if responseLower.contains("question") || responseLower.contains("ask") {
            playVideo(label: .prompt)
        } else if responseLower.contains("pause") || responseLower.contains("slow") || responseLower.contains("breathe") {
            playVideo(label: .pause)
        } else {
            // Rotate through encouraging videos instead of always focus
            let encouragingVideos: [VideoLabel] = [.focus, .steady, .check, .listen, .prompt]
            let selected = encouragingVideos.randomElement() ?? .steady
            playVideo(label: selected)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }
}
