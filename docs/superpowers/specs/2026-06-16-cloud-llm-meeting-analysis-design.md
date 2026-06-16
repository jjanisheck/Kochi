# Cloud LLM Post-Meeting Analysis — Design

**Date:** 2026-06-16
**Status:** Approved (design phase)
**Author:** Joey Janisheck (with Claude)

## Problem

Kōchi summarizes meetings with Apple's on-device Foundation Models, which have a
~4096-token context window. Any meeting longer than ~15–20 minutes overflows that
window; the current fallback (`FoundationModelsService.swift:76`) keeps only the
*last 50%* of the transcript, silently dropping the first half — exactly where
action items and ownership are often established. The result is unreliable
"who's doing what" extraction for real-length meetings.

## Goal

Add an **opt-in** ability to run a finished meeting's transcript through a cloud
LLM (Anthropic Claude or OpenAI) using the user's own API key. When configured,
this unlocks a post-meeting analysis that produces:

1. A meeting **summary**.
2. **Action items** with owners (who is doing what).
3. A **professional-effectiveness review** — how well the user communicated,
   stayed focused, and conducted themselves.

The analysis is saved alongside the existing goals, timestamp, and raw transcript.

Cloud models have 200K–1M-token context windows, so the entire transcript fits in
a single request — eliminating the on-device truncation problem.

## Non-goals (v1 / YAGNI)

- No streaming responses (single request + spinner).
- No auto-run on meeting end (manual button only).
- No user-editable analysis prompt (fixed prompt in v1).
- No multi-key management (one key per provider).
- No retry/backoff loop (surface the error; user re-clicks).

## Guiding principle — preserve the privacy promise

Kōchi's identity is "100% on-device, no API keys." This feature must not erode
that for users who don't opt in:

- **Off by default.** With no key saved, the app behaves exactly as today —
  on-device Foundation Models only. No network code runs.
- **Explicit consent twice:** saving a key, and clicking "Run AI Analysis" per
  meeting. Nothing is sent automatically.
- **Plain disclosure** in the AI settings tab: *"With a personal API key, your
  meeting transcript is sent to Anthropic/OpenAI for analysis. This is the only
  feature that leaves your device."*

## User decisions (locked)

| Decision | Choice |
|---|---|
| Providers | Claude **and** OpenAI (user-selectable) |
| Trigger | Manual "Run AI Analysis" button per saved meeting |
| Output | Summary + action items (with owners) + effectiveness coaching |
| Effectiveness format | **Letter grade (A–F) + short note** per dimension |
| Default Claude model | `claude-sonnet-4-6` (user-overridable) |
| Settings location | New top-level **"AI"** tab |

## Architecture

All Apple-framework / `URLSession` only — **no Swift Package added** (consistent
with the project's no-dependencies rule). There is no official Anthropic Swift
SDK, so we call the REST API directly.

### New components

| File | Role |
|---|---|
| `Services/KeychainStore.swift` | Minimal `SecItem` wrapper: `save`/`read`/`delete` by account. First Keychain use in the app — API keys never touch `UserDefaults`. |
| `Managers/CloudAnalysisManager.swift` | `ObservableObject`. Owns provider + model (in `UserDefaults`) and the key (in Keychain). Exposes `isConfigured`, `analyze(meeting:) async throws -> MeetingAnalysis`. Builds prompt, dispatches to client, parses result. |
| `Services/CloudLLM/CloudLLMClient.swift` | Protocol: `func complete(system: String, user: String, schema: [String: Any]) async throws -> String`. Plus `CloudLLMError` enum. |
| `Services/CloudLLM/AnthropicClient.swift` | `POST https://api.anthropic.com/v1/messages`. Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type`. Body: `{model, max_tokens, system, messages, output_config:{format:{type:"json_schema", schema}}}`. Detects `stop_reason == "refusal"` before parsing. |
| `Services/CloudLLM/OpenAIClient.swift` | `POST https://api.openai.com/v1/chat/completions`. Header: `Authorization: Bearer`. Body uses `response_format: {type:"json_schema", json_schema:{...}}`. |

### Model defaults

- **Claude:** `claude-sonnet-4-6` (strong for summarization/coaching, ~40% cheaper
  than Opus; a single meeting transcript costs cents). User-overridable to
  `claude-opus-4-8` or others via a text field.
- **OpenAI:** editable model string, default `gpt-5.5`. OpenAI model IDs are the
  user's to set — presented as a text field, not a fixed picker, because the
  exact current OpenAI model strings are not verified in this codebase.

### Data model

Extend the existing `MeetingSession` (`Managers/GoalManager.swift:328`) with one
optional, `Codable`, backward-compatible field:

```swift
var analysis: MeetingAnalysis? = nil
```

New types (saved transparently inside the existing `meetingHistory` UserDefaults
JSON blob, alongside goals / timestamps / notes):

```swift
struct MeetingAnalysis: Codable {
    var summary: String
    var actionItems: [ActionItem]
    var effectiveness: Effectiveness
    var overallCoaching: String
    var provider: String      // e.g. "Claude (claude-sonnet-4-6)" — provenance
    var generatedAt: Date
}

struct ActionItem: Codable {
    var task: String
    var owner: String?        // nil when no owner was stated
}

struct Effectiveness: Codable {
    var communication: Dimension
    var focus: Dimension
    var professionalism: Dimension
}

struct Dimension: Codable {
    var grade: String         // "A" … "F"
    var note: String
}
```

`GoalManager` gains `updateMeetingAnalysis(_ meeting: MeetingSession, analysis: MeetingAnalysis)`
mirroring the existing `updateMeetingNotes` (`GoalManager.swift:181`), which finds
the meeting by `id` and re-saves history.

## Prompt design

System prompt frames Claude/GPT as a meeting-effectiveness coach. The transcript
is speaker-separated (`Me:` / `Them:`), so the effectiveness review focuses on the
`Me:` turns. The user prompt embeds the goals (for context), the transcript, and
requests the structured JSON schema. Both providers are asked for the same JSON
shape via their structured-output features; the parser is defensive (decodes the
returned JSON string into `MeetingAnalysis`, surfaces `CloudLLMError.badResponse`
on mismatch).

## UI

### New "AI" tab in `Views/SettingsView.swift`

`SettingsView` currently switches `selectedTab` across 4 tabs
(`SettingsView.swift:44`). Add a 5th: `Transcripts · Search · Goals · AI · About`.
Built entirely with the existing design system — `kCard()`, `SlabLabel`,
`KColor`/`KFont`, `BeveledKeyStyle`, and the existing search-field styling pattern
(`SettingsView.swift:326`) reused for a `SecureField`.

Contents:
- Provider segmented picker (Claude / OpenAI).
- `SecureField` for the API key.
- Model text field (prefilled with the provider default).
- "Save" button (`BeveledKeyStyle(variant: .primary)`) + "Remove key" button.
- Live status: "✓ Key saved" / "No key set".
- Privacy disclosure text.

### "Run AI Analysis" in `MeetingDetailView`

On each saved meeting's detail panel, add a button shown only when
`cloudAnalysisManager.isConfigured`. States:
- **Idle:** "Run AI Analysis" (or "Re-run" if an analysis already exists).
- **Loading:** spinner + "Analyzing…".
- **Done:** renders the saved `MeetingAnalysis` — summary, action items (task +
  owner), the three letter-graded dimensions with notes, and overall coaching.
- **Error:** inline, non-destructive message.

Result persists via `goalManager.updateMeetingAnalysis(...)` and re-renders from
the saved model on subsequent opens.

## Error handling

```swift
enum CloudLLMError: Error {
    case missingKey, auth, rateLimited, network(Error), badResponse, refusal
}
```

- Anthropic refusal: HTTP 200 + `stop_reason: "refusal"` → `.refusal`.
- 401 → `.auth`; 429 → `.rateLimited`; transport failures → `.network`.
- JSON decode failure → `.badResponse`.
- No automatic retry in v1.

## Backward compatibility & testing

- `MeetingAnalysis?` is optional → old saved meetings decode unchanged.
- Keychain wrapper is additive; no migration.
- Verify: macOS build succeeds (`xcodebuild ... build`); existing tests pass;
  a meeting analyzed with a real key round-trips (save → reopen → still shows).
- The no-key path must be verified to behave identically to today.

## Out of scope / future

- Auto-analyze-on-end toggle.
- Streaming the analysis as it generates.
- Editable coaching prompt / custom rubric.
- Chunked map-reduce (unnecessary for cloud context windows; would matter only if
  we later improve the *on-device* path).
