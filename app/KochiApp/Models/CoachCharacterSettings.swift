import Foundation
import Combine

/// Shared by the live renderer and workshop. Units are pixels in the source portrait.
nonisolated struct CoachCharacterTuning: Codable, Equatable, Sendable {
    var handScale: Double = 1.7
    var handWidth: Double = 1
    var armWidth: Double = 1
    var upperArmLength: Double = 170
    var forearmLength: Double = 160
    var shoulderSpread: Double = 0
    var shoulderLift: Double = 0
    var breathAmplitude: Double = 14
    var breathPeriod: Double = 4.4
    var framingHeight: Double = 500

    static let standard = CoachCharacterTuning()

    init() {}

    enum CodingKeys: String, CodingKey {
        case handScale, handWidth, armWidth, upperArmLength, forearmLength
        case shoulderSpread, shoulderLift, breathAmplitude, breathPeriod, framingHeight
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        handScale = try values.decodeIfPresent(Double.self, forKey: .handScale) ?? 1.7
        handWidth = try values.decodeIfPresent(Double.self, forKey: .handWidth) ?? 1
        armWidth = try values.decodeIfPresent(Double.self, forKey: .armWidth) ?? 1
        upperArmLength = try values.decodeIfPresent(Double.self, forKey: .upperArmLength) ?? 170
        forearmLength = try values.decodeIfPresent(Double.self, forKey: .forearmLength) ?? 160
        shoulderSpread = try values.decodeIfPresent(Double.self, forKey: .shoulderSpread) ?? 0
        shoulderLift = try values.decodeIfPresent(Double.self, forKey: .shoulderLift) ?? 0
        breathAmplitude = try values.decodeIfPresent(Double.self, forKey: .breathAmplitude) ?? 14
        breathPeriod = try values.decodeIfPresent(Double.self, forKey: .breathPeriod) ?? 4.4
        framingHeight = try values.decodeIfPresent(Double.self, forKey: .framingHeight) ?? 500
        self = sanitized
    }

    var sanitized: CoachCharacterTuning {
        var value = self
        func bound(_ number: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
            number.isFinite ? min(upper, max(lower, number)) : fallback
        }
        value.handScale = bound(handScale, 0.8, 3, 1.7)
        value.handWidth = bound(handWidth, 0.65, 1.6, 1)
        value.armWidth = bound(armWidth, 0.65, 1.6, 1)
        value.upperArmLength = bound(upperArmLength, 110, 210, 170)
        value.forearmLength = bound(forearmLength, 110, 210, 160)
        value.shoulderSpread = bound(shoulderSpread, -30, 30, 0)
        value.shoulderLift = bound(shoulderLift, -20, 20, 0)
        value.breathAmplitude = bound(breathAmplitude, 0, 24, 14)
        value.breathPeriod = bound(breathPeriod, 2.5, 8, 4.4)
        value.framingHeight = bound(framingHeight, 440, 540, 500)
        return value
    }

    func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(sanitized)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

@MainActor
final class CoachCharacterSettings: ObservableObject {
    static let shared = CoachCharacterSettings()
    @Published private(set) var tuning: CoachCharacterTuning
    private let defaults: UserDefaults
    private let key = "coachCharacterTuning.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode(CoachCharacterTuning.self, from: data) {
            tuning = stored.sanitized
        } else {
            tuning = .standard
        }
    }

    func apply(_ value: CoachCharacterTuning) {
        tuning = value.sanitized
        if let data = try? JSONEncoder().encode(tuning) { defaults.set(data, forKey: key) }
    }
}

nonisolated struct CoachPreviewControl: Equatable {
    var reaction: CoachReaction
    var thinking = false
    var seekID = UUID()
    var seekTime: Double = 1.4
    var playing = false
    var speed: Double = 1
    var joints = true
    var grid = false
}
