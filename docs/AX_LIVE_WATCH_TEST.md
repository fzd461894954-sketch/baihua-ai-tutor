# Accessibility Live Watch Test Report

## Executive Summary

STEP 2C adds an explicit, observer-driven Accessibility Live Watch for one
user-selected external PID. A first real ChatGPT stream produced 180 AX events,
24 bounded snapshots, and 18 distinct revisions in about 26 seconds. That trial
also exposed a transient AX read failure at the end of a dynamic redraw; the
monitor now records that failure without detaching the observer and recovers on
the next coalesced event. A permission-matched rerun produced 66 events, 11
snapshots, and 10 revisions in about 27 seconds, with an exact notification
distribution and a PASS known-string check.

No message parsing, context diff, Tutor/Pet integration, AI API, OCR, screenshot
capture, network transfer, or polling was added.

## Live Watch Architecture

Live Watch is OFF by default. Starting it locks `lastExternalApplication` by PID
and bundle identifier, creates one `AXObserver`, registers a small best-effort
notification set, and routes lightweight `AXChangeEvent` values into a
configurable coalescer. Snapshot reads reuse the bounded STEP 2B reader with a
single-flight request. A SHA-256 fingerprint prevents identical snapshots from
creating a new revision. Stopping removes the observer source and registrations,
cancels pending work, and clears live body text from memory.

Transient `focusedWindowUnavailable`, `readFailed`, and `timedOut` snapshot
failures keep the explicit observer session alive. Permission loss, target
termination, or PID replacement still stop immediately.

## Observer Registration Results

First ChatGPT device trial (`com.openai.codex`, PID 25380):

- `AXObserverCreate`: success (0)
- Supported: `AXFocusedWindowChanged`, `AXFocusedUIElementChanged`,
  `AXValueChanged`, `AXCreated`, `AXLayoutChanged`, `AXUIElementDestroyed`,
  `AXTitleChanged`
- Unsupported: none

The permission-matched rerun produced the same registration results.

## ChatGPT Streaming Real Test

First trial started at 13:11:55 and the last event arrived at 13:12:21 on
2026-08-20, for an observed duration of about 26 seconds.

- Events received: 180
- Events coalesced: 174
- Snapshots generated: 24
- Distinct revisions: 18
- Latest successful snapshot: 4,469 characters, 300 nodes, not truncated
- Final known-string verification: pending rerun
- Result: observer events clearly tracked streaming changes; a transient final
  read failure revealed and motivated the recovery fix described above

Permission-matched rerun, 13:19:53-13:20:20 on 2026-08-20:

- Events received: 66
- Events coalesced: 13
- Snapshots generated: 11
- Distinct revisions: 10
- Latest snapshot: 3,101 characters, 176 nodes, not truncated
- Final known-string verification: PASS (boolean result only; body not echoed)
- Leaving the target moved the session to `paused` without retargeting

No body text or content fingerprint is stored in this report.

## Notification Distribution

ChatGPT permission-matched rerun:

- `AXTitleChanged`: 47
- `AXValueChanged`: 19

Chrome short run:

- `AXValueChanged`: 35
- `AXTitleChanged`: 10
- `AXFocusedUIElementChanged`: 2

Safari short run:

- `AXUIElementDestroyed`: 321
- `AXValueChanged`: 87
- `AXFocusedUIElementChanged`: 5
- `AXCreated`: 2

Xcode short run:

- `AXValueChanged`: 131
- `AXUIElementDestroyed`: 110
- `AXFocusedUIElementChanged`: 56
- `AXFocusedWindowChanged`: 10
- `AXCreated`: 9

## Event Count vs Snapshot Count

First ChatGPT trial: 180 events to 24 snapshots (7.5:1). Snapshot work was
materially lower than event volume and remained single-flight.

ChatGPT rerun: 66 events to 11 snapshots (6:1). Chrome short run: 47 events to
16 snapshots (2.9:1). Xcode short run: 316 events to 16 snapshots (19.8:1).
All remained below one full snapshot per event.

## Distinct Revisions

First ChatGPT trial: 18 distinct revisions from 24 successful snapshots. Six
identical full-snapshot fingerprints were skipped as new revisions.

## Observer Sufficiency

Result: **SUFFICIENT**. Two ChatGPT runs produced sustained AX notifications for
about 26-27 seconds and drove multiple distinct revisions. The second run also
confirmed an exact notification distribution and a known-string PASS.

## Polling Fallback

**NOT USED.** The real ChatGPT trial produced abundant observer events, so the
evidence does not justify a background polling fallback.

## Focused Window Change

Automated coverage verifies that a locked session remains bound to its original
PID and pauses rather than retargeting another app. The observer registers
`AXFocusedWindowChanged`, and every snapshot re-resolves the focused window from
the application root. The Xcode device run received 10 focused-window changes;
a later no-focused-window read was treated as transient and did not detach the
observer.

## Target Termination

Automated coverage verifies immediate observer cleanup, snapshot cancellation,
and `targetUnavailable` state on termination or same-bundle PID replacement.
No automatic reattachment occurs.

## Permission Revocation

Automated coverage verifies that permission loss on a subsequent event stops the
observer and moves to `permissionRequired` without retrying.

## 30 Start/Stop Stress

Automated 30-cycle coverage passes: 30 starts, 30 stops, no observer left
running, and final state OFF.

## Streaming Performance

First ChatGPT trial showed 180 events, 174 coalesced events, and 24 snapshots;
the rerun showed 66 events, 13 coalesced events, and 11 snapshots. Three paused
samples measured 0.1%, 0.5%, and 0.1% CPU (0.23% average) with 156,256 KB RSS.
Three idle-watching Safari samples measured 0.0% CPU with 151,056 KB RSS. Live
Watch OFF has no polling task.

## Real-Application Matrix

| App | Bundle identifier | Registration/event result | Status |
| --- | --- | --- | --- |
| ChatGPT | `com.openai.codex` | all seven supported; rerun: 66 events, 11 snapshots, 10 revisions; known-string PASS | PASS |
| Safari | `com.apple.Safari` | all seven supported; 415 events; existing STEP 2B reader produced 0 successful snapshots | PARTIAL |
| Google Chrome | `com.google.Chrome` | all seven supported; 47 events, 16 snapshots, 2 revisions | PASS |
| Xcode | `com.apple.dt.Xcode` | all seven supported; 316 events, 16 snapshots, 3 revisions | PASS |

## Privacy

- Live Watch is explicit and visibly indicates its state and locked target.
- Only one locked external PID is observed; switching apps never retargets it.
- The callback stores lightweight metadata, not chat text.
- Only the latest full snapshot exists in memory; stopping clears it.
- Body preview requires an explicit user action; no body history is persisted.
- Accessibility content is not copied, logged, or uploaded automatically.

## Permissions

STEP 2C reuses Accessibility only. It adds no Screen Recording, Camera, Photos,
or network permission. Microphone behavior remains limited to explicit PTT.

## Existing Regression

The full project suite covers Shell, Pet and custom Pet behavior, eight Pet
states, TTS, STT, App Awareness, manual Accessibility Snapshot, and Live Watch.
All 104 tests pass.

## Tests

`AccessibilityLiveTests` contains 13 tests covering observer lifecycle,
duplicate start, cleanup, unsupported registration, creation failure, target
termination, PID replacement, self-target rejection, permission loss, pause and
resume, coalescing/rate/trailing behavior, single-flight reads, dirty follow-up,
fingerprint revision rules, notification distribution, transient-read recovery,
and 30 start/stop cycles.

Full result: 104 tests, 0 failures.

## Build

- Debug build: PASS
- Full tests: PASS (104/104)
- Release build: PASS (`CODE_SIGNING_ALLOWED=NO` test artifact)
- `git diff --check`: PASS

## Known Issues

- The current local Debug product is ad-hoc signed. Rebuilding changes its code
  identity and macOS may require removing and re-adding that exact `.app` in
  Accessibility settings. Stable development-team signing is recommended.
- The current Safari window produces abundant observer events, but both live and
  manual STEP 2B reads return `readFailed`. This is an inherited Snapshot Reader
  compatibility issue, not evidence for polling; STEP 2C leaves the frozen
  reader architecture intact and records Safari as PARTIAL.

## Git Status

Work remains on `feat/accessibility-live-watch`; it is intentionally uncommitted
and has not been pushed, deployed, or released.

## Manual Test Steps

1. Add the exact freshly built Debug `.app` to Accessibility settings and verify
   `AXIsProcessTrusted == true`.
2. Focus ChatGPT (`com.openai.codex`), open Accessibility Debug, and start Live
   Watch before a 20-30 second response.
3. Record Notification Counts, Events, Coalesced, Snapshots, Revision, CPU, and
   RSS; explicitly view the latest snapshot only to record known-string PASS or
   FAIL, without copying the string into this report.
4. Switch away and back to verify pause/resume without retargeting.
5. Stop and confirm counters no longer change and live content is cleared.
6. Repeat a short benign event run for Safari, Chrome, and Xcode.
