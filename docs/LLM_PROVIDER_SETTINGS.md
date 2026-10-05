# LLM Provider Settings

## Scope

The product supports one active OpenAI-compatible provider profile. The first
release includes an Ark preset and a custom OpenAI-compatible option. Both use
the same `OpenAICompatibleProvider`; no provider marketplace or additional
adapters are part of this stage.

## Configuration boundary

The production flow is:

```text
AI Model Settings
  ├─ non-sensitive settings → LLMProviderSettingsStore (UserDefaults)
  └─ API Key → KeychainCredentialStore (macOS Keychain)
                         ↓
                TutorProviderFactory
                         ↓
           immutable provider snapshot
                         ↓
             OpenAICompatibleProvider
```

`LLMProviderSettings` contains profile identity, provider type, preset,
endpoint, model, response-format capability, temperature, output-token limit,
and enabled state. It has no API key field. The profile ID is the stable
Keychain account reference.

The Keychain generic-password service is derived from the app bundle ID plus
`.llm` (normally `com.baihuaai.AITutorMac.llm`). The account is the active
provider profile ID. Updating a key uses `SecItemUpdate`, avoiding duplicate
items.

## Settings and credential lifecycle

- A key enters Keychain only after the user presses Save.
- The SecureField value is cleared immediately after a successful save.
- Existing secrets are never read back into a text field.
- Replacing a key requires entering a new value.
- Deleting the key removes only the provider credential.
- Deleting the model configuration removes both settings and credential, but
  does not touch Pet, Context, or Voice preferences.
- Keychain errors never fall back to UserDefaults, plist, JSON files, or source.

The Debug Real LLM Demo keeps its independent process-memory configuration. It
is not a production runtime configuration source.

## Provider snapshot and runtime

`TutorProviderFactory` reads validated settings and the credential at the
start of each request. It creates one immutable snapshot containing endpoint,
model, response format, generation parameters, credential reference, and a
redacted runtime credential wrapper. The provider receives the secret only by
runtime injection.

Settings changes cancel the active Tutor request. The next request builds a
new snapshot, so one request cannot mix old and new model or credential data.
Release and Debug production Panels use the same runtime composition.

If settings are incomplete or the credential is absent, no HTTP request is
made. The Panel reports that no teaching model is configured and offers a link
to AI Model Settings.

## Ark preset

The Ark preset suggests:

```text
https://ark.cn-beijing.volces.com/api/v3/chat/completions
```

The model remains user-supplied because model access differs by account. Ark
uses JSON Object compatibility mode by default; custom endpoints default to
JSON Schema unless the advanced setting overrides this behavior.

## Connection test

Connection Test uses a minimal JSON generation request. It verifies endpoint
reachability, credential acceptance, model availability, and response parsing.
The UI records only latency and a redacted outcome category. It never records
the API key, request body, response body, source chunk, or Tutor prompt.

User-facing categories are API key invalid, model unavailable, rate limited,
network failure, invalid endpoint, timeout, invalid response, and incomplete
configuration. Raw HTTP bodies and internal error names are not shown.

## Privacy

Only an explicitly requested Tutor explanation sends text to the configured
provider. The source is the current stable `SemanticChunk` used by
`TutorRequest`; full Accessibility snapshots and the full screen are not sent.

## Tests

The default suite uses dummy credentials and mocked providers/transports. It
performs no real provider network request. Keychain tests use isolated service
names and delete test items. Any real-network verification remains opt-in and
skips when its environment credential is absent.
