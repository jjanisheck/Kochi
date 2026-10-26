import Foundation
import AVFoundation

/// Records a single AAC (`.m4a`) file that mixes the microphone ("Me") with the
/// captured system audio ("Them") so the saved recording has both sides of the
/// conversation.
///
/// The microphone is the master clock: every mic buffer is copied to a bounded
/// serial writer queue, keeping AAC encoding and disk IO off the realtime tap,
/// with whatever system audio has accumulated mixed on top (silence-filled if the
/// system stream is quiet/absent). This keeps the file aligned to real time
/// without needing to resample two independent capture clocks onto each other.
///
/// `appendMic(_:)` is called from the audio engine's input tap; `appendSystem(_:)`
/// from the ScreenCaptureKit sample queue. A lock guards the shared system FIFO.
nonisolated final class MixedAudioRecorder: @unchecked Sendable {
    /// The writer exclusively owns this copy after it leaves the tap.
    private struct OwnedBuffer: @unchecked Sendable { let buffer: AVAudioPCMBuffer }
    private var file: AVAudioFile?
    private var outputFormat: AVAudioFormat?

    private var micConverter: AVAudioConverter?
    private var micInputFormat: AVAudioFormat?
    private var systemConverter: AVAudioConverter?
    private var systemInputFormat: AVAudioFormat?

    /// Mono float samples of system audio awaiting mixing, with a read cursor so
    /// dequeuing is O(1) (the processed prefix is compacted periodically).
    private var systemFIFO: [Float] = []
    private var systemRead: Int = 0
    private let lock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.kochi.audio.writer", qos: .userInitiated)
    private var accepting = false
    private var pendingBuffers = 0
    private let maximumPendingBuffers = 256
    private var micPower: Float = -160
    var onFailure: (@Sendable (String) -> Void)?

    /// Most recent mic RMS power in dBFS, for the UI level meter (no AVAudioRecorder needed).
    var latestMicPowerDb: Float { lock.lock(); defer { lock.unlock() }; return micPower }

    // MARK: - Lifecycle

    func start(url: URL) throws {
        try writerQueue.sync {
            // Write AAC into an .m4a container.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let file = try AVAudioFile(forWriting: url, settings: settings)
            self.file = file
            self.outputFormat = file.processingFormat
            lock.lock(); accepting = true; lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        accepting = false
        lock.unlock()
        writerQueue.sync {
            file = nil // All previously accepted buffers drain before finalizing.
            outputFormat = nil
            systemFIFO.removeAll()
            systemRead = 0
            micConverter = nil; micInputFormat = nil
            systemConverter = nil; systemInputFormat = nil
        }
    }

    // MARK: - Inputs

    /// Master clock. Convert the mic buffer to the output format, mix in pending
    /// system audio, write, and update the meter level.
    func appendMic(_ buffer: AVAudioPCMBuffer) {
        let power = Self.powerDb(of: buffer)
        lock.lock(); micPower = power; lock.unlock()
        enqueue(buffer, microphone: true)
    }

    private func writeMic(_ buffer: AVAudioPCMBuffer) {

        guard let outFormat = outputFormat, let file = file,
              let mic = convert(buffer, to: outFormat,
                                converter: &micConverter, cachedFormat: &micInputFormat),
              let micData = mic.floatChannelData else { return }

        let n = Int(mic.frameLength)
        guard n > 0, let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(n)),
              let outData = out.floatChannelData else { return }
        out.frameLength = AVAudioFrameCount(n)

        for i in 0..<n {
            var sample = micData[0][i]
            if systemRead < systemFIFO.count {
                sample += systemFIFO[systemRead]
                systemRead += 1
            }
            // Clamp the summed signal to avoid clipping artifacts.
            outData[0][i] = max(-1, min(1, sample))
        }
        // Compact the FIFO once the consumed prefix grows large (~1s @ 48k).
        if systemRead > 48000 {
            systemFIFO.removeFirst(systemRead)
            systemRead = 0
        }

        do { try file.write(from: out) }
        catch { fail("Audio could not be saved: \(error.localizedDescription)") }
    }

    /// Convert system audio to the output format and enqueue its samples for mixing.
    func appendSystem(_ buffer: AVAudioPCMBuffer) {
        enqueue(buffer, microphone: false)
    }

    private func writeSystem(_ buffer: AVAudioPCMBuffer) {
        guard let outFormat = outputFormat,
              let sys = convert(buffer, to: outFormat,
                                converter: &systemConverter, cachedFormat: &systemInputFormat),
              let data = sys.floatChannelData else { return }
        let n = Int(sys.frameLength)
        guard n > 0 else { return }
        systemFIFO.append(contentsOf: UnsafeBufferPointer(start: data[0], count: n))
        // A stalled/disconnected mic must not accumulate unlimited far-side audio.
        if systemFIFO.count - systemRead > 96_000 {
            systemFIFO.removeFirst(systemFIFO.count - 96_000)
            systemRead = 0
        }
    }

    private func enqueue(_ buffer: AVAudioPCMBuffer, microphone: Bool) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        guard accepting else { lock.unlock(); return }
        guard pendingBuffers < maximumPendingBuffers else {
            lock.unlock()
            fail("Audio storage fell behind. Recording was stopped to protect the audio already saved.")
            return
        }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            lock.unlock(); fail("Not enough memory to buffer microphone audio."); return
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in source.indices {
            guard let from = source[index].mData, let to = destination[index].mData else { continue }
            memcpy(to, from, Int(source[index].mDataByteSize))
        }
        pendingBuffers += 1
        let owned = OwnedBuffer(buffer: copy)
        // Enqueue under the state lock so stop() cannot finalize ahead of an
        // accepted buffer whose producer was briefly descheduled.
        writerQueue.async {
            if microphone { self.writeMic(owned.buffer) } else { self.writeSystem(owned.buffer) }
            self.lock.lock(); self.pendingBuffers -= 1; self.lock.unlock()
        }
        lock.unlock()
    }

    private func fail(_ message: String) {
        lock.lock(); let shouldReport = accepting; accepting = false; lock.unlock()
        if shouldReport { onFailure?(message) }
    }

    /// Also used by the accelerated recorder verification to pace its producer.
    func flushPendingAudio() { writerQueue.sync {} }

    // MARK: - Helpers

    private func convert(_ buffer: AVAudioPCMBuffer, to outFormat: AVAudioFormat,
                         converter: inout AVAudioConverter?,
                         cachedFormat: inout AVAudioFormat?) -> AVAudioPCMBuffer? {
        let inFormat = buffer.format
        if inFormat == outFormat { return buffer }
        if converter == nil || cachedFormat == nil || !inFormat.isEqual(cachedFormat!) {
            converter = AVAudioConverter(from: inFormat, to: outFormat)
            cachedFormat = inFormat
        }
        guard let converter = converter, buffer.frameLength > 0 else { return nil }

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return nil }

        var fed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, inStatus in
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        if status == .error || err != nil { return nil }
        return out.frameLength > 0 ? out : nil
    }

    private static func powerDb(of buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
        let n = Int(buffer.frameLength)
        var sumSquares: Float = 0
        for i in 0..<n { let s = ch[0][i]; sumSquares += s * s }
        let rms = (sumSquares / Float(n)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
    }
}
