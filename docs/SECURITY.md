# Security

## Secrets

LLM API keys are stored only as macOS Keychain generic-password items through
`KeychainCredentialStore`. They must never be stored in UserDefaults, plist,
JSON, SwiftData, source code, fixtures, logs, crash annotations, Debug dumps,
Git, or documentation.

The provider layer does not access Keychain. `TutorProviderFactory` resolves a
credential at the composition boundary and injects it into an immutable,
request-scoped `OpenAICompatibleProvider`. Runtime credential descriptions are
redacted.

Never add fallback secret storage when Keychain is unavailable. The correct
behavior is to show a safe-save failure and keep Tutor Runtime unavailable.

## Logging and diagnostics

Allowed diagnostics are redacted categories, latency, token counts returned by
the provider, and success/failure state. Do not log:

- Authorization headers or API keys
- provider request or response bodies
- Tutor prompts or TutorResponse bodies
- SemanticChunk or Accessibility Snapshot text
- user-supplied endpoint query credentials

User-facing errors must not expose NSError domains, internal provider enums,
or raw HTTP response bodies.

## Local preferences

Non-sensitive provider settings may be stored in app-scoped UserDefaults:
endpoint, model, provider type, response format, temperature, output limit,
enabled state, and profile ID. `LLMProviderSettings` deliberately has no secret
field.

Deleting an LLM configuration deletes its matching Keychain item and provider
preferences only. Pet, Context, and Voice domains remain independent.

## Network privacy

The app contacts the configured model service only after an explicit user
request. A Tutor request contains the current stable SemanticChunk required for
the lesson. The app does not automatically upload a full screen or complete
Accessibility snapshot.

## Permissions

- Accessibility is requested only after the user chooses the menu action and is
  used only for the explicitly started single-target Live Watch.
- Microphone and speech recognition are requested only after Push-to-Talk is
  actively used.
- V0.1 does not request Screen Recording, Camera, Photos, or Full Disk Access.
- TTS, Pet state, custom-Pet storage, and ordinary UI appearance remain local.

## Internal beta distribution

The V0.1 test artifact is not an external release unless it is signed with a
valid Developer ID, notarized, stapled, and verified. An ad-hoc signature is
acceptable only for a clearly labeled internal QA build; it must not be
described as a notarized or broadly distributable macOS release.

## Development credentials

Tests use values such as `test-api-key` and Mock URLProtocol. Real credentials
are opt-in, process-local, and absent from the default suite. A credential ever
shared in chat or another uncontrolled channel must be considered exposed and
rotated; it must never be copied into source, fixtures, comments, or docs.
