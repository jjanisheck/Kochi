import SwiftUI
import Speech

/// On-device transcription status. The app transcribes entirely on-device using
/// Apple's Speech framework (via `DualTranscriptionEngine`) — no API keys, no
/// cloud upload. This view reports availability of that on-device pipeline.
struct TranscriptionSettingsView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var llmManager: LLMManager

    private var accentColor: Color { Color(red: 249/255, green: 81/255, blue: 0) }

    /// Whether on-device speech recognition is authorized and available.
    private var speechAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && (SFSpeechRecognizer()?.isAvailable ?? false)
    }

    private var authorizationStatusText: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "Authorized"
        case .denied: return "Denied — enable in System Settings ▸ Privacy ▸ Speech Recognition"
        case .restricted: return "Restricted on this device"
        case .notDetermined: return "Not yet requested — start a recording to grant access"
        @unknown default: return "Unknown"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                TabHeader(
                    icon: "gearshape.fill",
                    title: "Settings",
                    subtitle: "On-device transcription and model status."
                )

                // MARK: - On-Device Transcription Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundColor(accentColor)
                        Text("On-Device Transcription")
                            .font(.headline)
                            .foregroundColor(Color.black)
                    }

                    Text("Speech-to-text runs entirely on this device using Apple's Speech framework. No internet connection or API key is required, and audio never leaves your device.")
                        .font(.caption)
                        .foregroundColor(Color.black.opacity(0.7))

                    HStack {
                        Image(systemName: speechAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(speechAvailable ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(speechAvailable ? "On-device speech recognition is ready" : "On-device speech recognition is not ready")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color.black)
                            Text(authorizationStatusText)
                                .font(.caption2)
                                .foregroundColor(Color.black.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)

                    HStack {
                        Image(systemName: llmManager.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(llmManager.isAvailable ? .green : .orange)
                        Text(llmManager.isAvailable ? "Apple Intelligence model: Ready" : "Apple Intelligence model: Unavailable")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Color.black)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
                .background(KColor.paper.opacity(0.92))
                .cornerRadius(10)
                .padding(.horizontal)

                // MARK: - Privacy Benefits
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Private by Design")
                            .font(.headline)
                            .foregroundColor(Color.black)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        BenefitRow(icon: "iphone", text: "Fully on-device — nothing is uploaded")
                        BenefitRow(icon: "wifi.slash", text: "Works without an internet connection")
                        BenefitRow(icon: "key.slash", text: "No API keys or accounts required")
                        BenefitRow(icon: "person.2.wave.2", text: "Dual-channel speaker separation (Me / Them)")
                    }
                }
                .padding()
                .background(KColor.paper.opacity(0.92))
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .padding(.bottom)
        }
        .navigationTitle("Transcription Settings")
        .inlineNavigationTitle()
    }
}

// MARK: - Benefit Row
struct BenefitRow: View {
    let icon: String
    let text: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundColor(Color.black)

            Spacer()
        }
    }
}

struct TranscriptionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TranscriptionSettingsView()
                .environmentObject(AudioManager())
                .environmentObject(ThemeManager())
                .environmentObject(LLMManager())
        }
    }
}
