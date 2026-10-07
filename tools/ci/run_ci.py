#!/usr/bin/env python3
"""按顺序跑 validate、architecture、smoke、dev 命名单元测试。任一失败立即非 0 退出。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
STEPS = (
    ("validate.py", TOOLS / "validate.py"),
    ("architecture.py", TOOLS / "architecture.py"),
    ("smoke.py", TOOLS / "smoke.py"),
    ("test_dev_naming.py", TOOLS.parent / "test" / "test_dev_naming.py"),
)


def main() -> int:
    python = sys.executable
    for name, script in STEPS:
        print("", flush=True)
        print("== %s ==" % name, flush=True)
        proc = subprocess.run([python, str(script)])
        if proc.returncode != 0:
            print("[FAIL] %s exit %s" % (name, proc.returncode))
            return proc.returncode
    print("", flush=True)
    print("[PASS] WPG CI", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
