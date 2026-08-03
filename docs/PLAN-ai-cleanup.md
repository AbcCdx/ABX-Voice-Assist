# Plan: AI Transcript Cleanup ("Wispr Flow-style" post-processing)

> Status: ready to execute. Grounded in upstream `shlgd/SuperDictate` @ `d15ef38` (v0.2.39).
> All line numbers refer to `swift/Sources/Parakey/main.swift` unless noted.

## Goal

After ASR produces a transcript and existing local post-processing runs, optionally
send the text to an LLM (OpenAI-compatible chat-completions API) to fix grammar,
punctuation, and obvious recognition mistakes, then paste the improved text.
Users bring their own API key (BYOK). Default provider preset: OpenCode Zen
(`https://opencode.ai/zen/v1`), default model `north-mini-code-free` (free, fast),
but any OpenAI-compatible endpoint/model must work (OpenAI, OpenRouter, etc.).

## Non-negotiable design rules

1. **Off by default.** Privacy-first app; existing behavior unchanged until the
   user enables the feature and enters a key.
2. **Never lose a transcript.** On any AI failure (network, timeout, bad JSON,
   empty output) paste the pre-AI `cleaned` text. Do NOT route through
   `dictationFailed` (that path pastes nothing, `12078`).
3. **Never block the main thread.** The hotkey event tap dies after a >1s
   main-runloop stall (`7060–7068`). All networking is `await`ed — the pipeline
   is already async end-to-end.
4. **Secrets never in UserDefaults/repo/logs.** API key goes to macOS Keychain.
   Log lines must never contain transcript text or keys (PRIVACY.md rule).
5. **Docs stay truthful.** PRIVACY.md ("Network access", lines 16–21) currently
   promises network is only used for model downloads and update checks — must be
   updated. README too if it claims fully-offline operation.

## API facts (OpenCode Zen)

- Chat completions: `POST https://opencode.ai/zen/v1/chat/completions`
  (OpenAI-compatible; `Authorization: Bearer <key>`, `messages` array).
- Model list/metadata: `GET https://opencode.ai/zen/v1/models` (use for the
  "Test connection" button).
- Default model id: `north-mini-code-free` (free tier).
- **Privacy caveat to surface in UI:** during its free period, North Mini Code
  Free *retains submitted data* for model improvement. Add an inline warning in
  the settings UI and let users switch to a paid model (e.g. `deepseek-v4-flash`,
  $0.14/$0.28 per 1M tokens, zero-retention) or another provider. Dictation is
  personal — the user must make this choice knowingly.
- Zen free models may change/disappear; model must be an editable text field
  with the default prefilled, not a hardcoded constant.

## Architecture

New stage in the dictation pipeline:

```
ASR result
 → SpeechModelTextRepair          (existing, 5847)
 → TranscriptCorrector.apply      (existing user corrections, 5848)
 → FillerWordRemover              (existing, if enabled, 5856)
 → AICleanupService.clean         (NEW — optional, network)
 → history + paste                (existing)
```

AI cleanup runs **last**, so the LLM sees the user's canonical corrections and
cannot resurrect removed filler words.

### Hook point

In `ParakeyApp.handleRelease` (recording stops at `11898`, result handled in the
`Task { @MainActor in` at `11972`):

- `let cleaned = processed.text` at `11994`, history at `11998`, paste at `12024`.
- Insert between `11994` and `11996`:

```swift
var finalText = cleaned
if settings.aiCleanupEnabled, !cleaned.isEmpty {
    let started = Date()
    do {
        finalText = try await AICleanupService.shared.clean(
            text: cleaned, language: language)
        aiCleanupSeconds = Date().timeIntervalSince(started)   // log via DictationLatencyMetrics
    } catch {
        log("AI cleanup failed, pasting raw transcript: \(error.localizedDescription)")
        flashErrorFeedback()   // subtle signal; text still delivered
    }
}
```

- Use `finalText` for history (`11998`) and paste (`12024`) — history stores what
  was actually pasted. (Alternative considered: store pre-AI text; rejected —
  history should match what landed in the target app.)
- Recovery paths (`recoverPendingDictationsAfterStartup` processing at `10562`,
  `recoverActiveRecordingToHistory` at `12143`) write history only and never
  paste — leave them WITHOUT AI cleanup (no network on recovery; keep it simple).

### New types (add near the other post-processing stages, ~`5600`)

```swift
struct AICleanupSettings: Equatable {
    var enabled: Bool            // UserDefaults ai_cleanup_enabled
    var baseURL: String          // ai_cleanup_base_url, default https://opencode.ai/zen/v1
    var model: String            // ai_cleanup_model, default north-mini-code-free
    var timeoutSeconds: Double   // constant 3.0, not user-editable
    // API key: Keychain only, service "com.local.superdictate.ai", account "api-key"
}

enum AICleanupError: LocalizedError {   // mirror UpdateCheckFailure style (7581)
    case noAPIKey, network(Error), httpStatus(Int), unexpectedResponse, emptyResult
}

enum AICleanupService {
    static func clean(text: String, language: DictationLanguage) async throws -> String
    // internal, pure & unit-testable:
    static func makeRequestBody(text:language:model:) -> [String: Any]   // prompt lives here
    static func parseResponse(_ data: Data) throws -> String             // OpenAI shape
    static func sanitizeOutput(_ raw: String, original: String) -> String // strip fences/quotes
}

enum AIKeyStore {   // thin Security-framework wrapper, ~50 lines
    static func read() -> String?
    static func write(_ key: String) throws
    static func delete() throws
}
```

### Request details

- Mirror `UpdateCheck.fetchLatest` (`7612`): ephemeral `URLSessionConfiguration`,
  caching disabled, explicit timeouts, `defer { session.finishTasksAndInvalidate() }`,
  response size cap (256 KB), validate HTTPURLResponse + 2xx.
- `timeoutInterval = 3.0` (dictation is latency-sensitive; total added wait must
  stay < ~3s. `isBusy` blocks new recordings while we wait, `11848`).
- Body: `model`, `messages: [system, user]`, `temperature: 0.2`,
  `max_tokens: max(256, inputTokens * 2)`. No streaming.
- System prompt (English regardless of UI language; instruct model to preserve
  the input language):

```
You are a dictation post-processor. The user spoke the text below; it was
transcribed by a speech-to-text model and may contain recognition errors,
missing punctuation, wrong homophones, and grammar mistakes. Rewrite it as
the speaker intended: fix punctuation, capitalization, grammar, and obvious
transcription errors using context. Remove leftover filler words and false
starts. Keep the original meaning, tone, and language. Output ONLY the
corrected text — no explanations, no quotes, no markdown.
```

- `sanitizeOutput`: trim, strip wrapping quotes / ``` fences, collapse 3+
  newlines; if result is empty or >3× input length, throw `.unexpectedResponse`
  (falls back to raw).

### Settings persistence

Follow the existing `Settings` pattern (`2589`, keys at `2590–2633`):

- `ai_cleanup_enabled` → Bool, default `false` (like `removeFillerWords`, `3267`).
- `ai_cleanup_base_url`, `ai_cleanup_model` → String with defaults.
- Key: **Keychain via `AIKeyStore`** (SecItemAdd/CopyMatching/Delete,
  `kSecClassGenericPassword`). No entitlement needed — app is not sandboxed
  (`entitlements.plist` has only mic keys; Hardened Runtime needs nothing for
  Keychain or outbound HTTPS).
- Cross-process propagation is free: control panel posts
  `SETTINGS_CHANGED_NOTIFICATION` and the agent re-reads settings on every
  release (`11904`). Keychain reads are per-dictation, always fresh.

### UI

1. **Menu bar** (strings hardcoded English here, no `t()`): Text submenu
   `buildTextSettingsItem` (`14042`) — add toggle "AI cleanup" with `on/off`
   state mark, selector like `toggleRemoveFillerWords` (`15522`). Disabled state
   (dimmed, subtitle "add API key in Settings") when no key stored.
2. **Control panel** (`SuperDictateControlPanelApp`, `20946`; content at
   `makeSettingsContentView` `21194`): new "AI Cleanup" section after
   `enterDelayRow` (`21214`), following the draft/save pattern
   (`ControlPanelSettingsDraft` `20893`, `saveSettingsClicked` `22911`):
   - Enable checkbox, base-URL field, model field (prefilled defaults),
     API-key secure field (write-once; show "•••• saved" state; "Remove key"
     button), "Test connection" button (GET `{base}/models` with the key,
     report ok/HTTP status via existing alert style `showError` `22972`).
   - Inline privacy note (localized): free Zen models may retain data; link to
     https://opencode.ai/docs/zen/.
   - All strings via `t("…ru…", "…en…")` (Localization.swift pattern; app is
     RU/EN only).

### Latency observability

Add `aiCleanupSeconds: Double?` to `DictationLatencyMetrics` (`918`) alongside
`postprocessingSeconds` (`932`), include in the log line (`969`) — never log text.

### Self-tests (no XCTest exists — in-binary harness)

Add suite `ai-cleanup`:
- dispatch: `case "ai-cleanup"` near `16211`, runner `testAICleanup()`,
  register in `testAll` (`16265`).
- Cover pure functions only (model: `UpdateCheck.parseLatest` tests):
  prompt-body construction, `parseResponse` (valid OpenAI JSON, missing
  choices, error body, >cap), `sanitizeOutput` (fences, quotes, empty,
  oversized), fallback decision logic.
- No network in tests. Verify with:
  `swift run -c debug --package-path swift Parakey --self-test all`

### Docs

- PRIVACY.md: new subsection — when AI cleanup is enabled, transcript text is
  sent to the user-configured endpoint; key stored in Keychain; off by default.
- README.md: feature paragraph + setup (get key at opencode.ai → Zen, paste in
  Settings → AI Cleanup). Do NOT commit any real key.
- `docs/privacy/network-calls.json` is referenced by the comment at `7615–7617`
  but doesn't exist in this checkout — if it appears later, add the new call.

## Execution steps (suggested order)

1. `AIKeyStore` + self-test for round-trip (manual check only; Keychain in
   self-test binary may prompt — keep automated tests to pure functions).
2. `AICleanupSettings` keys + `Settings` computed properties.
3. `AICleanupService` (pure parts first: body/parse/sanitize) + `ai-cleanup`
   self-test suite green.
4. Pipeline hook in `handleRelease` + `DictationLatencyMetrics` field.
5. Menu-bar toggle; 6. Control-panel section + Test button; 7. Localizations.
8. PRIVACY.md / README.md updates.
9. `./scripts/check.sh`, full self-test suite, then `scripts/install-local.sh`
   (builds via `swift build -c release --package-path swift`, signs with the
   stable Apple Development identity, atomically swaps `/Applications/SuperDictate.app`
   — per AGENTS.md invariants; never launch a copied bundle).
10. Manual smoke: dictate with feature off (unchanged), on with bad key
    (raw text pastes + error flash), on with good key (cleaned text pastes,
    ~1–2s added latency), RU and EN dictation.

## Open decisions for the user (defaults chosen, change if desired)

- Default model `north-mini-code-free` despite its free-tier data retention —
  flagged in UI; easy to switch. Cheapest zero-retention alternative on Zen:
  `deepseek-v4-flash`.
- History stores post-AI text (what was pasted).
- AI cleanup skipped in recovery paths (no surprise network calls on launch).
