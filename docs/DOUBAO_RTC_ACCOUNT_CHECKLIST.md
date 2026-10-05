# Doubao RTC Account Checklist

Phase 0 status: **E2E PENDING**

This checklist must be completed by a human against the current Volcengine
console and account contract before a real macOS ↔ RTC ↔ Doubao S2S test.
Do not paste secrets, tokens, keys, screenshots containing secrets, or complete
credential responses into this file or Git.

## RTC account

- [ ] RTC AppId confirmed (record only a non-secret alias or last four characters):
- [ ] RTC application is enabled for the target account/project:
- [ ] StartVoiceChat API version actually available to this account:
- [ ] RTC macOS SDK version approved for the spike:
- [ ] RTC macOS SDK supports the required Intel/Apple Silicon build targets:
- [ ] RTC concurrency limit:
- [ ] RTC billing unit and current account price:

## Doubao S2S account

- [ ] Doubao end-to-end realtime voice service is enabled:
- [ ] `S2SConfig.Provider` value confirmed:
- [ ] `S2SConfig.OutputMode` value confirmed for pure S2S:
- [ ] Actual S2S-O `model` value confirmed for this account:
- [ ] Doubao App ID confirmed (record only a non-secret alias or last four characters):
- [ ] Doubao Access Token exists and is stored only by the bootstrap service:
- [ ] S2S concurrency limit:
- [ ] S2S billing unit and current account price:
- [ ] Trial/resource-package limits and expiry date:

## Backend bootstrap

- [ ] Development bootstrap service owns Volcengine AK/SK:
- [ ] Development bootstrap service owns the RTC AppKey:
- [ ] Development bootstrap service owns the Doubao Access Token:
- [ ] `createSession` generates a short-lived RTC token:
- [ ] `createSession` calls StartVoiceChat with the confirmed API version:
- [ ] `createSession` returns only rtcAppID, rtcToken, roomID, userID, taskID, expiresAt:
- [ ] `interruptSession` reaches the real remote task:
- [ ] `stopSession` calls StopVoiceChat using the same AppId/RoomId/TaskId:
- [ ] Server logs redact all credentials and RTC tokens:
- [ ] Server enforces a 3–5 minute development session limit:

## Manual E2E evidence

Record only timestamps, request/log IDs that are safe to share, durations, and
PASS/FAIL. Never record audio or transcript content here.

- [ ] Mac built-in microphone + speaker
- [ ] Headphones
- [ ] Automatic barge-in while AI is speaking
- [ ] Manual interrupt
- [ ] Normal Stop
- [ ] Forced network interruption
- [ ] App Quit cleanup
- [ ] Every test confirms the cloud task stopped

## Exit gate

Phase 1A may be marked `E2E PASS` only when every account item and required
manual test above is confirmed. Until then the only allowed status is:

**CODE PASS / E2E PENDING**
