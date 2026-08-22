# V0.1 Release Checklist

Date: 2026-08-23
Version: 0.1.0 (1)
Freeze: FEATURE FREEZE

`PASS` 表示本轮已有可重现证据；`MANUAL PENDING` 表示必须由测试者在真实硬件或视觉环境中完成，不冒充 PASS。

## Core QA

| QA | Result | Evidence / remaining action |
|---|---|---|
| 1. First launch | PASS | Debug app launched, MenuBar runtime and Pet started; Info.plist contains only microphone and speech-recognition usage strings, with no Screen Recording, Camera, or Photos request. Accessibility is refreshed without prompting at launch. |
| 2. Accessibility / Live Watch | MANUAL PENDING | Existing observer tests and prior real Chrome/ChatGPT reports pass. Final Release UI now exposes permission/start/stop after a P0 fix. Rebuilt 0.1.0 app still needs one real target run confirming SemanticChunk, stop, close-window independence, and app switching. |
| 3. Provider settings | PASS | Saved Ark settings survived multiple app/test-host launches; Keychain item exists; 5-run benchmark and six-case suite used the persisted credential successfully without showing it. |
| 4. Tutor core E2E | MANUAL PENDING | Real provider Decode/Validate/quality passes, and automated runtime/panel tests cover loading, lesson sections and duplicate suppression. Final Chrome/ChatGPT → Live Watch → SemanticChunk → Panel run remains paired with QA-2. |
| 5. Pet Tutor notification | MANUAL PENDING | Automated router/bubble tests cover unread, opening an existing presentation and no second request. Final hidden-panel visual interaction remains. |
| 6. Tutor voice | MANUAL PENDING | Automated Apple TTS, speaking state, stop, restoration and no-autoplay tests exist. Final audible check remains. |
| 7. Push-to-Talk | MANUAL PENDING | `REAL_MIC_VALIDATION_PENDING` remains open for Chinese, English and mixed speech on a real microphone, including permission, partial/final transcript, release-to-stop and TTS arbitration. |
| 8. Custom Pet | MANUAL PENDING | Automated import/validation/library/persistence/delete/fallback and eight-state tests exist. Final transparent-PNG visual pass remains. |
| 9. Accessibility / UI | MANUAL PENDING | Source and tests cover PTT label, hint, toggle action, keyboard behavior and Reduce Motion policy. VoiceOver focus ring plus light/dark/Reduce Motion visual checks remain. |
| 10. Privacy | PASS | Repository/history hits were code identifiers or explicit dummy test values only. App logs contained 0 private markers, UserDefaults contained no secret field, the artifact contained 0 private fixture markers, and no `.profraw` / `.profdata` files exist. API key remains Keychain-only. |
| 11. Regression | PASS | 357 tests: 354 passed, 3 explicit opt-in network tests skipped, 0 failed. Debug and Release builds passed; `git diff --check` passed. |

## Bug classification

| ID | Severity | Status | Result |
|---|---|---|---|
| V01-001 | P0 | FIXED | Release had no entry to start the existing Live Watch, making the core Context-to-Tutor flow unreachable. The menu now exposes permission, start and stop actions without changing Context architecture. |

## Packaging and signing

- Marketing version: `0.1.0`
- Build: `1`
- Developer ID identities on this machine: none
- Distribution class: V0.1 Internal Beta only
- External distribution still requires Developer ID signing and notarization
- Artifact: `artifacts/Baihua-AI-v0.1.0-internal-beta-arm64.zip`
- SHA-256: `5af311f588cdb682e6edabe49fbac1851354b8b200d08be2e6ea3cd8139a416e`
- `codesign --verify --deep --strict`: PASS
- Signature: ad-hoc with hardened runtime; no TeamIdentifier
- Gatekeeper `spctl`: rejected, as expected for a non-Developer-ID, non-notarized internal build

## Freeze gate

- Remaining P0 product bugs: 0 known
- Remaining P1 product bugs: 0 known
- Blocking validation gap: real microphone QA and the final rebuilt-app manual UI matrix
- V0.1 status: BLOCKED until every `MANUAL PENDING` item is completed
