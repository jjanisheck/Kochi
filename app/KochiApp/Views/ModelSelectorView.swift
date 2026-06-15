import SwiftUI

// MARK: - Apple Foundation Models Info View
// Since we're using 100% Apple native AI, there's no model selection needed
struct ModelSelectorView: View {
    @ObservedObject var llmManager: LLMManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header Card
                        AppleAIHeaderCard()

                        // Capabilities
                        CapabilitiesCard()

                        // Privacy Card
                        PrivacyCard()

                        // Requirements
                        RequirementsCard()
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Models")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.accentColor)
                }
            }
        }
    }
}

// MARK: - Apple AI Header Card
struct AppleAIHeaderCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 16) {
            // Apple logo and title
            HStack(spacing: 12) {
                Image(systemName: "apple.logo")
                    .font(.largeTitle)
                    .foregroundColor(themeManager.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Foundation Models")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(themeManager.textColor)

                    Text("100% On-Device AI")
                        .font(.subheadline)
                        .foregroundColor(themeManager.accentColor)
                }
            }

            // Status badge
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text("Active & Ready")
                    .font(.headline)
                    .foregroundColor(.green)

                Spacer()

                // No download needed badge
                Label("No Download", systemImage: "icloud.slash")
                    .font(.caption)
                    .foregroundColor(themeManager.textColor.opacity(0.6))
            }
            .padding(.horizontal)
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Capabilities Card
struct CapabilitiesCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Capabilities")
                .font(.headline)
                .foregroundColor(themeManager.textColor)

            VStack(spacing: 12) {
                CapabilityRow(
                    icon: "brain",
                    title: "Semantic Analysis",
                    description: "NLEmbedding for goal matching"
                )

                CapabilityRow(
                    icon: "chart.bar",
                    title: "Sentiment Detection",
                    description: "Real-time emotion analysis"
                )

                CapabilityRow(
                    icon: "sparkles",
                    title: "Key Topic Extraction",
                    description: "Automatic phrase identification"
                )

                CapabilityRow(
                    icon: "text.badge.checkmark",
                    title: "Goal Evaluation",
                    description: "Smart goal completion detection"
                )

                CapabilityRow(
                    icon: "lightbulb",
                    title: "Intelligent Coaching",
                    description: "Context-aware feedback"
                )
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Capability Row
struct CapabilityRow: View {
    let icon: String
    let title: String
    let description: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(themeManager.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(themeManager.textColor)

                Text(description)
                    .font(.caption)
                    .foregroundColor(themeManager.textColor.opacity(0.6))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}

// MARK: - Privacy Card
struct PrivacyCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Privacy First")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                PrivacyFeature(
                    icon: "iphone",
                    text: "100% on-device processing"
                )

                PrivacyFeature(
                    icon: "wifi.slash",
                    text: "No internet connection required"
                )

                PrivacyFeature(
                    icon: "lock",
                    text: "Zero data sent to servers"
                )

                PrivacyFeature(
                    icon: "shield.checkmark",
                    text: "Apple's privacy standards"
                )
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Privacy Feature
struct PrivacyFeature: View {
    let icon: String
    let text: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundColor(themeManager.textColor.opacity(0.8))
        }
    }
}

// MARK: - Requirements Card
struct RequirementsCard: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(themeManager.accentColor)

                Text("System Requirements")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                RequirementRow(
                    title: "macOS Version",
                    value: "27.0+",
                    met: true
                )

                RequirementRow(
                    title: "Framework",
                    value: "NaturalLanguage.framework",
                    met: true
                )

                RequirementRow(
                    title: "Speech Recognition",
                    value: "Speech.framework",
                    met: true
                )

                RequirementRow(
                    title: "Storage",
                    value: "0 MB (built-in)",
                    met: true
                )
            }

            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.yellow)

                Text("No downloads, no setup, always ready!")
                    .font(.caption)
                    .foregroundColor(themeManager.textColor.opacity(0.7))
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Requirement Row
struct RequirementRow: View {
    let title: String
    let value: String
    let met: Bool
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(themeManager.textColor.opacity(0.7))

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(themeManager.textColor)

            Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(met ? .green : .red)
        }
    }
}

// MARK: - Previews
struct ModelSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        ModelSelectorView(llmManager: LLMManager())
            .environmentObject(ThemeManager())
    }
}
