import SwiftUI
import SpriteKit
import ImageIO

struct RetroCoachView: View {
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var manager: VideoCoachingManager
    @ObservedObject private var characterSettings = CoachCharacterSettings.shared
    var body: some View {
        GeometryReader { geometry in
            CoachSceneSurface(
                folder: themes.current.folderURL.appendingPathComponent("avatar"),
                reaction: manager.avatarReaction,
                meetingActive: manager.avatarMeetingActive,
                thinking: manager.avatarThinking,
                reduceMotion: reduceMotion,
                paused: scenePhase == .background,
                tuning: characterSettings.tuning
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach")
        .accessibilityValue(manager.avatarReaction.intent.rawValue)
    }
}

/// Own the native SpriteKit surface and configure its scene BEFORE presenting it.
/// SwiftUI supplies an explicit viewport rather than relying on SpriteView's
/// intrinsic size inside the layered coach card.
struct CoachSceneSurface {
    let folder: URL
    let reaction: CoachReaction
    let meetingActive: Bool
    let thinking: Bool
    let reduceMotion: Bool
    let paused: Bool
    var tuning: CoachCharacterTuning = .standard
    var preview: CoachPreviewControl? = nil
    var onPreviewFrame: ((Double, CGFloat, CGFloat) -> Void)? = nil

    func configure(_ view: CoachSpriteView) {
        view.display(folder: folder, reaction: reaction, meetingActive: meetingActive,
                     thinking: thinking, reduceMotion: reduceMotion, paused: paused, tuning: tuning)
        if let avatar = view.scene as? RetroCoachScene {
            avatar.setPreview(preview)
            avatar.onPreviewFrame = onPreviewFrame
        }
    }
}

#if os(macOS)
extension CoachSceneSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> CoachSpriteView {
        let view = CoachSpriteView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ view: CoachSpriteView, context: Context) { configure(view) }

    static func dismantleNSView(_ view: CoachSpriteView, coordinator: ()) {
        view.presentScene(nil)
    }
}
#else
extension CoachSceneSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> CoachSpriteView {
        let view = CoachSpriteView(frame: .zero)
        view.isUserInteractionEnabled = false
        configure(view)
        return view
    }

    func updateUIView(_ view: CoachSpriteView, context: Context) { configure(view) }

    static func dismantleUIView(_ view: CoachSpriteView, coordinator: ()) {
        view.presentScene(nil)
    }
}
#endif

final class CoachSpriteView: SKView {
    private var artworkFolder: URL?
    private var reactionID: UUID?
    private var pauseRequested = false

    func display(folder: URL, reaction: CoachReaction, meetingActive: Bool,
                 thinking: Bool, reduceMotion: Bool, paused: Bool, tuning: CoachCharacterTuning = .standard) {
        if artworkFolder != folder || scene == nil {
            let avatar = RetroCoachScene()
            avatar.tuning = tuning.sanitized
            avatar.configure(folder: folder)
            avatar.reduceMotion = reduceMotion
            avatar.meetingActive = meetingActive
            avatar.thinking = thinking
            avatar.perform(reaction)
            // Mount a complete scene. There is no later onAppear mutation needed
            // to make the first frame visible, even if the app starts inactive.
            presentScene(avatar)
            artworkFolder = folder
            reactionID = reaction.id
        }
        if let avatar = scene as? RetroCoachScene {
            avatar.tuning = tuning.sanitized
            avatar.reduceMotion = reduceMotion
            avatar.meetingActive = meetingActive
            avatar.thinking = thinking
            avatar.updateCameraFraming(viewport: bounds.size)
            if reactionID != reaction.id {
                avatar.perform(reaction)
                reactionID = reaction.id
            }
        }
        preferredFramesPerSecond = reduceMotion ? 10 : 30
        pauseRequested = paused
        updatePlayback()
    }

    private func updatePlayback() {
        isPaused = pauseRequested || window == nil
    }

    #if os(macOS)
    override func layout() {
        super.layout()
        (scene as? RetroCoachScene)?.updateCameraFraming(viewport: bounds.size)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePlayback()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        (scene as? RetroCoachScene)?.updateCameraFraming(viewport: bounds.size)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePlayback()
    }
    #endif
}

/// Small movements in source-image pixels. The neutral pose is the untouched portrait.
struct RetroCoachPose: Equatable {
    var blink: Float = 0
    var gazeX: Float = 0
    var gazeY: Float = 0
    var brow: Float = 0
    var smile: Float = 0
    var nod: Float = 0
    var tilt: Float = 0
    var breath: Float = 0
}

/// A continuous mesh keeps skin, eye sockets, jaw and uniform connected. Features
/// deform their original pixels; no rectangles, replacement mouth, or cut-out limbs
/// are painted over the character. Weights are computed once, outside the frame loop.
struct RetroCoachRig {
    private struct Vertex {
        let source: SIMD2<Float>
        let pixel: SIMD2<Float>
        let head: Float
        let breath: Float
        let eye: Float
        let lid: Float
        let brow: Float
        let mouthCorner: Float
    }

    // Extra control rows around the eyelids preserve their shape during a blink.
    private let xs: [Float] = [0,80,160,190,220,235,250,257,265,273,281,289,297,305,313,
                              325,337,345,353,361,369,377,385,393,401,409,425,450,475,500,540,580,620,664]
    private let ys: [Float] = [0,30,60,90,120,135,141,146,151,156,160,164,168,172,176,180,
                              184,190,205,225,245,253,260,266,272,278,285,305,330,350,380,420,460,500,540]
    private var vertices: [Vertex] = []
    let geometry: SKWarpGeometryGrid

    init() {
        // SpriteKit's grid begins at the bottom left; artwork coordinates start at the top.
        var samples: [Vertex] = []
        for y in ys.reversed() {
            for x in xs {
                let head = Self.ramp(180,225,x) * (1 - Self.ramp(440,485,x))
                    * Self.ramp(0,30,y) * (1 - Self.ramp(300,365,y))
                let leftEye = Self.ramp(258,266,x) * (1 - Self.ramp(298,305,x))
                let rightEye = Self.ramp(358,366,x) * (1 - Self.ramp(398,405,x))
                let eyeX = max(leftEye, rightEye)
                let lid = eyeX * (1 - Self.ramp(4,10,abs(y - 174)))
                let eye = eyeX * (1 - Self.ramp(12,28,abs(y - 172)))
                let brow = max(Self.oval(x,y,284,151,39,15), Self.oval(x,y,378,151,39,15))
                let mouth = max(Self.oval(x,y,298,266,21,20), Self.oval(x,y,365,266,21,20))
                let breath = Self.ramp(305,390,y) * (1 - Self.ramp(490,540,y))
                    * Self.ramp(0,45,x) * (1 - Self.ramp(619,664,x))
                samples.append(Vertex(source: SIMD2(x / 664, 1 - y / 540), pixel: SIMD2(x,y),
                    head: head, breath: breath, eye: eye, lid: lid, brow: brow, mouthCorner: mouth))
            }
        }
        vertices = samples
        geometry = SKWarpGeometryGrid(columns: xs.count - 1, rows: ys.count - 1,
                                      sourcePositions: samples.map(\.source),
                                      destinationPositions: samples.map(\.source))
    }

    func positions(for pose: RetroCoachPose) -> [SIMD2<Float>] {
        vertices.map { v in
            let rotationX = -(v.pixel.y - 235) * pose.tilt
            let rotationY = (v.pixel.x - 332) * pose.tilt
            let expansion = (v.pixel.x - 332) * pose.breath * 0.0028 * v.breath
            let dx = rotationX * v.head + pose.gazeX * v.eye + expansion
            // Closing the eye compresses the ORIGINAL eye into its lash line.
            // The connected upper/lower skin stretches into place without a cover patch.
            let blink = -(v.pixel.y - 174) * 0.94 * min(1, max(0, pose.blink)) * v.lid
            let dy = (pose.nod + rotationY - pose.breath * 0.12) * v.head - pose.breath * v.breath
                + blink + pose.gazeY * v.eye - pose.brow * v.brow - pose.smile * v.mouthCorner
            return v.source + SIMD2(dx / 664, -dy / 540)
        }
    }

    /// Sample the same deformed surface used by the portrait, so sleeve roots
    /// follow its shoulders through breathing and head/body movement.
    func scenePoint(_ source: CGPoint, positions: [SIMD2<Float>]) -> CGPoint {
        let xi = min(xs.count - 2, max(0, (xs.lastIndex { $0 <= Float(source.x) } ?? 0)))
        let yi = min(ys.count - 2, max(0, (ys.lastIndex { $0 <= Float(source.y) } ?? 0)))
        let u = min(1, max(0, (Float(source.x) - xs[xi]) / (xs[xi + 1] - xs[xi])))
        let v = min(1, max(0, (Float(source.y) - ys[yi]) / (ys[yi + 1] - ys[yi])))
        let top = (ys.count - 1 - yi) * xs.count + xi
        let bottom = top - xs.count
        let a = positions[top] * (1 - u) + positions[top + 1] * u
        let b = positions[bottom] * (1 - u) + positions[bottom + 1] * u
        let point = a * (1 - v) + b * v
        return CGPoint(x: CGFloat(point.x) * 664, y: CGFloat(point.y) * 540)
    }

    private static func ramp(_ start: Float, _ end: Float, _ value: Float) -> Float {
        let t = min(1, max(0, (value - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }

    private static func oval(_ x: Float, _ y: Float, _ cx: Float, _ cy: Float,
                             _ rx: Float, _ ry: Float) -> Float {
        let u = (x - cx) / rx, v = (y - cy) / ry
        return 1 - ramp(0.1, 1, u * u + v * v)
    }
}

final class RetroCoachScene: SKScene {
    var reduceMotion = false
    var meetingActive = false
    var thinking = false
    var tuning: CoachCharacterTuning = .standard
    var onPreviewFrame: ((Double, CGFloat, CGFloat) -> Void)?
    private var previewControl: CoachPreviewControl?
    private var previewNeedsSeek = false
    private var previewOverlayDirty = true
    private var previewWallClock: TimeInterval?
    private var previewTuning: CoachCharacterTuning = .standard
    private let jointOverlay = SKNode()
    private let gridOverlay = SKNode()
    var previewPlayhead: TimeInterval { elapsed }

    private let portrait = SKSpriteNode()
    private let rig = RetroCoachRig()
    private var reaction: CoachReaction = .idle
    private var reactionStart: TimeInterval = 0
    private var lastUpdate: TimeInterval?
    private var elapsed: TimeInterval = 0
    private var nextBlink: TimeInterval = 3.4
    private var blinkStart: TimeInterval = -.infinity
    private var lookStart: TimeInterval = 0
    private var nextLook: TimeInterval = 5
    private var lookFrom: Float = 0
    private var lookTo: Float = 0
    private(set) var pose = RetroCoachPose()
    private(set) var renderedFrameCount = 0
    private var configured = false
    private let gestureCamera = SKCameraNode()
    private var leftArm: CoachArticulatedArm?
    private var rightArm: CoachArticulatedArm?
    private let leftAmount = SKUniform(name: "u_left_arm", float: 0)
    private let rightAmount = SKUniform(name: "u_right_arm", float: 0)
    private let bodyAmount = SKUniform(name: "u_body_visibility", float: 0)
    private var posedPositions: [SIMD2<Float>] = []
    private var armGesture: CoachGesture = .none
    private var armStart: TimeInterval = -.infinity
    private var armDuration: TimeInterval = 4
    private var fromLeftOpacity: CGFloat = 0
    private var fromRightOpacity: CGFloat = 0
    private var leftOpacity: CGFloat = 0
    private var rightOpacity: CGFloat = 0
    private var handAngle: CGFloat = .pi
    private var fromHandAngle: CGFloat = .pi
    private var fromLeftJoints: (CGFloat, CGFloat) = (0,0)
    private var fromRightJoints: (CGFloat, CGFloat) = (0,0)
    private var rightBend: CGFloat = -1
    private var handPosture: CoachArticulatedArm.Hand = .closed
    private var demoStep = -1

    var containsOriginalPortrait: Bool { portrait.texture != nil }
    var articulatedArms: [CoachArticulatedArm] { [leftArm, rightArm].compactMap { $0 } }

    override init() {
        super.init(size: CGSize(width: 664, height: 540))
        scaleMode = .aspectFill
        backgroundColor = SKColor(white: 0.36, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(folder: URL) {
        guard !configured else { return }
        let url = folder.appendingPathComponent("general.png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            assertionFailure("Missing general.png avatar artwork")
            return
        }
        configured = true
        posedPositions = rig.positions(for: RetroCoachPose())
        gestureCamera.position = CGPoint(x: 332, y: 270)
        addChild(gestureCamera)
        camera = gestureCamera
        jointOverlay.zPosition = 100
        gridOverlay.zPosition = 90
        addChild(jointOverlay)
        addChild(gridOverlay)
        if let art = CoachArmArtwork(folder: folder),
           let source = CGImageSourceCreateWithURL(folder.appendingPathComponent("arm-background.png") as CFURL, nil),
           let wall = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let bodyMask = CoachBodyMask.texture(image: image) {
            let wallTexture = SKTexture(cgImage: wall)
            wallTexture.filteringMode = .nearest
            let background = SKSpriteNode(texture: wallTexture, size: CGSize(width: 2400, height: 1800))
            background.shader = SKShader(source: """
                void main() {
                    vec2 tile = v_tex_coord * vec2(2400.0 / 664.0, 1800.0 / 540.0)
                        - vec2(868.0 / 664.0, 630.0 / 540.0);
                    gl_FragColor = texture2D(u_texture, vec2(0.035) + fract(tile) * 0.93);
                }
                """)
            background.position = CGPoint(x: 332, y: 270)
            background.zPosition = -5
            addChild(background)
            portrait.shader = SKShader(source: """
                void main() {
                    vec4 color = texture2D(u_texture, v_tex_coord);
                    vec2 pixel = vec2(v_tex_coord.x * 664.0, (1.0 - v_tex_coord.y) * 540.0);
                    float body = texture2D(u_body_mask, v_tex_coord).r;
                    float leftEdge = 77.0 + (pixel.y - 410.0) * 0.035;
                    float rightEdge = 584.0 - (pixel.y - 410.0) * 0.04;
                    float belowShoulder = smoothstep(405.0, 430.0, pixel.y);
                    float cutLeft = belowShoulder * (1.0 - smoothstep(leftEdge - 3.0, leftEdge + 3.0, pixel.x)) * u_left_arm;
                    float cutRight = belowShoulder * smoothstep(rightEdge - 3.0, rightEdge + 3.0, pixel.x) * u_right_arm;
                    float foreground = mix(1.0, body, u_body_visibility);
                    gl_FragColor = color * foreground * (1.0 - max(cutLeft, cutRight));
                }
                """, uniforms: [leftAmount, rightAmount, bodyAmount, SKUniform(name: "u_body_mask", texture: bodyMask)])
            let left = CoachArticulatedArm(art: art, mirrorHand: true)
            let right = CoachArticulatedArm(art: art, mirrorHand: false)
            left.zPosition = 2; right.zPosition = 3
            addChild(left); addChild(right)
            leftArm = left; rightArm = right
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        portrait.texture = texture
        portrait.size = size
        portrait.position = CGPoint(x: size.width / 2, y: size.height / 2)
        portrait.warpGeometry = rig.geometry
        portrait.subdivisionLevels = 0
        addChild(portrait)
        applyPose(RetroCoachPose())
        updateArms(reduced: true)
    }

    func perform(_ next: CoachReaction) {
        reaction = next
        reactionStart = elapsed
        var gesture = next.gesture.portraitGesture
        if next.intent == .goal { gesture = .salute }
        if [.salute, .wave, .point, .openHand, .checkWatch].contains(gesture) {
            beginArms(gesture, duration: next.intent == .goal ? 3.2 : 4)
        } else if next.intent == .idle && (leftOpacity > 0 || rightOpacity > 0) {
            beginArms(.none, duration: 0.6)
        }
        // A new instruction never resets the breathing/blink clocks or snaps the face.
    }

    override func update(_ currentTime: TimeInterval) {
        if let control = previewControl {
            updatePreview(control, wallClock: currentTime)
        } else {
            advanceAnimation(currentTime)
        }
    }

    private func advanceAnimation(_ currentTime: TimeInterval) {
        renderedFrameCount += 1
        let dt = min(1.0 / 15, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        elapsed += dt
        if previewControl == nil, CommandLine.arguments.contains("--avatar-demo"), elapsed > 1 {
            let step = Int((elapsed - 1) / 5)
            if step != demoStep {
                demoStep = step
                let gestures: [CoachGesture] = [.salute, .wave, .point, .openHand, .checkWatch]
                let gesture = gestures[step % gestures.count]
                perform(CoachReaction(intent: gesture == .salute ? .goal : gesture == .checkWatch ? .timing : .prompt,
                                      expression: .encouraging, gesture: gesture, intensity: 0.6))
            }
        }
        if reduceMotion {
            pose = RetroCoachPose()
            applyPose(pose)
            updateArms(reduced: true, delta: dt)
            return
        }
        let age = elapsed - reactionStart
        let duration = reaction.intent == .goal ? 3.2 : 4
        let strength = Float(reaction.intensity)
        let expression = Float(Self.ease(age / 0.55) * (1 - Self.ease((age - duration + 0.7) / 0.7)))
        var target = RetroCoachPose()
        // A visible, unhurried inhale/exhale at the compact card's display scale.
        // The chest rises and broadens; the head follows slightly.
        let breathPeriod = tuning.sanitized.breathPeriod * (meetingActive ? 4.8 / 4.4 : 1)
        target.breath = Float((1 - cos(elapsed * 2 * .pi / breathPeriod)) / 2 * tuning.sanitized.breathAmplitude)
        if elapsed >= nextBlink {
            blinkStart = elapsed
            nextBlink = elapsed + Double.random(in: 3.8...6.4)
        }
        let blinkAge = elapsed - blinkStart
        if blinkAge < 0.09 { target.blink = Float(Self.ease(blinkAge / 0.09)) }
        else if blinkAge < 0.12 { target.blink = 1 }
        else if blinkAge < 0.28 { target.blink = Float(1 - Self.ease((blinkAge - 0.12) / 0.16)) }

        let lookProgress = Float(Self.ease((elapsed - lookStart) / 0.45))
        let currentLook = lookFrom + (lookTo - lookFrom) * lookProgress
        if elapsed >= nextLook {
            lookFrom = currentLook
            lookTo = meetingActive ? ([-1.2, 0, 0, 0, 1.2].randomElement() ?? 0) : 0
            lookStart = elapsed
            nextLook = elapsed + Double.random(in: 5...8)
        }
        target.gazeX = thinking ? 1.3 : currentLook
        target.gazeY = thinking ? -0.8 : 0
        if age < duration {
            switch reaction.expression {
            case .pleased: target.smile = 3.2 * strength * expression; target.brow = 1.1 * expression
            case .encouraging: target.smile = 1.8 * strength * expression; target.brow = 1.4 * expression
            case .thoughtful: target.brow = 1.5 * expression
            case .concerned: target.brow = -0.8 * expression
            default: break
            }
            // A nod is independent of the articulated hand/arm gestures.
            if reaction.gesture.portraitGesture == .nod || reaction.intent == .goal {
                target.nod = Float(Self.ease((age - 0.15) / 0.35) - Self.ease((age - 0.65) / 0.5)) * 4.5 * strength
            }
            if reaction.gesture.portraitGesture == .tilt {
                target.tilt = 0.008 * strength * expression
            }
            if reaction.gesture == .checkWatch || reaction.intent == .timing {
                target.gazeY = 2.0 * expression
                target.nod = 3.0 * expression
            }
        }
        if thinking { target.brow = max(target.brow, 1) }
        // Blend between instructions so a fresh model response never pops facial parts.
        let blend = Float(1 - exp(-dt * 9))
        pose.gazeX += (target.gazeX - pose.gazeX) * blend
        pose.gazeY += (target.gazeY - pose.gazeY) * blend
        pose.brow += (target.brow - pose.brow) * blend
        pose.smile += (target.smile - pose.smile) * blend
        pose.nod += (target.nod - pose.nod) * blend
        pose.tilt += (target.tilt - pose.tilt) * blend
        pose.breath = target.breath
        pose.blink = target.blink
        applyPose(pose)
        updateArms(reduced: false, delta: dt)
    }

    /// Also used by the renderer checks to inspect exact neutral and peak poses.
    func applyPose(_ pose: RetroCoachPose) {
        posedPositions = rig.positions(for: pose)
        portrait.warpGeometry = rig.geometry.replacingByDestinationPositions(positions: posedPositions)
    }

    private func beginArms(_ gesture: CoachGesture, duration: TimeInterval) {
        fromLeftOpacity = leftOpacity
        fromRightOpacity = rightOpacity
        fromHandAngle = handAngle
        if let arm = leftArm { fromLeftJoints = (arm.solution.upperRotation, arm.solution.forearmRotation - arm.solution.upperRotation) }
        if let arm = rightArm { fromRightJoints = (arm.solution.upperRotation, arm.solution.forearmRotation - arm.solution.upperRotation) }
        if gesture != .none { rightBend = [.openHand, .point, .checkWatch].contains(gesture) ? 1 : -1 }
        armGesture = gesture
        armDuration = duration
        armStart = elapsed
        switch gesture {
        case .salute: handPosture = .salute
        case .wave, .openHand: handPosture = .open
        case .point, .checkWatch: handPosture = .point
        default: break // Keep the current hand while lowering it.
        }
    }

    private func updateArms(reduced: Bool, delta: TimeInterval = 1.0 / 30) {
        guard let leftArm, let rightArm else { return }
        let age = max(0, elapsed - armStart)
        let value = tuning.sanitized
        let leftShoulder = rig.scenePoint(CGPoint(x: 89 - value.shoulderSpread, y: 414 - value.shoulderLift), positions: posedPositions)
        let rightShoulder = rig.scenePoint(CGPoint(x: 575 + value.shoulderSpread, y: 414 - value.shoulderLift), positions: posedPositions)
        let restLength = CGFloat(value.upperArmLength + value.forearmLength - 6)
        let leftRest = CGPoint(x: leftShoulder.x - 16, y: leftShoulder.y - restLength)
        let rightRest = CGPoint(x: rightShoulder.x + 16, y: rightShoulder.y - restLength)
        let returning = armGesture == .none
        // Minimum-jerk easing gives zero velocity and acceleration at each end.
        // Joint rotation creates an arc; the fingers finish after the arm arrives.
        let enter = Self.gestureEase(age / (returning ? 1.2 : 1.45))
        let leave: CGFloat = returning ? 0 : Self.gestureEase((age - armDuration + 1.2) / 1.2)
        let leftActive = armGesture == .checkWatch
        let rightActive = !returning && armGesture != .checkWatch
        let fade = 1 - Self.gestureEase((age - (returning ? 1.2 : armDuration) + 0.12) / 0.12)
        let inactiveFade = 1 - Self.gestureEase((age - (returning ? 1.0 : 1.05)) / 0.2)
        leftOpacity = reduced ? 0 : (leftActive ? mix(fromLeftOpacity, 1, Self.gestureEase(age / 0.16)) : fromLeftOpacity * inactiveFade) * fade
        rightOpacity = reduced ? 0 : (rightActive ? mix(fromRightOpacity, 1, Self.gestureEase(age / 0.16)) : fromRightOpacity * inactiveFade) * fade
        let leftPeak = sourcePoint(338,425)
        let leftTarget = leftActive ? leftPeak : leftRest
        let leftRotations = armRotations(from: fromLeftJoints, shoulder: leftShoulder, peak: leftTarget,
            rest: leftRest, bend: -1, enter: enter, leave: leave, tuning: value)
        leftArm.apply(shoulder: leftShoulder, wrist: leftTarget, handAngle: nil,
                      posture: .closed, visibility: leftOpacity, showWatch: leftActive || fromLeftOpacity > 0,
                      bend: -1, rotations: leftRotations, tuning: value)
        var peak = rightRest
        var angle: CGFloat = .pi
        switch armGesture {
        case .salute:
            let temple = rig.scenePoint(CGPoint(x: 443, y: 139), positions: posedPositions)
            let tipLength = CGFloat(78 * value.handScale * 0.92)
            let heading = atan2(18.0, -70.0)
            peak = CGPoint(x: temple.x - cos(heading) * tipLength, y: temple.y - sin(heading) * tipLength)
            angle = heading - .pi / 2
        case .wave:
            // Two small wrist-led waves, with a quiet shoulder and bent elbow.
            let waving = Self.gestureEase((age - 1.0) / 0.25) * (1 - Self.gestureEase((age - 2.55) / 0.3))
            let swing = sin(max(0, age - 1.0) * 5.5) * waving
            peak = sourcePoint(566 + swing * 4, 208)
            angle = -0.10 + swing * 0.16
        case .openHand:
            peak = sourcePoint(520,445)
            angle = -1.05
        case .point:
            peak = sourcePoint(520,435)
            angle = -0.15
        case .checkWatch:
            // A one-handed watch check leaves the other arm relaxed.
            peak = rightRest
        default: break
        }
        if !rightActive { peak = rightRest }
        let rotations = armRotations(from: fromRightJoints, shoulder: rightShoulder, peak: peak,
            rest: rightRest, bend: rightBend, enter: enter, leave: leave, tuning: value)
        let following = rotations.0 + rotations.1 - .pi
        let wristSettle = Self.gestureEase((age - 0.3) / 0.9) * (1 - leave)
        let startAngle = angleMix(fromHandAngle, following, enter)
        handAngle = angleMix(startAngle, angle, wristSettle)
        rightArm.apply(shoulder: rightShoulder, wrist: peak, handAngle: handAngle,
                       posture: handPosture, visibility: rightOpacity, bend: rightBend, rotations: rotations, tuning: value)
        leftAmount.floatValue = Float(leftOpacity)
        rightAmount.floatValue = Float(rightOpacity)

        bodyAmount.floatValue = 1
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        updateCameraFraming(viewport: view.bounds.size)
    }

    /// Only viewport/layout or an explicit framing edit can change the camera.
    /// Arm positions, reaction changes, and playback time never enter this calculation.
    func updateCameraFraming(viewport: CGSize? = nil) {
        let bounds = viewport ?? view?.bounds.size ?? size
        guard bounds.width > 0, bounds.height > 0 else { return }
        let visibleHeight = min(540, 664 * bounds.height / bounds.width)
        let scale = max(1, CGFloat(tuning.sanitized.framingHeight) / visibleHeight)
        gestureCamera.setScale(scale)
        gestureCamera.position = CGPoint(x: 332, y: visibleHeight * scale / 2)
    }

    private func armRotations(from start: (CGFloat, CGFloat), shoulder: CGPoint, peak: CGPoint,
                              rest: CGPoint, bend: CGFloat, enter: CGFloat, leave: CGFloat,
                              tuning: CoachCharacterTuning) -> (CGFloat, CGFloat) {
        let goal = CoachArmSolution.solve(shoulder: shoulder, target: peak,
            upper: CGFloat(tuning.upperArmLength), forearm: CGFloat(tuning.forearmLength), bend: bend)
        let end = CoachArmSolution.solve(shoulder: shoulder, target: rest,
            upper: CGFloat(tuning.upperArmLength), forearm: CGFloat(tuning.forearmLength), bend: bend)
        // Flex the elbow while lifting, keeping the hand near the body. A
        // straight-arm sweep would take the hand far outside the card.
        func relativeAngle(_ solution: CoachArmSolution) -> CGFloat {
            atan2(sin(solution.forearmRotation - solution.upperRotation),
                  cos(solution.forearmRotation - solution.upperRotation))
        }
        let goalElbow = relativeAngle(goal), endElbow = relativeAngle(end)
        let sameBend = start.1 * goalElbow >= 0
        let returning = armGesture == .none
        let elbowEnter = sameBend && !returning ? Self.gestureEase(min(1, Double(enter) * 2.2)) : enter
        let sign: CGFloat = (armGesture == .none ? start.1 : goalElbow) < 0 ? -1 : 1
        let folding: CGFloat = sameBend && !returning ? (abs(goalElbow) < 2.3 ? 0.8 : 0.15) : 0
        let raisedElbow = min(2.9, max(-2.9, mix(start.1,goalElbow,elbowEnter) + sign * sin(enter * .pi) * folding))
        let age = max(0,elapsed - armStart)
        let upperEnter = returning ? enter : Self.gestureEase((age - 0.12) / 1.33)
        let upperLeave = leave
        let upper = angleMix(angleMix(start.0, goal.upperRotation, upperEnter), end.upperRotation, upperLeave)
        let relative = min(2.9, max(-2.9, mix(raisedElbow,endElbow,leave) + sign * sin(leave * .pi) * folding))
        return (upper,relative)
    }

    private static func gestureEase(_ value: Double) -> CGFloat {
        let t = CGFloat(min(1, max(0,value)))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    func setPreview(_ control: CoachPreviewControl?) {
        if let control {
            if previewControl?.joints != control.joints || previewControl?.grid != control.grid {
                previewOverlayDirty = true
            }
            if previewControl?.seekID != control.seekID || previewControl?.reaction.id != control.reaction.id || previewTuning != tuning {
                previewNeedsSeek = true
            }
            previewTuning = tuning
        } else {
            jointOverlay.isHidden = true
            gridOverlay.isHidden = true
        }
        previewControl = control
        updateCameraFraming()
    }

    private func resetPreview(to time: Double, control: CoachPreviewControl) {
        elapsed = 0
        lastUpdate = nil
        pose = RetroCoachPose()
        reaction = .idle
        reactionStart = 0
        armGesture = .none
        rightBend = -1
        armStart = -.infinity
        leftOpacity = 0; rightOpacity = 0
        fromLeftOpacity = 0; fromRightOpacity = 0
        handAngle = .pi; fromHandAngle = .pi
        nextBlink = 3.4; blinkStart = -.infinity
        nextLook = .infinity; lookFrom = 0; lookTo = 0
        reduceMotion = false
        thinking = control.thinking
        meetingActive = control.reaction.intent != .idle
        applyPose(pose)
        updateArms(reduced: true)
        perform(control.reaction)
        advanceAnimation(0)
        var clock: Double = 0
        let target = min(5, max(0, time))
        while clock < target - 0.000001 {
            clock = min(target, clock + 1.0 / 30)
            advanceAnimation(clock)
        }
    }

    private func updatePreview(_ control: CoachPreviewControl, wallClock: TimeInterval) {
        let delta = min(1.0 / 15, max(0, wallClock - (previewWallClock ?? wallClock)))
        previewWallClock = wallClock
        var advanced = false
        if previewNeedsSeek {
            previewNeedsSeek = false
            resetPreview(to: control.seekTime, control: control)
            advanced = true
        } else if control.playing {
            if elapsed + delta * control.speed >= 5 {
                resetPreview(to: 0, control: control)
            } else {
                advanceAnimation((lastUpdate ?? 0) + min(1.0 / 15, delta * control.speed))
            }
            advanced = true
        }
        guard advanced || previewOverlayDirty else { return }
        previewOverlayDirty = false
        updateDebugOverlays(control)
        let gap = articulatedArms.map { $0.maximumJointGap(in: self) }.max() ?? 0
        let reach = articulatedArms.filter { !$0.isHidden }.map {
            let distance = hypot($0.requestedTarget.x - $0.solution.shoulder.x, $0.requestedTarget.y - $0.solution.shoulder.y)
            return max(0, distance - CGFloat(tuning.upperArmLength + tuning.forearmLength - 0.1),
                       CGFloat(abs(tuning.upperArmLength - tuning.forearmLength) + 0.1) - distance)
        }.max() ?? 0
        onPreviewFrame?(elapsed, gap, reach)
    }

    private func updateDebugOverlays(_ control: CoachPreviewControl) {
        gridOverlay.isHidden = !control.grid
        if control.grid && gridOverlay.children.isEmpty {
            let path = CGMutablePath()
            for x in stride(from: 0, through: 664, by: 32) {
                path.move(to: CGPoint(x: x,y: 0)); path.addLine(to: CGPoint(x: x,y: 540))
            }
            for y in stride(from: 0, through: 540, by: 32) {
                path.move(to: CGPoint(x: 0,y: y)); path.addLine(to: CGPoint(x: 664,y: y))
            }
            let grid = SKShapeNode(path: path)
            grid.strokeColor = SKColor.white.withAlphaComponent(0.25)
            grid.lineWidth = 1
            gridOverlay.addChild(grid)
        }
        jointOverlay.isHidden = !control.joints
        guard control.joints else { return }
        jointOverlay.removeAllChildren()
        for arm in articulatedArms where !arm.isHidden {
            let points = [arm.solution.shoulder, arm.solution.elbow, arm.solution.wrist]
            let path = CGMutablePath()
            path.addLines(between: points)
            let bones = SKShapeNode(path: path)
            bones.strokeColor = .cyan
            bones.lineWidth = 3
            jointOverlay.addChild(bones)
            for (index, point) in points.enumerated() {
                let marker = SKShapeNode(circleOfRadius: 7)
                marker.fillColor = index == 2 ? .yellow : .cyan
                marker.strokeColor = .black
                marker.lineWidth = 2
                marker.position = point
                jointOverlay.addChild(marker)
                let label = SKLabelNode(fontNamed: "Menlo-Bold")
                label.text = ["S", "E", "W"][index]
                label.fontSize = 18
                label.fontColor = .white
                label.position = CGPoint(x: point.x + 15, y: point.y + 8)
                jointOverlay.addChild(label)
            }
            let targetPath = CGMutablePath()
            let target = arm.requestedTarget
            targetPath.move(to: CGPoint(x: target.x - 9,y: target.y)); targetPath.addLine(to: CGPoint(x: target.x + 9,y: target.y))
            targetPath.move(to: CGPoint(x: target.x,y: target.y - 9)); targetPath.addLine(to: CGPoint(x: target.x,y: target.y + 9))
            let targetMarker = SKShapeNode(path: targetPath)
            targetMarker.strokeColor = .orange
            targetMarker.lineWidth = 2
            jointOverlay.addChild(targetMarker)
        }
    }

    private func sourcePoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 540 - y) }
    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: mix(a.x,b.x,t), y: mix(a.y,b.y,t))
    }
    private func angleMix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + atan2(sin(b - a), cos(b - a)) * t
    }

    private static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
