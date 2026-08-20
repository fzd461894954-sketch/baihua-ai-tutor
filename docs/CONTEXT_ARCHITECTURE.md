# Context Architecture

## Scope

STEP 2A implements Context Level 0: Application Awareness. STEP 2B adds Level 1A,
an explicitly triggered, read-only Accessibility snapshot of the most recent
external application's focused window. Neither level changes `PetState` or
connects to the tutor, TTS, or any AI provider.

## Context levels

| Level | Capability | Status |
| --- | --- | --- |
| Level 0 | Application Awareness | Implemented in STEP 2A |
| Level 1A | On-demand Accessibility Snapshot | Implemented in STEP 2B |
| Level 1B | Live Accessibility Observer | Future; no `AXObserver` in STEP 2B |
| Level 2 | Conversation Parsing / Context Diff | Future |
| Fallback | ScreenCapture + OCR | Future, only after explicit design and permission review |

Level 0 cannot distinguish a browser tab, page, window, or content inside an
application. Level 1A can report the focused window and accessible text that the
target application exposes, but it does not infer a web page, identify user and
assistant messages, or understand the text.

## Event-driven data flow

```text
macOS application activation
        ↓
NSWorkspace.didActivateApplicationNotification
        ↓
SystemApplicationWorkspace
        ↓
ActiveApplicationMonitor
        ↓
ContextState
```

`ActiveApplicationMonitor.start()` installs one activation observer and one
termination observer. It also reads `NSWorkspace.shared.frontmostApplication`
once so the initial state is available before the next switch. Normal operation
has no timer or polling loop. A duplicate `start()` is a no-op, and `stop()`
cancels both observations.

Application lifecycle ownership is in `AppContainer`:

- app startup calls `activeApplicationMonitor.start()`;
- app termination calls `activeApplicationMonitor.stop()`;
- opening a menu or panel does not install another observer.

When the last external application changes, `AppContainer` cancels any in-flight
Level 1A read and clears its previous snapshot. A completed snapshot stays only
in memory.

## Level 1A on-demand snapshot flow

```text
user clicks Read Current Window
        ↓
Accessibility permission + target validation
        ↓
lastExternalApplication PID
        ↓
AX application → focused window
        ↓
bounded, read-only Accessibility tree traversal
        ↓
AccessibleTextSnapshot (memory only)
```

The permission prompt is never shown at launch. An untrusted read first presents
the product explanation; only the user's Continue action asks macOS for
Accessibility access. The session guard prevents repeated system prompts.

The reader calls `AXUIElementCopyAttributeValue` for a small allowlist: role,
subrole, title, value, description, help, children, and the focused window. It
does not call `AXUIElementSetAttributeValue`, `AXUIElementPerformAction`, or any
`AXObserver` API.

The output preserves both structured `AccessibleTextNode` values and normalized
plain text. A node records role, depth, source attribute, and text. The window
snapshot records the observed application, bundle identifier, PID, title, role,
subrole, time, and `accessibility` source. It deliberately performs no
app-specific parsing.

Traversal defaults are depth 40, 2,000 visited nodes, and 100,000 plain-text
characters. The depth was raised from the suggested initial value of 20 after a
real ChatGPT package test showed that the native hierarchy nests useful content
more deeply. Any reached budget returns a valid snapshot with `truncated = true`.
Each AX element has a 0.5-second messaging timeout; the overall request has a
6-second timeout and a cooperative cancellation token.

Secure text elements and their descendants are skipped before value or child
attributes are requested. Exact normalized duplicates are kept once. This is a
basic extraction policy, not a guarantee that every application exposes all
visible text.

## Data model

`ActiveApplicationSnapshot` is a value containing only:

- localized application name;
- bundle identifier;
- process identifier;
- observation time.

It deliberately contains no window, text, file, page, microphone, or image data.

`ContextState` is independent from `AppState` and `PetStateController`. Future
context levels can extend it without assigning application activation semantics
to the eight pet states.

## Raw frontmost vs last external

`rawFrontmostApplication` is the latest application reported by macOS, including
白话 AI itself. `lastExternalApplication` is updated only when the activated
bundle identifier differs from `Bundle.main.bundleIdentifier`.

```text
Codex/ChatGPT package → 白话 AI → Safari

after 白话 AI activation:
  raw frontmost = 白话 AI
  last external = Codex/ChatGPT package

after Safari activation:
  raw frontmost = Safari
  last external = Safari
```

This preserves the user's work context while they interact with the pet, menu,
or tutor panel. The self identifier is not hardcoded in the monitor; production
uses `Bundle.main.bundleIdentifier`, while tests inject a deterministic value.

## Termination handling

The monitor observes `NSWorkspace.didTerminateApplicationNotification`. If the
terminated process identifier matches either stored snapshot, that snapshot is
cleared. A subsequent activation notification establishes the replacement. This
prevents a terminated external application from remaining permanent context.

## Classification boundary

`TargetApplicationClassifier` maps exact, observed bundle identifiers to a small
category enum. Unknown or missing identifiers always fall back to `other`.
Application display names are not used to infer an AI product.

The default identifiers were verified on the test Mac on 2026-08-14 and are
recorded in `APP_AWARENESS_TEST.md`. On this installation,
`/Applications/ChatGPT.app` reports the bundle identifier `com.openai.codex`.
Level 0 therefore classifies that package as `codex`, but it cannot distinguish
which product surface is visible inside the package.

## UI and logging

The menu shows a factual `当前应用` value. Debug builds additionally show:

- Raw Frontmost App;
- Last External App;
- Bundle Identifier;
- PID;
- Observed Time;
- Classification.

Accessibility Debug additionally shows permission, target, focused-window
metadata, counts, the most frequent roles, duration, and a preview capped at
3,000 characters. Copying the same capped preview requires a separate user
action.

Logs contain only the activated bundle identifier and snapshot counts,
truncation state, duration, or a stable error name. No snapshot body, window
title, file name, page, or user text is logged.

## Privacy and permissions

Level 1A adds user-initiated Accessibility access. It reads only after the user
clicks the snapshot button, keeps the result in memory, and makes no network
request. It adds no Screen Recording, Camera, or Photos access. Existing
microphone and speech-recognition behavior remains limited to user-initiated
Push-to-Talk.
