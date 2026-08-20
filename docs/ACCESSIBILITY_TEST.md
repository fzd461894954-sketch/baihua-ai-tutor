# Accessibility Window Reader Test Report

## Executive summary

STEP 2B is complete. A final, permission-matched Debug binary produced real,
user-triggered snapshots from ChatGPT, Safari, Google Chrome, and Xcode. All
four focused windows returned structured nodes and normalized text without UI
freeze or crash. Chrome reached the 2,000-node budget and returned a bounded,
explicitly truncated snapshot; the other three completed within budget.

## Scope and method

This report covers STEP 2B only: an explicit user action reads one bounded,
read-only Accessibility snapshot from STEP 2A's `lastExternalApplication`.
Snapshot bodies are not included in this document.

## Permission UX

The complete first-run flow was exercised on 2026-08-14:

1. launch with Accessibility disabled;
2. confirm the UI says permission is not enabled;
3. click **Allow reading the current AI window**;
4. verify the product explanation appears before any system request;
5. click **Continue**;
6. enable AITutorMac in System Settings;
7. reactivate the app and confirm the UI changes to enabled.

There was no launch-time prompt. The product explanation stated that the app
reads displayed text and does not click, type, modify apps, control the mouse,
or execute actions. The denied path returned a friendly permission message and
the session guard prevented a repeated macOS prompt.

## Real application matrix

| App | Permission | Focused window | Text result | Nodes / visited | Characters | Truncated | Duration |
| --- | --- | --- | --- | ---: | ---: | --- | ---: |
| ChatGPT (`com.openai.codex`) | Granted | `ChatGPT`, `AXWindow` / `AXStandardWindow` | SUCCESS; known-string checks found user and assistant text | 185 / 682 | 3,063 | No | 0.158s |
| Safari (`com.apple.Safari`, display name `Safari浏览器`) | Granted | `起始页`, `AXWindow` / `AXStandardWindow` | SUCCESS for the start page | 60 / 122 | 863 | No | 0.063s |
| Google Chrome (`com.google.Chrome`) | Granted | Current Chrome tab, `AXWindow` / `AXStandardWindow` | SUCCESS, bounded by node budget | 654 / 2,000 | 12,614 | Yes | 0.455s |
| Xcode (`com.apple.dt.Xcode`) | Granted | `Welcome to Xcode`, `AXWindow` / `AXUnknown` | SUCCESS | 10 / 13 | 155 | No | 0.049s |

Exact normalized duplicate strings were removed in all snapshots. The Debug
preview remained capped at 3,000 characters and no test used the clipboard.

## AX tree observations

- ChatGPT: leading roles were `AXGroup`, `AXButton`, `AXStaticText`, `AXImage`,
  `AXPopUpButton`, `AXCheckBox`, `AXHeading`, and `AXListMarker`. The tree exposed
  both parties' displayed text, but no stable message-author semantic was
  inferred.
- Safari start page: leading roles were `AXButton`, `AXStaticText`, `AXGroup`,
  `AXImage`, `AXLink`, and `AXList`. Because the observed window was the native
  start page, no `WebArea` finding is claimed.
- Chrome: leading roles were `AXGroup`, `AXStaticText`, `AXCell`, `AXButton`,
  `AXLink`, `AXHeading`, `AXPopUpButton`, and `AXSplitter`. Its large hierarchy
  hit the node budget and safely returned partial output.
- Xcode Welcome: leading roles were `AXButton`, `AXStaticText`, `AXColumn`,
  `AXGroup`, `AXImage`, `AXOutline`, `AXScrollArea`, and `AXWindow`. This confirms
  that the reader is not hardcoded to ChatGPT or browsers.

## Tree budgets and performance controls

- maximum depth: 40 (adjusted from 20 after the real ChatGPT calibration);
- maximum visited nodes: 2,000;
- maximum normalized characters: 100,000, including separators;
- per-element AX messaging timeout: 0.5s;
- overall request timeout: 6s;
- preview and explicit clipboard copy: first 3,000 characters only.

Reaching any traversal budget sets `truncated = true` and returns the bounded
snapshot. Target change, debug-window close, app quit, explicit Cancel, or the
overall timeout cancels the active request and discards stale output.

## Automated tests

The Accessibility suite covers permission gating, explicit/non-repeating system
prompt behavior, self-bundle rejection, self-PID rejection, stale target PID,
depth/node/character limits, exact-text deduplication, secure-text filtering,
empty trees, cancellation, target-change discard, timeout, traversal order,
plain-text composition, role counts, and truncation.

Final result: 91 tests executed, 0 failures. Of those, 15 directly cover the
Accessibility reader and 76 are existing feature regressions.

## Existing feature regression checklist

The full pre-existing test suite remains the automated regression gate for:

- shell lifecycle and global hotkey registration;
- desktop pet and custom pet library;
- all eight pet states;
- TTS and user-initiated Push-to-Talk;
- STEP 2A event-driven application awareness.

Manual smoke checks use the real Debug app for pet → teaching panel →
Accessibility Debug. Accessibility reads do not transition pet state, invoke
TTS, or activate microphone capture.

## Build and static boundary validation

- Debug build: succeeded;
- Release build: succeeded;
- full test suite: 91/91 passed;
- `git diff --check`: passed;
- Xcode project plist lint: passed;
- forbidden API scan: no `AXUIElementSetAttributeValue`,
  `AXUIElementPerformAction`, `AXObserverCreate`, `AXObserverAddNotification`,
  ScreenCaptureKit, or Vision OCR use;
- Info.plist: no Screen Recording, Camera, or Photos permission was added;
- logging/persistence audit: no snapshot body logging or storage path exists.

## Known limitations

- AX output quality and role naming are controlled by each target application.
- A snapshot cannot see content the target does not expose, including some
  virtualized or off-screen regions.
- Generic exact-text deduplication does not solve semantic duplicates.
- No message-role parsing, live watch, context diff, OCR, or fallback exists in
  STEP 2B.
- A locally rebuilt ad-hoc Debug binary can require the user to refresh its
  Accessibility entry because TCC binds the grant to that build's code hash.

## Manual reproduction

1. Build and launch the Debug app.
2. If needed, add that exact `.app` to System Settings → Privacy & Security →
   Accessibility.
3. Focus the target application/window.
4. Open the pet or menu, then **Context Debug · Accessibility**.
5. Confirm Target App matches the intended external app.
6. Click **Read Current Window** once.
7. Inspect only window metadata, counts, roles, truncation, duration, and the
   capped preview. Copying remains a separate explicit action.

## Git status

Work is on `feat/accessibility-window-reader`, based on committed STEP 2A. STEP
2B changes are intentionally uncommitted. Nothing was pushed, deployed, or
merged.
