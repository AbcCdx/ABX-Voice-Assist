# ABX Voice Assist Tasks

## Deferred: optional Google Cloud translation

Status: deferred. Apple Translation remains the active and default engine.

### Context

- The free `translate.google.com` website must not be embedded, automated, or scraped.
  It is not a supported application API and can change or block automation at any time.
- Google Cloud Translation NMT is the supported server-side integration for English to
  Russian and Russian to English.
- Google Cloud currently credits the first 500,000 NMT characters each month. Google AI
  Pro may also provide $10 in monthly Google Cloud credits through Google Developer
  Program Premium. Before implementation, verify the exact subscription, redemption,
  billing account, project eligibility, and whether the credit applies to this project.
- The user does not authorize paid translation. The application must never silently
  exceed the free allowance.

### Proposed design

- Keep Apple Translation as the offline default and permanent fallback.
- Add Google Cloud NMT only as an explicit optional engine.
- Store its restricted credential in macOS Keychain, never in preferences, logs, source,
  or the repository.
- Explain before activation that translated text is sent to Google.
- Count submitted characters locally by billing month and stop Google requests at a
  conservative limit, initially 450,000 characters.
- Fall back automatically to Apple on the local limit, missing network, timeout,
  authentication failure, quota response, or any Google service error.
- Show the selected engine, current monthly character count, limit, and fallback state in
  Advanced settings.
- Do not reuse the Google Translate website, browser cookies, DOM automation, or hidden
  web views.

### Validation before release

- Compare Apple and Google on the same reviewed set of at least 100 real EN/RU and RU/EN
  phrases, including long dictation, ambiguity, slang, punctuation, names, and ABX project
  terms.
- Confirm Google provides a meaningful quality improvement before retaining the option.
- Test that the hard local limit cannot be bypassed by retries, restarts, month changes,
  concurrent requests, or failed responses.
- Verify API keys are restricted to Cloud Translation and never appear in diagnostics.
- Verify every Google failure returns to Apple without losing or duplicating user text.

