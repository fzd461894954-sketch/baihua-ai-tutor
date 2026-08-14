# Voice Privacy

## When the microphone is used

The app uses the microphone only after the user presses and holds the “按住说话”
control in the Pet action bubble. App launch, Pet launch, opening the action
bubble, switching applications, and normal background operation do not start the
microphone. There is no wake word or always-listening mode.

While capture is active, the user can see a microphone badge on the Pet, “正在听…”
in the bubble, and a listening label in the menu bar.

## When the microphone stops

Capture stops when the user releases the button, including after dragging the
pointer outside it. It is also stopped or cancelled when:

- the hold-to-talk control or its bubble disappears;
- the Pet is dragged or hidden;
- the Tutor window is opened from the bubble;
- the 60-second per-utterance limit is reached;
- the input audio device changes or becomes unavailable;
- recognition fails or is cancelled;
- the app quits.

Releasing the button stops microphone capture before the recognizer completes its
final text result.

While a push-to-talk gesture is active, the app temporarily observes only the
left-mouse-up event so release outside the bubble can stop capture. The monitor is
removed immediately on release or cancellation, records no pointer history, and
does not request Accessibility permission.

## Permissions

No voice permission is requested at app startup. The first active attempt shows a
product explanation. The app requests system access only after the user chooses
Continue:

1. Microphone — to capture speech while the button is held.
2. Speech Recognition — to convert that actively supplied speech to text.

If either permission is denied, the app identifies which permission is missing
and offers the matching macOS Privacy & Security settings page. Voice Input does
not request Accessibility, Screen Recording, Camera, or Photos access.

## Audio and transcript storage

Microphone buffers are streamed from `AVAudioEngine` to Apple's Speech framework
in memory. The app creates no `.wav`, `.m4a`, `.caf`, `.mp3`, or other audio file.

Partial and final transcripts are kept only in memory for the current interaction.
The app does not save a speech history, database record, or transcript log. OSLog
messages contain lifecycle and permission outcomes only, never the words spoken
by the user.

The only saved Voice Input preferences are whether the product explanation was
acknowledged and whether Apple service recognition was explicitly allowed. They
contain no speech or audio content.

## On-device mode

When the selected language supports Apple's on-device recognition, the app
requires it. In this mode the app does not opt into Apple's network-backed speech
recognition service.

## Apple service mode

Some languages or system configurations do not support on-device recognition.
The app then asks for explicit consent before allowing Apple's speech recognition
service. Choosing “仅使用本机” stops the recognition attempt; it never silently
falls back to network processing. Choosing “允许 Apple 语音识别” records that
preference and allows Speech framework to use Apple's service according to the
system service's availability and Apple's policies.

This application does not send the transcript to Tutor Engine, an AI provider, or
any third-party STT SDK in STEP 1.8B.

## Teacher speech arbitration

Starting Voice Input immediately stops active teacher text-to-speech before the
microphone starts. The interrupted speech is not resumed. Starting teacher speech
also cancels active Voice Input, so the microphone and speaker workflows never run
concurrently.
