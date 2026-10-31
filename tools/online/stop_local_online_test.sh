#!/usr/bin/env bash
# 停止 Phase 2C 本地 Dedicated Server（不关闭 WildBoat / Docker）。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT/build/logs/online-test"
DS_PID_FILE="$LOG_DIR/dedicated_server.pid"
READY_FILE="$LOG_DIR/wpg_ds_ready"

if [[ -f "$DS_PID_FILE" ]]; then
  PID="$(cat "$DS_PID_FILE" 2>/dev/null || true)"
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "停止 Dedicated Server (pid=$PID)…"
    kill "$PID" 2>/dev/null || true
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
    fi
    echo "已停止。"
  else
    echo "Dedicated Server 未在运行。"
  fi
  rm -f "$DS_PID_FILE"
else
  echo "没有找到运行中的 Dedicated Server 记录。"
fi
rm -f "$READY_FILE"
