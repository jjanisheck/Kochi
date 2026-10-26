import SpriteKit
import ImageIO

/// A two-bone solution. Segment lengths stay fixed, including for unreachable targets.
struct CoachArmSolution {
    let shoulder: CGPoint
    let elbow: CGPoint
    let wrist: CGPoint
    let upperRotation: CGFloat
    let forearmRotation: CGFloat

    static func solve(shoulder: CGPoint, target: CGPoint, upper: CGFloat = 140,
                      forearm: CGFloat = 140, bend: CGFloat = -1) -> CoachArmSolution {
        let dx = target.x - shoulder.x, dy = target.y - shoulder.y
        let distance = max(0.001, hypot(dx, dy))
        let reach = min(upper + forearm - 0.1, max(abs(upper - forearm) + 0.1, distance))
        let direction = atan2(dy, dx)
        let cosine = min(1, max(-1, (upper * upper + reach * reach - forearm * forearm) / (2 * upper * reach)))
        let heading = direction + bend * acos(cosine)
        let elbow = CGPoint(x: shoulder.x + cos(heading) * upper, y: shoulder.y + sin(heading) * upper)
        let wrist = CGPoint(x: shoulder.x + cos(direction) * reach, y: shoulder.y + sin(direction) * reach)
        return CoachArmSolution(shoulder: shoulder, elbow: elbow, wrist: wrist,
            upperRotation: heading + .pi / 2,
            forearmRotation: atan2(wrist.y - elbow.y, wrist.x - elbow.x) + .pi / 2)
    }
}

struct CoachArmArtwork {
    struct Part {
        let texture: SKTexture
        let wristAnchor: CGFloat
    }
    let upper: Part
    let forearm: Part
    let open: Part
    let salute: Part
    let point: Part
    let closed: Part

    init?(folder: URL) {
        guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent("arm-parts.png") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let decoded = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard decoded else { return nil }
        func part(_ column: Int, _ row: Int) -> Part? {
            let x0 = column * w / 3, x1 = (column + 1) * w / 3
            let y0 = row * h / 2, y1 = (row + 1) * h / 2
            var left = x1, top = y1, right = x0, bottom = y0
            for y in y0..<y1 {
                for x in x0..<x1 where rgba[(y * w + x) * 4 + 3] > 220 {
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
            guard right > left, bottom > top,
                  let crop = image.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) else { return nil }
            // Find the wrist center at the base of each hand rather than assuming
            // that an asymmetrical thumb puts the wrist at the image's midpoint.
            var total: CGFloat = 0, count: CGFloat = 0
            for y in max(top, bottom - 12)...bottom {
                for x in left...right where rgba[(y * w + x) * 4 + 3] > 220 {
                    total += CGFloat(x - left); count += 1
                }
            }
            let texture = SKTexture(cgImage: crop)
            texture.filteringMode = .nearest
            return Part(texture: texture, wristAnchor: count > 0 ? total / count / CGFloat(right - left + 1) : 0.5)
        }
        guard let upper = part(0,0), let forearm = part(1,0), let open = part(2,0),
              let salute = part(0,1), let point = part(1,1), let closed = part(2,1) else { return nil }
        self.upper = upper; self.forearm = forearm; self.open = open
        self.salute = salute; self.point = point; self.closed = closed
    }
}

/// Every part inherits its parent's transform: shoulder → upper arm → elbow →
/// forearm → wrist → hand. One continuous sleeve contour covers both bones.
final class CoachArticulatedArm: SKNode {
    enum Hand { case open, salute, point, closed }
    let upperBone = SKNode()
    let elbowJoint = SKNode()
    let wristJoint = SKNode()
    private let handPivot = SKNode()
    private let sleeveContour = SKShapeNode()
    private let sleeveLight = SKShapeNode()
    private let sleeveShade = SKShapeNode()
    private let sleeveFold = SKShapeNode()
    private let sleeveOutline = SKShapeNode()
    private let cuff = SKSpriteNode(color: SKColor(white: 0.48, alpha: 1), size: .zero)
    private(set) var requestedTarget: CGPoint = .zero
    var renderedHandSize: CGSize { hand.size }
    private let hand = SKSpriteNode()
    private let watch = SKNode()
    private let art: CoachArmArtwork
    private let mirrorHand: Bool
    private(set) var solution = CoachArmSolution.solve(shoulder: .zero, target: CGPoint(x: 0, y: -279))
    private var currentHand: Hand?
    private let hardPixels = SKShader(source: """
        void main() {
            vec4 color = texture2D(u_texture, v_tex_coord);
            if (color.a < 0.72) discard;
            gl_FragColor = vec4(color.rgb / max(color.a, 0.01), 1.0) * v_color_mix.a;
        }
        """)

    init(art: CoachArmArtwork, mirrorHand: Bool) {
        self.art = art
        self.mirrorHand = mirrorHand
        super.init()
        addChild(upperBone)
        // The coat is one silhouette, so bending never exposes a floating
        // rectangular sleeve end or a dark seam through the middle of the elbow.
        for shape in [sleeveContour, sleeveLight, sleeveShade, sleeveFold, sleeveOutline] {
            shape.isAntialiased = false
            shape.strokeColor = .clear
            addChild(shape)
        }
        sleeveContour.fillColor = SKColor(white: 0.24, alpha: 1)
        sleeveOutline.strokeColor = SKColor(white: 0.055, alpha: 1)
        sleeveOutline.fillColor = .clear
        sleeveOutline.lineWidth = 8
        sleeveLight.fillColor = SKColor(white: 0.29, alpha: 1)
        sleeveShade.fillColor = SKColor(white: 0.18, alpha: 1)
        sleeveFold.strokeColor = SKColor(white: 0.12, alpha: 1)
        sleeveFold.lineWidth = 6
        upperBone.addChild(elbowJoint)
        elbowJoint.position = CGPoint(x: 0, y: -140)
        elbowJoint.zPosition = 2
        wristJoint.position = CGPoint(x: 0, y: -140)
        wristJoint.zPosition = 1
        elbowJoint.addChild(wristJoint)
        wristJoint.addChild(cuff)
        cuff.position.y = 12
        cuff.zPosition = 1
        handPivot.zPosition = 2
        wristJoint.addChild(handPivot)
        hand.shader = hardPixels
        handPivot.addChild(hand)
        handPivot.xScale = mirrorHand ? -1 : 1
        makeWatch()
        watch.position = CGPoint(x: 0, y: -118)
        watch.zPosition = 5
        elbowJoint.addChild(watch)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Build a tapered coat around the solved centerline. The elbow uses a
    /// shared miter, and the stepped contour uses the portrait's pixel scale.
    private func updateSleeve(width: CGFloat) {
        let s = CGPoint.zero
        let e = CGPoint(x: solution.elbow.x - position.x, y: solution.elbow.y - position.y)
        let w = CGPoint(x: solution.wrist.x - position.x, y: solution.wrist.y - position.y)
        func normal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            let length = max(1, hypot(b.x - a.x, b.y - a.y))
            return CGVector(dx: -(b.y - a.y) / length, dy: (b.x - a.x) / length)
        }
        func offset(_ point: CGPoint, _ direction: CGVector, _ distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + direction.dx * distance, y: point.y + direction.dy * distance)
        }
        func path(_ points: [CGPoint], close: Bool = true, rounded: Bool = true) -> CGPath {
            let path = CGMutablePath()
            var outline = points
            if rounded {
                outline = []
                for i in points.indices {
                    if !close && (i == 0 || i == points.count - 1) { outline.append(points[i]); continue }
                    let before = points[(i + points.count - 1) % points.count]
                    let corner = points[i], after = points[(i + 1) % points.count]
                    let a = hypot(before.x - corner.x, before.y - corner.y)
                    let b = hypot(after.x - corner.x, after.y - corner.y)
                    let radius = min(i == 1 || i == 4 ? 46 : 16, min(a,b) * 0.32)
                    let start = CGPoint(x: corner.x + (before.x - corner.x) * radius / max(1,a),
                                        y: corner.y + (before.y - corner.y) * radius / max(1,a))
                    let end = CGPoint(x: corner.x + (after.x - corner.x) * radius / max(1,b),
                                      y: corner.y + (after.y - corner.y) * radius / max(1,b))
                    for step in 0...5 {
                        let t = CGFloat(step) / 5, u = 1 - t
                        outline.append(CGPoint(x: u * u * start.x + 2 * u * t * corner.x + t * t * end.x,
                                               y: u * u * start.y + 2 * u * t * corner.y + t * t * end.y))
                    }
                }
            }
            path.addLines(between: outline.map { CGPoint(x: ($0.x / 4).rounded() * 4, y: ($0.y / 4).rounded() * 4) })
            if close { path.closeSubpath() }
            return path
        }
        let upper = normal(s,e), lower = normal(e,w)
        let sum = CGVector(dx: upper.dx + lower.dx, dy: upper.dy + lower.dy)
        let length = max(0.01, hypot(sum.dx,sum.dy))
        let miter = CGVector(dx: sum.dx / length, dy: sum.dy / length)
        let elbowRadius = min(62, 43 / max(0.65, miter.dx * upper.dx + miter.dy * upper.dy)) * width
        let left = [offset(s,upper,53 * width), offset(e,miter,elbowRadius), offset(w,lower,34 * width)]
        let right = [offset(w,lower,-34 * width), offset(e,miter,-elbowRadius), offset(s,upper,-53 * width)]
        sleeveContour.path = path(left + right)
        // Leave the shoulder edge open so it blends into the existing coat.
        sleeveOutline.path = path(left + right, close: false)
        sleeveLight.path = path([offset(s,upper,40 * width), offset(e,miter,elbowRadius - 10 * width),
            offset(w,lower,23 * width), offset(w,lower,7 * width), offset(e,miter,8 * width), offset(s,upper,9 * width)])
        sleeveShade.path = path([offset(s,upper,-43 * width), offset(e,miter,-elbowRadius + 8 * width),
            offset(w,lower,-27 * width), offset(w,lower,-11 * width), offset(e,miter,-17 * width), offset(s,upper,-22 * width)])
        sleeveFold.path = path([offset(e,upper,12 * width), offset(e,miter,-7 * width),
            offset(CGPoint(x: e.x * 0.87, y: e.y * 0.87),upper,-26 * width)], close: false, rounded: false)
        cuff.size = CGSize(width: 64 * width, height: 12)
    }

    func apply(shoulder: CGPoint, wrist: CGPoint, handAngle: CGFloat?, posture: Hand,
               visibility: CGFloat, showWatch: Bool = false, bend: CGFloat = -1, rotations: (CGFloat, CGFloat)? = nil, tuning: CoachCharacterTuning = .standard) {
        let value = tuning.sanitized
        let upperLength = CGFloat(value.upperArmLength), forearmLength = CGFloat(value.forearmLength)
        requestedTarget = wrist
        if let (upper, relativeElbow) = rotations {
            let elbow = CGPoint(x: shoulder.x + sin(upper) * upperLength, y: shoulder.y - cos(upper) * upperLength)
            let forearm = upper + relativeElbow
            let end = CGPoint(x: elbow.x + sin(forearm) * forearmLength, y: elbow.y - cos(forearm) * forearmLength)
            solution = CoachArmSolution(shoulder: shoulder, elbow: elbow, wrist: end,
                upperRotation: upper, forearmRotation: forearm)
        } else {
            solution = CoachArmSolution.solve(shoulder: shoulder, target: wrist, upper: upperLength, forearm: forearmLength, bend: bend)
        }
        position = shoulder
        upperBone.zRotation = solution.upperRotation
        elbowJoint.position.y = -upperLength
        elbowJoint.zRotation = solution.forearmRotation - solution.upperRotation
        wristJoint.position.y = -forearmLength
        handPivot.zRotation = (handAngle ?? (solution.forearmRotation - .pi)) - solution.forearmRotation
        updateSleeve(width: CGFloat(value.armWidth))
        watch.position.y = -forearmLength + 22
        alpha = visibility
        isHidden = visibility < 0.002
        watch.isHidden = !showWatch
        let part: CoachArmArtwork.Part
        let baseSize: CGSize
        switch posture {
        case .open: part = art.open; baseSize = CGSize(width: 64, height: 80)
        case .salute: part = art.salute; baseSize = CGSize(width: 40, height: 78)
        case .point: part = art.point; baseSize = CGSize(width: 50, height: 78)
        case .closed: part = art.closed; baseSize = CGSize(width: 52, height: 56)
        }
        if currentHand != posture {
            hand.texture = part.texture
            hand.anchorPoint = CGPoint(x: part.wristAnchor, y: 0.08)
            currentHand = posture
        }
        // Apply size even when only the workshop slider changes, keeping the
        // anatomical wrist anchor fixed as the hand grows.
        hand.size = CGSize(width: baseSize.width * value.handScale * value.handWidth,
                           height: baseSize.height * value.handScale)
    }

    func fingertip(in scene: SKScene) -> CGPoint {
        scene.convert(CGPoint(x: 0, y: hand.size.height * 0.92), from: handPivot)
    }

    var watchCenter: CGPoint {
        guard let scene else { return .zero }
        return scene.convert(watch.position, from: elbowJoint)
    }

    /// Screen-space endpoints are used in the regression tests, not just the IK equations.
    func maximumJointGap(in scene: SKScene) -> CGFloat {
        let upperEnd = scene.convert(elbowJoint.position, from: upperBone)
        let elbow = scene.convert(CGPoint.zero, from: elbowJoint)
        let forearmEnd = scene.convert(wristJoint.position, from: elbowJoint)
        let wrist = scene.convert(CGPoint.zero, from: wristJoint)
        let handRoot = scene.convert(CGPoint.zero, from: handPivot)
        return max(hypot(upperEnd.x - elbow.x, upperEnd.y - elbow.y),
                   hypot(forearmEnd.x - wrist.x, forearmEnd.y - wrist.y),
                   hypot(handRoot.x - wrist.x, handRoot.y - wrist.y))
    }

    private func makeWatch() {
        for (w,h,gray) in [(58.0,12.0,0.08),(30,26,0.08),(24,20,0.7),(17,13,0.22)] {
            watch.addChild(SKSpriteNode(color: SKColor(white: gray, alpha: 1), size: CGSize(width: w, height: h)))
        }
        let minute = SKSpriteNode(color: SKColor(white: 0.85, alpha: 1), size: CGSize(width: 3, height: 7))
        minute.position = CGPoint(x: 0, y: 2)
        watch.addChild(minute)
        let hour = SKSpriteNode(color: SKColor(white: 0.85, alpha: 1), size: CGSize(width: 6, height: 3))
        hour.position = CGPoint(x: 2, y: 0)
        watch.addChild(hour)
    }
}

/// A source-space silhouette protects ALL interior face/uniform pixels. A color
/// key is unsafe here: gray skin and camouflage share colors, and gaps in the
/// portrait outline would let a background flood-fill erase the character.
struct CoachBodyMask {
    static let outline: [[CGFloat]] = [
        [227,0],[402,0],[402,8],[436,8],[436,20],[455,20],[455,35],
        [474,35],[474,54],[489,54],[489,75],[501,75],[501,112],
        [484,112],[484,130],[472,130],[472,180],[479,180],[479,228],
        [463,228],[463,253],[445,253],[445,280],[427,280],[427,301],
        [407,301],[407,317],[444,317],[444,328],[485,328],[485,340],
        [537,340],[537,351],[581,351],[581,368],[615,368],[615,387],
        [638,387],[638,414],[656,414],[656,445],[664,445],[664,540],
        [0,540],[0,445],[5,445],[5,419],[15,419],[15,394],[28,394],
        [28,375],[57,375],[57,361],[96,361],[96,345],[140,345],
        [140,333],[195,333],[195,323],[231,323],[231,304],[226,290],
        [210,273],[204,251],[196,232],[189,232],[189,179],[200,179],
        [200,132],[182,132],[182,121],[161,121],[161,98],[158,98],
        [158,71],[172,71],[172,52],[188,52],[188,34],[205,34],[205,15],[227,15]
    ]

    static func path() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: outline.map { CGPoint(x: $0[0], y: 540 - $0[1]) })
        path.closeSubpath()
        return path
    }

    static func texture(image: CGImage) -> SKTexture? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }
        context.setAllowsAntialiasing(false)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(path())
        context.fillPath()
        guard let mask = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: mask)
        texture.filteringMode = .nearest
        return texture
    }
}
