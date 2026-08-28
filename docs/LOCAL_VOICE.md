# Local Qwen3 Voice

白话 AI 可以优先使用完全运行在本机的 Qwen3-TTS，并在本地服务未安装、未启动或生成失败时自动回退到 Apple 系统中文语音。

## 当前基线

- Runtime: MLX-Audio on Apple Silicon
- Model: `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit`
- Model license: Apache 2.0
- Model download: approximately 1.65 GB
- Endpoint: `http://127.0.0.1:8000/v1/audio/speech`
- Default voice: `Serena`
- Audio returned to the app: WAV

本地服务只监听 loopback 地址。应用不会把朗读文字发送到局域网或第三方 TTS API。

## Install

From the repository root:

```bash
./scripts/setup-local-voice.sh
```

The script creates an isolated Python 3.12 environment at:

```text
~/Library/Application Support/BaihuaAI/LocalVoice/.venv
```

It installs MLX-Audio and downloads the model into the normal Hugging Face cache. No API key is required.

## Verify independently

```bash
./scripts/verify-local-voice.sh
```

The verification script starts a temporary loopback server when needed, generates one Chinese sentence, saves it under the system temporary directory, and plays it with `afplay`.

## App lifecycle

At launch, `HybridSpeechSynthesizer` checks `127.0.0.1:8000`. If the endpoint is not already healthy and the isolated runtime is installed, the app launches `mlx_audio.server` itself. A process started by the app is terminated during app shutdown.

Service startup output is written to `~/Library/Application Support/BaihuaAI/LocalVoice/service.log` for local diagnosis. It contains model-loading and HTTP route status, not the submitted teacher text.

The app exposes five local Qwen voices in its voice picker. Selecting an Apple voice bypasses the local service. Selecting a Qwen voice uses the local service and falls back to an installed `zh-CN` Apple voice if local generation fails.

## Upgrade path

The 0.6B 8-bit model is intentionally the first production baseline because it keeps setup size and latency bounded. After the baseline is measured on representative lessons, the next candidate is `Qwen3-TTS-12Hz-1.7B-CustomVoice-6bit` for stronger instruction and emotion control.
