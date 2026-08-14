# Context Architecture

## Scope

STEP 2A implements Context Level 0: Application Awareness. It records only which
macOS application is active. The data path ends at `ContextState`; it does not
change `PetState` and does not connect to the tutor, TTS, or any AI provider.

## Context levels

| Level | Capability | Status |
| --- | --- | --- |
| Level 0 | Application Awareness | Implemented in STEP 2A |
| Level 1 | Accessibility Window/Text | Future STEP 2B |
| Level 2 | Context Diff | Future |
| Fallback | ScreenCapture + OCR | Future, only after explicit design and permission review |

Level 0 cannot distinguish a browser tab, a page, a window, or content inside an
application. For example, it can report Safari but cannot claim that Safari is
showing ChatGPT.com.

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

Logs contain only the activated bundle identifier. No content, window title,
file name, page, or user text is logged.

## Privacy and permissions

Level 0 processes application name, bundle identifier, PID, and activation or
termination events in memory. It introduces no new TCC usage description and
does not request Accessibility, Screen Recording, Camera, or Photos access.
Existing microphone and speech-recognition behavior remains limited to the
user-initiated Push-to-Talk feature.
