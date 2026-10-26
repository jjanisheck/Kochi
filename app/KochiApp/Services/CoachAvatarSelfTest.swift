#if os(macOS)
import AppKit
import SwiftUI
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

/// Run the built app with --selftest-avatar. No meeting capture or AI request is made.
enum CoachAvatarSelfTest {
    @MainActor static func run() {
        var failures = 0
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if !condition() { failures += 1; print("FAIL: \(name)") }
        }

        var performance = CoachPerformance()
        check(!performance.receive(.achievement, at: 0), "No celebration outside a meeting")
        performance.setMeetingActive(true, at: 10)
        check(performance.reaction.intent == .listen, "Start in listening state")
        check(performance.receive(.achievement, at: 11), "Verified achievement accepted")
        check(!performance.receive(.achievement, at: 12), "Duplicate achievement coalesced")
        check(!performance.receive(.listening, at: 13), "Celebration has priority over routine advice")
        check(!performance.isPerforming(at: 15), "Celebration expires")
        let nod = CoachReaction(intent: .steady, gesture: .nod)
        check(performance.receive(nod, at: 15), "Advice accepted after celebration")
        check(performance.reaction.gesture == .none, "Gesture cooldown suppresses repeated motion")
        check(performance.receive(nod, at: 18), "Advice accepted after cooldown")
        check(performance.reaction.gesture == .nod, "Gesture resumes after cooldown")
        performance.setMeetingActive(false, at: 19)
        check(performance.reaction.intent == .idle, "Stopping resets to idle")
        check(!performance.receive(nod, at: 20), "Late result after stop rejected")
        performance.setMeetingActive(true, at: 21)
        check(performance.receive(nod, at: 21), "New meeting clears old cooldown")
        check(performance.reaction.gesture == .nod, "New meeting can gesture immediately")
        check(CoachReaction(intent: .listen, intensity: .nan).intensity == 0.4, "Invalid intensity normalized")
        check(CoachReaction(intent: .listen, intensity: 3).intensity == 1, "Intensity bounded")
        let directive = CoachingDirective(intent: .goal, expression: .pleased, gesture: .salute,
                                         intensity: 0.6, caption: "Great question.")
        let sanitized = CoachReaction(directive: directive)
        check(sanitized.intent == .steady && sanitized.gesture == .nod, "Model compliments cannot create goal events")
        check(CoachReaction.fallback(goals: []).intent == .listen, "Fallback listens instead of inventing a celebration")
        check(CoachIntent.thinking.videoLabel == .focus, "Video themes accept typed intentions")
        check(CoachGesture.acknowledge.portraitGesture == .nod && CoachGesture.shrug.portraitGesture == .openHand,
              "Richer semantic gestures retain compatible portrait motions")

        let partialPreset = try! JSONDecoder().decode(CoachCharacterTuning.self, from: Data("{\"handScale\":2.2}".utf8))
        check(partialPreset.handScale == 2.2 && partialPreset.forearmLength == CoachCharacterTuning.standard.forearmLength, "Partial presets preserve safe defaults")
        check((try? JSONDecoder().decode(CoachCharacterTuning.self, from: Data(partialPreset.json().utf8))) == partialPreset,
              "Workshop settings round-trip through shareable JSON")
        var invalidPreset = CoachCharacterTuning.standard
        invalidPreset.handScale = .nan
        invalidPreset.forearmLength = -100
        check(invalidPreset.sanitized.handScale == 1.7 && invalidPreset.sanitized.forearmLength == 110,
              "Invalid proportions cannot create invalid bone lengths")
        let suite = "kochi-character-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = CoachCharacterSettings(defaults: defaults)
        let workshop = CoachWorkshopModel(settings: settings)
        workshop.draft.handScale = 2.2
        check(settings.tuning.handScale == 1.7, "Preview edits do not alter the live coach before Apply")
        workshop.apply()
        check(CoachCharacterSettings(defaults: defaults).tuning.handScale == 2.2, "Apply persists character proportions")
        let oldRequest = workshop.seekID
        workshop.seek(3)
        workshop.receiveFrame(time: 1.4, gap: 0, offset: 0, requestID: oldRequest)
        check(workshop.playhead == 3 && workshop.control.seekTime == 3, "Late frames cannot overwrite a scrub request")
        defaults.removePersistentDomain(forName: suite)

        guard let themesURL = Bundle.main.url(forResource: "Themes", withExtension: nil),
              let defaultTheme = Theme.load(folderURL: themesURL.appendingPathComponent("default")) else {
            print("FAIL: Missing bundled default theme"); exit(1)
        }
        check(defaultTheme.coachRenderer == .mannequin, "Default theme selects mannequin renderer")
        for id in ["bricks", "hero", "noir", "zen"] {
            check(Theme.load(folderURL: themesURL.appendingPathComponent(id))?.coachRenderer == .video,
                  "\(id) uses video rendering")
            for variation in 1...4 {
                check(Bundle.main.url(forResource: "idle-\(variation)", withExtension: "mp4",
                                      subdirectory: "Themes/\(id)/videos") != nil,
                      "\(id) includes idle video \(variation)")
            }
        }
        for target in [CGPoint(x: 500,y: 350), CGPoint(x: 455,y: 220), CGPoint(x: 50,y: 50), CGPoint(x: 2000,y: -2000), CGPoint(x: 565,y: 138)] {
            let solution = CoachArmSolution.solve(shoulder: CGPoint(x: 565,y: 138), target: target)
            check(abs(hypot(solution.elbow.x - solution.shoulder.x, solution.elbow.y - solution.shoulder.y) - 140) < 0.001,
                  "Upper-arm length is fixed for target \(target)")
            check(abs(hypot(solution.wrist.x - solution.elbow.x, solution.wrist.y - solution.elbow.y) - 140) < 0.001,
                  "Forearm length is fixed for target \(target)")
        }
        let folder = defaultTheme.folderURL.appendingPathComponent("avatar")
        check(CoachArmArtwork(folder: folder) != nil, "All articulated sleeve and hand parts decode")
        for point in [CGPoint(x: 332,y: 200), CGPoint(x: 332,y: 310), CGPoint(x: 330,y: 50),
                      CGPoint(x: 520,y: 450), CGPoint(x: 220,y: 480), CGPoint(x: 330,y: 530)] {
            check(CoachBodyMask.path().contains(CGPoint(x: point.x, y: 540 - point.y)),
                  "Gesture mask retains original character at \(point)")
        }
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("general.png").path), "Original portrait bundled")
        let rig = RetroCoachRig()
        let neutral = rig.positions(for: RetroCoachPose())
        let blink = rig.positions(for: RetroCoachPose(blink: 1))
        let smile = rig.positions(for: RetroCoachPose(smile: 2.4, nod: 3))
        let inhale = rig.positions(for: RetroCoachPose(breath: 14))
        check(neutral != blink, "Blink deforms the original eyelids")
        check(neutral != smile, "Acknowledgment deforms the original face")
        check(zip(neutral, inhale).contains { abs($0.y - $1.y) * 540 > 12 },
              "Idle chest rise remains visible at compact display size")
        check(zip(neutral, inhale).contains { abs($0.x - $1.x) * 664 > 6 },
              "Idle inhale gently broadens the shoulders")
        check(neutral.first == blink.first && neutral.last == smile.last, "Outer frame remains anchored")
        check(zip(neutral, smile).allSatisfy { abs($0.x - $1.x) < 0.01 && abs($0.y - $1.y) < 0.015 }, "Motion stays subtle")
        for row in 0..<rig.geometry.numberOfRows {
            for col in 0...rig.geometry.numberOfColumns {
                let i = row * (rig.geometry.numberOfColumns + 1) + col
                if blink[i].y >= blink[i + rig.geometry.numberOfColumns + 1].y {
                    check(false, "Blink mesh must not fold over itself")
                }
            }
        }

        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kochi-avatar-preview")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            // Exercise the actual SwiftUI/native integration. Offscreen scene renders
            // alone cannot catch a zero-sized surface or an initially paused scene.
            let root = CoachSceneSurface(folder: folder, reaction: .idle, meetingActive: false,
                                         thinking: false, reduceMotion: false, paused: false)
                .frame(width: 408, height: 166)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 408, height: 166),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Coach rendering check"
            window.contentView = host
            window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            func findSurface(_ view: NSView) -> CoachSpriteView? {
                if let surface = view as? CoachSpriteView { return surface }
                return view.subviews.lazy.compactMap { findSurface($0) }.first
            }
            if let surface = findSurface(host), let avatar = surface.scene as? RetroCoachScene {
                check(surface.bounds.width > 0 && surface.bounds.height > 0, "Mounted coach receives a visible viewport")
                check(avatar.containsOriginalPortrait, "Mounted scene already contains the original portrait")
                check(!surface.isPaused && avatar.renderedFrameCount > 0, "Mounted idle coach renders live frames")
                let firstFrame = avatar.renderedFrameCount
                let firstBreath = avatar.pose.breath
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                check(avatar.renderedFrameCount > firstFrame && avatar.pose.breath != firstBreath,
                      "Idle breathing continues without a meeting")
                surface.display(folder: folder, reaction: .idle, meetingActive: false,
                                thinking: false, reduceMotion: false, paused: true)
                check(surface.isPaused, "Backgrounding pauses the mounted coach")
                surface.display(folder: folder, reaction: .idle, meetingActive: false,
                                thinking: false, reduceMotion: false, paused: false)
                check(!surface.isPaused, "Returning resumes the mounted coach")
            } else { check(false, "SwiftUI mounts the native coach surface") }
            window.orderOut(nil)
            window.contentView = nil
            let view = SKView(frame: CGRect(x: 0, y: 0, width: 664, height: 540))
            let scene = RetroCoachScene()
            scene.configure(folder: folder)
            view.presentScene(scene)
            var clock: TimeInterval = 100
            let samples: [(String, CoachReaction)] = [
                ("idle", .idle), ("listen", .listening),
                ("encourage", CoachReaction(intent: .prompt, expression: .encouraging, gesture: .openHand)),
                ("goal", .achievement),
                ("wave", CoachReaction(intent: .wrap, gesture: .wave)),
                ("point", CoachReaction(intent: .focus, gesture: .point)),
                ("watch", CoachReaction(intent: .timing, gesture: .checkWatch))
            ]
            for (name, reaction) in samples {
                scene.meetingActive = name != "idle"
                scene.perform(reaction)
                var gaps: CGFloat = 0
                for _ in 0..<45 {
                    clock += 1.0 / 30; scene.update(clock)
                    for arm in scene.articulatedArms { gaps = max(gaps, arm.maximumJointGap(in: scene)) }
                }
                check(gaps < 0.001, "Shoulder/elbow/wrist/hand stay connected throughout \(name)")
                if let image = view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))?.cgImage() {
                    let url = output.appendingPathComponent("\(name).png")
                    if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(destination, image, nil)
                        check(CGImageDestinationFinalize(destination), "Render \(name)")
                    } else { check(false, "Create \(name) preview") }
                } else { check(false, "Render \(name) texture") }
                for _ in 0..<100 {
                    clock += 1.0 / 30; scene.update(clock)
                    for arm in scene.articulatedArms { gaps = max(gaps, arm.maximumJointGap(in: scene)) }
                }
                check(gaps < 0.001, "Joints remain attached through the complete \(name) return")
                check(scene.articulatedArms.allSatisfy { $0.isHidden && $0.alpha < 0.01 },
                      "\(name) returns to resting arms")
            }
            for (name, pose) in [("neutral", RetroCoachPose()), ("blink", RetroCoachPose(blink: 1)),
                                 ("smile", RetroCoachPose(smile: 2.4, nod: 3))] {
                scene.applyPose(pose)
                if let image = view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))?.cgImage(),
                   let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    check(CGImageDestinationFinalize(destination), "Render \(name) pose")
                } else { check(false, "Render \(name) pose") }
            }
            // This is the exact crop used by the compact 408×166 hero.
            if let image = view.texture(from: scene, crop: CGRect(x: 0, y: 135, width: 664, height: 270))?.cgImage(),
               let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("hero-crop.png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                check(CGImageDestinationFinalize(destination), "Render compact hero crop")
            } else { check(false, "Render compact hero crop") }
            scene.reduceMotion = true
            scene.perform(.achievement)
            scene.update(clock + 1)
            check(scene.pose == RetroCoachPose(), "Reduced motion uses the untouched neutral portrait")
            scene.reduceMotion = false
            scene.perform(.achievement)
            scene.update(clock + 1.03)
            let before = scene.pose
            scene.perform(CoachReaction(intent: .focus, expression: .concerned, gesture: .tilt))
            scene.update(clock + 1.06)
            check(abs(scene.pose.nod - before.nod) < 0.5 && abs(scene.pose.brow - before.brow) < 0.5,
                  "New directions blend without a visible jump")
            for i in 1...150 { scene.update(clock + 1.06 + Double(i) / 30) }
            check(abs(scene.pose.smile) < 0.01 && abs(scene.pose.nod) < 0.01,
                  "Gestures settle without looping")

            let previewScene = RetroCoachScene()
            previewScene.configure(folder: folder)
            view.presentScene(previewScene)
            var control = CoachPreviewControl(reaction: .achievement, seekTime: 1.4)
            previewScene.setPreview(control)
            previewScene.update(100)
            let firstWrist = previewScene.articulatedArms.last!.solution.wrist
            let firstSize = previewScene.articulatedArms.last!.renderedHandSize
            check(abs(previewScene.previewPlayhead - 1.4) < 0.0001, "Workshop seeks to the requested pose time")
            previewScene.update(101)
            check(abs(previewScene.previewPlayhead - 1.4) < 0.0001, "Paused workshop holds the exact frame")
            control.seekID = UUID(); control.seekTime = 0.4
            previewScene.setPreview(control); previewScene.update(102)
            control.seekID = UUID(); control.seekTime = 1.4
            previewScene.setPreview(control); previewScene.update(103)
            let repeatedWrist = previewScene.articulatedArms.last!.solution.wrist
            check(hypot(firstWrist.x - repeatedWrist.x, firstWrist.y - repeatedWrist.y) < 0.001,
                  "Scrubbing back reproduces the same wrist position")
            previewScene.tuning.handScale = 2.4
            previewScene.setPreview(control); previewScene.update(104)
            check(previewScene.articulatedArms.last!.renderedHandSize.width > firstSize.width,
                  "Hand-size edits update the same frozen pose immediately")
            check(previewScene.articulatedArms.allSatisfy { $0.maximumJointGap(in: previewScene) < 0.001 },
                  "Resizing hands leaves the wrist and sleeve attached")
            control.playing = true; control.speed = 0.25
            previewScene.setPreview(control); previewScene.update(104.03)
            check(previewScene.previewPlayhead > 1.4 && previewScene.previewPlayhead < 1.42,
                  "Quarter-speed workshop playback advances slowly")

            // Validate anatomy and continuity, not only coincident node origins.
            previewScene.tuning = .standard
            for gesture: CoachGesture in [.salute, .wave, .openHand, .point, .checkWatch] {
                control = CoachPreviewControl(reaction: CoachReaction(intent: gesture == .salute ? .goal : .prompt,
                    gesture: gesture), seekTime: 1.6)
                previewScene.setPreview(control); previewScene.update(200)
                let arms = previewScene.articulatedArms
                let right = arms[1], left = arms[0]
                if gesture == .salute {
                    let poseRig = RetroCoachRig()
                    let temple = poseRig.scenePoint(CGPoint(x: 443,y: 139), positions: poseRig.positions(for: previewScene.pose))
                    let tip = right.fingertip(in: previewScene)
                    check(hypot(tip.x - temple.x, tip.y - temple.y) < 3, "Saluting fingertips meet the deformed temple")
                }
                if gesture == .openHand || gesture == .point {
                    check(right.solution.elbow.y < right.solution.shoulder.y,
                          "\(gesture.rawValue) keeps the elbow naturally below the shoulder")
                }
                if gesture == .checkWatch {
                    check(left.solution.elbow.y < left.solution.shoulder.y && right.isHidden,
                          "Watch check raises one forearm with a relaxed elbow")
                }
            }
            let motion = RetroCoachScene()
            motion.configure(folder: folder)
            view.presentScene(motion)
            motion.update(0)
            var motionClock: Double = 0
            var maximumStep: CGFloat = 0
            var stepContext = ""
            for gesture: CoachGesture in [.salute, .openHand, .wave, .checkWatch, .point] {
                let previous = motion.articulatedArms.map { $0.solution.wrist }
                motion.perform(CoachReaction(intent: .prompt, gesture: gesture))
                var last = previous
                // Interrupt in mid-gesture too: a new pose must start from the actual joints.
                for frame in 0..<100 {
                    if frame == 70 { motion.perform(.idle) }
                    motionClock += 1.0 / 60
                    motion.update(motionClock)
                    for (index,arm) in motion.articulatedArms.enumerated() {
                        let step = hypot(arm.solution.wrist.x - last[index].x, arm.solution.wrist.y - last[index].y)
                        if step > maximumStep { maximumStep = step; stepContext = "\(gesture.rawValue) frame \(frame) arm \(index) alpha \(arm.alpha)" }
                        last[index] = arm.solution.wrist
                    }
                }
            }
            check(maximumStep < 30, "Joint-led transitions and interrupted gestures have no wrist jumps (max \(String(format: "%.1f", maximumStep)) px/frame; \(stepContext))")
            // Reactions must never pan or zoom at any viewport aspect ratio.
            for viewport in [CGSize(width: 408,height: 166), CGSize(width: 664,height: 540), CGSize(width: 320,height: 540)] {
                view.frame.size = viewport
                let fixed = RetroCoachScene()
                fixed.configure(folder: folder); view.presentScene(fixed)
                let baseline = (fixed.camera!.position, fixed.camera!.xScale, fixed.camera!.yScale)
                func cameraUnchanged() -> Bool {
                    fixed.camera!.position == baseline.0 && fixed.camera!.xScale == baseline.1 && fixed.camera!.yScale == baseline.2
                }
                var unchanged = true
                var fixedClock: Double = 0
                fixed.update(fixedClock)
                for gesture: CoachGesture in [.salute, .wave, .point, .openHand, .checkWatch, .none] {
                    fixed.perform(CoachReaction(intent: gesture == .none ? .idle : .prompt, gesture: gesture))
                    for _ in 0..<150 {
                        fixedClock += 1.0 / 30; fixed.update(fixedClock)
                        unchanged = unchanged && cameraUnchanged()
                    }
                }
                fixed.reduceMotion = true; fixed.update(fixedClock + 0.03)
                check(unchanged && cameraUnchanged(), "Camera is fixed through all gestures at \(viewport)")
                for time in [0.0,0.5,1.4,2.8,4.8] {
                    fixed.setPreview(CoachPreviewControl(reaction: .achievement, seekTime: time))
                    fixed.update(fixedClock + 1)
                    unchanged = unchanged && cameraUnchanged()
                }
                check(unchanged, "Scrubbing and replay cannot reset the camera at \(viewport)")
            }
            view.frame.size = CGSize(width: 664,height: 540)

            if CommandLine.arguments.contains("--avatar-export-arms") {
                let frames = output.appendingPathComponent("arm-frames")
                try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
                let demo = RetroCoachScene()
                demo.configure(folder: folder)
                demo.meetingActive = true
                view.presentScene(demo)
                let gestures: [CoachGesture] = [.salute, .wave, .point, .openHand, .checkWatch]
                var gap: CGFloat = 0
                for i in 0..<375 {
                    let step = i / 75
                    if i % 75 == 0 {
                        let gesture = gestures[step]
                        demo.perform(CoachReaction(intent: gesture == .salute ? .goal : gesture == .checkWatch ? .timing : .prompt,
                                                  expression: .encouraging, gesture: gesture))
                    }
                    demo.update(100 + Double(i) / 15)
                    for arm in demo.articulatedArms { gap = max(gap, arm.maximumJointGap(in: demo)) }
                    guard let image = view.texture(from: demo, crop: CGRect(origin: .zero, size: demo.size))?.cgImage(),
                          let destination = CGImageDestinationCreateWithURL(
                            frames.appendingPathComponent(String(format: "%04d.png", i)) as CFURL,
                            UTType.png.identifier as CFString, 1, nil) else {
                        check(false, "Export articulated frame \(i)"); break
                    }
                    CGImageDestinationAddImage(destination, image, nil)
                    if !CGImageDestinationFinalize(destination) { check(false, "Write articulated frame \(i)"); break }
                }
                check(gap < 0.001, "Every exported articulation frame keeps joints attached")
            }

            if CommandLine.arguments.contains("--avatar-export-frames") {
                let frames = output.appendingPathComponent("frames")
                try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
                let demo = RetroCoachScene()
                demo.configure(folder: folder)
                demo.meetingActive = true
                demo.perform(.listening)
                view.presentScene(demo)
                for i in 0..<240 {
                    if i == 60 { demo.thinking = true }
                    if i == 120 { demo.thinking = false; demo.perform(.achievement) }
                    demo.update(100 + Double(i) / 30)
                    guard let image = view.texture(from: demo, crop: CGRect(origin: .zero, size: demo.size))?.cgImage(),
                          let destination = CGImageDestinationCreateWithURL(
                            frames.appendingPathComponent(String(format: "%04d.png", i)) as CFURL,
                            UTType.png.identifier as CFString, 1, nil) else {
                        check(false, "Export animation frame \(i)"); break
                    }
                    CGImageDestinationAddImage(destination, image, nil)
                    if !CGImageDestinationFinalize(destination) { check(false, "Write animation frame \(i)"); break }
                }
            }
        } catch {
            print("FAIL: Preview export: \(error)")
            failures += 1
        }
        #if DEBUG
        if CommandLine.arguments.contains("--verify-workshop-bridge") {
            var delivered: Bool?
            CoachWorkshopBridge.shared.publish(CoachReaction(intent: .steady, expression: .encouraging,
                gesture: .acknowledge, caption: "Workshop connection verified.")) { delivered = $0 }
            let deadline = Date().addingTimeInterval(5)
            while delivered == nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            check(delivered == true, "Native coach response reaches the live browser workshop")
        }
        #endif
        print("Avatar: \(checks) checks, \(failures) failures. Previews: \(output.path)")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
