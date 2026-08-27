# Dictation post-processing

## Goal

Turn a local ASR transcript into the text the speaker intended without
answering the speaker, inventing facts, or changing meaning.

## Current pipeline

1. A local audio gate rejects silence and steady low-level noise before ASR.
2. Parakeet TDT 0.6B v3 runs locally through FluidAudio and Core ML. Automatic
   mode is limited to Russian, English, and Ukrainian verification when the
   first decode has low confidence.
3. Empty or suspicious low-confidence stock phrases are rejected.
4. Token timestamps place exactly one line break at a deliberate logical pause.
   Ordinary hesitations and list pauses remain inside the same paragraph.
5. Deterministic repair removes known ASR artifacts.
6. A conservative project dictionary replaces complete spoken aliases with
   canonical English names.
7. User corrections override built-in aliases.
8. Optional filler removal and app-specific punctuation rules run locally.
9. History receives the same final content prepared for insertion. Insertion
   publishes one text-only pasteboard item and restores the previous clipboard
   only after the target reads the full string.
10. Cloud LLM cleanup is not part of the required local path. A future local
    model must pass meaning-preservation and hallucination tests before use.

## Canonical project dictionary

| Canonical name | Spoken aliases |
| --- | --- |
| `ABLX` | `аблэкс`, `аблекс`, `абл икс`, `эй би эл экс` |
| `ABX Voice Assist` | `абикс войс ассист`, `аб икс войс ассист`, `эй би экс войс ассист`, `войс ассист` |

The list stays intentionally small. Add an alias only after it appears in a
real transcript. Broad or ambiguous aliases can corrupt ordinary speech.

## Next research-backed stage

Use the confirmed private corpus and live corrections to measure future local
model changes against the current Parakeet TDT v3 baseline. Whisper large-v3
remains an offline comparison engine. Do not switch the live path again unless
word accuracy, latency, mixed-language names, silence rejection, and paragraph
placement all remain acceptable.

The evaluation set should record, for each phrase:

- audio and unedited ASR output;
- expected canonical text;
- deterministic output;
- optional LLM output;
- whether meaning, punctuation, and paragraph structure were preserved.

Promote a candidate alias into the deterministic dictionary only when it fixes
repeated errors without false replacements in ordinary text.

## Planned stages

1. Completed: compare Parakeet and Whisper large-v3 on the user's private
   RU/EN/UK Telegram corpus.
2. Completed: integrate native WhisperKit as an offline comparison engine;
   live dictation uses Parakeet after measured Whisper latency and morphology
   regressions on this Mac.
3. Completed: reject clips without local speech evidence and suspicious
   low-confidence stock hallucinations.
4. Completed: place one paragraph from ASR word gaps without splitting
   normal list hesitations.
5. Collect confirmed recognition failures from History. Do not learn directly
   from every transcript because unconfirmed output may teach new mistakes.
6. Suggest an alias only after the same acoustic form fails repeatedly. The
   user remains the authority for its canonical spelling.
7. Retrieve only dictionary entries relevant to the current transcript for a local LLM
   cleanup. A small context is safer and faster than sending the full glossary.
8. Evaluate CTC vocabulary boosting in the Parakeet fallback for terms that still fail before deterministic
   correction. Tune it against both name recall and false-positive rate.
9. Keep deterministic validation and local fallback after every probabilistic
   stage.

## Research references

- [FluidAudio custom vocabulary](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/CustomVocabulary.md)
  describes canonical terms, phonetic aliases, CTC evidence, and the separate
  encoder required by Parakeet TDT 0.6B v3.
- [NVIDIA NeMo word boosting](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/asr_customization/word_boosting.html)
  documents contextual boosting for uncommon words and named entities.
- [Four-in-One](https://arxiv.org/abs/2210.15063) treats inverse text
  normalization, punctuation, capitalization, and disfluency as one ASR
  post-processing problem.
- [Phonetic retrieval-based ASR contextualization](https://arxiv.org/abs/2409.15353)
  combines a retrieved vocabulary subset with an LLM instead of giving the
  model an unrestricted glossary.
- [Contextual LLM revision for named entities](https://arxiv.org/abs/2506.10779)
  combines phonetic and semantic evidence for proper-name correction.
