# Tutor Latency Benchmark

Date: 2026-08-22
Scope: STEP 09-4.5 — explicit first Tutor explanation only

This document contains metadata from synthetic Debug fixtures. It contains no
SemanticChunk body, prompt body, TutorResponse body, Accessibility snapshot,
credential, or user conversation text.

## Product targets

- First useful feedback: under 5 seconds.
- Full compact lesson: preferably under 10 seconds.
- Never hide provider wait time behind a fabricated percentage.

Neither target is met by the currently configured Ark model.

## Configuration

| Item | Value |
|---|---|
| Provider | Ark, OpenAI-compatible Chat Completions |
| Model | `doubao-seed-evolving-latest-version` |
| Input | Checked-in synthetic `API` evaluation case |
| Runs | 5 serial requests per response format |
| Temperature | Saved active Provider setting; benchmark did not alter it |
| Compact output budget | 900 max output tokens |
| Lesson target | 80–250 Chinese characters, at most 3 key points and 3 glossary terms |
| Quality gate | Decoder + Validator + `TutorQualityEvaluator` |

Historical full-chain observations before this step were approximately 19.9s,
27.8s, and 34.8s. They used different live content, so they are context rather
than an apples-to-apples baseline.

## Five-run results

`providerDefault` resolved to Ark's current production `json_object` path.

| Format | Runs | Total min | Total p50 / median | Total max | TTFB median | Response transfer median | Input tokens median | Output tokens median | Quality |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `json_object` | 5 | 17.884s | 23.046s | 26.496s | 23.041s | 3ms | 2,005 | 887 | 5/5 PASS |
| `json_schema` | 5 | 15.486s | 19.464s | 19.810s | 19.456s | 2ms | 1,529 | 861 | 5/5 PASS |

For this five-run sample, `json_schema` reduced median total latency by about
15.5% and median provider-reported input tokens by about 23.7%. This is a useful
Debug comparison, not enough evidence by itself to change the production
automatic format.

### Raw metadata

| Format | Run | Input tokens | Output tokens | TTFB | Total | Quality |
|---|---:|---:|---:|---:|---:|---|
| `json_object` | 1 | 2,006 | 887 | 23.041s | 23.046s | PASS |
| `json_object` | 2 | 2,005 | 900 | 25.500s | 25.504s | PASS |
| `json_object` | 3 | 2,005 | 1,317 | 26.491s | 26.496s | PASS |
| `json_object` | 4 | 2,007 | 858 | 17.878s | 17.884s | PASS |
| `json_object` | 5 | 2,005 | 883 | 22.826s | 22.831s | PASS |
| `json_schema` | 1 | 1,527 | 861 | 19.456s | 19.464s | PASS |
| `json_schema` | 2 | 1,530 | 945 | 19.721s | 19.725s | PASS |
| `json_schema` | 3 | 1,526 | 837 | 17.619s | 17.622s | PASS |
| `json_schema` | 4 | 1,530 | 931 | 19.805s | 19.810s | PASS |
| `json_schema` | 5 | 1,529 | 837 | 15.481s | 15.486s | PASS |

Provider output usage can exceed the configured visible output budget. The most
likely explanation is provider-counted hidden reasoning or other model-side
tokens, but the provider response does not expose a safe breakdown, so this is
an inference and not recorded as fact.

## Latency breakdown

One instrumented `json_object` run recorded:

| Stage | Duration |
|---|---:|
| Current content resolution | <1ms |
| Prompt build | <1ms |
| Request setup | 1ms |
| Provider TTFB | 20.156s |
| Response transfer | 2ms |
| Decode | 2ms |
| Validation | <1ms |
| Presentation mapping | <1ms |
| Total to panel | 20.163s |

The non-streaming endpoint does not expose a trustworthy model-generation
boundary. Provider queueing and model generation are folded into TTFB. The
final metrics therefore leave `generationDuration` and
`timeToFirstModelContent` nil for non-streaming requests instead of reporting
response-transfer time as model generation. Streaming traces can populate both.

## Bottleneck classification

| Candidate | Finding |
|---|---|
| A. Provider TTFB | Primary bottleneck. More than 99.9% of measured local-to-panel time is before the first response byte. |
| B. Model generation | Likely inside Provider TTFB, but not separately observable in non-streaming mode. |
| C. Prompt too large | Secondary contributor. Provider input is about 1.5k–2.0k tokens for a 39-character synthetic source. |
| D. Output too large | Secondary contributor. Provider reports roughly 0.8k–1.3k output tokens despite a compact visible lesson. |
| E. Structured Output overhead | `json_schema` was faster and smaller in the five-run API sample, not slower. Reliability evidence is not yet sufficient for a production switch. |
| F. Local runtime | Not a bottleneck; content, prompt, decode, validation, and presentation are millisecond-scale. |

## Prompt budget audit

The current prompt package for the synthetic API case measured:

| Component | Characters | Approximate share |
|---|---:|---:|
| System instruction | 297 | 5.0% |
| Tutor and safety rules | 1,741 | 29.2% |
| TutorResponse schema | 3,392 | 56.8% |
| User envelope | 541 | 9.1% |
| Source inside user envelope | 39 | not additive |
| Total prompt package | 5,971 | 100% |

The schema is the largest component. Critical controls remain unchanged:
source-is-data / prompt-injection defense, no fabricated chain-of-thought,
source-grounding, and strict response structure.

`json_schema` lowers provider input usage because the schema travels as the
structured response format rather than being repeated as ordinary prompt text.
The provider-neutral `PromptPackage` remains unchanged for validation and audit.

## Output budget

The compact first lesson now uses these product defaults for new settings:

- `plainExplanation`: required, target 80–250 Chinese characters.
- `keyPoints`: at most 3.
- `glossary`: at most 3.
- `analogy` and `example`: optional when they materially help.
- `checkQuestion`: disabled for the first compact lesson.
- `caveats`: only when supported and necessary.
- Max output tokens: 900, reduced from 1,800.

Existing saved Provider settings are not silently rewritten. A saved higher
limit remains active until the user explicitly saves a new value. The compact
prompt preference still applies to the first lesson.

## Quality regression

All six checked-in synthetic cases were run through the real provider with the
compact 900-token budget.

| Format | API | HTTP | JSON | Error | Database Migration | Permission Error |
|---|---|---|---|---|---|---|
| Production `json_object` | PASS | PASS | NEEDS REVIEW | PASS | PASS | PASS |
| Debug `json_schema` | PASS | NEEDS REVIEW | NEEDS REVIEW | PASS | PASS | PASS |

The review-only results were `unsupportedFacts` heuristic warnings caused by
extra numeric anchors in teaching examples. Decoder and Validator passed for
all completed runs; there were no explicit hallucination markers and no failed
quality signal. One earlier `json_schema` quality-suite attempt also stopped on
a Provider error before producing a record. For that reliability reason,
Ark `automatic` remains on `json_object` in production for this step.

## Model comparison

No alternate Ark model was selected, so no cross-model recommendation is made.
The Debug benchmark supports a temporary model override without changing or
saving the active production model. Future comparisons must weigh latency,
provider usage, Decoder/Validator success, and all quality signals together.

## Streaming feasibility

**NOT YET SAFE.** The provider and latency trace support SSE and record first
model content. The production Tutor UI requires a complete, validated
`TutorResponse` JSON envelope. Showing partial JSON before completion would
create truncation, escaping, ordering, and ownership risks. Safe first-useful
content needs a dedicated incremental structured decoder and its own lifecycle
tests; it is intentionally deferred.

## Real Chrome chain

A Chrome/ChatGPT conversation containing synthetic HTTP teaching content was
prepared without recording its body. The latency build could not start Live
Watch because macOS reported Accessibility permission as false for the rebuilt
Debug code signature. No SemanticChunk, prompt, TutorResponse, or credential was
logged, and the conversation content was not sent to Ark during this attempt.

This is an environment authorization blocker, not a Context algorithm change.
The previously reviewed product chain remains untouched. Re-running the live
chain requires the developer to grant Accessibility access to the rebuilt app;
this step did not modify macOS privacy settings.

## Recommended production defaults

1. Keep compact first-lesson preferences and the 900-token default for new
   Provider settings.
2. Keep Ark `automatic` on `json_object` until a larger `json_schema` reliability
   sample passes all six cases without Provider failures.
3. Use the Debug benchmark to compare faster Ark models temporarily; never
   change the active model unless the user saves it.
4. Treat Provider/model selection as the next performance lever. Prompt and
   local-runtime changes alone cannot reach the under-10-second target on the
   current model.
5. Keep streaming partial UI deferred until an incremental structured decoder
   can preserve Decode, Validate, cancellation, and session ownership guarantees.

## Privacy

Latency traces retain timestamps, opaque IDs, model identifier, character
counts, and provider-reported token counts only. Token counts remain nil when
the provider omits usage. Logs never include a credential, source body, prompt
body, TutorResponse body, Accessibility snapshot, or user conversation text.

## Verification

- Focused Tutor/Provider/Settings regression: 76 tests executed, 75 passed,
  1 live-network test skipped, 0 failed.
- Full Debug regression after integration with Design System baseline: 350 test
  results, 349 passed, 1 live-network test
  skipped, 0 failed.
- Release build with signing disabled: PASS.
- `git diff --check`: PASS.
