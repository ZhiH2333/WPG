#!/usr/bin/env bash
# Phase 2C — 一键启动本地真实 Online 测试环境（WildBoat + Dedicated Server）。
# 面向不熟悉终端的使用者：双击同目录的「一键启动本地Online测试.command」即可。
# 本脚本不把 S2S credential 写进客户端；只用于本机 DS 进程环境变量。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WILDBOAT_DIR="${WPG_WILDBOAT_DIR:-$ROOT/../WildBoat}"
LOG_DIR="$ROOT/build/logs/online-test"
DS_LOG="$LOG_DIR/dedicated_server.log"
DS_PID_FILE="$LOG_DIR/dedicated_server.pid"
READY_FILE="$LOG_DIR/wpg_ds_ready"
PORT="${WPG_GAME_PORT:-24567}"
BASE_URL="${WPG_WILDBOAT_BASE_URL:-http://127.0.0.1:8080}"

mkdir -p "$LOG_DIR"
rm -f "$READY_FILE"

echo ""
echo "========================================"
echo "  WPG Online 本地测试环境（Phase 2C）"
echo "========================================"
echo ""

if [[ ! -f "${ROOT}/project.godot" ]]; then
  echo "ERROR: WPG project not found: ${ROOT}/project.godot"
  exit 1
fi

if [[ ! -d "${WILDBOAT_DIR}" ]]; then
  echo "ERROR: WildBoat folder not found: ${WILDBOAT_DIR}"
  echo "Put WildBoat next to wpg, or set WPG_WILDBOAT_DIR."
  exit 1
fi

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  CANDIDATE="$ROOT/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot"
  if [[ -x "$CANDIDATE" ]]; then
    GODOT_BIN="$CANDIDATE"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
if [[ -z "${GODOT_BIN}" || ! -x "${GODOT_BIN}" ]]; then
  echo "ERROR: Godot 4.6.2 not found. Set GODOT_BIN=/path/to/Godot"
  exit 1
fi

DS_CRED="${DEDICATED_SERVER_CREDENTIAL:-}"
if [[ -z "$DS_CRED" && -f "$WILDBOAT_DIR/.env" ]]; then
  DS_CRED="$(grep -E '^DEDICATED_SERVER_CREDENTIAL=' "$WILDBOAT_DIR/.env" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
fi
if [[ -z "$DS_CRED" ]]; then
  DS_CRED="local-ds-credential-32chars-min!!"
fi

echo "1/3 Checking WildBoat at ${BASE_URL} ..."
if ! curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then
  echo "   WildBoat is down. Starting it (Docker Desktop must be open)..."
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed. Install Docker Desktop, then re-run."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running. Open Docker Desktop, wait until ready, then re-run."
    exit 1
  fi
  (cd "${WILDBOAT_DIR}" && make up)
  echo "   Waiting for WildBoat..."
  for _ in $(seq 1 60); do
    if curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  if ! curl -fsS "${BASE_URL}/healthz" >/dev/null 2>&1; then
    echo "ERROR: WildBoat start timed out. Open Docker Desktop and retry."
    exit 1
  fi
fi
echo "   WildBoat OK."

if [[ -f "${DS_PID_FILE}" ]]; then
  OLD_PID="$(cat "${DS_PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${OLD_PID:-}" ]] && kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "2/3 Stopping old Dedicated Server (pid=${OLD_PID})..."
    kill "${OLD_PID}" 2>/dev/null || true
    sleep 1
  fi
  rm -f "${DS_PID_FILE}"
fi

echo "2/3 Starting Dedicated Server (real WildBoat tickets)..."
env \
  WPG_ADMISSION_MODE=wildboat \
  WPG_WILDBOAT_BASE_URL="${BASE_URL}" \
  DEDICATED_SERVER_CREDENTIAL="${DS_CRED}" \
  WPG_ADVERTISE_HOST=127.0.0.1 \
  WPG_GAME_PORT="${PORT}" \
  WPG_MAX_PLAYERS=4 \
  WPG_READY_FILE="${READY_FILE}" \
  "${GODOT_BIN}" --headless --path "${ROOT}" -- --dedicated-server \
  >"${DS_LOG}" 2>&1 &
DS_PID=$!
echo "${DS_PID}" >"${DS_PID_FILE}"

echo "   Waiting for Dedicated Server..."
READY=0
for _ in $(seq 1 45); do
  if ! kill -0 "${DS_PID}" 2>/dev/null; then
    echo "ERROR: Dedicated Server exited. Log: ${DS_LOG}"
    tail -n 40 "${DS_LOG}" || true
    exit 1
  fi
  if [[ -f "${READY_FILE}" ]] || grep -q "WPG_DS_READY" "${DS_LOG}" 2>/dev/null; then
    READY=1
    break
  fi
  if grep -q "WPG_DS_FAIL" "${DS_LOG}" 2>/dev/null; then
    echo "ERROR: Dedicated Server register failed (WildBoat down or bad credential)."
    tail -n 40 "${DS_LOG}" || true
    exit 1
  fi
  sleep 1
done
if [[ "${READY}" -ne 1 ]]; then
  echo "ERROR: Dedicated Server start timed out. Log: ${DS_LOG}"
  tail -n 40 "${DS_LOG}" || true
  exit 1
fi
echo "   Dedicated Server ready (port=${PORT})."

echo "3/3 Local Online test environment is ready."
echo ""
echo "----------------------------------------"
echo "Next steps (no terminal knowledge needed):"
echo "  A. Double-click: 打开两个游戏窗口.command"
echo "  B. In each window:"
echo "       MULTIPLAYER -> Online (test) ->"
echo "       Register/Login different accounts -> Join Match"
echo "  C. Both should show Connected and players 2/4."
echo "  D. Leave Match returns to Online lobby safely."
echo ""
echo "Guide: docs/phase-2c-player-online-test.md"
echo "Stop:  停止本地Online测试.command"
echo "Log:   ${DS_LOG}"
echo "----------------------------------------"
echo ""
