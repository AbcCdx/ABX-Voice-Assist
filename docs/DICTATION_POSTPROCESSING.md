# Dictation post-processing

## Goal

Turn a local ASR transcript into the text the speaker intended without
answering the speaker, inventing facts, or changing meaning.

## Current pipeline

1. Parakeet TDT 0.6B v3 produces the local transcript.
2. In automatic language mode, both mean confidence and the weakest token
   confidence can trigger local RU/EN/UK verification. Candidate ranking uses
   the lower confidence tail so one broken word is not hidden by a high mean.
3. Long pauses are detected in the audio, but the full utterance is decoded
   once. FluidAudio token timings place one paragraph break after each pause;
   separate segment decoding is used only as a safe fallback when timings are
   unavailable.
4. Deterministic repair removes known ASR artifacts.
5. A conservative project dictionary replaces complete spoken aliases with
   canonical English names.
6. User corrections override built-in aliases.
7. Optional filler removal and punctuation rules run locally.
8. Optional LLM cleanup fixes punctuation, capitalization, grammar, and clear
   recognition errors. It receives only the canonical project names and must
   not introduce a name that was not spoken.
9. Invalid, incomplete, conversational, or implausibly changed LLM output is
   rejected and the local transcript is kept.

## Canonical project dictionary

| Canonical name | Spoken aliases |
| --- | --- |
| `ABLX` | `аблэкс`, `аблекс`, `эй би эл экс` |
| `ABX Voice Assist` | `абикс войс ассист`, `эй би экс войс ассист`, `войс ассист` |

The list stays intentionally small. Add an alias only after it appears in a
real transcript. Broad or ambiguous aliases can corrupt ordinary speech.

## Next research-backed stage

FluidAudio supports CTC vocabulary boosting for Parakeet TDT 0.6B v3 through
a separate CTC encoder. That can improve recognition before text correction,
but adds a model download, memory use, and another inference pass. Integrate it
only after collecting a small private evaluation set with the project names in
Russian, English, and Ukrainian speech.

The evaluation set should record, for each phrase:

- audio and unedited ASR output;
- expected canonical text;
- deterministic output;
- optional LLM output;
- whether meaning, punctuation, and paragraph structure were preserved.

Promote a candidate alias into the deterministic dictionary only when it fixes
repeated errors without false replacements in ordinary text.

## Planned stages

1. Completed: preserve whole-utterance decoder context across long pauses and
   place paragraphs from token timings instead of decoding each part alone.
2. Completed: use lower-tail token confidence for automatic language
   verification and candidate selection, instead of trusting only the mean.
3. Collect confirmed recognition failures from History. Do not learn directly
   from every transcript because unconfirmed output may teach new mistakes.
4. Suggest an alias only after the same acoustic form fails repeatedly. The
   user remains the authority for its canonical spelling.
5. Retrieve only dictionary entries relevant to the current transcript for LLM
   cleanup. A small context is safer and faster than sending the full glossary.
6. Add CTC vocabulary boosting for terms that still fail before deterministic
   correction. Tune it against both name recall and false-positive rate.
7. Keep deterministic validation and local fallback after every probabilistic
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
