# Text Postprocessing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, disabled-by-default rule that removes one final ASCII period from completed dictation without changing other punctuation or slowing the disabled path.

**Architecture:** Persist one Boolean in the existing `Settings` store and pass it into the shared `processedDictationText` function used by normal and recovery transcription paths. A small pure transform handles only the enabled case; the shared processor branches before invoking it. The existing AppKit settings draft/save flow exposes the option without restarting the speech model.

**Tech Stack:** Swift 6, AppKit, Foundation `UserDefaults`, existing command-line self-test harness, shell verification scripts.

## Global Constraints

- The settings labels are exactly `Обработка текста` / `Text processing` and `Убирать точку в конце` / `Remove final period`.
- The setting defaults to `false` and existing users retain current behavior.
- Enabled behavior removes only one literal final ASCII `.`; `!`, `?`, `...`, `…`, internal periods, and empty text remain unchanged.
- The transform runs after model repair, custom corrections, and optional filler removal, but before history storage and text insertion.
- When disabled, the pure period-removal function is not called; the completed-transcript path pays only one Boolean branch.
- Normal and recovery transcription paths must use the same saved value.
- Saving this setting must not restart or reload the speech model.
- The only runnable installed bundle remains `/Applications/SuperDictate.app` with bundle identifier `com.local.superdictate`.
- Local installation must use `scripts/install-local.sh`; never reset TCC permissions or launch copied/test bundles.

---

### Task 1: Pure Final-Period Rule And Shared Processing Path

**Files:**
- Modify: `swift/Sources/Parakey/main.swift:5836-5863`
- Test: `swift/Sources/Parakey/main.swift:17089-17120`
- Test: `swift/Sources/Parakey/main.swift:19821-19880`

**Interfaces:**
- Consumes: `processedDictationText(rawTranscript:corrections:removeFillerWords:removeFinalPeriod:language:)` inputs from every transcription completion path.
- Produces: `removingFinalPeriod(from: String) -> String` and a new `removeFinalPeriod: Bool = false` processing argument.

- [ ] **Step 1: Write failing tests for the pure rule and disabled shared path**

Add assertions equivalent to:

```swift
try expect(removingFinalPeriod(from: "Привет."), equals: "Привет", "final period should be removed")
try expect(removingFinalPeriod(from: "Привет!"), equals: "Привет!", "exclamation mark should remain")
try expect(removingFinalPeriod(from: "Привет?"), equals: "Привет?", "question mark should remain")
try expect(removingFinalPeriod(from: "Ну вот..."), equals: "Ну вот...", "ASCII ellipsis should remain")
try expect(removingFinalPeriod(from: "Ну вот…"), equals: "Ну вот…", "Unicode ellipsis should remain")
try expect(removingFinalPeriod(from: "Версия 1.2 готова."), equals: "Версия 1.2 готова", "internal periods should remain")
try expect(removingFinalPeriod(from: ""), equals: "", "empty text should remain empty")

let disabled = processedDictationText(
    rawTranscript: "Привет.",
    corrections: [],
    removeFillerWords: false,
    removeFinalPeriod: false
)
try expect(disabled.text, equals: "Привет.", "disabled rule should preserve the final period")
```

- [ ] **Step 2: Run the targeted self-test and verify RED**

Run: `swift run -c debug --package-path swift Parakey --self-test paste`

Expected: compilation fails because `removingFinalPeriod(from:)` and the new processor argument do not exist.

- [ ] **Step 3: Implement the minimal pure transform and gated shared processing**

Implement a pure function that returns immediately unless the final character is `.` and the preceding character is not another `.`, then returns `String(text.dropLast())`. Refactor `processedDictationText` so filler removal first produces a local text value, then:

```swift
let finalText = removeFinalPeriod
    ? removingFinalPeriod(from: textAfterFillers)
    : textAfterFillers
```

Return `finalText` while preserving correction and filler counts. The ternary ensures the transform is not invoked when disabled.

- [ ] **Step 4: Pass the saved setting through every completion path**

At all three calls around the startup recovery, normal dictation, and fallback recovery paths, add:

```swift
removeFinalPeriod: settings.removeFinalPeriod,
```

- [ ] **Step 5: Run targeted tests and verify GREEN**

Run:

```bash
swift run -c debug --package-path swift Parakey --self-test paste
swift run -c debug --package-path swift Parakey --self-test corrections
swift run -c debug --package-path swift Parakey --self-test fillers
```

Expected: all three suites print `PASS`.

---

### Task 2: Persisted Setting And Control Panel

**Files:**
- Modify: `swift/Sources/Parakey/main.swift:2615-2650`
- Modify: `swift/Sources/Parakey/main.swift:3255-3280`
- Modify: `swift/Sources/Parakey/main.swift:13612-13620`
- Modify: `swift/Sources/Parakey/main.swift:20893-20920`
- Modify: `swift/Sources/Parakey/main.swift:21194-21295`
- Modify: `swift/Sources/Parakey/main.swift:21870-22180`
- Modify: `swift/Sources/Parakey/main.swift:22718-22950`
- Test: `swift/Sources/Parakey/main.swift` existing settings self-test area discovered by `rg 'Settings\('`.

**Interfaces:**
- Consumes: `Settings`, `ControlPanelSettingsDraft`, the existing `NSSwitch` target/action pattern, and the existing save notification flow.
- Produces: `Settings.removeFinalPeriod: Bool`, `ControlPanelSettingsDraft.removeFinalPeriod: Bool`, `toggleRemoveFinalPeriod(_:)`, and one bilingual control-panel row.

- [ ] **Step 1: Write a failing persistence test**

Create an isolated `UserDefaults` suite, remove its persistent domain, initialize `Settings(defaults:)`, assert `removeFinalPeriod == false`, assign `true`, call `synchronize()`, initialize a second `Settings(defaults:)`, and assert the second instance reads `true`. Clean up the suite at the end.

- [ ] **Step 2: Run the owning self-test and verify RED**

Run the suite containing the new assertion (or `--self-test all` if the settings assertions live in the aggregate suite).

Expected: compilation fails because `Settings.removeFinalPeriod` does not exist.

- [ ] **Step 3: Add the persisted property**

Add key `remove_final_period_v1` and:

```swift
var removeFinalPeriod: Bool {
    get { defaults.bool(forKey: Self.keyRemoveFinalPeriod) }
    set { defaults.set(newValue, forKey: Self.keyRemoveFinalPeriod) }
}
```

No registration default is needed because `UserDefaults.bool(forKey:)` returns `false` when absent.

- [ ] **Step 4: Add draft, row, toggle, save, and diagnostics wiring**

Add `removeFinalPeriod` to `ControlPanelSettingsDraft` and initialize it from settings. Add a compact section header plus an `NSSwitch` row after microphone settings and before capsule appearance settings, using:

```swift
t("Обработка текста", "Text processing")
t("Убирать точку в конце", "Remove final period")
t("Убирает только последнюю точку. !, ?, многоточия и точки внутри текста сохраняются.",
  "Removes only the final period. !, ?, ellipses, and periods inside the text remain.")
```

Wire `toggleRemoveFinalPeriod(_:)` to mutate only the draft, and write `settings.removeFinalPeriod = draft.removeFinalPeriod` in `saveSettingsClicked`. Add the saved value to diagnostics and any settings render fingerprint needed for live refresh. Do not invoke a service operation or model reload.

- [ ] **Step 5: Adjust the fixed settings window only if the new row is clipped**

Build the layout first. If the content exceeds the existing 680x660 window, increase only its fixed height enough to show all controls without overlap; preserve width and current visual style.

- [ ] **Step 6: Run persistence and aggregate tests**

Run:

```bash
swift run -c debug --package-path swift Parakey --self-test all
```

Expected: every suite prints `PASS`, including default-disabled and persistence assertions.

---

### Task 3: Repository Verification And Local Installation

**Files:**
- Verify: `swift/Sources/Parakey/main.swift`
- Verify: `scripts/check.sh`
- Install through: `scripts/install-local.sh`

**Interfaces:**
- Consumes: the complete Tasks 1-2 implementation.
- Produces: one verified local `/Applications/SuperDictate.app`; no public release or version bump is part of this plan.

- [ ] **Step 1: Run formatting and repository checks**

Run:

```bash
git diff --check
./scripts/check.sh
```

Expected: no whitespace errors and `SuperDictate checks passed`.

- [ ] **Step 2: Build and install through the invariant-preserving script**

Run: `./scripts/install-local.sh`

Expected: the script atomically replaces `/Applications/SuperDictate.app`, preserves the stable signing identity, and restarts only `com.local.superdictate.agent`.

- [ ] **Step 3: Verify the installed singleton and runtime**

Run commands that confirm:

```text
/Applications/SuperDictate.app has bundle id com.local.superdictate
exactly one com.local.superdictate.agent process is running
the runtime state reaches ready
```

- [ ] **Step 4: Inspect the final diff and commit**

Review `git diff --stat`, `git diff -- swift/Sources/Parakey/main.swift`, and `git status --short`. Commit only the implementation and plan with an explicit message such as `Add optional final period removal`.
