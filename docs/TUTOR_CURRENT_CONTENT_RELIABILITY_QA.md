# Tutor Current Content Reliability QA

Date: 2026-08-27

Branch: `codex/tutor-latency-isolated`

HEAD: `b4d8940afd696b79eefbdd3ba0cf8e38f8130acd`

## Scope and policy

This QA pass measures Current Content selection through Final Request Assembly. It uses only artificial text, keeps AX snapshots in memory, does not add analytics, and treats provider `networkUnavailable` as out of scope. No selector heuristic, candidate score, priority, fallback policy, provider, model, or Voice behavior was changed.

The reliability verdict is negative. Several explicit targets work correctly, and Whole Snapshot Fallback remains fail-closed, but ordinary web containers can silently include unrelated siblings, ChatGPT can select an older message when no message is explicitly targeted, and explicit Xcode/TextEdit captures currently fail before selection.

## Change inventory

The pre-QA working tree contained 42 tracked modifications and 8 untracked files. The categories below overlap intentionally; shared files are marked cross-feature.

| Category | Pre-existing or fail-closed work | QA-pass additions |
|---|---|---|
| AX / Context | `AXApplicationReader`, `AXTextExtractor`, snapshot controller/models, app classifier, revision pipeline, normalizer, semantic buffer | no selector/traversal change |
| Tutor | current-content provider, engine/provider, latency, prompts, coordinator/manual runtime/request, panel/pet routing | no production selection change |
| Tutor Debug | Inspector view/window controller and Inspector tests | QA Outcome, manual judgment, local metrics, source/truncation/marker observability |
| Voice | Voice controller/debug view, local synthesizer, Voice tests/docs/scripts | untouched in this pass |
| UI | app container/delegate, panel store/router, pet adapter | untouched in this pass |
| Tests | AX, context, provider, prompt, Tutor, panel, runtime, Voice | deterministic QA Outcome, selected-text, focus A/B/C, long-content, window-identity and metric tests |
| Docs | README, AX/Voice/Tutor Debug documents | this QA report |
| Project / Build | project file, plist, entitlement and identity scripts | untouched in this pass |
| Cross-feature | `AppContainer.swift`, `AppDelegate.swift`, project/plist/entitlement and shared runtime tests | preserved; not broadened |

Whole Snapshot fail-closed work already present before this QA pass spans `AppContainer`, current-content provider, Inspector, manual runtime, pet/panel presentation, runtime tests, Inspector tests, and pet bubble tests.

Files materially edited by this QA pass:

- `AITutorMac/AITutorMac/Tutor/Debug/TutorDebugView.swift`
- `AITutorMac/AITutorMacTests/TutorDebugInspectorTests.swift`
- `docs/TUTOR_CURRENT_CONTENT_RELIABILITY_QA.md`

## Debug-only QA model

QA Outcome distinguishes:

- `allowed · selected-text`
- `allowed · focused-element`
- `allowed · explicit candidate`
- `blocked · ambiguous content`
- `blocked · whole snapshot fallback`
- `empty · no explainable content`
- `rejected · unsupported`

Manual judgment distinguishes `correct`, `incorrect`, `blocked-as-expected`, `unexpected-block`, and `not-evaluable`. The Inspector and console also expose Selection Source, Transport Decision, source/input character counts, Tutor-input truncation, Whole Snapshot Fallback, and unique-marker matches. All records and metrics are Debug-only and memory-only.

## Real-application baseline

| Application | Scenario | Expected | Source | Transport | Input | Judgment | Foreign markers | Notes |
|---|---|---|---|---:|---:|---|---|---|
| Chrome / ChatGPT | Message A focus | A only | focused-element | ALLOWED | 124 | correct | none | explicit editor focus |
| Chrome / ChatGPT | Message B focus | student program only | focused-element | ALLOWED | 1142 | correct | none | complete program |
| Chrome / ChatGPT | Message C focus | article only | focused-element | ALLOWED | 113 | correct | none | natural language |
| Chrome / ChatGPT | sentence selected in C | selected sentence only | selected-text | ALLOWED | 23 | correct | none | strong contract holds |
| Chrome / ChatGPT | blank/chat-container focus | ambiguous block | latest-visible-content-container | ALLOWED | 1138 | incorrect | current marker | silently selected Message B |
| Chrome / ordinary web | single paragraph focus | paragraph only | focused-element | ALLOWED | 40 | correct | none | exact focusable paragraph |
| Chrome / ordinary web | article-container focus | four article paragraphs | focused-container | ALLOWED | 179 | incorrect | other marker | comment was included |
| Chrome / ordinary web | modal control focus | modal explanation only | single-coherent-candidate | ALLOWED | 12 | correct | none | Chromium removed background from AX |
| Chrome / ordinary web | no explicit target | ambiguous block | focused-container | ALLOWED | 179 | incorrect | other marker | article and comment allowed together |
| Safari | single paragraph focus | paragraph only | focused-container | ALLOWED | 179 | incorrect | other marker | article and comment allowed together |
| Safari | modal control focus | modal explanation only | focused-container | ALLOWED | 12 | correct | none | WebKit removed background from AX |
| Safari | no explicit target | ambiguous block | latest-visible-content-container | ALLOWED | 179 | incorrect | other marker | article and comment allowed together |
| Xcode | focused artificial Swift editor | file only | unavailable | readFailed | 0 | unexpected-block | none | AX reader failed before selector |
| TextEdit | focused artificial four-paragraph text | document only | unavailable | readFailed | 0 | unexpected-block | none | AX reader failed before selector |
| Terminal | artificial output | output only | unavailable | not attempted | 0 | not-evaluable | none | UI-control policy disallowed test |
| Chrome / long page | 4464-char focused code after app switches | bounded target | focused-element | ALLOWED | 3994 | correct | none | truncation=yes; prefix/opening syntax dropped |
| Chrome / multi-block | one message with A and B | whole message, each block once | focused-container | ALLOWED | 115 | correct | none | order and uniqueness correct |
| Chrome / ambiguous page | two unrelated offscreen sections | ambiguous block | single-coherent-candidate | ALLOWED | 73 | incorrect | old + other | unrelated sections grouped together |
| Chrome / fallback baseline | two candidates, unknown geometry | ambiguous block | whole-snapshot-fallback | BLOCKED | 0 | blocked-as-expected | none | provider not called |

`Foreign markers` means a unique marker outside the expected target. Correct records contain no cross-message unique marker.

## Metrics

There are 19 recorded attempts, of which 18 are evaluable. Terminal is excluded. Ground-truth judgments are 9 correct selections, 6 incorrect selections, 1 expected ambiguous block, and 2 unexpected pre-selector blocks.

| Metric | Formula | Baseline |
|---|---|---:|
| Selection Accuracy | `correct / (correct + incorrect)` | `9 / 15 = 60.0%` |
| Direct Explain Coverage | `allowed / evaluable` | `15 / 18 = 83.3%` |
| Ambiguous Rejection Rate | `blocked ambiguous / evaluable` | `1 / 18 = 5.6%` |
| Unexpected Block Rate | `unexpected block / evaluable` | `2 / 18 = 11.1%` |
| Incorrect Selection Count | ground-truth `incorrect` | `6` |
| Selected-text Accuracy | correct selected-text / evaluable selected-text | `1 / 1 = 100%` |
| `.focused-element` Accuracy | correct / evaluable decisions with that exact source | `5 / 5 = 100%` |
| Explicit-focus Accuracy | correct / (correct + incorrect) for all allowed explicit-focus attempts | `8 / 10 = 80.0%` |

Blocked attempts are not counted as incorrect. Xcode/TextEdit unexpected blocks affect coverage and Unexpected Block Rate, but not Selection Accuracy.

## Deterministic and automated coverage

The QA tests cover selected-text exact boundaries, focused A/B/C isolation, unique-marker contamination, ambiguous rejection with zero provider calls, Current Turn Only transport enforcement, multi-block order, 500/1100/2500/3900/>4000 character behavior, truncation observability, window identity changes, blocked-to-allowed recovery, and Production Whole Snapshot rejection.

Regression gates completed successfully:

- Full test run: 410 XCTest cases plus 4 Swift Testing cases; 411 passed, 3 skipped, 0 failed.
- Debug build: succeeded.
- Release build: succeeded.
- `git diff --check`: passed.
- Identity regression script: passed.
- Built Debug identity: `com.baihuaai.AITutorMac.debug`, `AITutorMac Debug`, executable `AITutorMac`.
- Built Release identity: `com.baihuaai.AITutorMac`, `花花老师`, executable `AITutorMac`.

The >4000 policy is tail-bounded. In the 4464-character real sample, the source was reported as 4464, Current Tutor Input was 3994, `current_content_truncated=yes`, the leading marker and opening function/array syntax were removed, and the suffix was retained. This is observable but can make otherwise valid code syntactically incomplete; the limit was not enlarged.

## Risks and next decision

The most important failures are:

1. Chrome/ChatGPT with no explicit message target: `latest-visible-content-container` silently selected Message B instead of blocking (1/1 observed ambiguous blank-focus attempt incorrect).
2. Chrome/Safari article-like AX containers: `focused-container` or `latest-visible-content-container` included a sibling comment (4/5 relevant ordinary-article/no-target attempts incorrect across the two browsers; the exact single-paragraph Chrome path was correct).
3. Xcode/TextEdit explicit snapshots: `AXApplicationReader` returned `readFailed` before selection (2/2 attempts unexpectedly blocked).

The current selector is therefore not ready to be treated as a generally reliable cross-application Current Content boundary. The next pass should first isolate these AX structures and source paths, then seek explicit approval before changing selector heuristics or scoring.

## Selection Safety Hardening V1

This follow-up keeps every candidate score and selector precedence rule unchanged. It adds an evidence-derived transport gate after selection, so the selector can still expose its best candidate for diagnosis while ambiguous content is stopped before Current Tutor Input, prompt assembly, or provider transport.

The Inspector and console now expose `selectedText`, `focusedElement`, direct-container focus, provenance, candidate count, selected-candidate node count, independent-region count, inferred-only status, transport trust (`strong`, `weak`, or `ambiguous`), and the final ALLOW/BLOCK decision.

Trust policy:

- `selected-text` and a true focused explainable element are strong.
- A directly focused coherent container is strong only when it is the sole candidate or a semantic user-directed container role.
- A sole, one-text-node, one-region candidate whose focus was propagated from an excluded control is weak and allowed. This preserves modal-body explanation in WebKit without allowing a multi-node inferred page region.
- Multiple candidates with inferred-only evidence, multiple independent regions, Whole Snapshot Fallback, or an unresolved focused container are ambiguous and blocked.

### Real-application V1 result

| Application | Scenario | V1 trust | V1 decision | Result |
|---|---|---|---|---|
| Chrome / ChatGPT | Message A, B, or C explicitly focused | strong | ALLOW | exact focused message; no foreign marker |
| Chrome / ChatGPT | sentence explicitly selected | strong | ALLOW | exact 23-character selection |
| Chrome / ChatGPT | blank/chat-container focus | ambiguous | BLOCK | zero Current Tutor Input; provider not called |
| Chrome / ordinary web | single paragraph focus | strong | ALLOW | exact paragraph only |
| Chrome / ordinary web | article-container focus | ambiguous | BLOCK | prior article/comment contamination stopped |
| Chrome / ordinary web | modal control focus | weak | ALLOW | modal text only; background excluded |
| Chrome / ordinary web | no explicit target | ambiguous | BLOCK | zero Current Tutor Input |
| Chrome / ordinary web | one focused multi-block container | strong | ALLOW | both intended blocks once and in order |
| Chrome / ordinary web | two unrelated offscreen sections | ambiguous | BLOCK | zero Current Tutor Input |
| Safari | paragraph click represented only as generic container focus | ambiguous | BLOCK | prior article/comment contamination stopped |
| Safari | modal button focus with one modal text node | weak | ALLOW | modal text only; background excluded |
| Safari | no explicit target / WebArea focus | ambiguous | BLOCK | zero Current Tutor Input; provider not called |

The six baseline `incorrect + ALLOW` records are now ambiguous blocks: ChatGPT blank root (1), Chrome article/no-target/offscreen (3), and Safari paragraph/no-target (2). No baseline silent wrong-content ALLOW remains.

### V1 metrics

The same 18 evaluable baseline scenarios now contain 9 correct selections, 0 incorrect selections, 7 expected ambiguity blocks, and the two unchanged Xcode/TextEdit pre-selector blocks.

| Metric | V1 |
|---|---:|
| Selection Accuracy | `9 / (9 + 0) = 100%` |
| Direct Explain Coverage | `9 / 18 = 50.0%` |
| Ambiguous Rejection Rate | `7 / 18 = 38.9%` |
| Unexpected Block Rate | `2 / 18 = 11.1%` |
| Incorrect Selection Count | `0` |
| Selected-text Accuracy | `1 / 1 = 100%` |
| `.focused-element` Accuracy | `5 / 5 = 100%` |

V1 regression gates passed: 33 targeted Inspector tests; 417 XCTest cases with 3 skipped and 0 failures; 4 Swift Testing cases with 0 failures; Debug build; Release build; `git diff --check`; and the app-identity verification script. The built identities remain `com.baihuaai.AITutorMac.debug` / `AITutorMac Debug` and `com.baihuaai.AITutorMac` / `花花老师`.

Xcode/TextEdit `readFailed`, the 4000-character tail-bounding policy, provider networking, prompts/models, Voice, and OCR remain outside this hardening pass. One known AX limitation remains: generic Chromium `AXGroup` structures can under-report independent regions. V1 still fails closed for the observed case because the evidence is inferred-only; expanding semantic-region recognition should be handled separately with new real fixtures.

## AX Reader Reliability V1

The Xcode/TextEdit pre-selector failures had one reproducible root cause. In both applications, application identity, AX trust, focused window, and focused element succeeded. The focused element was an `AXTextArea`; `AXValue`, `AXSelectedText`, `AXSelectedTextRange`, `AXChildren`, and `AXParent` were readable. The fatal event occurred later during tree traversal:

- Xcode: `AXUIElementCopyAttributeValue(AXDescription)` returned `AXError.failure` (`-25200`) on a non-content `AXMenuButton`.
- TextEdit: the same operation returned the same error on the focused `AXTextArea`, even though its 54-character `AXValue` was already available.

The old extractor converted either optional metadata failure into generic `AccessibilityReaderError.readFailed`, discarding reliable text. This was not a permission, identity, stale PID, focused-window, focused-element, or thread/actor failure. Chrome, Xcode, and TextEdit all performed the AX read on the same background path; only identity preflight ran on the main actor.

The minimum production fix treats only an unexpected `AXDescription` read failure as optional and observable. Required role/value paths remain fail-closed. A child traversal failure may be skipped only after the same element has already yielded reliable text and is explicitly focused, selected, or has selected text; an unfocused/non-text container child failure remains fatal. No application-name special case, whole-window transport fallback, Selector change, score change, or trust-policy change was added.

Debug-only, in-memory AX Read Trace now records stage, operation, attribute, symbolic and raw AXError, role/subrole when known, expected/resolved bundle ID, PID, `AXIsProcessTrusted`, focused window/element availability, thread, result, and timestamped events. It is shown compactly in the existing Tutor Inspector and included in the console QA capture; it is not persisted or uploaded.

### Real editor result

| Application | Scenario | Reader | Selection | Decision | Exact input |
|---|---|---|---|---|---|
| Xcode | caret in artificial Swift function | READY | focused-element / strong | ALLOW | complete 155-character source |
| Xcode | select `values.reduce(0, +)` | READY | selected-text / strong | ALLOW | exact 19 characters |
| TextEdit | caret in artificial three-paragraph document | READY | focused-element / strong | ALLOW | complete 53-character normalized document |
| TextEdit | select one sentence | READY | selected-text / strong | ALLOW | exact 8 characters |
| TextEdit | select two paragraphs | READY | selected-text / strong | ALLOW | exact 18 characters |

Provider networking still ended with the expected out-of-scope `networkUnavailable`, after the Reader, Selector, Current Tutor Input, and Final Request had been assembled correctly.

### AX capability comparison

All three focused editors expose `AXRole=AXTextArea`, readable `AXValue`, readable `AXSelectedText`, readable `AXSelectedTextRange`, and zero `AXChildren`. Chrome exposes `AXDescription` and `AXVisibleChildren`; Xcode exposes focused-editor `AXDescription` but reports `AXVisibleChildren` unsupported; TextEdit returns `AXError.failure(-25200)` for focused-editor `AXDescription` and reports `AXVisibleChildren` unsupported. Xcode's original fatal description failure belonged to a separate `AXMenuButton`, not its source editor.

### Safety and gates

Post-fix real safety regression remained unchanged: ChatGPT A/B/C explicit focus selected only its unique marker; ChatGPT selected text remained exact; ChatGPT conversation/WebArea with no explicit target blocked with zero Tutor Input and zero provider calls; Chrome and Safari multi-region artificial articles both blocked as ambiguous.

Regression gates passed: 62 targeted Accessibility/Inspector tests; 425 XCTest cases with 3 skipped and 0 failures; 4 Swift Testing cases with 0 failures; independent Debug build; Release build; `git diff --check`; and identity verification. Built identities remain `com.baihuaai.AITutorMac.debug` / `AITutorMac Debug` and `com.baihuaai.AITutorMac` / `花花老师`.

Known residual risk: other optional AX metadata attributes may return application-specific errors in untested controls and still fail closed. They were not broadly downgraded without evidence. Empty ChatGPT composer focus can expose its accessibility placeholder as the focused editor value; that is a separate placeholder/Selector policy question and was not changed in this Xcode/TextEdit reader pass. The 4000-character policy and provider networking remain out of scope.

## Structure-Aware Long Content Policy V1

The former manual-explain boundary was applied after normalization and after the existing selection-safety gate. Both explicit selected text and focused-element content passed through the same helper. When normalized content exceeded the 4000-character request budget, that helper used a suffix and then removed a leading partial line when enough text remained. The result was observable as truncated, but it did not say which part was dropped and the prompt could treat the remaining tail as the complete explanation object. Manual explain uses a fresh AX snapshot and this provider path; the live semantic-buffer pipeline normally emits smaller chunks and does not ordinarily reach this boundary.

V1 keeps the 4000-character transport budget and leaves AX reading, Selector precedence, candidate scores, Selection Trust, Current Turn Only, and Production Whole Snapshot policy unchanged. Length handling still runs only after a selection is allowed. Content at or below the budget is sent unchanged as `complete`. Longer content is a deterministic prefix excerpt with explicit coordinates and the strongest boundary available within the budget:

- code-like content: complete supported code block when deterministically detectable, otherwise newline/word/character fallback;
- natural language: paragraph, then sentence/newline/word/character fallback;
- explicit selected text: never expands to the parent object; a long selection becomes an explicitly declared selection excerpt;
- unknown or mixed content: a bounded prefix excerpt with an explicit fallback boundary.

Every request now carries content type, content completeness (`complete` or `excerpt`), length policy, original/normalized/sent character counts, excerpt start/end, dropped prefix/suffix counts, and the structure boundary used. The Inspector and in-memory console capture show the same fields. The prompt tells the Tutor that an excerpt is only the declared range of a longer object and forbids claims that definitions, declarations, delimiters, facts, or sections are absent from the full source merely because they are outside that range.

`AXSelectedTextRange` remains visible in the AX read trace, but it is not part of the current production snapshot model. V1 therefore does not guess at caret position and does not modify the AX Reader main path. The prefix policy is deliberately stable across caret positions.

### Automated and real results

- 500, 1100, 2500, and 3900 characters remain exact `complete` content.
- 4100-character and 8000-character code fixtures produce `excerpt` metadata and never use a silent suffix. Prefix/suffix markers and coordinate accounting match the actual sent range.
- Brace-heavy code ends on the strongest supported deterministic boundary; long prose ends at a paragraph/sentence boundary.
- Short selected text remains exact; long selected text is a declared excerpt and never expands its parent.
- Ambiguous content, Production Whole Snapshot, and Current Turn Only remain unable to bypass the safety gate; a blocked request makes zero provider calls.
- Full regression: 433 XCTest cases, 3 skipped, 0 failures; 4 Swift Testing cases, 0 failures. Debug and Release builds, `git diff --check`, and identity verification passed.

Real Xcode captures used artificial Swift files with `AX_LONG_PREFIX_MARKER`, `AX_LONG_MIDDLE_MARKER`, and `AX_LONG_SUFFIX_MARKER`:

| Fixture | Caret | Selection / trust | Sent range | Boundary | Result |
|---|---|---|---:|---|---|
| 4521 original / 4520 normalized | beginning | focused-element / strong | `0..<3998` | code-block | explicit excerpt; dropped prefix 0, suffix 522 |
| 7992 normalized | middle | focused-element / strong | `0..<3972` | code-block | explicit excerpt; dropped prefix 0, suffix 4020 |
| 7992 normalized | end | focused-element / strong | `0..<3972` | code-block | identical stable range; no caret guess |

Real TextEdit used a 6458-character artificial article with prefix/middle/suffix markers. It produced `focused-natural-language`, `structure-aware-prose-excerpt`, range `0..<3912`, paragraph boundary, dropped prefix 0, and dropped suffix 2546.

The existing dedicated ChatGPT conversation was reused because it contained only the artificial A/B/C fixtures; no new conversation was needed. Selected A, B, and C markers each produced `selected-text / strong / ALLOW`, exact single-marker Current Tutor Input, and no foreign marker. Clicking the conversation blank area remained `ambiguous / BLOCKED`. Chrome and Safari artificial multi-region articles also remained `ambiguous / BLOCKED`. All blocked real captures stopped before prompt/provider assembly. The subsequent `networkUnavailable` on allowed captures remains a provider/network issue outside this policy.

Residual risks: V1 uses conservative structure signals rather than a language parser, so some code falls back to a line/word boundary; it is intentionally not caret-aware; a syntactically valid block may still lack semantic dependencies outside the excerpt. Those limitations are now explicit and must not be described as full-source absence. Empty ChatGPT composer placeholder exposure remains P3 and out of scope.
