import Foundation

/// Which cloud provider runs the analysis. Raw value persisted in UserDefaults.
enum CloudProvider: String, CaseIterable, Codable {
    case claude
    case openai

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        }
    }

    /// Default model id used when this provider is freshly selected.
    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-6"
        case .openai: return "gpt-5.5"
        }
    }

    /// Keychain account under which this provider's key is stored.
    var keychainAccount: String { "cloud-llm-\(rawValue)" }
}

/// A single action item extracted from a meeting.
struct ActionItem: Codable, Equatable {
    var task: String
    var owner: String?   // nil when the transcript named no owner
}

/// One graded effectiveness dimension.
struct Dimension: Codable, Equatable {
    var grade: String    // normalized "A"…"F" (or "N/A")
    var note: String
}

struct Effectiveness: Codable, Equatable {
    var communication: Dimension
    var focus: Dimension
    var professionalism: Dimension
}

/// Token spend and an estimated USD cost for one analysis call.
struct TokenUsage: Codable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    /// Estimated cost from published per-token rates; nil when the model's price is unknown.
    var estimatedCostUSD: Double?
}

/// Published per-1M-token prices for known models, used to estimate analysis cost.
enum AnalysisPricing {
    /// (inputPerMTok, outputPerMTok) in USD, or nil for an unknown model.
    private static func rates(for model: String) -> (input: Double, output: Double)? {
        switch model {
        case "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5":
            return (5.0, 25.0)
        case "claude-sonnet-4-6", "claude-sonnet-4-5":
            return (3.0, 15.0)
        case "claude-haiku-4-5":
            return (1.0, 5.0)
        case "claude-fable-5", "claude-mythos-5":
            return (10.0, 50.0)
        default:
            return nil
        }
    }

    /// Estimated USD cost from token counts, or nil when the model's price is unknown.
    static func estimatedCostUSD(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let r = rates(for: model) else { return nil }
        return Double(inputTokens) / 1_000_000 * r.input + Double(outputTokens) / 1_000_000 * r.output
    }
}

/// The full saved analysis for a meeting.
struct MeetingAnalysis: Codable, Equatable {
    var summary: String
    var actionItems: [ActionItem]
    var effectiveness: Effectiveness
    var overallCoaching: String
    var suggestedName: String?   // AI-proposed meeting title (nil for older analyses)
    var usage: TokenUsage?       // token spend + estimated cost (nil for older analyses)
    var provider: String     // provenance, e.g. "Claude (claude-sonnet-4-6)"
    var generatedAt: Date

    /// Normalizes a model-emitted grade to a single uppercase letter A–F, else "N/A".
    /// Accepts "A", "B-", "c+", etc. (1–2 char strings starting with a grade letter).
    /// Rejects words like "excellent" that merely start with a valid letter.
    static func normalizeGrade(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow at most 2 characters: the letter and an optional modifier (+/-)
        guard trimmed.count <= 2,
              let firstChar = trimmed.uppercased().first,
              ["A", "B", "C", "D", "E", "F"].contains(firstChar) else {
            return "N/A"
        }
        return String(firstChar)
    }

    /// The JSON shape the model returns (no provenance fields — we stamp those).
    private struct Payload: Codable {
        struct Dim: Codable { var grade: String; var note: String }
        struct Eff: Codable { var communication: Dim; var focus: Dim; var professionalism: Dim }
        struct Item: Codable { var task: String; var owner: String? }
        var summary: String
        var actionItems: [Item]
        var effectiveness: Eff
        var overallCoaching: String
        var suggestedName: String?
    }

    /// Builds a `MeetingAnalysis` from the model's raw JSON text plus provenance.
    /// Throws `CloudLLMError.badResponse` if the JSON doesn't match the schema.
    static func from(jsonText: String, providerLabel: String, date: Date) throws -> MeetingAnalysis {
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw CloudLLMError.badResponse
        }
        func dim(_ d: Payload.Dim) -> Dimension {
            Dimension(grade: normalizeGrade(d.grade), note: d.note)
        }
        return MeetingAnalysis(
            summary: payload.summary,
            actionItems: payload.actionItems.map { ActionItem(task: $0.task, owner: $0.owner) },
            effectiveness: Effectiveness(
                communication: dim(payload.effectiveness.communication),
                focus: dim(payload.effectiveness.focus),
                professionalism: dim(payload.effectiveness.professionalism)
            ),
            overallCoaching: payload.overallCoaching,
            suggestedName: payload.suggestedName,
            provider: providerLabel,
            generatedAt: date
        )
    }
}

/// JSON Schema describing the analysis payload, shared by both providers'
/// structured-output features. All objects set `additionalProperties: false`
/// and list every property as required; `owner` is nullable.
enum AnalysisSchema {
    static let jsonSchema: [String: Any] = {
        func dim() -> [String: Any] {
            [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "grade": ["type": "string", "description": "Letter grade A–F"],
                    "note": ["type": "string", "description": "One-sentence justification"]
                ],
                "required": ["grade", "note"]
            ]
        }
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "summary": ["type": "string", "description": "2–3 sentence meeting summary"],
                "actionItems": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "task": ["type": "string"],
                            "owner": ["type": ["string", "null"], "description": "Owner if stated, else null"]
                        ],
                        "required": ["task", "owner"]
                    ]
                ],
                "effectiveness": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "communication": dim(),
                        "focus": dim(),
                        "professionalism": dim()
                    ],
                    "required": ["communication", "focus", "professionalism"]
                ],
                "overallCoaching": ["type": "string", "description": "Actionable coaching paragraph"],
                "suggestedName": ["type": "string", "description": "A concise 4-8 word meeting title based on the topic and the people involved"]
            ],
            "required": ["summary", "actionItems", "effectiveness", "overallCoaching", "suggestedName"]
        ]
    }()
}

/// Builds the system and user prompts for the analysis call.
enum AnalysisPrompt {
    static let system = """
    You are a professional meeting-effectiveness coach. You are given a transcript \
    of a meeting where the user's own speech is labeled "Me:" and others are "Them:". \
    Produce a concise summary, the concrete action items with their owners (use null \
    when no owner was stated), and an honest assessment of how the user ("Me") \
    performed across three dimensions: communication, focus, and professionalism. \
    Grade each dimension with a single letter A–F and a one-sentence note, then give \
    one short paragraph of overall coaching. Also propose a concise meeting name (4-8 \
    words) based on the topic and the people involved. Be specific and direct; base every \
    claim on the transcript. Respond only with the requested JSON.
    """

    static func user(goalTexts: [String], transcript: String) -> String {
        let goals = goalTexts.isEmpty ? "None set." : goalTexts.map { "- \($0)" }.joined(separator: "\n")
        return """
        Meeting goals:
        \(goals)

        Transcript:
        \"\"\"
        \(transcript)
        \"\"\"
        """
    }
}

extension MeetingAnalysis {
    /// Markdown rendering for the on-disk `analysis.md` file.
    func markdown() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var out = "# AI Analysis\n\n"
        out += "_Generated by \(provider) on \(df.string(from: generatedAt))_\n\n"
        if let suggestedName, !suggestedName.isEmpty {
            out += "**Suggested name:** \(suggestedName)\n\n"
        }
        if let usage {
            let cost = usage.estimatedCostUSD.map { String(format: " \u{2014} ~$%.4f (est.)", $0) } ?? ""
            out += "_Tokens: \(usage.inputTokens) in / \(usage.outputTokens) out\(cost)_\n\n"
        }
        out += "## Summary\n\n\(summary)\n\n"
        out += "## Action Items\n\n"
        if actionItems.isEmpty {
            out += "_None._\n\n"
        } else {
            for item in actionItems {
                if let owner = item.owner, !owner.isEmpty {
                    out += "- \(item.task) \u{2014} \(owner)\n"
                } else {
                    out += "- \(item.task)\n"
                }
            }
            out += "\n"
        }
        out += "## Effectiveness\n\n"
        out += "- **Communication (\(effectiveness.communication.grade)):** \(effectiveness.communication.note)\n"
        out += "- **Focus (\(effectiveness.focus.grade)):** \(effectiveness.focus.note)\n"
        out += "- **Professionalism (\(effectiveness.professionalism.grade)):** \(effectiveness.professionalism.note)\n\n"
        out += "## Coaching\n\n\(overallCoaching)\n"
        return out
    }

    /// Plain-text rendering appended to the clipboard copy (matches the copy's
    /// existing uppercase-header style).
    func plainText() -> String {
        var lines: [String] = []
        lines.append("AI ANALYSIS (\(provider))")
        if let suggestedName, !suggestedName.isEmpty {
            lines.append("Suggested name: \(suggestedName)")
        }
        if let usage {
            let cost = usage.estimatedCostUSD.map { String(format: " \u{2014} ~$%.4f (est.)", $0) } ?? ""
            lines.append("Tokens: \(usage.inputTokens) in / \(usage.outputTokens) out\(cost)")
        }
        lines.append("")
        lines.append("Summary:")
        lines.append(summary)
        lines.append("")
        lines.append("Action items:")
        if actionItems.isEmpty {
            lines.append("(none)")
        } else {
            for item in actionItems {
                if let owner = item.owner, !owner.isEmpty {
                    lines.append("- \(item.task) \u{2014} \(owner)")
                } else {
                    lines.append("- \(item.task)")
                }
            }
        }
        lines.append("")
        lines.append("Effectiveness:")
        lines.append("- Communication (\(effectiveness.communication.grade)): \(effectiveness.communication.note)")
        lines.append("- Focus (\(effectiveness.focus.grade)): \(effectiveness.focus.note)")
        lines.append("- Professionalism (\(effectiveness.professionalism.grade)): \(effectiveness.professionalism.note)")
        lines.append("")
        lines.append("Coaching:")
        lines.append(overallCoaching)
        return lines.joined(separator: "\n")
    }
}
