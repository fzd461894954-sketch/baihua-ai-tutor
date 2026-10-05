# Voice Architecture

STEP 1.8 separates teacher output from user input:

- `VoiceController` owns local text-to-speech playback.
- `SpeechInputController` owns push-to-talk speech recognition.
- `PetState` remains the teacher's semantic state.
- `VoiceInputState` independently describes the user's microphone interaction.

This layer does not call Tutor Engine or an AI service. A completed transcript is
shown only in the current Pet action bubble and is never spoken automatically.

## Runtime boundaries

```text
Teacher text                           User holds button
     |                                        |
VoiceController                        SpeechInputController
     |                                        |
SpeechSynthesizing                     SpeechRecognizing
     |                                        |
AVSpeechSynthesizer        SFSpeechRecognizer + AVAudioEngine
     |                                        |
PetState.speaking                   VoiceInputState.listening
```

The small `SpeechSynthesizing` and `SpeechRecognizing` protocols keep Apple
framework details out of controllers and make lifecycle behavior deterministic in
tests.

## Text-to-speech

`HybridSpeechSynthesizer` exposes local Qwen3 voices before installed system voices.
For a Qwen voice it sends text only to the loopback MLX-Audio endpoint, receives WAV,
and plays it with `AVAudioPlayer`. The app starts the isolated local service when it
is installed and stops an app-owned service process during shutdown. A launch,
health, generation, or playback failure falls back to an installed `zh-CN` Apple
voice with the same request UUID.

`SystemSpeechSynthesizer` adapts `AVSpeechSynthesizer` and remains the explicit
system-voice path and automatic local failure fallback. Each utterance has a UUID,
so a stale completion from a replaced utterance cannot finish the current one.
There is no application-level speech queue.

`VoiceController` captures the current stable Pet state before entering
`.speaking`. Completion, cancellation, start failure, or explicit stop restores
that state. A transient `.success` state restores to `.idle`. Voice selection uses
the saved voice, then an installed `zh-CN` voice, then the system default.

Only voice identifier, rate, pitch, and volume are saved in `UserDefaults`.
Spoken teacher text is not persisted or logged.

## Voice input

`SpeechAuthorizationController` is the only component that requests or reads
microphone and Speech Recognition authorization. `SpeechInputController` owns:

- push-to-talk start, finish, timeout, and cancellation;
- partial and final transcript state held in memory;
- locale selection (`zh-CN` by default, with `en-US` available);
- on-device policy and Apple service consent;
- user-facing denied, unavailable, silence, and device-change messages.

`SystemSpeechRecognizerAdapter` streams microphone buffers directly from the
`AVAudioEngine` input tap to `SFSpeechAudioBufferRecognitionRequest`. It does not
create an audio file. A recognition completion, cancellation, timeout, start
failure, or audio-device configuration change stops the engine, removes the input
tap, and releases both request and task.

## Push-to-talk

Single-clicking the Pet opens a lightweight action bubble. The microphone is
started only by `mouseDown` on the hold-to-talk control. `mouseUp` stops audio
capture immediately, ends the recognition request, and waits for the final
result. App launch, opening the bubble, or changing focus never starts capture.

The action bubble is a fixed-size, borderless, key-capable panel. It becomes key
only after the user clicks the Pet, so its SwiftUI controls receive normal AppKit
mouse events and the window remains visible to accessibility tools. Replacing its
hosting controller cannot collapse the intended 330 × 230 layout.

The control keeps receiving the current mouse gesture when the pointer leaves its
bounds. A local and global left-mouse-up monitor exists only for the duration of
an active hold, allowing release outside the panel or after an application switch
to stop capture. Dismantling the control, hiding the Pet, dragging the Pet (which
hides the bubble), opening the Tutor window, quitting the app, or reaching the
60-second limit also cancels or finishes active input.

The Pet displays a microphone badge, the bubble displays “正在听…”, and the menu
bar also reports the listening state only while the audio engine confirms that it
is capturing. No second Pet transform animation is introduced.

## VoiceInputState

The input lifecycle is independent of the eight existing `PetState` values:

```text
idle -> requestingPermission -> ready
ready/completed -> listening -> transcribing -> completed
                         |             |
                         +-> denied / unavailable / error
```

Cancellation and clear return the interaction to `idle`. Starting input while
the Pet is `.warning`, for example, leaves `.warning` unchanged throughout the
recognition lifecycle.

## Permission flow

The app does not request voice permissions at startup. On the first active press
with an undetermined system status it shows an in-product explanation that the
microphone is used only while the user holds the button. Only the explanation's
Continue action requests microphone permission, followed by Speech Recognition
permission.

Denied microphone and denied Speech Recognition states have distinct messages and
open their respective macOS Privacy & Security settings pages. Restricted and
unavailable states do not repeatedly trigger system dialogs.

## On-device recognition

For each selected locale, the adapter checks `supportsOnDeviceRecognition`. When
supported, the request sets `requiresOnDeviceRecognition = true`; this is the
default and requires no network consent.

When on-device recognition is unavailable, the controller does not silently
disable that requirement. It first asks whether the user permits Apple's speech
recognition service. Choosing local-only stops the attempt with a clear message.
Choosing Apple service saves the non-sensitive boolean preference and permits a
network-backed request. A service/network failure is shown as a retryable message
and does not change the local-mode policy.

## TTS/STT arbitration

Starting microphone capture calls `VoiceController.stop()` before installing the
audio tap. This prevents teacher output from being re-recognized. The interrupted
utterance is not resumed. Conversely, starting a new TTS utterance cancels active
voice input through `VoiceController.onWillSpeak`, so output and input cannot run
at the same time.

This arbitration does not map Voice Input onto `PetState`; stopping TTS restores
the state that preceded `.speaking`, and STT then maintains it.

## Privacy and shutdown

Partial and final transcripts live only in observable memory for the current
bubble. They are cleared by the UI and disappear with the process. Neither
transcripts nor microphone buffers are logged, written to disk, placed in a
database, or added to a history.

Application shutdown cancels recognition before stopping TTS and before windows
are torn down. See `VOICE_PRIVACY.md` for the user-data policy and permission
matrix.
