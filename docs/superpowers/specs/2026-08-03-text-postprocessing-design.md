# Text Postprocessing Settings

## Goal

Add a small, extensible **Text processing** section to SuperDictate settings.
The first and only rule in this release is an optional removal of the final
period produced by the speech model.

## User Experience

- Add a settings section named `Обработка текста` / `Text processing`.
- Add one checkbox named `Убирать точку в конце` / `Remove final period`.
- The checkbox is off by default, so existing users keep the current output.
- The description explains that only the final `.` is removed. Question marks,
  exclamation marks, ellipses, and punctuation inside the text are preserved.
- The setting is saved and applied through the existing settings flow.

## Text Rule

The rule runs after model text repair, custom corrections, and optional filler
removal, but before the transcript is added to history and inserted.

When enabled:

- `Привет.` becomes `Привет`.
- `Привет!` and `Привет?` remain unchanged.
- `Ну вот...` and `Ну вот…` remain unchanged.
- Internal periods remain unchanged.
- An empty transcript remains empty.

This first version only removes a literal final ASCII period. It does not try
to infer abbreviations or rewrite sentence structure.

## Performance

The saved setting defaults to `false`. When it is disabled, the postprocessing
rule function is not called and no string scan or copy is performed. The normal
path pays only one boolean branch while processing a completed transcript; audio
capture and model inference are unaffected.

## Architecture

- Persist a new boolean setting in the existing `Settings` store.
- Keep the period-removal transform as a small pure function so it can be tested
  independently and later joined by other explicit text rules.
- Gate the transform at the call site. Do not create or execute a generic rule
  pipeline while all postprocessing rules are disabled.
- Apply the same setting to normal dictation and recovery transcription paths so
  history and inserted text remain consistent.

## Verification

- Unit-test enabled and disabled behavior, including `.`, `!`, `?`, `...`, `…`,
  internal punctuation, and empty text.
- Verify the default remains disabled and persists across settings reloads.
- Run the full self-test suite and build the signed app locally.
- Confirm changing the checkbox does not restart or reload the speech model.
