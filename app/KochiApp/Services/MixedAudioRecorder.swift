import Foundation
import AVFoundation

/// Records a single AAC (`.m4a`) file that mixes the microphone ("Me") with the
/// captured system audio ("Them") so the saved recording has both sides of the
/// conversation.
///
/// The microphone is the master clock: every mic buffer is written immediately,
/// with whatever system audio has accumulated mixed on top (silence-filled if the
/// system stream is quiet/absent). This keeps the file aligned to real time
/// without needing to resample two independent capture clocks onto each other.
///
/// `appendMic(_:)` is called from the audio engine's input tap; `appendSystem(_:)`
/// from the ScreenCaptureKit sample queue. A lock guards the shared system FIFO.
final class MixedAudioRecorder {
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

    /// Most recent mic RMS power in dBFS, for the UI level meter (no AVAudioRecorder needed).
    private(set) var latestMicPowerDb: Float = -160

    // MARK: - Lifecycle

    func start(url: URL) {
        do {
            // Write AAC into an .m4a container.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let file = try AVAudioFile(forWriting: url, settings: settings)
            self.file = file
            self.outputFormat = file.processingFormat
        } catch {
            print("❌ MixedAudioRecorder: failed to open \(url.lastPathComponent): \(error)")
        }
    }

    func stop() {
        lock.lock()
        file = nil            // releasing the AVAudioFile finalizes the .m4a
        systemFIFO.removeAll()
        systemRead = 0
        lock.unlock()
    }

    // MARK: - Inputs

    /// Master clock. Convert the mic buffer to the output format, mix in pending
    /// system audio, write, and update the meter level.
    func appendMic(_ buffer: AVAudioPCMBuffer) {
        latestMicPowerDb = Self.powerDb(of: buffer)

        guard let outFormat = outputFormat, let file = file,
              let mic = convert(buffer, to: outFormat,
                                converter: &micConverter, cachedFormat: &micInputFormat),
              let micData = mic.floatChannelData else { return }

        let n = Int(mic.frameLength)
        guard n > 0, let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(n)),
              let outData = out.floatChannelData else { return }
        out.frameLength = AVAudioFrameCount(n)

        lock.lock()
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
        lock.unlock()

        do { try file.write(from: out) }
        catch { print("⚠️ MixedAudioRecorder write failed: \(error)") }
    }

    /// Convert system audio to the output format and enqueue its samples for mixing.
    func appendSystem(_ buffer: AVAudioPCMBuffer) {
        guard let outFormat = outputFormat,
              let sys = convert(buffer, to: outFormat,
                                converter: &systemConverter, cachedFormat: &systemInputFormat),
              let data = sys.floatChannelData else { return }
        let n = Int(sys.frameLength)
        guard n > 0 else { return }
        lock.lock()
        systemFIFO.append(contentsOf: UnsafeBufferPointer(start: data[0], count: n))
        lock.unlock()
    }

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
