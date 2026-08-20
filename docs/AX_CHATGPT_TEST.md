# ChatGPT Accessibility Test

## Environment

- Date: 2026-08-14
- macOS test machine: Apple silicon Mac
- Display name observed by `NSWorkspace`: `ChatGPT`
- Bundle identifier observed: `com.openai.codex`
- Mode: user-triggered Accessibility Debug snapshot
- Parser/adapters: none

The display name and bundle identifier above are the real package observation on
this machine. The implementation does not rename or reinterpret the package.

## Result: SUCCESS

The final post-build depth-40 snapshot observed:

- focused window: `ChatGPT`;
- window role/subrole: `AXWindow` / `AXStandardWindow`;
- unique text nodes: 185;
- visited AX nodes: 682;
- normalized characters: 3,063;
- truncated: no;
- duration: 0.158s;
- leading role counts: `AXGroup` 221, `AXButton` 149, `AXStaticText` 133,
  `AXImage` 120, `AXPopUpButton` 17, `AXCheckBox` 12, `AXHeading` 9, and
  `AXListMarker` 9.

Without copying the captured body into this report, known-string checks against
the capped Debug preview confirmed the presence of both a user permission
message and an assistant permission reply, plus the current task title. This is
a successful answer to STEP 2B's question: the generic reader can see both sides'
displayed text in this real package. It does not mean STEP 2B can label which
side authored any arbitrary node.

The earlier permission-complete calibration used the suggested initial
depth-20 budget and returned `PARTIAL`: 46 unique text nodes, 153 visited AX
nodes, 500 characters, `truncated = true`, in 0.048s. The preview reached native
navigation and task UI but not enough message content. That observation drove
the measured default-depth adjustment from 20 to 40 while retaining the
2,000-node and 100,000-character hard limits.

## Structure and limitations

- Focused window role observed: `AXWindow`
- Focused window subrole observed: `AXStandardWindow`
- Root/window title observed: `ChatGPT`
- Text was exposed through multiple control roles rather than a stable
  conversation-message schema.
- Exact normalized duplicate strings are removed by the generic extractor.
- STEP 2B cannot distinguish user and assistant messages from role or position.
- Collapsed, virtualized, off-screen, or otherwise unexposed regions may be
  absent.
- No ChatGPT-specific role, DOM, or layout rule is hardcoded.

## Privacy of this report

This report records metadata and structural findings only. It intentionally
does not include the captured conversation body, window history, or copied
snapshot text.
