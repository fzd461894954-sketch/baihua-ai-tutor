# Semantic Buffer Architecture

## Scope

STEP 2D-3 converts incremental `ContextRevision` values into stable
`SemanticChunk` events. It does not interpret, summarize, classify, or send the
text to a Tutor, LLM, AI provider, TTS, Pet state, or voice subsystem.

```text
ContextRevision
        ↓
SemanticBuffer
        ↓
SemanticChunk
```

The layer answers one question only: has the newly added text become stable
enough for a later consumer?

## Input contract

`SemanticBuffer` receives the output of `ContextRevisionPipeline`.

- `added` revisions are appended to the pending buffer. The Diff Engine uses
  this one kind for both exact append and exact insertion evidence.
- `noChange` and `ambiguous` revisions do not append or extend the idle
  deadline.
- `baseline` and `reset` revisions discard pending text and cancel scheduled
  work.
- A change in any `ContextIdentity` component (bundle identifier, PID, focused
  window identity, or live session identifier) discards pending text before
  the new context can be accepted.

The layer does not modify snapshot extraction, normalization, fingerprints,
diffing, or revision generation.

## Output model

`SemanticChunk` contains:

- a UUID;
- the most recent contributing revision ID;
- stable text;
- the lowest Diff confidence among its contributing revisions;
- creation time;
- `sentenceComplete`, `idleTimeout`, `sizeLimit`, or `manualFlush` reason.

Chunks are delivered through a one-shot callback. Production code does not keep
an array of emitted chunks or retain previous chunk bodies. `chunkCount`, last
flush reason, and last confidence are scalar Debug metadata only.

## State model

```text
idle
  ↓ added text
buffering
  ↓ 700 ms stability check
ready
  ↓ 1500 ms total idle time
flushing
  ↓ chunk emitted
idle / buffering
```

`flushing` is intentionally transient. If a flush leaves a remainder, the
state returns to `buffering`; otherwise it returns to `idle`.

## Flush rules

### Sentence completion

Outside fenced Markdown code blocks, the following terminators make a complete
sentence eligible for immediate flush:

- Chinese: `。`, `？`, `！`
- English: `.`, `?`, `!`

Several complete sentences in one revision become separate chunks. A trailing
incomplete fragment remains pending. Decimal periods such as `3.14` are not
treated as sentence boundaries. Punctuation inside triple-backtick or
triple-tilde fenced code stays inside the code block and waits for another
flush rule.

### Idle timeout

The default 700 ms interval is only a stability check. It changes the state to
`ready` but never emits a chunk. A chunk is emitted only after 1500 ms with no
new added revision.

Each addition cancels and replaces the previous task. The implementation uses
one finite, cancellable Swift `Task`; it has no repeating or infinite timer.

### Size limit

Pending text is bounded to fewer than 1000 characters after ingestion. On
reaching the default limit, the buffer flushes at the most recent sentence
boundary at or before the limit. If none exists, it cuts at exactly 1000 Swift
`Character` values, preserving extended grapheme clusters such as emoji.

### Manual flush

`manualFlush()` emits the current pending text with reason `manualFlush`. An
empty buffer is a no-op.

## Streaming example

```text
Revision 1: "API 是"
Revision 2: "接口"
Revision 3: "。"

SemanticChunk: "API 是接口。"
Reason: sentenceComplete
```

Input removed by the Diff Engine is not reconstructed. The buffer only joins
text that arrived as supported added content. When the normalized character
count proves that Diff cleanup removed a boundary whitespace character, the
buffer restores a single separator between pending fragments.

## Lifecycle and memory

At runtime, `AccessibilityLiveMonitor` passes each published revision directly
to the buffer. Live Watch stop, permission loss, target termination, and other
content-clearing session exits call `clear()`.

Memory contains only:

- current `ContextIdentity`;
- current pending text (bounded by the size rule);
- pending source revision ID and confidence;
- one optional idle task;
- scalar Debug metadata.

There is no revision-body history or semantic-chunk-body history.

## Debug and privacy

Accessibility Debug shows state, pending character count, last flush reason,
last confidence, and chunk count. It does not display body text by default.
The user must click **查看当前 Buffer** to reveal the current pending body; this
does not reveal previously emitted chunks.

No Semantic Buffer body or chunk body is logged, persisted, copied to the
clipboard, uploaded, or sent over the network. The layer adds no permissions.

## Verification

Automated coverage includes complete sentences, streaming growth, multiple
sentences, the 700/1500 ms timing split, idle-task replacement, size-boundary
cutting, baseline/reset/identity/stop cleanup, 100-revision aggregation, emoji,
fenced code, mixed Chinese/English, manual flush, confidence aggregation, and a
1000-revision bounded-state stress run.

For a real ChatGPT stream, start Live Watch before requesting a long answer and
record only the Revision and Chunk Count metadata. Expected behavior is several
revisions per stable sentence and materially fewer chunks than revisions. Do
not copy answer text into the test report.

## Real ChatGPT validation

A permission-matched run on 2026-08-20 locked the native ChatGPT process
(`com.openai.codex`, PID 25380) while a long, sentence-structured answer streamed
into the same conversation. Only Debug metadata was recorded:

- AX events: 136;
- coalesced events: 121;
- successful snapshots: 54;
- final revision ID: 44;
- semantic chunks: 23;
- final state: `idle`;
- pending characters: 0;
- last flush: `sentenceComplete`, confidence `high`;
- latest snapshot: not truncated.

The stream produced about 48% fewer chunks than revisions while preserving its
sentence-level units. No Snapshot, Revision, pending Buffer, or Chunk body was
copied into this document. Stopping Live Watch then returned Revision to 0,
Chunk Count to 0, left the buffer `idle` with 0 pending characters, and cleared
the current identity, confirming session cleanup.
