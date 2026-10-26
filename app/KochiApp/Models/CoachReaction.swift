import Foundation
import FoundationModels

/// The model directs a performance; it never generates frames or arbitrary animation code.
@Generable
enum CoachIntent: String, Codable, CaseIterable, Sendable {
    case idle, listen, thinking, prompt, goal, focus, pause, timing, mute, check, steady, wrap

    var videoLabel: VideoLabel { VideoLabel(rawValue: rawValue) ?? .focus }
}

@Generable
enum CoachExpression: String, Codable, CaseIterable, Sendable {
    case neutral, attentive, thoughtful, encouraging, pleased, concerned
    case relieved, amused, uncertain, firm
}

@Generable
enum CoachGesture: String, Codable, Sendable {
    case none, nod, tilt, salute, openHand, checkWatch, breathe, wave, point
    case acknowledge, agree, disagree, shrug, talk, sigh, celebrate

    /// The portrait renderer retains its small vocabulary; the browser workshop
    /// uses the semantic gesture directly to select a matching imported clip.
    var portraitGesture: CoachGesture {
        switch self {
        case .acknowledge, .agree, .celebrate: return .nod
        case .disagree: return .tilt
        case .shrug, .talk: return .openHand
        case .sigh: return .breathe
        default: return self
        }
    }
}

@Generable
struct CoachingDirective {
    @Guide(description: "The most useful coaching action supported by the recent conversation. Use listen when no intervention is needed. Goal celebrations are triggered by the app, never choose goal just for positive wording.")
    var intent: CoachIntent
    var expression: CoachExpression
    @Guide(description: "Choose none for quiet listening. Acknowledge recognizes a useful contribution; agree is a gentle yes; disagree is a considered correction. Talk or openHand explains a suggestion; point refocuses; shrug expresses uncertainty; sigh releases tension; celebrate gives restrained encouragement; checkWatch marks time; wave signs off. Use relieved, amused, uncertain, or firm only when that describes YOUR coaching response, never an emotion inferred about a participant. Salute is reserved for app-verified achievements.")
    var gesture: CoachGesture
    @Guide(description: "Subtle performance intensity", .range(0.2...0.8))
    var intensity: Double
    @Guide(description: "ONE useful coaching sentence, at most 15 words. Do not infer emotions or speaking balance without evidence.")
    var caption: String
}

#if DEBUG && (os(macOS) || targetEnvironment(simulator))
/// Development-only, loopback-only handoff to the browser character workshop.
/// A service handshake and the workshop's Live coach switch must both be on.
@MainActor
final class CoachWorkshopBridge {
    static let shared = CoachWorkshopBridge()
    private let sessionID = UUID().uuidString
    private var sequence = 0
    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func publish(_ reaction: CoachReaction, completion: ((Bool) -> Void)? = nil) {
        task?.cancel()
        sequence += 1
        let packet: [String: Any] = [
            "intent": reaction.intent.rawValue,
            "expression": reaction.expression.rawValue,
            "gesture": reaction.gesture.rawValue,
            "intensity": reaction.intensity,
            "caption": reaction.caption,
            "verifiedGoal": reaction.intent == .goal,
            "source": "app", "sessionId": sessionID,
            "sequence": sequence, "eventId": "\(sessionID):\(sequence)"
        ]
        task = Task { [session] in
            do {
                let (statusData, statusResponse) = try await session.data(from: URL(string: "http://127.0.0.1:4173/api/coach-status")!)
                guard !Task.isCancelled,
                      (statusResponse as? HTTPURLResponse)?.statusCode == 200,
                      let status = try JSONSerialization.jsonObject(with: statusData) as? [String: Any],
                      status["service"] as? String == "kochi-character-workshop",
                      status["live"] as? Bool == true else { completion?(false); return }
                var request = URLRequest(url: URL(string: "http://127.0.0.1:4173/api/react")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: packet)
                let (_, response) = try await session.data(for: request)
                completion?((response as? HTTPURLResponse)?.statusCode == 200)
            } catch {
                // The workshop is optional. Closing it never affects coaching.
                completion?(false)
            }
        }
    }
}
#endif

nonisolated struct CoachReaction: Equatable, Sendable, Identifiable {
    let id: UUID
    let intent: CoachIntent
    let expression: CoachExpression
    let gesture: CoachGesture
    let intensity: Double
    let caption: String

    init(intent: CoachIntent, expression: CoachExpression = .attentive,
         gesture: CoachGesture = .none, intensity: Double = 0.4, caption: String = "") {
        id = UUID()
        self.intent = intent
        self.expression = expression
        self.gesture = gesture
        self.intensity = intensity.isFinite ? min(1, max(0, intensity)) : 0.4
        self.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Goal achievement is an app event, never a model's interpretation of a compliment.
    init(directive: CoachingDirective) {
        self.init(intent: directive.intent == .goal ? .steady : directive.intent,
                  expression: directive.expression,
                  gesture: directive.gesture == .salute ? .nod : directive.gesture,
                  intensity: directive.intensity,
                  caption: directive.caption)
    }

    static let idle = CoachReaction(intent: .idle, expression: .neutral, caption: "Ready when you are.")
    static let listening = CoachReaction(intent: .listen, caption: "I'm listening. Stay present.")
    static let achievement = CoachReaction(intent: .goal, expression: .pleased,
        gesture: .salute, intensity: 0.75, caption: "Goal achieved. Well done!")

    static func fallback(goals: [Goal]) -> CoachReaction {
        let completed = goals.filter(\.isCompleted).count
        return CoachReaction(intent: completed > 0 ? .steady : .listen,
                             expression: completed > 0 ? .encouraging : .attentive,
                             gesture: completed > 0 ? .nod : .none,
                             caption: completed > 0 ? "Good progress. Keep your remaining goals in mind." : "Listen closely and keep your goals in mind.")
    }
}

/// Small deterministic policy, shared by the renderer and tests. All times use a monotonic clock.
struct CoachPerformance {
    private(set) var reaction: CoachReaction = .idle
    private(set) var startedAt: TimeInterval = 0
    private(set) var lastGestureAt: TimeInterval = -.infinity
    private(set) var isMeetingActive = false

    var duration: TimeInterval { reaction.intent == .goal ? 3.2 : 4.0 }

    mutating func setMeetingActive(_ active: Bool, at time: TimeInterval) {
        isMeetingActive = active
        reaction = active ? .listening : .idle
        startedAt = time
        lastGestureAt = -.infinity
    }

    @discardableResult
    mutating func receive(_ next: CoachReaction, at time: TimeInterval) -> Bool {
        guard isMeetingActive || next.intent == .idle else { return false }
        // Let a verified achievement finish before accepting routine advice or duplicate events.
        guard reaction.intent != .goal || time - startedAt >= duration else { return false }
        let suppressGesture = next.gesture != .none && time - lastGestureAt < 6 && next.intent != .goal
        reaction = suppressGesture
            ? CoachReaction(intent: next.intent, expression: next.expression, intensity: next.intensity, caption: next.caption)
            : next
        startedAt = time
        if reaction.gesture != .none { lastGestureAt = time }
        return true
    }

    func isPerforming(at time: TimeInterval) -> Bool { time - startedAt < duration }
}
