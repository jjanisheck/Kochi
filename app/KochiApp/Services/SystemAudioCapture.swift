import Foundation
import AVFoundation
import ScreenCaptureKit

/// Captures system audio output (the far side of a video call) using
/// ScreenCaptureKit. Requires the user to grant Screen Recording permission.
/// Excludes our own process audio so the coaching videos aren't transcribed.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.kochi.systemaudio.samples")

    func start(completion: @escaping (Bool, Error?) -> Void) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false
                )
                guard let display = content.displays.first else {
                    completion(false, NSError(domain: "SystemAudioCapture", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No display available for capture"]))
                    return
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true  // don't capture Kochi's own audio
                config.sampleRate = 48000
                config.channelCount = 1
                // SCStream still expects a video config; keep it minimal.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                self.stream = stream
                try await stream.startCapture()
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("⚠️ System audio stream stopped: \(error.localizedDescription)")
    }

    // MARK: - Conversion

    /// Convert a ScreenCaptureKit audio CMSampleBuffer into an AVAudioPCMBuffer.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else { return nil }

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            return nil
        }
        pcm.frameLength = AVAudioFrameCount(frames)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        )
        guard status == noErr else { return nil }
        return pcm
    }
}
