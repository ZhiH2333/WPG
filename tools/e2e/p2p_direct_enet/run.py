#!/usr/bin/env python3
"""P2P Direct ENet E2E（Phase 9.2.3）——注册到 tools/test/run_e2e.py 的入口。

**这里不再自己实现一套 runner**：真多进程 E2E 的唯一实现是
`tools/p2p/e2e_direct_enet_test.py`（real rendezvous + real UDP hole punch +
real ENet + real protocol 6 + 逐条状态断言）。

本文件只是薄封装：保证 `python3 tools/test/run_e2e.py p2p_direct_enet` 跑的
就是那套真实 E2E，不会出现「两条 runner 语义分叉、其中一条偷偷放宽判定」。

    tools/e2e/p2p_direct_enet/{host,guest}.gd   ← 由 canonical runner 直接调用
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CANONICAL = ROOT / "tools" / "p2p" / "e2e_direct_enet_test.py"


def main() -> int:
    if not CANONICAL.is_file():
        print("P2P_DIRECT_ENET_E2E_FAIL: 缺少 %s" % CANONICAL, flush=True)
        return 1
    proc = subprocess.run([sys.executable, str(CANONICAL), "--test-case", "all", "--runs", "1"])
    if proc.returncode != 0:
        print("P2P_DIRECT_ENET_E2E_FAIL", flush=True)
        return 1
    print("P2P_DIRECT_ENET_E2E_OK", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
