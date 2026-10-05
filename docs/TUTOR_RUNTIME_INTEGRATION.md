# Tutor Runtime Integration (STEP 09-2A)

## Scope

This Debug-only integration connects the opt-in Accessibility Live Watch to the
Tutor Panel. It does not add Keychain storage, automatic model calls, Pet/Voice
behavior, or Release credentials.

## Runtime path

1. The user presses **解释当前内容** or submits a question in the teacher card.
2. `TutorManualRuntimeController` creates an on-demand UUID-scoped session when
   no Accessibility Live Watch session is active.
3. `AccessibilitySnapshotController` performs one bounded read against the last
   external application. This explicit read does not require continuous watch.
4. `CurrentExplainableContentProvider` converts that fresh snapshot into one
   bounded `SemanticChunk` owned by the active session.
5. `TutorManualRuntimeController` validates the model configuration and asks
   `TutorCoordinator` for a `.userInitiated` explanation.
6. `OpenAICompatibleProvider` produces a validated `TutorResponse`, which is
   mapped to `TutorPresentationModel` and routed to Tutor Panel.

Accessibility Live Watch and Semantic Buffer remain optional and never call a
Tutor engine by themselves. An explicit user action always attempts a fresh
snapshot so observer startup or notification failures do not block explanation.

## Session and cancellation ownership

- Stop, target invalidation, or a new live session clears current explainable
  content and cancels current Tutor work.
- Coordinator and presentation router both validate the live session UUID, so a
  late result cannot update the Panel after ownership changes.
- If a newer stable chunk replaces the requested chunk in the same live session,
  the in-flight explanation is cancelled and cannot overwrite the new context.
- A second Explain/Retry cancels the older request and starts a new request.
- Dismiss cancels loading without converting cancellation into an error.
- Closing/hiding the floating Panel does not cancel a request; the request may
  finish while hidden and will be visible when the user reopens the Panel.
- Stopping the app cancels and clears the runtime.

## Debug model configuration

Endpoint, model, and API key are entered in **Tutor Debug > Real LLM Demo** and
shared in process memory with the Panel runtime. They are not persisted or
logged. Closing Tutor Debug preserves them; exiting the app clears them. Without a complete valid configuration,
the Panel performs no network request and shows **还没有配置教学模型**.

Release builds retain the unavailable Panel action and do not construct this
Debug model runtime.

## Privacy boundary

The Panel displays: **解释内容会发送给当前配置的 AI 模型服务。**

No source body, prompt, raw response, API key, token, snapshot body, or response
history is logged or persisted by this integration. The current-content adapter
holds only one current chunk and exposes no revision/snapshot history. Tutor
Quality Evaluation remains an independent Debug tool and does not mutate runtime
content.

## Manual real E2E procedure

1. Open ChatGPT or Codex and make it the last external application.
2. In Tutor Debug > Real LLM Demo, enter a valid endpoint, model, and API key.
   Leave that Debug window open so its in-memory configuration remains available.
3. Open Tutor Panel and press **解释当前内容** without starting Live Watch.
4. Confirm loading appears immediately and a real `TutorPresentationModel`
   lesson replaces it.
5. Repeat with a changed ChatGPT/Codex response, double-click/retry, Live Watch
   stop, and a new live session. Confirm no request is started before a user
   action and no old-session result is presented.

Real credentials and real chat text must never be added to fixtures, screenshots,
logs, documentation, or Git.
