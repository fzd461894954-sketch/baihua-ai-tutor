# Voice Privacy

## When the microphone is used

The app uses the microphone only after the user clicks the microphone button in
the teacher card. App launch, Pet launch, opening the card, switching
applications, and normal background operation do not start the microphone.
There is no wake word or always-listening mode.

While capture is active, the user can see a microphone badge on the teacher,
live partial transcript feedback in the card, and a listening label in the menu
bar. The user clicks “结束并提问” to stop capture.

## When the microphone stops

Capture stops when the user clicks “结束并提问”. It is also stopped or cancelled
when:

- the teacher card disappears;
- the teacher is dragged or hidden;
- the 60-second per-utterance limit is reached;
- the input audio device changes or becomes unavailable;
- recognition fails or is cancelled;
- the app quits.

Clicking the end button stops microphone capture before the recognizer completes
its final text result.

## Permissions

No voice permission is requested at app startup. The first active attempt shows a
product explanation. The app requests system access only after the user chooses
Continue:

1. Microphone — to capture speech between the explicit start and end actions.
2. Speech Recognition — to convert that actively supplied speech to text.

If either permission is denied, the app identifies which permission is missing
and offers the matching macOS Privacy & Security settings page. Voice Input does
not request Accessibility, Screen Recording, Camera, or Photos access.

## Audio and transcript storage

Microphone buffers are streamed from `AVAudioEngine` to Apple's Speech framework
in memory. The app creates no `.wav`, `.m4a`, `.caf`, `.mp3`, or other audio file.

Partial and final transcripts are kept only in memory for the current interaction.
After recognition finishes, the app explicitly reads the last external window
and submits its bounded visible-text excerpt together with the final transcript
to the currently configured AI model provider. If the external window cannot be
read, the app shows an error instead of silently pretending it saw that content.
The app does not save a
speech history, database record, or transcript log. OSLog messages contain
lifecycle and permission outcomes only, never the words spoken by the user.

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

The app sends audio only through Apple's Speech framework according to the choice
above. The configured AI model provider receives the final transcript as text,
not the microphone audio. The teacher card discloses that teaching content is
sent to the configured model service.

## Teacher speech arbitration

Starting Voice Input immediately stops active teacher text-to-speech before the
microphone starts. The interrupted speech is not resumed. Starting teacher speech
also cancels active Voice Input, so the microphone and speaker workflows never run
concurrently.

## Local teacher speech

When a local Qwen3 voice is selected, teacher text is sent to the MLX-Audio service
at `127.0.0.1` and never to a third-party TTS API. The service returns WAV bytes in
memory. The app plays those bytes and does not save them as an audio file.

If the local runtime is not installed, cannot start, or fails to synthesize a
request, the app automatically uses an installed Apple `zh-CN` system voice. The
teacher text is never logged in either path.
