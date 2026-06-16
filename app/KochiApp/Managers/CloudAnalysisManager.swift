import Foundation
import Combine

/// Owns cloud-LLM configuration (provider + model in UserDefaults, API key in the
/// Keychain) and runs a finished meeting's transcript through the selected provider.
@MainActor
final class CloudAnalysisManager: ObservableObject {
    @Published var provider: CloudProvider
    @Published var model: String
    /// True when a key is stored for the *currently selected* provider.
    @Published private(set) var hasKey: Bool

    private let defaults = UserDefaults.standard
    private let providerKey = "cloudLLMProvider"
    private let modelKey = "cloudLLMModel"

    init() {
        let p = CloudProvider(rawValue: defaults.string(forKey: "cloudLLMProvider") ?? "") ?? .claude
        self.provider = p
        self.model = defaults.string(forKey: "cloudLLMModel") ?? p.defaultModel
        self.hasKey = KeychainStore.read(account: p.keychainAccount) != nil
    }

    /// True when the selected provider has a saved key — gates the analysis UI.
    var isConfigured: Bool { hasKey }

    /// Switches provider, resetting the model to that provider's default and
    /// refreshing the key-present flag.
    func selectProvider(_ p: CloudProvider) {
        provider = p
        model = p.defaultModel
        defaults.set(p.rawValue, forKey: providerKey)
        defaults.set(model, forKey: modelKey)
        refreshHasKey()
    }

    func setModel(_ m: String) {
        let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
        model = trimmed.isEmpty ? provider.defaultModel : trimmed
        defaults.set(model, forKey: modelKey)
    }

    func saveKey(_ key: String) throws {
        try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines),
                               account: provider.keychainAccount)
        refreshHasKey()
    }

    func removeKey() {
        KeychainStore.delete(account: provider.keychainAccount)
        refreshHasKey()
    }

    private func refreshHasKey() {
        hasKey = KeychainStore.read(account: provider.keychainAccount) != nil
    }

    /// Runs the analysis for a meeting and returns a stamped `MeetingAnalysis`.
    func analyze(meeting: MeetingSession) async throws -> MeetingAnalysis {
        guard let key = KeychainStore.read(account: provider.keychainAccount), !key.isEmpty else {
            throw CloudLLMError.missingKey
        }
        let client: CloudLLMClient = (provider == .claude) ? AnthropicClient() : OpenAIClient()
        let user = AnalysisPrompt.user(goalTexts: meeting.goals.map { $0.text },
                                       transcript: meeting.notes)
        let json = try await client.complete(system: AnalysisPrompt.system,
                                             user: user,
                                             apiKey: key,
                                             model: model)
        let label = "\(provider.displayName) (\(model))"
        return try MeetingAnalysis.from(jsonText: json, providerLabel: label, date: Date())
    }
}
