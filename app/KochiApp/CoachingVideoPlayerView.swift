//
//  CoachingVideoPlayerView.swift
//  KochiApp
//
//  Created on November 1, 2025.
//

import SwiftUI
import AVKit
import AVFoundation

// MARK: - Coaching Video Player View
// SwiftUI view for displaying the coaching video
struct CoachingVideoPlayerView: View {
    @ObservedObject var videoManager: VideoCoachingManager
    /// Corner radius applied to the video *layer* itself — SwiftUI's clipShape
    /// can't clip an AVPlayerLayer, so the parent passes its radius down here.
    var cornerRadius: CGFloat = 0

    var body: some View {
        // Video Player - fills entire available space
        ZStack {
            if let player = videoManager.player {
                // Bare AVPlayerLayer surface: just the video frames, with no
                // transport controls and no hover/click behavior of any kind.
                PlayerLayerView(player: player, cornerRadius: cornerRadius)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false) // not interactive
                    .id(videoManager.currentVideoLabel) // Force re-render on video change
                    .onAppear {
                        print("📺 VideoPlayer appeared for: \(videoManager.currentVideoLabel.rawValue)")
                        // Ensure playback starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if player.rate == 0 {
                                print("📺 Player paused, restarting...")
                                player.seek(to: .zero)
                                player.play()
                            }
                        }
                    }
            } else {
                // Placeholder when no video
                Color.black.opacity(0.3)

                VStack(spacing: 8) {
                    Image(systemName: getIconForLabel(videoManager.currentVideoLabel))
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text(videoManager.currentVideoLabel.description)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))
                }
            }
        }
        // Framing (corner radius + border) is owned by the parent coach-hero
        // section so the player can be reused inside the device layout.
    }

    private func getIconForLabel(_ label: VideoLabel) -> String {
        switch label {
        case .idle: return "figure.stand"
        case .goal: return "checkmark.circle.fill"
        case .timing: return "clock.fill"
        case .pause: return "pause.circle.fill"
        case .listen: return "ear.fill"
        case .prompt: return "questionmark.circle.fill"
        case .mute: return "speaker.slash.fill"
        case .focus: return "eye.fill"
        case .check: return "checklist"
        case .steady: return "speedometer"
        case .wrap: return "flag.checkered"
        }
    }
}

// MARK: - Non-interactive video surface
// Renders an AVPlayer through a raw AVPlayerLayer — no playback controls, no
// hover affordances, not clickable. Used instead of AVKit's `VideoPlayer`,
// which always overlays transport controls on pointer hover.
import AppKit

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = player
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.playerLayer.player = player
        nsView.cornerRadius = cornerRadius
    }
}

final class PlayerLayerHostView: NSView {
    let playerLayer = AVPlayerLayer()
    var cornerRadius: CGFloat = 0 { didSet { applyCornerRadius() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyCornerRadius() {
        // Clip the video at the layer level — SwiftUI clipShape can't. Mask the
        // host layer too so the rounded clip is reliable on macOS.
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = cornerRadius > 0
        playerLayer.cornerRadius = cornerRadius
        playerLayer.masksToBounds = cornerRadius > 0
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
        applyCornerRadius()
    }

    // Let every pointer event pass straight through — the video is decorative.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct CoachingVideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        CoachingVideoPlayerView(videoManager: VideoCoachingManager())
            .frame(height: 200)
            .padding()
            .background(Color.black)
    }
}
