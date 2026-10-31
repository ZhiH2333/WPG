#!/usr/bin/env python3
"""RC 发布共用常量与命名（正式 Release 不引用本模块）。"""

from __future__ import annotations

import re

# 允许的基准提交（WebRTC Roomcode 之前、CI/Dev CD 已知成功）。
BASELINE_SHA = "f43b21a6b514144c7f0db4c7280d11529a04a26e"
RC_VERSION_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-rc\.([1-9]\d*)$"
)
ALLOWED_BRANCH_PREFIXES = ("rc/", "release/rc-", "dev-rc/")
ALLOWED_BRANCH_EXACT = frozenset({"rc/0.3.0"})


def rc_package_name(version: str, platform_key: str) -> str:
    if platform_key == "android":
        return "WPG-%s-android.apk" % version
    return "WPG-%s-%s.zip" % (version, platform_key)


def is_allowed_branch_name(name: str) -> bool:
    if name in ALLOWED_BRANCH_EXACT:
        return True
    for prefix in ALLOWED_BRANCH_PREFIXES:
        if name.startswith(prefix):
            return True
    return False
