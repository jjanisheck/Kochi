import Foundation
import Darwin

/// Local, bounded diagnostic events. Never includes transcript text or audio.
/// A marker survives an unexpected exit; it is evidence of an unfinished session,
/// not proof of a crash (force quitting or installing an update can do that too).
nonisolated final class RecordingDiagnostics: @unchecked Sendable {
    static let shared = RecordingDiagnostics()
    private let queue = DispatchQueue(label: "com.kochi.recording.diagnostics", qos: .utility)
    private let root: URL
    private var logURL: URL?
    private var audioURL: URL?
    private var started: TimeInterval = 0
    private let maxLogBytes = 1_048_576

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecordingDiagnostics", isDirectory: true)
        queue.sync {
            try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            if let marker = try? Data(contentsOf: self.root.appendingPathComponent("active.json")),
               let value = try? JSONSerialization.jsonObject(with: marker) as? [String: String],
               let path = value["log"] {
                self.logURL = URL(fileURLWithPath: path)
                self.started = ProcessInfo.processInfo.systemUptime
                self.write("previous_session_unfinished", ["note": "The last recording did not finish normally. This alone does not identify why."])
                self.logURL = nil
                try? FileManager.default.removeItem(at: self.root.appendingPathComponent("active.json"))
            }
        }
    }

    func start(meetingFolder: URL, audioURL: URL) {
        queue.async {
            self.logURL = meetingFolder.appendingPathComponent("recording-diagnostics.jsonl")
            self.audioURL = audioURL
            self.started = ProcessInfo.processInfo.systemUptime
            let value = ["log": self.logURL!.path]
            if let data = try? JSONSerialization.data(withJSONObject: value) {
                try? data.write(to: self.root.appendingPathComponent("active.json"), options: .atomic)
                try? data.write(to: self.root.appendingPathComponent("latest.json"), options: .atomic)
            }
            self.write("recording_started", [
                "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "sampleRate": 48_000, "channels": 1, "bitRate": 64_000
            ])
        }
    }

    func event(_ name: String, _ fields: [String: String] = [:]) {
        queue.async { self.write(name, fields) }
    }

    func sample(seconds: TimeInterval, transcriptCharacters: Int, bufferGap: TimeInterval) {
        queue.async {
            self.write("heartbeat", ["meetingSeconds": seconds, "transcriptCharacters": transcriptCharacters,
                                      "secondsSinceAudioBuffer": bufferGap])
        }
    }

    func finish(seconds: TimeInterval, reason: String = "user_stopped") {
        queue.async {
            self.write("recording_finished", ["meetingSeconds": seconds, "reason": reason])
            try? FileManager.default.removeItem(at: self.root.appendingPathComponent("active.json"))
            self.logURL = nil
            self.audioURL = nil
        }
    }

    private func write(_ event: String, _ fields: [String: Any]) {
        guard let logURL else { return }
        var packet = fields
        packet["event"] = event
        packet["time"] = ISO8601DateFormatter().string(from: Date())
        packet["elapsedSeconds"] = max(0, ProcessInfo.processInfo.systemUptime - started)
        packet["memoryMB"] = Self.residentMemoryMB
        packet["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        packet["freeDiskMB"] = Self.availableDiskBytes(at: logURL.deletingLastPathComponent()).map { $0 / 1_000_000 }
        if let audioURL {
            packet["audioBytes"] = Self.fileBytes(at: audioURL)
        }
        guard var data = try? JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys]) else { return }
        data.append(10)
        do {
            let size = Self.fileBytes(at: logURL) ?? 0
            if size >= maxLogBytes {
                let previous = logURL.deletingPathExtension().appendingPathExtension("previous.jsonl")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: logURL, to: previous)
            }
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { print("Recording diagnostic write failed: \(error.localizedDescription)") }
    }

    func exportReport() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let data = try? Data(contentsOf: self.root.appendingPathComponent("latest.json")),
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let path = value["log"] else { continuation.resume(returning: nil); return }
                let source = URL(fileURLWithPath: path)
                var report = Data("Kochi recording diagnostics — no transcript or audio included.\n".utf8)
                for url in [source.deletingPathExtension().appendingPathExtension("previous.jsonl"), source] {
                    if let events = try? Data(contentsOf: url) { report.append(events) }
                }
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Kochi-recording-diagnostics.txt")
                do { try report.write(to: destination, options: .atomic); continuation.resume(returning: destination) }
                catch { continuation.resume(returning: nil) }
            }
        }
    }

    static var residentMemoryMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    static func availableDiskBytes(at url: URL) -> Int64? {
        ((try? FileManager.default.attributesOfFileSystem(forPath: url.path))?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    static func fileBytes(at url: URL) -> Int64? {
        // URL resource values can cache sizes for the life of a URL. Recording
        // heartbeats and log rotation need a fresh stat of a growing file.
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }
}

/// Tap callbacks update only this small lock-protected clock, rather than adding
/// dozens of closures per second to the UI queue during long meetings.
nonisolated final class RecordingCaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var lastBuffer: TimeInterval = ProcessInfo.processInfo.systemUptime
    func markBuffer() { lock.lock(); lastBuffer = ProcessInfo.processInfo.systemUptime; lock.unlock() }
    var gap: TimeInterval { lock.lock(); defer { lock.unlock() }; return max(0, ProcessInfo.processInfo.systemUptime - lastBuffer) }
}
