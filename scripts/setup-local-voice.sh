#!/bin/zsh

set -euo pipefail

VOICE_ACCOUNT_NAME="$(id -un)"
VOICE_USER_DIR="$(dscl . -read "/Users/${VOICE_ACCOUNT_NAME}" NFSHomeDirectory | sed 's/^NFSHomeDirectory: //')"
VOICE_ROOT="${AITUTOR_LOCAL_VOICE_ROOT:-${VOICE_USER_DIR}/Library/Application Support/BaihuaAI/LocalVoice}"
VOICE_VENV="${VOICE_ROOT}/.venv"
VOICE_PYTHON="${VOICE_VENV}/bin/python"
VOICE_MODEL="mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
VOICE_UV="$(command -v uv || true)"

if [[ -z "${VOICE_UV}" ]]; then
  print -u2 "没有找到 uv。请先从 https://docs.astral.sh/uv/ 安装 uv。"
  exit 1
fi

mkdir -p "${VOICE_ROOT}"

print "正在创建本地语音运行环境：${VOICE_ROOT}"
"${VOICE_UV}" venv --python 3.12 "${VOICE_VENV}"

print "正在安装 MLX-Audio 与本地 API 服务…"
"${VOICE_UV}" pip install \
  --python "${VOICE_PYTHON}" \
  --prerelease=allow \
  --upgrade \
  "mlx-audio[server,tts]"

print "正在下载 Qwen3-TTS 0.6B 8-bit 模型（约 1.65GB）…"
"${VOICE_PYTHON}" -c \
  'import sys; from huggingface_hub import snapshot_download; snapshot_download(repo_id=sys.argv[1])' \
  "${VOICE_MODEL}"

print "本地语音安装完成。重新打开白话 AI 后，应用会自动启动本地服务。"
print "也可以运行 scripts/verify-local-voice.sh 做独立合成检查。"
