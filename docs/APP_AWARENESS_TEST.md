# App Awareness Test Report

Test date: 2026-08-14

Branch: `feat/context-app-awareness`

Baseline: `7373b3a feat: add push-to-talk speech recognition`

Environment: macOS 15.7.4 (24G517), Apple silicon, Xcode 26.3 (17C529)

## Executive Summary

STEP 2A is implemented as an event-driven `NSWorkspace` monitor. The app reads
one initial frontmost application, then updates an independent `ContextState`
from activation notifications. Self-app activation changes the raw value without
overwriting the last external context. No window content, screenshot, OCR,
Accessibility API, tutor connection, or pet-state automation was added.

Debug and Release builds succeed. All 76 unit tests pass, including 10 new
Context tests. A real 30-transition application-switch run delivered every
expected event and finished on Finder.

## Architecture

```text
NSWorkspace frontmost application (initial read)
NSWorkspace activation/termination notifications
                    ↓
        ActiveApplicationMonitor
                    ↓
              ContextState
```

There is no timer in the normal Context path. `AppContainer.start()` owns monitor
startup and `AppContainer.stop()` owns observer removal. The Context path stops
at `ContextState` and does not update any of the eight `PetState` values.

## Raw Frontmost vs Last External

The real app activation stream included this sequence:

```text
com.openai.codex → com.baihuaai.AITutorMac → com.apple.Safari
```

The corresponding invariant is covered by
`testExternalAToSelfToExternalBLeavesExternalBAsContext` and
`testSelfApplicationDoesNotOverwriteLastExternalApplication`:

- while 白话 AI is active, raw is the self application and last external remains
  the previously activated external package;
- after Safari becomes active, both values become Safari.

Self filtering uses the runtime `Bundle.main.bundleIdentifier`; the production
monitor does not depend on a hardcoded 白话 AI identifier.

## Observed Applications

The following values came from `NSRunningApplication`/`NSWorkspace` on the test
Mac, not from remembered identifiers. Names reflect the machine's locale.

| App requested | Observed name | Observed bundle id | Detected | Notes |
| --- | --- | --- | --- | --- |
| Finder | 访达 | `com.apple.finder` | `other` | Installed, activated, event received |
| Safari | Safari浏览器 | `com.apple.Safari` | `browser` | Installed, activated, event received |
| Chrome | Google Chrome | `com.google.Chrome` | `browser` | Installed, activated, event received |
| Xcode | Xcode | `com.apple.dt.Xcode` | `xcode` | Installed, activated, event received |
| ChatGPT | ChatGPT | `com.openai.codex` | `codex` | `/Applications/ChatGPT.app`; installed, activated, event received |
| Codex | NOT INSTALLED as a separate app | NOT TESTED separately | N/A | The installed ChatGPT package above owns `com.openai.codex`; Level 0 cannot distinguish its internal ChatGPT/Codex surface |
| 白话 AI | 白话 AI | `com.baihuaai.AITutorMac` | `other` | Debug build, activated, self-filter event received |

No bundle identifier was invented for a separate ChatGPT or Codex application.
The `.chatGPT` category remains available but has no default identifier until a
distinct package is actually observed.

## Event-driven Result

An `OSLog` stream from the running Debug build recorded activation events for:

```text
com.apple.finder
com.apple.Safari
com.google.Chrome
com.apple.dt.Xcode
com.openai.codex
com.baihuaai.AITutorMac
```

Updates arrived from workspace notifications. Source inspection confirms the
Context module has no `Timer` and no periodic frontmost-app query.

Duplicate start and stop behavior are verified by unit tests: a second start
does not add observers or repeat the initial read; stop removes both observers
and later mock events cannot mutate state.

## 30-switch Stress Test

The run began on Finder and executed six cycles of:

```text
Safari → Xcode → ChatGPT/Codex package → Safari → Finder
```

Result:

- initial activation states: 1;
- subsequent transitions: 30;
- activation requests: 31;
- monitor events: 31;
- activation failures: 0;
- final frontmost application: `访达` / `com.apple.finder`;
- observer count under the 30-event unit stress test: 1 activation observer.

The unit stress test independently sends 30 rapid activation callbacks and
asserts that both raw and last-external state equal the final application.

## Performance

Measurements were taken from the Debug process before opening extra test UI:

| Point | CPU | RSS |
| --- | ---: | ---: |
| Idle after launch | 0.0% | 110,048 KB |
| Immediately after 30 transitions | 0.0% | 110,272 KB |
| Three seconds after transitions | 0.2% | 110,224 KB |

The stress interval changed RSS by about 176 KB from idle to the settled sample.
No per-second work occurs while applications are not switching. These are simple
`ps` spot measurements, not a long-duration Instruments leak profile.

## Permissions

| Permission | STEP 2A result |
| --- | --- |
| Accessibility | NOT REQUESTED; no usage description added |
| Screen Recording | NOT REQUESTED; no usage description added |
| Microphone | NOT REQUESTED by Context; existing Push-to-Talk explanation was shown and cancelled before the system request |
| Camera | NOT REQUESTED |
| Photos | NOT REQUESTED |

The built app's Info.plist contains neither
`NSAccessibilityUsageDescription` nor `NSScreenCaptureUsageDescription`.

## Existing Feature Regression

| Feature | Result | Evidence |
| --- | --- | --- |
| MenuBar process/lifecycle | PASS | Debug app launched as an accessory app and remained responsive; source and builds include the current-app and Debug Context menu rows |
| Context Debug status menu visual layout | MANUAL FOLLOW-UP | The local UI tool does not expose `MenuBarExtra` status items for inspection |
| Tutor Panel | PASS | Desktop-pet double click opened the panel in the real Debug build |
| Esc | PASS | Esc closed the visible tutor panel |
| Option + Space | MANUAL FOLLOW-UP | Global shortcut registration path built; the local UI tool cannot synthesize a global hotkey event |
| Desktop Pet | PASS | Pet was visible and responsive in the real Debug build |
| Custom Pet | PASS | 16 existing CustomPet tests passed |
| Eight PetState values | PASS | 8 existing PetState tests passed, including all-state rendering and 30 transitions |
| TTS | PASS | 12 existing Voice tests passed |
| Push-to-Talk STT | PASS (non-permission path) | Real action bubble and pre-permission explanation opened; it was cancelled before the system prompt; 23 SpeechInput tests passed |

Application awareness did not trigger a pet-state transition during real or unit
testing.

## Tests

`xcodebuild test` result: **SUCCEEDED**.

- total tests: 76;
- Context tests: 10;
- existing regression tests: 66;
- failures: 0.

Context coverage includes initial snapshot, external activation, self filtering,
external A → self → external B, duplicate start, stop/removal, terminated
external cleanup, classifier fallback, observed-identifier classification, and
30 rapid activation events.

## Build

| Command | Result |
| --- | --- |
| Debug build | SUCCEEDED |
| Full test suite | SUCCEEDED |
| Release build | SUCCEEDED |
| `git diff --check` | SUCCEEDED |

The only build warning was Xcode's existing AppIntents metadata message because
the target has no AppIntents dependency.

## Known Issues

- Level 0 cannot identify a browser page, a focused window, or visible text. This
  is a deliberate boundary, not a detection failure.
- The installed `/Applications/ChatGPT.app` reports `com.openai.codex`. A separate
  Codex application was not installed, so ChatGPT-vs-Codex UI cannot be resolved
  from the application identity alone.
- `MenuBarExtra` visual inspection and the global Option + Space gesture require
  the short manual follow-up below because the local UI test tool does not expose
  status items or generate global hotkeys.
- Performance data is a short spot check; a long soak with Instruments remains
  optional future validation, not a STEP 2A code dependency.

## Git Status

- branch: `feat/context-app-awareness`;
- started from clean `7373b3a` baseline;
- no push, remote operation, deploy, release, or commit performed;
- working tree contains only the STEP 2A implementation, tests, project entries,
  and these two documents.

## Manual Test Steps

1. Run the Debug scheme and click the 白话 AI menu-bar item.
2. Confirm `当前应用` shows the last external application and `Context Debug`
   shows Raw Frontmost App, Last External App, bundle id, PID, time, and category.
3. Switch Finder → Safari → Chrome → Xcode → ChatGPT and confirm each factual
   application name updates without any claim that content was read.
4. From ChatGPT/Codex, click the pet. Confirm raw becomes 白话 AI while last external
   remains `ChatGPT` / `com.openai.codex`.
5. Switch to Safari and confirm last external becomes Safari.
6. Press Option + Space twice and confirm the tutor panel opens then hides. Open it
   again and confirm Esc hides it.
7. Quit the current external test application and confirm its stale snapshot is
   cleared or replaced by the next activation.
8. Leave all applications unchanged for one minute and confirm there is no
   repeating Context log or sustained Context CPU work.

STOP after this STEP 2A validation. Do not proceed to window or content awareness.
