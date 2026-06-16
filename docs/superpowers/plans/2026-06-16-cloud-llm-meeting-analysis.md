# Cloud LLM Post-Meeting Analysis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in feature that runs a finished meeting's transcript through the user's own Claude or OpenAI API key to produce a summary, action items with owners, and a letter-graded professional-effectiveness review, saved with the meeting.

**Architecture:** A `KeychainStore` holds the API key; a `CloudAnalysisManager` (`ObservableObject`) owns provider/model config and orchestrates analysis; two thin `URLSession` clients (`AnthropicClient`, `OpenAIClient`) call the providers' REST endpoints with structured-JSON output. The result is a `MeetingAnalysis` saved onto the existing `MeetingSession`. A new "AI" settings tab manages the key; a "Run AI Analysis" button on each saved meeting triggers and displays the analysis.

**Tech Stack:** Swift / SwiftUI (macOS), Foundation `URLSession`, `Security` (Keychain). No Swift Package added — Apple frameworks only.

---

## Spec reference

Design spec: `docs/superpowers/specs/2026-06-16-cloud-llm-meeting-analysis-design.md`.

## Testing approach (read first)

This Xcode project has **no test target** — `xcodebuild -list` shows only the `KochiApp` app target/scheme, and the files under `KochiApp/Tests/` are orphaned (not members of any build phase). Therefore:

- **Pure Foundation logic** (models, JSON schema, response parsing, request building, grade normalization, error mapping, prompt building) is verified by compiling the source file(s) together with a throwaway `main.swift` via `swiftc` and running real assertions. These verify scripts live in `/tmp/kochi-verify/` and are **not committed**.
- **Integration / UI / Keychain / networking** is verified by the canonical project gate — `xcodebuild ... build` succeeding — plus a described manual run-through.

The project build/verify commands (run from `app/`):

```bash
# Build gate
xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build

# Pure-logic verify pattern (example; exact sources per task)
mkdir -p /tmp/kochi-verify
swiftc KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```

`swiftc` allows top-level executable code only in a file literally named `main.swift`, so all verify scripts are written to `/tmp/kochi-verify/main.swift`.

## File structure

New files (all in the `KochiApp` app target):

| File | Responsibility |
|---|---|
| `KochiApp/Services/KeychainStore.swift` | Generic-password Keychain wrapper (`save`/`read`/`delete`). Foundation + Security only. |
| `KochiApp/Services/CloudLLM/CloudAnalysisModels.swift` | `CloudProvider`, `MeetingAnalysis` + sub-types, `AnalysisSchema` (JSON schema), `AnalysisPrompt` (system/user prompt builders), grade normalization, `MeetingAnalysis.from(jsonText:…)`. Foundation only. |
| `KochiApp/Services/CloudLLM/CloudLLMClient.swift` | `CloudLLMClient` protocol, `CloudLLMError`, `cloudError(forStatus:)`. Foundation only. |
| `KochiApp/Services/CloudLLM/AnthropicClient.swift` | Anthropic `/v1/messages` request builder, response parser, async `complete`. Foundation only. |
| `KochiApp/Services/CloudLLM/OpenAIClient.swift` | OpenAI `/v1/chat/completions` request builder, response parser, async `complete`. Foundation only. |
| `KochiApp/Managers/CloudAnalysisManager.swift` | `ObservableObject`: provider/model state (UserDefaults), key (Keychain), `analyze(meeting:)`. |

Modified files:

| File | Change |
|---|---|
| `KochiApp/Managers/GoalManager.swift` | Add `MeetingSession.analysis: MeetingAnalysis?` + `updateMeetingAnalysis(_:analysis:)`. |
| `KochiApp/KochiApp.swift` | Add `@StateObject` + `.environmentObject` for `CloudAnalysisManager`. |
| `KochiApp/ContentView.swift` | Add `CloudAnalysisManager` to the preview `.environmentObject` block. |
| `KochiApp/Views/SettingsView.swift` | Add 5th "AI" tab + `AITab` view; add analysis card + run action to `MeetingDetailView`. |
| `Kochi.xcodeproj/project.pbxproj` | Register the 6 new source files. |

---

## Task 1: Register new source files in the Xcode project

Create all six new files as minimal compilable stubs and register them in `project.pbxproj`, so later tasks edit already-wired files. This isolates the fragile pbxproj surgery into one build-verified step.

**Files:**
- Create: all six new files (stubs)
- Modify: `app/Kochi.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the subfolder and stub files**

```bash
cd app
mkdir -p KochiApp/Services/CloudLLM
```

Create `KochiApp/Services/KeychainStore.swift`:

```swift
import Foundation

enum KeychainStore {}
```

Create `KochiApp/Services/CloudLLM/CloudAnalysisModels.swift`:

```swift
import Foundation

enum CloudProvider: String, CaseIterable, Codable { case claude, openai }
```

Create `KochiApp/Services/CloudLLM/CloudLLMClient.swift`:

```swift
import Foundation

protocol CloudLLMClient {}
```

Create `KochiApp/Services/CloudLLM/AnthropicClient.swift`:

```swift
import Foundation

struct AnthropicClient {}
```

Create `KochiApp/Services/CloudLLM/OpenAIClient.swift`:

```swift
import Foundation

struct OpenAIClient {}
```

Create `KochiApp/Managers/CloudAnalysisManager.swift`:

```swift
import Foundation
import Combine

final class CloudAnalysisManager: ObservableObject {}
```

- [ ] **Step 2: Add `PBXBuildFile` entries**

In `app/Kochi.xcodeproj/project.pbxproj`, find this exact line:

```
		04SYSAUD001 /* KochiApp/Services/SystemAudioCapture.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04SYSAUD002 /* KochiApp/Services/SystemAudioCapture.swift */; };
```

Insert these six lines immediately after it (keep the leading two tabs):

```
		04KEYCH001 /* KochiApp/Services/KeychainStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04KEYCH002 /* KochiApp/Services/KeychainStore.swift */; };
		04CAMODELS001 /* KochiApp/Services/CloudLLM/CloudAnalysisModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04CAMODELS002 /* KochiApp/Services/CloudLLM/CloudAnalysisModels.swift */; };
		04CLLMCL001 /* KochiApp/Services/CloudLLM/CloudLLMClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04CLLMCL002 /* KochiApp/Services/CloudLLM/CloudLLMClient.swift */; };
		04ANTHRO001 /* KochiApp/Services/CloudLLM/AnthropicClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04ANTHRO002 /* KochiApp/Services/CloudLLM/AnthropicClient.swift */; };
		04OPENAI001 /* KochiApp/Services/CloudLLM/OpenAIClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04OPENAI002 /* KochiApp/Services/CloudLLM/OpenAIClient.swift */; };
		04CAMGR001 /* KochiApp/Managers/CloudAnalysisManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 04CAMGR002 /* KochiApp/Managers/CloudAnalysisManager.swift */; };
```

- [ ] **Step 3: Add `PBXFileReference` entries**

Find this exact line:

```
		04SYSAUD002 /* KochiApp/Services/SystemAudioCapture.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Services/SystemAudioCapture.swift; sourceTree = "<group>"; };
```

Insert these six lines immediately after it:

```
		04KEYCH002 /* KochiApp/Services/KeychainStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Services/KeychainStore.swift; sourceTree = "<group>"; };
		04CAMODELS002 /* KochiApp/Services/CloudLLM/CloudAnalysisModels.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Services/CloudLLM/CloudAnalysisModels.swift; sourceTree = "<group>"; };
		04CLLMCL002 /* KochiApp/Services/CloudLLM/CloudLLMClient.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Services/CloudLLM/CloudLLMClient.swift; sourceTree = "<group>"; };
		04ANTHRO002 /* KochiApp/Services/CloudLLM/AnthropicClient.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Services/CloudLLM/AnthropicClient.swift; sourceTree = "<group>"; };
		04OPENAI002 /* KochiApp/Services/CloudLLM/OpenAIClient.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Services/CloudLLM/OpenAIClient.swift; sourceTree = "<group>"; };
		04CAMGR002 /* KochiApp/Managers/CloudAnalysisManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = KochiApp/Managers/CloudAnalysisManager.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: Add the files to the Sources build phase**

Find this exact line (four leading tabs):

```
				04SYSAUD001 /* KochiApp/Services/SystemAudioCapture.swift in Sources */,
```

Insert these six lines immediately after it:

```
				04KEYCH001 /* KochiApp/Services/KeychainStore.swift in Sources */,
				04CAMODELS001 /* KochiApp/Services/CloudLLM/CloudAnalysisModels.swift in Sources */,
				04CLLMCL001 /* KochiApp/Services/CloudLLM/CloudLLMClient.swift in Sources */,
				04ANTHRO001 /* KochiApp/Services/CloudLLM/AnthropicClient.swift in Sources */,
				04OPENAI001 /* KochiApp/Services/CloudLLM/OpenAIClient.swift in Sources */,
				04CAMGR001 /* KochiApp/Managers/CloudAnalysisManager.swift in Sources */,
```

- [ ] **Step 5: Add the files to the navigator group**

Find this exact line (four leading tabs, ends with a comma):

```
				04SYSAUD002 /* KochiApp/Services/SystemAudioCapture.swift */,
```

Insert these six lines immediately after it:

```
				04KEYCH002 /* KochiApp/Services/KeychainStore.swift */,
				04CAMODELS002 /* KochiApp/Services/CloudLLM/CloudAnalysisModels.swift */,
				04CLLMCL002 /* KochiApp/Services/CloudLLM/CloudLLMClient.swift */,
				04ANTHRO002 /* KochiApp/Services/CloudLLM/AnthropicClient.swift */,
				04OPENAI002 /* KochiApp/Services/CloudLLM/OpenAIClient.swift */,
				04CAMGR002 /* KochiApp/Managers/CloudAnalysisManager.swift */,
```

- [ ] **Step 6: Build to verify the project still compiles with the new files**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add app/KochiApp/Services/KeychainStore.swift app/KochiApp/Services/CloudLLM app/KochiApp/Managers/CloudAnalysisManager.swift app/Kochi.xcodeproj/project.pbxproj
git commit -m "chore: scaffold cloud-LLM analysis source files"
```

---

## Task 2: KeychainStore

**Files:**
- Modify: `app/KochiApp/Services/KeychainStore.swift`

- [ ] **Step 1: Implement the Keychain wrapper**

Replace the entire contents of `KochiApp/Services/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Used to store cloud-LLM API keys
/// so they never touch UserDefaults. Keys are stored per `account`.
enum KeychainStore {
    private static let service = "com.kochi.cloudllm"

    /// Saves (or replaces) the value for `account`. Throws on an unexpected status.
    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        // Delete any existing item first so this is an upsert.
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    /// Returns the stored value for `account`, or nil if none / unreadable.
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored value for `account` (no-op if absent).
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error { case status(OSStatus) }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

> Functional Keychain behavior (save → read back → delete) is verified at runtime during the AI-settings manual run-through in Task 9, because Keychain calls require an app-bundle context that a standalone `swiftc` binary cannot reliably provide.

- [ ] **Step 3: Commit**

```bash
git add app/KochiApp/Services/KeychainStore.swift
git commit -m "feat: add KeychainStore for cloud-LLM API keys"
```

---

## Task 3: Cloud analysis models, schema, prompts

**Files:**
- Modify: `app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift`
- Modify: `app/KochiApp/Services/CloudLLM/CloudLLMClient.swift` (needed for `CloudLLMError`, implemented fully in Task 4 — add the error type here first so this task's verify compiles)
- Verify: `/tmp/kochi-verify/main.swift`

- [ ] **Step 1: Add `CloudLLMError` to CloudLLMClient.swift (minimal, for this task)**

Replace the entire contents of `KochiApp/Services/CloudLLM/CloudLLMClient.swift`:

```swift
import Foundation

/// Failure modes for a cloud-LLM analysis call.
enum CloudLLMError: Error, Equatable {
    case missingKey
    case auth
    case rateLimited
    case refusal
    case badResponse
    case http(Int)
    case network(String)
}

/// A provider client that returns the raw structured-JSON text for one completion.
protocol CloudLLMClient {
    func complete(system: String, user: String, apiKey: String, model: String) async throws -> String
}
```

- [ ] **Step 2: Write the failing verify script**

Create `/tmp/kochi-verify/main.swift`:

```swift
import Foundation

// 1. CloudProvider defaults
assert(CloudProvider.claude.defaultModel == "claude-sonnet-4-6", "claude default model")
assert(CloudProvider.openai.defaultModel == "gpt-5.5", "openai default model")
assert(CloudProvider.claude.keychainAccount == "cloud-llm-claude", "claude account")

// 2. Grade normalization
assert(MeetingAnalysis.normalizeGrade("b") == "B", "lowercase b -> B")
assert(MeetingAnalysis.normalizeGrade("A-") == "A", "A- -> A")
assert(MeetingAnalysis.normalizeGrade("excellent") == "N/A", "non-grade -> N/A")

// 3. Decode a model JSON payload into MeetingAnalysis (+ provenance stamping)
let json = """
{"summary":"We aligned on the Q3 roadmap.",
 "actionItems":[{"task":"Send the budget","owner":"Alice"},{"task":"Book the room","owner":null}],
 "effectiveness":{"communication":{"grade":"B","note":"Clear but interrupted."},
                  "focus":{"grade":"A","note":"Stayed on agenda."},
                  "professionalism":{"grade":"a","note":"Courteous."}},
 "overallCoaching":"Let others finish their point."}
"""
let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
let analysis = try! MeetingAnalysis.from(jsonText: json, providerLabel: "Claude (claude-sonnet-4-6)", date: fixedDate)
assert(analysis.summary == "We aligned on the Q3 roadmap.", "summary")
assert(analysis.actionItems.count == 2, "two action items")
assert(analysis.actionItems[0].owner == "Alice", "owner Alice")
assert(analysis.actionItems[1].owner == nil, "null owner -> nil")
assert(analysis.effectiveness.professionalism.grade == "A", "lowercase a normalized to A")
assert(analysis.provider == "Claude (claude-sonnet-4-6)", "provenance label")
assert(analysis.generatedAt == fixedDate, "stamped date")

// 4. Codable round-trip
let encoded = try! JSONEncoder().encode(analysis)
let decoded = try! JSONDecoder().decode(MeetingAnalysis.self, from: encoded)
assert(decoded == analysis, "round-trip equality")

// 5. Bad JSON throws badResponse
do {
    _ = try MeetingAnalysis.from(jsonText: "not json", providerLabel: "x", date: fixedDate)
    assert(false, "should have thrown")
} catch let e as CloudLLMError { assert(e == .badResponse, "badResponse on bad json") }

// 6. Prompt builder includes goals + transcript and is non-empty
let prompt = AnalysisPrompt.user(goalTexts: ["discuss budget"], transcript: "Me: hello\nThem: hi")
assert(prompt.contains("discuss budget"), "prompt has goal")
assert(prompt.contains("Me: hello"), "prompt has transcript")
assert(!AnalysisPrompt.system.isEmpty, "system prompt non-empty")

print("ALL MODEL TESTS PASSED")
```

- [ ] **Step 3: Run the verify script to confirm it fails to compile**

Run:
```bash
mkdir -p /tmp/kochi-verify
swiftc app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       app/KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: compile errors (e.g. `MeetingAnalysis` / `AnalysisPrompt` not found).

- [ ] **Step 4: Implement the models**

Replace the entire contents of `KochiApp/Services/CloudLLM/CloudAnalysisModels.swift`:

```swift
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

/// The full saved analysis for a meeting.
struct MeetingAnalysis: Codable, Equatable {
    var summary: String
    var actionItems: [ActionItem]
    var effectiveness: Effectiveness
    var overallCoaching: String
    var provider: String     // provenance, e.g. "Claude (claude-sonnet-4-6)"
    var generatedAt: Date

    /// Normalizes a model-emitted grade to a single uppercase letter A–F, else "N/A".
    static func normalizeGrade(_ raw: String) -> String {
        let first = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().first
        guard let c = first.map(String.init), ["A", "B", "C", "D", "E", "F"].contains(c) else {
            return "N/A"
        }
        return c
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
                "overallCoaching": ["type": "string", "description": "Actionable coaching paragraph"]
            ],
            "required": ["summary", "actionItems", "effectiveness", "overallCoaching"]
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
    one short paragraph of overall coaching. Be specific and direct; base every claim \
    on the transcript. Respond only with the requested JSON.
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
```

- [ ] **Step 5: Run the verify script to confirm it passes**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       app/KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: `ALL MODEL TESTS PASSED`

- [ ] **Step 6: Build the app to confirm it still compiles**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift app/KochiApp/Services/CloudLLM/CloudLLMClient.swift
git commit -m "feat: add cloud analysis models, schema, and prompts"
```

---

## Task 4: HTTP status → error mapping

**Files:**
- Modify: `app/KochiApp/Services/CloudLLM/CloudLLMClient.swift`
- Verify: `/tmp/kochi-verify/main.swift`

- [ ] **Step 1: Write the failing verify script**

Replace `/tmp/kochi-verify/main.swift`:

```swift
import Foundation

assert(cloudError(forStatus: 200) == nil, "200 -> nil")
assert(cloudError(forStatus: 299) == nil, "299 -> nil")
assert(cloudError(forStatus: 401) == .auth, "401 -> auth")
assert(cloudError(forStatus: 403) == .auth, "403 -> auth")
assert(cloudError(forStatus: 429) == .rateLimited, "429 -> rateLimited")
assert(cloudError(forStatus: 500) == .http(500), "500 -> http(500)")
print("ALL ERROR-MAPPING TESTS PASSED")
```

- [ ] **Step 2: Run to confirm it fails**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudLLMClient.swift /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: compile error — `cloudError` not found.

- [ ] **Step 3: Add the mapping function**

Append to `KochiApp/Services/CloudLLM/CloudLLMClient.swift` (after the `protocol CloudLLMClient {...}` block):

```swift

/// Maps an HTTP status code to a `CloudLLMError`, or nil for 2xx success.
func cloudError(forStatus status: Int) -> CloudLLMError? {
    switch status {
    case 200...299: return nil
    case 401, 403:  return .auth
    case 429:       return .rateLimited
    default:        return .http(status)
    }
}
```

- [ ] **Step 4: Run to confirm it passes**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudLLMClient.swift /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: `ALL ERROR-MAPPING TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add app/KochiApp/Services/CloudLLM/CloudLLMClient.swift
git commit -m "feat: add HTTP status to CloudLLMError mapping"
```

---

## Task 5: AnthropicClient

**Files:**
- Modify: `app/KochiApp/Services/CloudLLM/AnthropicClient.swift`
- Verify: `/tmp/kochi-verify/main.swift`

- [ ] **Step 1: Write the failing verify script**

Replace `/tmp/kochi-verify/main.swift`:

```swift
import Foundation

// Request building
let req = AnthropicClient.makeRequest(system: "SYS", user: "USR", apiKey: "sk-test", model: "claude-sonnet-4-6")
assert(req.url?.absoluteString == "https://api.anthropic.com/v1/messages", "url")
assert(req.httpMethod == "POST", "method")
assert(req.value(forHTTPHeaderField: "x-api-key") == "sk-test", "x-api-key header")
assert(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "version header")
let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
assert(body["model"] as? String == "claude-sonnet-4-6", "model in body")
assert(body["system"] as? String == "SYS", "system in body")
let messages = body["messages"] as! [[String: Any]]
assert(messages[0]["content"] as? String == "USR", "user content in body")
assert(body["output_config"] != nil, "output_config present")

// Successful response parse
let ok = """
{"content":[{"type":"text","text":"{\\"summary\\":\\"x\\"}"}],"stop_reason":"end_turn"}
""".data(using: .utf8)!
assert(try! AnthropicClient.parseResponse(ok) == "{\"summary\":\"x\"}", "parses text")

// Refusal
let refusal = """
{"content":[],"stop_reason":"refusal"}
""".data(using: .utf8)!
do { _ = try AnthropicClient.parseResponse(refusal); assert(false, "should throw") }
catch let e as CloudLLMError { assert(e == .refusal, "refusal") }

// Bad shape
do { _ = try AnthropicClient.parseResponse(Data("nope".utf8)); assert(false, "should throw") }
catch let e as CloudLLMError { assert(e == .badResponse, "badResponse") }

print("ALL ANTHROPIC TESTS PASSED")
```

- [ ] **Step 2: Run to confirm it fails**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       app/KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       app/KochiApp/Services/CloudLLM/AnthropicClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: compile errors — `makeRequest` / `parseResponse` not found.

- [ ] **Step 3: Implement AnthropicClient**

Replace the entire contents of `KochiApp/Services/CloudLLM/AnthropicClient.swift`:

```swift
import Foundation

/// Calls Anthropic's Messages API with structured-JSON output.
struct AnthropicClient: CloudLLMClient {
    var session: URLSession = .shared

    /// Builds the POST request. Pure (no I/O) so it can be unit-checked.
    static func makeRequest(system: String, user: String, apiKey: String, model: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["format": ["type": "json_schema", "schema": AnalysisSchema.jsonSchema]]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extracts the assistant's structured-JSON text from a response body.
    /// Throws `.refusal` on `stop_reason == "refusal"`, `.badResponse` otherwise.
    static func parseResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudLLMError.badResponse
        }
        if (obj["stop_reason"] as? String) == "refusal" { throw CloudLLMError.refusal }
        guard let content = obj["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              !text.isEmpty else {
            throw CloudLLMError.badResponse
        }
        return text
    }

    func complete(system: String, user: String, apiKey: String, model: String) async throws -> String {
        let req = Self.makeRequest(system: system, user: user, apiKey: apiKey, model: model)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CloudLLMError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, let err = cloudError(forStatus: http.statusCode) {
            throw err
        }
        return try Self.parseResponse(data)
    }
}
```

- [ ] **Step 4: Run to confirm it passes**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       app/KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       app/KochiApp/Services/CloudLLM/AnthropicClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: `ALL ANTHROPIC TESTS PASSED`

- [ ] **Step 5: Build the app**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add app/KochiApp/Services/CloudLLM/AnthropicClient.swift
git commit -m "feat: add AnthropicClient for cloud meeting analysis"
```

---

## Task 6: OpenAIClient

**Files:**
- Modify: `app/KochiApp/Services/CloudLLM/OpenAIClient.swift`
- Verify: `/tmp/kochi-verify/main.swift`

- [ ] **Step 1: Write the failing verify script**

Replace `/tmp/kochi-verify/main.swift`:

```swift
import Foundation

let req = OpenAIClient.makeRequest(system: "SYS", user: "USR", apiKey: "sk-o", model: "gpt-5.5")
assert(req.url?.absoluteString == "https://api.openai.com/v1/chat/completions", "url")
assert(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-o", "auth header")
let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
assert(body["model"] as? String == "gpt-5.5", "model")
let messages = body["messages"] as! [[String: Any]]
assert(messages.count == 2, "system + user messages")
assert(messages[0]["role"] as? String == "system", "system role")
assert(messages[1]["content"] as? String == "USR", "user content")
assert(body["response_format"] != nil, "response_format present")

// Successful parse
let ok = """
{"choices":[{"message":{"role":"assistant","content":"{\\"summary\\":\\"y\\"}"}}]}
""".data(using: .utf8)!
assert(try! OpenAIClient.parseResponse(ok) == "{\"summary\":\"y\"}", "parses content")

// Refusal field
let refusal = """
{"choices":[{"message":{"role":"assistant","content":null,"refusal":"I can't help with that."}}]}
""".data(using: .utf8)!
do { _ = try OpenAIClient.parseResponse(refusal); assert(false, "should throw") }
catch let e as CloudLLMError { assert(e == .refusal, "refusal") }

// Bad shape
do { _ = try OpenAIClient.parseResponse(Data("nope".utf8)); assert(false, "should throw") }
catch let e as CloudLLMError { assert(e == .badResponse, "badResponse") }

print("ALL OPENAI TESTS PASSED")
```

- [ ] **Step 2: Run to confirm it fails**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       app/KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       app/KochiApp/Services/CloudLLM/OpenAIClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: compile errors — `makeRequest` / `parseResponse` not found.

- [ ] **Step 3: Implement OpenAIClient**

Replace the entire contents of `KochiApp/Services/CloudLLM/OpenAIClient.swift`:

```swift
import Foundation

/// Calls OpenAI's Chat Completions API with structured-JSON output.
struct OpenAIClient: CloudLLMClient {
    var session: URLSession = .shared

    /// Builds the POST request. Pure (no I/O) so it can be unit-checked.
    static func makeRequest(system: String, user: String, apiKey: String, model: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "meeting_analysis",
                    "strict": true,
                    "schema": AnalysisSchema.jsonSchema
                ]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Extracts the assistant's structured-JSON content from a response body.
    /// Throws `.refusal` if the model populated a `refusal`, `.badResponse` otherwise.
    static func parseResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw CloudLLMError.badResponse
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty {
            throw CloudLLMError.refusal
        }
        guard let content = message["content"] as? String, !content.isEmpty else {
            throw CloudLLMError.badResponse
        }
        return content
    }

    func complete(system: String, user: String, apiKey: String, model: String) async throws -> String {
        let req = Self.makeRequest(system: system, user: user, apiKey: apiKey, model: model)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CloudLLMError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, let err = cloudError(forStatus: http.statusCode) {
            throw err
        }
        return try Self.parseResponse(data)
    }
}
```

- [ ] **Step 4: Run to confirm it passes**

Run:
```bash
swiftc app/KochiApp/Services/CloudLLM/CloudAnalysisModels.swift \
       app/KochiApp/Services/CloudLLM/CloudLLMClient.swift \
       app/KochiApp/Services/CloudLLM/OpenAIClient.swift \
       /tmp/kochi-verify/main.swift -o /tmp/kochi-verify/run && /tmp/kochi-verify/run
```
Expected: `ALL OPENAI TESTS PASSED`

- [ ] **Step 5: Build the app**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add app/KochiApp/Services/CloudLLM/OpenAIClient.swift
git commit -m "feat: add OpenAIClient for cloud meeting analysis"
```

---

## Task 7: Data model — persist analysis on MeetingSession

**Files:**
- Modify: `app/KochiApp/Managers/GoalManager.swift` (`MeetingSession` struct ~line 328; `updateMeetingNotes` ~line 181)

- [ ] **Step 1: Add the `analysis` field to MeetingSession**

In `KochiApp/Managers/GoalManager.swift`, find the `MeetingSession` struct and add the field after `audioFolderName`:

```swift
    /// Cloud-LLM analysis (summary, action items, effectiveness), if the user has
    /// run "Run AI Analysis" on this meeting. Optional → old saved meetings decode
    /// unchanged.
    var analysis: MeetingAnalysis? = nil
```

(Place it directly after the existing line `var audioFolderName: String? = nil`.)

- [ ] **Step 2: Add the persistence method**

In the same file, directly after the `updateMeetingNotes(_:notes:)` method, add:

```swift

    /// Saves a cloud-LLM analysis onto a meeting in history and persists it.
    func updateMeetingAnalysis(_ meeting: MeetingSession, analysis: MeetingAnalysis) {
        guard let index = meetingHistory.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetingHistory[index].analysis = analysis
        saveMeetingHistory()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add app/KochiApp/Managers/GoalManager.swift
git commit -m "feat: persist MeetingAnalysis on MeetingSession"
```

---

## Task 8: CloudAnalysisManager

**Files:**
- Modify: `app/KochiApp/Managers/CloudAnalysisManager.swift`

- [ ] **Step 1: Implement the manager**

Replace the entire contents of `KochiApp/Managers/CloudAnalysisManager.swift`:

```swift
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
        let p = CloudProvider(rawValue: defaults.string(forKey: providerKey) ?? "") ?? .claude
        self.provider = p
        self.model = defaults.string(forKey: modelKey) ?? p.defaultModel
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add app/KochiApp/Managers/CloudAnalysisManager.swift
git commit -m "feat: add CloudAnalysisManager orchestrating analysis"
```

---

## Task 9: Inject the manager + AI settings tab

**Files:**
- Modify: `app/KochiApp/KochiApp.swift` (~lines 35–49)
- Modify: `app/KochiApp/ContentView.swift` (~lines 640–643)
- Modify: `app/KochiApp/Views/SettingsView.swift` (tab bar ~44–57, switch ~71–84, env objects ~10–12; add `AITab`)

- [ ] **Step 1: Register the manager at the app root**

In `KochiApp/KochiApp.swift`, after the line `@StateObject private var llmManager = LLMManager()`, add:

```swift
    @StateObject private var cloudAnalysisManager = CloudAnalysisManager()
```

And after the line `.environmentObject(llmManager)`, add:

```swift
                .environmentObject(cloudAnalysisManager)
```

- [ ] **Step 2: Add it to the ContentView preview environment**

In `KochiApp/ContentView.swift`, after the line `.environmentObject(LLMManager())` (~line 643), add:

```swift
            .environmentObject(CloudAnalysisManager())
```

- [ ] **Step 3: Add the env object to SettingsView**

In `KochiApp/Views/SettingsView.swift`, after `@EnvironmentObject var themeManager: ThemeManager` (~line 12), add:

```swift
    @EnvironmentObject var cloudAnalysisManager: CloudAnalysisManager
```

- [ ] **Step 4: Add the "AI" tab button and bump "About"**

In `SettingsView.swift`, replace the `About` tab button block (currently `isSelected: selectedTab == 3`) with the AI tab followed by About at index 4:

```swift
                        TabButton(title: "AI", icon: "sparkles", isSelected: selectedTab == 3) {
                            withAnimation { selectedTab = 3 }
                        }
                        TabButton(title: "About", icon: "info.circle", isSelected: selectedTab == 4) {
                            withAnimation { selectedTab = 4 }
                        }
```

Update the comment `// Beveled tab bar — 4 tabs` to `// Beveled tab bar — 5 tabs`.

- [ ] **Step 5: Route the new tab in the content switch**

In the `switch selectedTab` block, replace `case 3:` and add `case 4:`:

```swift
                        case 3:
                            AITab()
                        case 4:
                            AboutTab()
```

- [ ] **Step 6: Implement the AITab view**

At the end of `SettingsView.swift`, add this new view:

```swift

// MARK: - AI / API Key tab

/// Manages the optional cloud-LLM API key that unlocks post-meeting analysis.
struct AITab: View {
    @EnvironmentObject var cloudAnalysisManager: CloudAnalysisManager
    @State private var keyInput = ""
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                providerCard
                keyCard
                disclosureCard
            }
            .padding()
            .padding(.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("Provider") { EmptyView() }
            Picker("", selection: Binding(
                get: { cloudAnalysisManager.provider },
                set: { cloudAnalysisManager.selectProvider($0); keyInput = "" }
            )) {
                ForEach(CloudProvider.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 9) {
                Text("MODEL")
                    .font(KFont.mono(9, .medium))
                    .tracking(1.0)
                    .foregroundColor(KColor.muted)
                TextField(cloudAnalysisManager.provider.defaultModel, text: Binding(
                    get: { cloudAnalysisManager.model },
                    set: { cloudAnalysisManager.setModel($0) }
                ))
                .textFieldStyle(.plain)
                .font(KFont.sans(13, .medium))
                .foregroundColor(KColor.ink)
                .tint(KColor.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KColor.paper)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(KColor.line, lineWidth: 1))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("API Key") {
                Text(cloudAnalysisManager.hasKey ? "✓ Key saved" : "No key set")
                    .font(KFont.mono(10))
                    .foregroundColor(cloudAnalysisManager.hasKey ? KColor.good : KColor.muted)
            }
            SecureField("Paste your \(cloudAnalysisManager.provider.displayName) API key",
                        text: $keyInput)
                .textFieldStyle(.plain)
                .font(KFont.sans(13, .medium))
                .foregroundColor(KColor.ink)
                .tint(KColor.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KColor.paper)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(KColor.line, lineWidth: 1))
                )

            if let saveError {
                Text(saveError)
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.orangeDeep)
            }

            HStack(spacing: 8) {
                Button(action: saveKey) {
                    Text("Save")
                        .font(KFont.zilla(12.5, .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                if cloudAnalysisManager.hasKey {
                    Button(action: { cloudAnalysisManager.removeKey(); keyInput = "" }) {
                        Text("Remove key")
                            .font(KFont.zilla(12.5, .bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BeveledKeyStyle(variant: .light, radius: 7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
    }

    private var disclosureCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SlabLabel("Privacy") { EmptyView() }
            Text("Kōchi is on-device by default. With a personal API key, the meeting "
                 + "transcript you choose to analyze is sent to your selected provider "
                 + "(Anthropic or OpenAI). This is the only feature that leaves your device, "
                 + "and it only runs when you tap “Run AI Analysis” on a meeting.")
                .font(KFont.sans(12, .regular))
                .foregroundColor(KColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard()
    }

    private func saveKey() {
        do {
            try cloudAnalysisManager.saveKey(keyInput)
            keyInput = ""
            saveError = nil
        } catch {
            saveError = "Could not save the key to the Keychain."
        }
    }
}
```

- [ ] **Step 7: Build to verify it compiles**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Manual run-through (verifies Keychain + UI end-to-end)**

```bash
cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build
# Launch the built app, e.g.:
open ~/Library/Developer/Xcode/DerivedData/Kochi-*/Build/Products/Debug/KochiApp.app
```

In the running app: open Settings → AI tab. Confirm:
- Provider toggles Claude/OpenAI; model field shows the matching default.
- Paste any non-empty string, tap Save → status flips to "✓ Key saved".
- Quit and relaunch the app → status still shows "✓ Key saved" (Keychain persistence).
- Tap "Remove key" → status returns to "No key set".

- [ ] **Step 9: Commit**

```bash
git add app/KochiApp/KochiApp.swift app/KochiApp/ContentView.swift app/KochiApp/Views/SettingsView.swift
git commit -m "feat: add AI settings tab and inject CloudAnalysisManager"
```

---

## Task 10: Run + display analysis on a meeting

**Files:**
- Modify: `app/KochiApp/Views/SettingsView.swift` (`MeetingDetailView` ~line 758)

- [ ] **Step 1: Add manager + state to MeetingDetailView**

In `MeetingDetailView`, after `@EnvironmentObject var goalManager: GoalManager` (~line 764), add:

```swift
    @EnvironmentObject var cloudAnalysisManager: CloudAnalysisManager
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    /// The analysis to display — seeded from the saved meeting, updated on re-run.
    @State private var analysis: MeetingAnalysis?
```

- [ ] **Step 2: Seed the state and add the card to the scroll stack**

In the `ScrollView { VStack(...) { ... } }` (~lines 817–823), add the analysis card after `transcriptCard`:

```swift
                    sessionCard
                    goalsCard
                    transcriptCard
                    if cloudAnalysisManager.isConfigured || analysis != nil {
                        analysisCard
                    }
                    if let audioURL = audioURL { audioCard(audioURL) }
```

Then, on the outer `VStack(spacing: 0) { ... }` in `body`, add an `.onAppear` that seeds the displayed analysis from the saved meeting. Add this modifier right after the existing `.sheet(isPresented: $showAudioShare) { ... }` (~line 841):

```swift
        .onAppear { analysis = meeting.analysis }
```

- [ ] **Step 3: Implement the analysis card and run action**

At the end of `MeetingDetailView` (before its closing brace), add:

```swift

    // MARK: - AI analysis

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SlabLabel("AI Analysis") {
                if let analysis {
                    Text(analysis.provider)
                        .font(KFont.mono(9))
                        .foregroundColor(KColor.muted)
                }
            }

            if let analysis {
                analysisContent(analysis)
            } else {
                Text("Summarize this meeting into tasks and a professional-effectiveness review.")
                    .font(KFont.sans(12, .regular))
                    .foregroundColor(KColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let analysisError {
                Text(analysisError)
                    .font(KFont.mono(10))
                    .foregroundColor(KColor.orangeDeep)
            }

            if cloudAnalysisManager.isConfigured {
                Button(action: runAnalysis) {
                    HStack(spacing: 6) {
                        if isAnalyzing { ProgressView().controlSize(.small) }
                        Text(isAnalyzing ? "Analyzing…"
                             : (analysis == nil ? "Run AI Analysis" : "Re-run"))
                            .font(KFont.zilla(12.5, .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BeveledKeyStyle(variant: .primary, radius: 7))
                .disabled(isAnalyzing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(radius: 12, padding: 13)
    }

    @ViewBuilder
    private func analysisContent(_ a: MeetingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(a.summary)
                .font(KFont.sans(13, .medium))
                .foregroundColor(KColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !a.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ACTION ITEMS")
                        .font(KFont.mono(9, .medium)).tracking(1.0).foregroundColor(KColor.muted)
                    ForEach(Array(a.actionItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundColor(KColor.orange)
                            Text(item.owner.map { "\(item.task) — \($0)" } ?? item.task)
                                .font(KFont.sans(12.5, .regular))
                                .foregroundColor(KColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("EFFECTIVENESS")
                    .font(KFont.mono(9, .medium)).tracking(1.0).foregroundColor(KColor.muted)
                gradeRow("Communication", a.effectiveness.communication)
                gradeRow("Focus", a.effectiveness.focus)
                gradeRow("Professionalism", a.effectiveness.professionalism)
            }

            Text(a.overallCoaching)
                .font(KFont.sans(12.5, .regular))
                .foregroundColor(KColor.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gradeRow(_ title: String, _ d: Dimension) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(d.grade)
                .font(KFont.zilla(14, .bold))
                .foregroundColor(KColor.orangeDeep)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(KFont.sans(12, .semibold))
                    .foregroundColor(KColor.ink)
                Text(d.note)
                    .font(KFont.sans(11.5, .regular))
                    .foregroundColor(KColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runAnalysis() {
        isAnalyzing = true
        analysisError = nil
        Task {
            do {
                let result = try await cloudAnalysisManager.analyze(meeting: meeting)
                goalManager.updateMeetingAnalysis(meeting, analysis: result)
                analysis = result
            } catch let e as CloudLLMError {
                analysisError = message(for: e)
            } catch {
                analysisError = "Analysis failed. Please try again."
            }
            isAnalyzing = false
        }
    }

    private func message(for error: CloudLLMError) -> String {
        switch error {
        case .missingKey:   return "No API key set. Add one in Settings → AI."
        case .auth:         return "The API key was rejected. Check it in Settings → AI."
        case .rateLimited:  return "Rate limited by the provider. Try again shortly."
        case .refusal:      return "The model declined to analyze this transcript."
        case .badResponse:  return "The provider returned an unexpected response."
        case .http(let s):  return "Request failed (HTTP \(s))."
        case .network:      return "Network error. Check your connection and try again."
        }
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: End-to-end manual verification (requires a real API key)**

Launch the app. In Settings → AI, select Claude and paste a real Anthropic API key, Save. Open a saved meeting with a non-empty transcript:
- Confirm "Run AI Analysis" appears.
- Tap it → spinner → the card renders summary, action items (with owners), three letter-graded dimensions with notes, and overall coaching.
- Close the meeting and reopen it → the analysis is still shown (persisted).
- Tap "Re-run" → produces a fresh analysis.
- Temporarily set an invalid key → tapping run shows the "API key was rejected" message without crashing.

- [ ] **Step 6: Commit**

```bash
git add app/KochiApp/Views/SettingsView.swift
git commit -m "feat: run and display cloud AI analysis on a saved meeting"
```

---

## Task 11: Regression check + final verification

**Files:** none (verification only)

- [ ] **Step 1: No-key regression — confirm the on-device path is unchanged**

With **no** API key saved (Remove key in Settings → AI for both providers), launch the app and open a saved meeting. Confirm:
- The "AI Analysis" card shows no "Run AI Analysis" button (it only appears when `isConfigured`), and no analysis section is forced.
- All existing behavior (transcript, goals, audio, copy) works exactly as before.

- [ ] **Step 2: Full clean build**

Run: `cd app && xcodebuild -project Kochi.xcodeproj -scheme KochiApp -destination 'platform=macOS' clean build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Confirm backward compatibility of saved meetings**

Confirm that meetings saved before this feature still open without error (the `analysis` field is optional, so old JSON decodes with `analysis == nil`). Open at least one pre-existing meeting from history.

- [ ] **Step 4: Final commit (if any cleanup was needed)**

```bash
git status   # should be clean if no changes were needed
```

---

## Self-review notes

- **Spec coverage:** Providers (Task 5/6), manual trigger (Task 10), summary + action-items-with-owners + effectiveness coaching (Task 3 models, Task 10 display), letter grades (Task 3 `normalizeGrade` + Task 10 `gradeRow`), default model `claude-sonnet-4-6` (Task 3 `CloudProvider.defaultModel`), new AI tab (Task 9), Keychain storage (Task 2), `MeetingAnalysis` persisted on `MeetingSession` (Task 7), opt-in/off-by-default + privacy disclosure (Task 9 `disclosureCard`, Task 10 button gated on `isConfigured`), single-request whole-transcript (Task 8 `analyze`). All covered.
- **Type consistency:** `MeetingAnalysis.from(jsonText:providerLabel:date:)` is defined in Task 3 and called identically in Task 8. `cloudError(forStatus:)`, `CloudLLMError`, `AnalysisSchema.jsonSchema`, `AnalysisPrompt.system/user`, `CloudProvider.defaultModel/keychainAccount/displayName`, `KeychainStore.save/read/delete`, `CloudAnalysisManager.isConfigured/analyze/selectProvider/setModel/saveKey/removeKey/hasKey/provider/model`, `GoalManager.updateMeetingAnalysis` — all names match across tasks.
- **Out of scope (deferred):** streaming, auto-on-end, editable prompt, chunked map-reduce, wiring a real XCTest target.
