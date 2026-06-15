import Foundation

/// Manages meeting folder structure and real-time transcript file writing
/// Guarantees all spoken words are captured to disk immediately, crash-safe
class MeetingFileManager {

    // MARK: - Meeting Folder Structure
    private let meetingsRootURL: URL
    var currentMeetingURL: URL?
    private var transcriptFileHandle: FileHandle?
    private var lastWrittenLength = 0

    // Timestamp tracking
    private var currentTimeChunk = 0  // Current 15-second chunk (0, 1, 2, ...)
    private let chunkDuration = 15.0  // 15 seconds per chunk

    // File names
    private let transcriptFileName = "transcript.txt"
    private let metadataFileName = "metadata.json"
    private let audioFileName = "audio.m4a"

    init() {
        // Create root Meetings folder in Documents
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        meetingsRootURL = documentsURL.appendingPathComponent("Meetings")

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

            // Open file handle for appending
            transcriptFileHandle = try FileHandle(forWritingTo: transcriptURL)
            lastWrittenLength = 0
            currentTimeChunk = 0

            // Write initial timestamp header (00:00 - 00:15)
            let initialHeader = "00:00 - 00:15 "
            if let headerData = initialHeader.data(using: .utf8) {
                try? headerData.write(to: transcriptURL)
            }

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

    /// Appends new transcript text to the file (crash-safe, immediate write)
    /// Only writes NEW text that hasn't been written before
    /// Adds timestamp headers every 15 seconds
    func appendToTranscript(_ fullTranscript: String, currentTime: TimeInterval) {
        guard let fileHandle = transcriptFileHandle else {
            // Silent return - late-arriving transcripts after meeting ends are expected
            return
        }

        // Check if we've crossed into a new time chunk
        let newChunk = Int(currentTime / chunkDuration)
        if newChunk > currentTimeChunk {
            // Write timestamp header for new chunk
            let startTime = formatTime(Double(newChunk) * chunkDuration)
            let endTime = formatTime(Double(newChunk + 1) * chunkDuration)
            let header = "\n\(startTime) - \(endTime) "

            if let headerData = header.data(using: .utf8) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(headerData)
                try? fileHandle.synchronize()
                print("⏱️ New time chunk: \(startTime) - \(endTime)")
            }

            currentTimeChunk = newChunk
        }

        // Only write NEW text (avoid duplicates)
        guard fullTranscript.count > lastWrittenLength else {
            return // No new text to write
        }

        // Extract only the new portion
        let startIndex = fullTranscript.index(fullTranscript.startIndex, offsetBy: lastWrittenLength)
        let newText = String(fullTranscript[startIndex...])

        guard !newText.isEmpty else { return }

        // Write to disk immediately
        if let data = newText.data(using: .utf8) {
            do {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)

                // Force sync to disk (crash-safe)
                if #available(iOS 13.0, *) {
                    try fileHandle.synchronize()
                }

                lastWrittenLength = fullTranscript.count
                print("💾 Wrote \(newText.count) chars to transcript (total: \(lastWrittenLength))")

            } catch {
                print("❌ Failed to write transcript: \(error)")
            }
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

        // Close file handle
        if #available(iOS 13.0, *) {
            try? transcriptFileHandle?.close()
        } else {
            transcriptFileHandle?.closeFile()
        }
        transcriptFileHandle = nil

        // Update metadata with end time
        updateMetadata(endTime: Date(), duration: duration, transcriptLength: finalTranscript.count)

        print("🏁 Meeting ended. Final transcript: \(finalTranscript.count) chars")
        print("📁 Saved to: \(currentMeetingURL?.path ?? "unknown")")

        currentMeetingURL = nil
        lastWrittenLength = 0
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

    // MARK: - Metadata Management

    private func writeMetadata(startTime: Date) {
        guard let meetingURL = currentMeetingURL else { return }

        let deviceName = Host.current().localizedName ?? "Mac"

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
