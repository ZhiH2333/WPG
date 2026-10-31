#!/usr/bin/env bash
# 导出 Linux Dedicated Server 二进制到 build/dedicated_server/。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if [[ -z "${GODOT_BIN:-}" ]]; then
  if [[ -x "$ROOT/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot" ]]; then
    GODOT_BIN="$ROOT/build/netlify-godot/wpg-godot/editor/Godot.app/Contents/MacOS/Godot"
  elif command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  else
    echo "FAIL: 找不到 Godot。请设置 GODOT_BIN。" >&2
    exit 1
  fi
fi

OUT_DIR="$ROOT/build/dedicated_server"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/wpg_server.x86_64"

echo "INFO: exporting Linux Dedicated Server -> $OUT"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "Linux Dedicated Server" "$OUT"
test -f "$OUT"
chmod +x "$OUT"
echo "PASS: $OUT"
