# Tutor Quality Evaluation

STEP 08-3 adds deterministic, offline evaluation after a validated
`TutorResponse`. It does not change `OpenAICompatibleProvider` or add storage.

## Evaluation boundary

`TutorQualityEvaluator` receives the response, its `TutorRequest`, and optional
case expectations. It emits one signal for each of these checks:

- visible `plainExplanation`
- explanation length for the requested detail level
- key points and any case-required example
- glossary presence and entry quality
- analogy presence when requested
- overlap with source/case teaching anchors
- explicit hallucination markers and source-external decimal/URL anchors
- hollow or non-substantive summary text

An explicit structural or grounding violation produces `failed`. A signal that
cannot be proven offline, such as a newly introduced number or URL, produces
`warning` and makes the overall result `needsReview`. These heuristics are a
Debug aid, not a semantic fact checker.

## Debug dataset and privacy

`TutorEvaluationDataset` contains six synthetic cases: API, HTTP, JSON, Error,
Database Migration, and Permission Error. Every case contains a fixed
`SemanticChunk` and expected teaching characteristics. None comes from captured
application text, a real user, or a provider response.

The Quality Evaluation tab keeps endpoint, model, API key, source, and response
only in the window controller's memory. Closing the Debug window clears them.
Run history contains metadata and quality signals only. Source and response
bodies are hidden until manually expanded.

Running the same unchanged case again creates a new request while reusing the
same fixed `SemanticChunk` identity, which makes multiple LLM runs comparable.

## Verification coverage

Tests cover repeated runs of one chunk, empty response, malformed lesson,
excessive length, hallucination marker, missing glossary, missing analogy,
off-topic output, hollow summary, valid lesson, and the six-case dataset.
