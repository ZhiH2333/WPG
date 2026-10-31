#!/usr/bin/env python3
"""RC Pre-release 守门。独立于正式 Release Guard，不放宽 vX.Y.Z / main HEAD 约束。"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from wpg_common import PLATFORMS, PRESETS, TAG_RE, emit, git_output  # noqa: E402
from wpg_common import preset_exists  # noqa: E402
from rc_common import (  # noqa: E402
    BASELINE_SHA,
    RC_VERSION_RE,
    is_allowed_branch_name,
)


def fail(message: str) -> int:
    emit("FAIL", message)
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="WPG RC Pre-release Guard")
    parser.add_argument("--sha", required=True, help="目标完整 commit SHA")
    parser.add_argument("--version", required=True, help="RC 版本，例如 0.3.0-rc.1")
    parser.add_argument(
        "--skip-ci",
        action="store_true",
        help="跳过本地 CI 复跑（仅用于已在 workflow 里跑过 CI 的后续步骤）",
    )
    return parser.parse_args()


def _normalize_sha(raw: str) -> str:
    return raw.strip().lower()


def _is_full_sha(sha: str) -> bool:
    return bool(re.fullmatch(r"[0-9a-f]{40}", sha))


def _rev_parse(ref: str) -> str:
    code, value = git_output(["rev-parse", "--verify", "%s^{commit}" % ref])
    if code != 0 or not value.strip():
        return ""
    return value.strip().lower()


def _is_ancestor(ancestor: str, descendant: str) -> bool:
    code, _ = git_output(["merge-base", "--is-ancestor", ancestor, descendant])
    return code == 0


def _collect_candidate_refs() -> list[str]:
    candidates: list[str] = []
    code, head_branch = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
    if code == 0:
        name = head_branch.strip()
        if name and name != "HEAD":
            candidates.append(name)
    for name in ("rc/0.3.0", "origin/rc/0.3.0"):
        if name not in candidates:
            candidates.append(name)
    code, refs = git_output(
        ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"]
    )
    if code == 0:
        for ref in refs.splitlines():
            short = ref.strip()
            if not short:
                continue
            check_name = short[len("origin/") :] if short.startswith("origin/") else short
            if is_allowed_branch_name(check_name) and short not in candidates:
                candidates.append(short)
    return candidates


def _sha_on_allowed_lineage(sha: str) -> tuple[bool, str]:
    baseline = _rev_parse(BASELINE_SHA)
    if not baseline:
        return False, "本地缺少基准提交 %s" % BASELINE_SHA
    if sha == baseline:
        return True, "target == baseline %s" % BASELINE_SHA[:12]
    # 目标必须是基准的后代（含基准本身已在上面处理）。拒绝基准之前的旧 main 等提交。
    if not _is_ancestor(baseline, sha):
        return False, "目标 SHA 不是基准 %s 的后代" % BASELINE_SHA[:12]

    for ref in _collect_candidate_refs():
        tip = _rev_parse(ref)
        if not tip:
            continue
        check_name = ref[len("origin/") :] if ref.startswith("origin/") else ref
        if not is_allowed_branch_name(check_name):
            continue
        # 允许分支 tip 必须包含基准；目标 SHA 必须落在该 tip 的历史上。
        if not _is_ancestor(baseline, tip):
            continue
        if _is_ancestor(sha, tip):
            return True, "sha on allowed ref %s (descendant of baseline)" % ref
    return False, (
        "目标 SHA 不在允许的 RC 血统上（需为基准 %s 或 rc/* 分支上、且为基准后代的提交）"
        % BASELINE_SHA[:12]
    )


def main() -> int:
    args = parse_args()
    sha = _normalize_sha(args.sha)
    version = args.version.strip()
    if not sha:
        return fail("必须提供目标 commit SHA（不得默认 main HEAD）")
    if not _is_full_sha(sha):
        return fail("SHA 必须是 40 位完整十六进制：%s" % args.sha)
    if version.startswith("v") and TAG_RE.match(version) is not None:
        return fail("禁止使用正式 tag 格式 vX.Y.Z：%s" % version)
    if RC_VERSION_RE.match(version) is None:
        return fail("RC 版本格式必须是 X.Y.Z-rc.N，收到：%s" % version)
    emit("PASS", "RC version %s" % version)

    resolved = _rev_parse(sha)
    if not resolved:
        return fail("目标 SHA 在仓库中不存在：%s" % sha)
    if resolved != sha:
        return fail("rev-parse 结果与输入 SHA 不一致")
    emit("PASS", "target SHA exists: %s" % sha[:12])

    ok, reason = _sha_on_allowed_lineage(sha)
    if not ok:
        return fail(reason)
    emit("PASS", reason)

    for key in PLATFORMS:
        if not preset_exists(key):
            return fail("export preset 缺失：%s" % PRESETS[key])
    emit("PASS", "export presets（%s）" % ", ".join(PLATFORMS))

    if not args.skip_ci:
        ci = subprocess.run(
            [sys.executable, str(HERE.parent / "ci" / "run_ci.py")]
        )
        if ci.returncode != 0:
            return fail("WPG CI checks 未通过")
        emit("PASS", "RC Guard CI")
    else:
        emit("INFO", "skip-ci：假定 workflow 已跑过 CI")

    github_output = os.environ.get("GITHUB_OUTPUT", "")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as handle:
            handle.write("sha=%s\n" % sha)
            handle.write("short_sha=%s\n" % sha[:7])
            handle.write("version=%s\n" % version)
            handle.write("tag=%s\n" % version)
            handle.write("baseline=%s\n" % BASELINE_SHA)

    emit("PASS", "RC Guard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
