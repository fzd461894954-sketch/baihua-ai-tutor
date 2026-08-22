# Tutor Stream / Model Benchmark

Date: 2026-08-23
Scope: V0.1 final model decision

本报告只记录合成 Case 的指标和质量信号，不包含 SemanticChunk、Prompt、TutorResponse、Accessibility Snapshot 或凭据正文。

## Fixed configuration

| Item | Value |
|---|---|
| Provider | Ark OpenAI-compatible Chat Completions |
| Baseline | `doubao-seed-evolving` |
| Candidate | `doubao-seed-2-0-lite-260428` |
| Candidate source | Ark account `/api/v3/models`; listed without Shutdown/Retiring status |
| Synthetic case | API |
| Runs | 5 per model, serial |
| Language / learner | `zh-Hans` / product default |
| Temperature | saved active value, 0.2 |
| Compact budget | 900 max output tokens |
| Response format | `json_object` |
| Transport | existing `stream()`; no partial Tutor Panel UI |
| Gate | complete JSON, Decoder, Validator, TutorQualityEvaluator |

## Five-run model result

| Model | Success | TTFB min / median / max | First content min / median / max | Total min / median / max | Quality |
|---|---:|---|---|---|---|
| `doubao-seed-evolving` | 5/5 | 1.825 / 2.090 / 5.772s | 7.113 / 10.942 / 19.342s | 15.512 / 17.358 / 25.960s | 5 PASS |
| `doubao-seed-2-0-lite-260428` | 0/5 | 1.144 / 1.294 / 1.448s to terminal failure | unavailable | unavailable | 5 FAIL |

Ark 的 SSE 响应没有返回 usage，因此本轮 input/output tokens 记为 `unavailable`，不做估算。已有的同 API、`json_object`、非 streaming 5次参考数据为：input tokens median 2,005，output tokens median 887，TTFB median 23.041s，total median 23.046s。

新候选虽然在账号模型列表可见，但对本次固定 Tutor 请求 5/5 无法进入完整 Decode / Validate 链路，因此不是 V0.1 可用模型，也不进入六 Case 质量门禁。

## Six-case quality gate

只有基线模型通过 5次性能完整性检查。

| Model | API | HTTP | JSON | Error | Database Migration | Permission Error |
|---|---|---|---|---|---|---|
| `doubao-seed-evolving` | PASS | NEEDS REVIEW | NEEDS REVIEW | PASS | PASS | PASS |

结果为 4 PASS / 2 NEEDS REVIEW / 0 FAIL。两个 review 都是 `unsupportedFacts` 数值锚点启发式告警；教学结构、长度、来源对齐、Decoder 和 Validator 均通过。

## Streaming first-content result

Streaming 的 median first SSE event 约 2.09s，median first model content 约 10.94s，median completion 约 17.36s。它证明 SSE 事件可明显早于完整结果，但第一段模型内容仍未稳定进入 10 秒内。V0.1 不实现 Incremental Structured UI，不展示 partial JSON。

## V0.1 decision

- Recommended V0.1 model: `doubao-seed-evolving`
- Recommended response format: `json_object`
- Median TTFB: 2.090s in streaming measurement; current non-stream reference 23.041s
- Median total latency: 17.358s in streaming measurement; current production reference 23.046s
- Input tokens: streaming unavailable; non-stream reference median 2,005
- Output tokens: streaming unavailable; non-stream reference median 887
- Quality: 0 FAIL; 2 NEEDS REVIEW with explained heuristic warnings
- Streaming first content: median 10.942s
- Existing saved model: unchanged

**KNOWN LIMITATION: Tutor latency.**

**SHIP**
