#!/usr/bin/env python3
"""Solo 冒烟 E2E：离线建房 -> 真换场进 CombatSandbox -> role OFFLINE / 无 peer -> 回主菜单。

用法：python3 tools/e2e/solo/run.py
通过输出 SOLO_E2E_OK；失败输出 SOLO_E2E_FAIL 并返回非 0。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from wpg_common import LOG_DIR, ROOT, emit, find_godot, godot_log_args  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
SCRIPT = str(E2E_DIR / "solo.gd")
TIMEOUT_SEC = 90.0


def main() -> int:
    godot = find_godot()
    if godot is None:
        emit("FAIL", "找不到 Godot 可执行文件")
        print("SOLO_E2E_FAIL")
        return 1

    out = LOG_DIR / "e2e" / "solo"
    out.mkdir(parents=True, exist_ok=True)
    result = out / "solo.result"
    result.unlink(missing_ok=True)

    cmd = [
        str(godot),
        "--headless",
        "--path",
        str(ROOT),
        *godot_log_args(out / "solo.log"),
        "--script",
        SCRIPT,
        "--",
        str(result),
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT_SEC)
    except subprocess.TimeoutExpired:
        emit("FAIL", "Solo 进程超时")
        print("SOLO_E2E_FAIL")
        return 1

    text = result.read_text().strip() if result.is_file() else ""
    if not text.startswith("OK"):
        detail = text or (proc.stdout or "").strip()[-400:] or (proc.stderr or "").strip()[-400:]
        emit("FAIL", "Solo: %s" % (detail or "无结果"))
        print("SOLO_E2E_FAIL")
        return 1

    emit("PASS", "离线 Solo -> CombatSandbox(role OFFLINE / 无 peer) -> 退回主菜单无残留")
    print("SOLO_E2E_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
