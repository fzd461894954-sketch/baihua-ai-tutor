# Voice Architecture

STEP 1.8A adds local text-to-speech only. It does not add speech recognition,
microphone input, realtime voice, AI APIs, or audio-file export.

## Runtime flow

```text
Text
  ↓
VoiceController
  ↓
SpeechSynthesizing
  ↓
SystemSpeechSynthesizer (AVSpeechSynthesizer)
  ↓
PetState.speaking
  ↓
finish / cancel / user stop
  ↓
previous stable PetState
```

`VoiceController` is the application-facing boundary. Future teaching code calls
`speak(text:)`, while the tutor layer remains unaware of AVFoundation types.

## System adapter

`SystemSpeechSynthesizer` adapts `AVSpeechSynthesizer` to the small
`SpeechSynthesizing` protocol. Each utterance has a UUID. Delegate callbacks are
matched to that UUID so a stale cancellation or completion from a replaced
utterance cannot finish the current one.

Calling `speak(text:)` while another utterance is active stops the old utterance
immediately and starts the new one. There is no application-level speech queue.
Pause, continue, stop, start, completion, and cancellation are represented by the
controller's observable playback status.

The adapter never logs spoken text. Logs contain lifecycle information only.

## Voice selection and settings

The saved non-sensitive settings are:

- voice identifier
- rate
- pitch
- volume

They are stored in `UserDefaults`; spoken text is never persisted. Rate, pitch,
and volume are clamped to conservative UI ranges before storage and playback.

Voice selection follows this fallback order:

1. the saved voice identifier, if still installed;
2. an installed `zh-CN` voice;
3. `nil`, which asks AVFoundation to use the system default voice.

No machine-specific voice identifier is hard-coded.

## Pet state restoration

At the first utterance in a replacement sequence, `VoiceController` captures the
current stable Pet state. The Pet enters `.speaking` and keeps the existing generic
Speaking animation and badge. Normal completion, cancellation, a start failure,
or explicit stop restores the captured state.

`idle`, `thinking`, `warning`, and `needsInput` therefore return to themselves.
`success` is transient rather than stable, so speech begun during Success restores
to `idle`. Entering Speaking prepares the old Pet state, which cancels the Success
animation task; its stale completion callback is also rejected by
`PetStateController` because Success is no longer current.

Replacing A with B preserves the restoration state captured before A. A's later
delegate callback cannot restore the Pet while B is active.

## Pet visibility and custom pets

Voice has no dependency on `PetModel`, its image, or its source. Bundled and
user-imported static PNG pets use the same `.speaking` state and animation.
Changing the selected Pet recreates its view and immediately renders the current
Speaking state without stopping audio. Hiding the Pet only hides its windows;
speech continues until it completes or the user stops it.

Reduce Motion continues to be owned by `PetAnimationController`. Speech playback
is unaffected, while the existing reduced Speaking presentation remains in use.

## Privacy and permissions

Playback uses macOS system speech through AVFoundation. This stage sends no text
to a third-party TTS API, records nothing, and writes no audio files. It adds no
microphone, camera, screen-recording, or Accessibility permission usage strings
and performs no TCC permission request.

The app calls `VoiceController.stop()` during shutdown before its windows and Pet
are torn down.

## Future STT boundary

Speech-to-text belongs to a separate future module. It must not be added to
`VoiceController` or `SpeechSynthesizing`, which are playback-only abstractions.
A future realtime voice implementation can sit behind a new boundary or replace
the synthesis adapter without coupling Tutor prompts to AVFoundation.
