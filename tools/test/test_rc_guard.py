#!/usr/bin/env python3
"""RC Guard / 命名单元测试（不需要 Godot）。"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "release"))

from rc_common import (  # noqa: E402
    BASELINE_SHA,
    RC_VERSION_RE,
    is_allowed_branch_name,
    rc_package_name,
)


class RcCommonTests(unittest.TestCase):
    def test_rc_version_accepts(self) -> None:
        self.assertIsNotNone(RC_VERSION_RE.match("0.3.0-rc.1"))
        self.assertIsNotNone(RC_VERSION_RE.match("1.0.0-rc.12"))

    def test_rc_version_rejects_formal(self) -> None:
        self.assertIsNone(RC_VERSION_RE.match("0.3.0"))
        self.assertIsNone(RC_VERSION_RE.match("v0.3.0"))
        self.assertIsNone(RC_VERSION_RE.match("0.3.0-rc"))
        self.assertIsNone(RC_VERSION_RE.match("0.3.0-rc.0"))

    def test_branch_names(self) -> None:
        self.assertTrue(is_allowed_branch_name("rc/0.3.0"))
        self.assertTrue(is_allowed_branch_name("rc/hotfix"))
        self.assertTrue(is_allowed_branch_name("dev-rc/0.3.0"))
        self.assertFalse(is_allowed_branch_name("dev"))
        self.assertFalse(is_allowed_branch_name("main"))
        self.assertFalse(is_allowed_branch_name("feature/foo"))

    def test_package_names(self) -> None:
        self.assertEqual(rc_package_name("0.3.0-rc.1", "windows"), "WPG-0.3.0-rc.1-windows.zip")
        self.assertEqual(rc_package_name("0.3.0-rc.1", "android"), "WPG-0.3.0-rc.1-android.apk")

    def test_baseline_constant(self) -> None:
        self.assertEqual(len(BASELINE_SHA), 40)
        self.assertEqual(BASELINE_SHA, "f43b21a6b514144c7f0db4c7280d11529a04a26e")


if __name__ == "__main__":
    unittest.main()
