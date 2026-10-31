#!/usr/bin/env bash
# 打开两个游戏客户端窗口（隔离会话：WPG_CLIENT_SLOT=a / b）。
# 请先运行 start_local_online_test.sh。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  CANDIDATE="$ROOT/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot"
  if [[ -x "$CANDIDATE" ]]; then
    GODOT_BIN="$CANDIDATE"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
if [[ -z "${GODOT_BIN}" || ! -x "$GODOT_BIN" ]]; then
  echo "错误：找不到 Godot。请先能正常打开本项目。"
  exit 1
fi

echo "正在打开两个游戏窗口…"
echo "窗口 A / B 使用不同本地会话；请分别登录两个账号，再点 Join Match。"
WPG_CLIENT_SLOT=a "$GODOT_BIN" --path "$ROOT" >/dev/null 2>&1 &
sleep 1
WPG_CLIENT_SLOT=b "$GODOT_BIN" --path "$ROOT" >/dev/null 2>&1 &
echo "已启动。点击路径：MULTIPLAYER → Online (test) → Login → Join Match"
