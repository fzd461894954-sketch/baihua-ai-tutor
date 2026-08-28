#!/bin/zsh

set -euo pipefail

VOICE_ACCOUNT_NAME="$(id -un)"
VOICE_USER_DIR="$(dscl . -read "/Users/${VOICE_ACCOUNT_NAME}" NFSHomeDirectory | sed 's/^NFSHomeDirectory: //')"
VOICE_ROOT="${AITUTOR_LOCAL_VOICE_ROOT:-${VOICE_USER_DIR}/Library/Application Support/BaihuaAI/LocalVoice}"
VOICE_SERVER="${VOICE_ROOT}/.venv/bin/mlx_audio.server"
VOICE_OUTPUT="${TMPDIR%/}/baihua-local-voice-test.wav"
VOICE_MODEL="mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
VOICE_PID=""

if [[ ! -x "${VOICE_SERVER}" ]]; then
  print -u2 "本地语音尚未安装。请先运行 scripts/setup-local-voice.sh。"
  exit 1
fi

cleanup() {
  if [[ -n "${VOICE_PID}" ]]; then
    kill "${VOICE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if ! curl --silent --fail --max-time 2 http://127.0.0.1:8000/openapi.json >/dev/null; then
  "${VOICE_SERVER}" --host 127.0.0.1 --port 8000 >/dev/null 2>&1 &
  VOICE_PID="$!"

  for _ in {1..60}; do
    if curl --silent --fail --max-time 2 http://127.0.0.1:8000/openapi.json >/dev/null; then
      break
    fi
    sleep 0.25
  done
fi

print "正在生成本地测试语音…"
curl --silent --show-error --fail --max-time 300 \
  -X POST http://127.0.0.1:8000/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${VOICE_MODEL}\",\"input\":\"你好，我是完全运行在这台 Mac 上的花花老师。\",\"voice\":\"Serena\",\"speed\":1.0,\"pitch\":1.0,\"lang_code\":\"Chinese\",\"response_format\":\"wav\",\"stream\":false}" \
  --output "${VOICE_OUTPUT}"

print "测试成功：${VOICE_OUTPUT}"
afplay "${VOICE_OUTPUT}"
