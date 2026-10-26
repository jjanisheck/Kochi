import Foundation
#if os(iOS)
import UIKit
#endif

/// Manages meeting folder structure and real-time transcript file writing
/// Checkpoints the current transcript atomically off the UI thread.
nonisolated final class MeetingFileManager: @unchecked Sendable {

    // MARK: - Meeting Folder Structure
    private let meetingsRootURL: URL
    var currentMeetingURL: URL?
    private let transcriptQueue = DispatchQueue(label: "com.kochi.transcript.checkpoint", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingTranscript: (text: String, time: TimeInterval, url: URL)?
    private var checkpointWork: DispatchWorkItem?

    // File names
    private let transcriptFileName = "transcript.txt"
    private let metadataFileName = "metadata.json"
    private let audioFileName = "audio.m4a"
    private let analysisFileName = "analysis.md"

    init(rootURL: URL? = nil) {
        // Create root Meetings folder in Documents
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        meetingsRootURL = rootURL ?? documentsURL.appendingPathComponent("Meetings")

        // Ensure root folder exists
        try? FileManager.default.createDirectory(at: meetingsRootURL, withIntermediateDirectories: true)
        print("📁 Meetings root: \(meetingsRootURL.path)")
    }

    // MARK: - Meeting Lifecycle

    /// Creates a new meeting folder with timestamp-based name
    /// Returns: URL to the meeting folder
    func startNewMeeting() -> URL? {
        // Create meeting folder: meeting_2025-01-12_14-30-45
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let meetingFolderName = "meeting_\(timestamp)"

        let meetingURL = meetingsRootURL.appendingPathComponent(meetingFolderName)

        do {
            try FileManager.default.createDirectory(at: meetingURL, withIntermediateDirectories: true)
            currentMeetingURL = meetingURL

            // Create empty transcript file
            let transcriptURL = meetingURL.appendingPathComponent(transcriptFileName)
            FileManager.default.createFile(atPath: transcriptURL.path, contents: nil)

            // Write metadata
            writeMetadata(startTime: Date())

            print("✅ Meeting folder created: \(meetingURL.path)")
            print("📝 Transcript file: \(transcriptURL.path)")

            return meetingURL
        } catch {
            print("❌ Failed to create meeting folder: \(error)")
            return nil
        }
    }

    /// Coalesce volatile speech corrections into one atomic snapshot per second.
    /// Only the newest pending value is retained; disk work cannot queue the entire
    /// growing meeting on the main thread. Final stop flushes without waiting.
    func appendToTranscript(_ fullTranscript: String, currentTime: TimeInterval) {
        guard let folder = currentMeetingURL else { return }
        pendingLock.lock()
        pendingTranscript = (fullTranscript, currentTime, folder.appendingPathComponent(transcriptFileName))
        if checkpointWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.flushTranscriptCheckpoint() }
            checkpointWork = work
            transcriptQueue.asyncAfter(deadline: .now() + 1, execute: work)
        }
        pendingLock.unlock()
    }

    private func flushTranscriptCheckpoint() {
        pendingLock.lock()
        let snapshot = pendingTranscript
        pendingTranscript = nil
        checkpointWork = nil
        pendingLock.unlock()
        guard let snapshot else { return }
        let document = "00:00 - \(formatTime(snapshot.time))\n\(snapshot.text)"
        do { try Data(document.utf8).write(to: snapshot.url, options: .atomic) }
        catch {
            RecordingDiagnostics.shared.event("transcript_checkpoint_failed", ["error": error.localizedDescription])
        }
    }

    /// Formats time interval as MM:SS
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Closes the current meeting and finalizes files
    func endMeeting(finalTranscript: String, duration: TimeInterval) {
        // Write any remaining text (with final timestamp)
        appendToTranscript(finalTranscript, currentTime: duration)

        pendingLock.lock()
        checkpointWork?.cancel()
        pendingLock.unlock()
        transcriptQueue.sync { flushTranscriptCheckpoint() }

        // Update metadata with end time
        updateMetadata(endTime: Date(), duration: duration, transcriptLength: finalTranscript.count)

        print("🏁 Meeting ended. Final transcript: \(finalTranscript.count) chars")
        print("📁 Saved to: \(currentMeetingURL?.path ?? "unknown")")

        currentMeetingURL = nil
    }

    // MARK: - Audio File Management

    /// Returns the URL where the audio recording should be saved
    func getAudioFileURL() -> URL? {
        guard let meetingURL = currentMeetingURL else { return nil }
        return meetingURL.appendingPathComponent(audioFileName)
    }

    /// Resolves the audio file URL for a saved meeting folder, if the file exists.
    func audioURL(forFolderName name: String) -> URL? {
        let url = meetingsRootURL.appendingPathComponent(name).appendingPathComponent(audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes the AI analysis as `analysis.md` into the meeting's folder, creating
    /// the folder if it doesn't exist yet. `folderName` is the meeting's existing
    /// folder (its `audioFolderName`); when nil, a folder name is derived from
    /// `startTime` so a file is still saved for meetings that never recorded audio.
    /// Returns the folder name used, or nil on failure.
    @discardableResult
    func writeAnalysisMarkdown(_ markdown: String, folderName: String?, startTime: Date) -> String? {
        let name = folderName ?? Self.meetingFolderName(for: startTime)
        let folderURL = meetingsRootURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let url = folderURL.appendingPathComponent(analysisFileName)
            try markdown.data(using: .utf8)?.write(to: url)
            print("\u{2728} Analysis written: \(url.path)")
            return name
        } catch {
            print("\u{274C} Failed to write analysis.md: \(error)")
            return nil
        }
    }

    /// The `meeting_yyyy-MM-dd_HH-mm-ss` folder name for a date (matches startNewMeeting()).
    static func meetingFolderName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "meeting_\(f.string(from: date))"
    }

    // MARK: - Metadata Management

    private func writeMetadata(startTime: Date) {
        guard let meetingURL = currentMeetingURL else { return }

        #if os(macOS)
        let deviceName = Host.current().localizedName ?? "Mac"
        #else
        let deviceName = ProcessInfo.processInfo.hostName
        #endif

        let metadata: [String: Any] = [
            "startTime": ISO8601DateFormatter().string(from: startTime),
            "version": "1.0",
            "device": deviceName
        ]

        let metadataURL = meetingURL.appendingPathComponent(metadataFileName)
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            try? data.write(to: metadataURL)
        }
    }

    private func updateMetadata(endTime: Date, duration: TimeInterval, transcriptLength: Int) {
        guard let meetingURL = currentMeetingURL else { return }

        let metadataURL = meetingURL.appendingPathComponent(metadataFileName)

        // Read existing metadata
        var metadata: [String: Any] = [:]
        if let data = try? Data(contentsOf: metadataURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = existing
        }

        // Update with end information
        metadata["endTime"] = ISO8601DateFormatter().string(from: endTime)
        metadata["durationSeconds"] = duration
        metadata["transcriptCharacters"] = transcriptLength

        // Write back
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            try? data.write(to: metadataURL)
        }
    }

    // MARK: - Meeting History

    /// Lists all meeting folders (newest first)
    func getAllMeetings() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: meetingsRootURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        // Sort by creation date (newest first)
        return contents.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
    }

    /// Replaces a meeting's transcript file with a refined version (e.g. the
    /// higher-accuracy on-device re-transcription of the saved audio).
    func overwriteTranscript(_ text: String, at meetingURL: URL) {
        let transcriptURL = meetingURL.appendingPathComponent(transcriptFileName)
        do {
            try text.data(using: .utf8)?.write(to: transcriptURL)
            print("✨ Refined transcript written: \(text.count) chars → \(transcriptURL.lastPathComponent)")
        } catch {
            print("❌ Failed to write refined transcript: \(error)")
        }
    }

    /// Reads the transcript from a meeting folder
    func readTranscript(from meetingURL: URL) -> String? {
        let transcriptURL = meetingURL.appendingPathComponent(transcriptFileName)
        return try? String(contentsOf: transcriptURL, encoding: .utf8)
    }

    /// Reads metadata from a meeting folder
    func readMetadata(from meetingURL: URL) -> [String: Any]? {
        let metadataURL = meetingURL.appendingPathComponent(metadataFileName)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Deletes a meeting folder completely
    func deleteMeeting(at meetingURL: URL) {
        try? FileManager.default.removeItem(at: meetingURL)
        print("🗑️ Deleted meeting: \(meetingURL.lastPathComponent)")
    }
}
