#!/usr/bin/env python3
"""按顺序跑 validate、architecture、smoke。任一失败立即非 0 退出。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
STEPS = ("validate.py", "architecture.py", "smoke.py")


def main() -> int:
    python = sys.executable
    for name in STEPS:
        print("", flush=True)
        print("== %s ==" % name, flush=True)
        proc = subprocess.run([python, str(TOOLS / name)])
        if proc.returncode != 0:
            print("[FAIL] %s exit %s" % (name, proc.returncode))
            return proc.returncode
    print("", flush=True)
    print("[PASS] WPG CI", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
