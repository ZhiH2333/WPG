#!/usr/bin/env python3
"""手动把一个 Web 导出目录发布到 Netlify（默认 https://bwpg.netlify.app）。

**正常流程不走这里。** `dev` 上的每次 commit 由 Netlify 自己的 Git 集成构建发布
（见仓库根 `netlify.toml` 和 `tools/deploy/netlify_build.py`）。这个脚本是兜底：
Netlify 的构建坏了、或者你想把自己电脑上刚导出的那一版直接推上去时用。

认证只从环境变量读：

- `NETLIFY_AUTH_TOKEN`  Netlify personal access token
- `NETLIFY_SITE_ID`     Netlify site ID（名字是 `bwpg` 的那个站点）

两个都缺或者只缺一个，直接 BLOCKED，不会上传半个站点。token 不会被打印，
也不会写进仓库。要发布的是「已经导出好的目录」，脚本不会自己调 Godot：

```bash
python3 tools/build/export_platform.py web
NETLIFY_AUTH_TOKEN=... NETLIFY_SITE_ID=... python3 tools/deploy/deploy_netlify.py
```
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import (  # noqa: E402
    LOG_DIR,
    ROOT,
    Outcome,
    emit,
    emit_outcome,
    git_branch,
    git_commit,
    run_cmd,
    web_package_problem,
)

DEFAULT_FOLDER = "build/web/raw"
DEFAULT_URL = "https://bwpg.netlify.app"
DEFAULT_SITE_NAME = "bwpg"
GAME_MARKER = "wpg-game-markers"
DEPLOY_TIMEOUT = 900.0
# 只有 `netlify` 不在 PATH 时才走 npx；CI 里会预装 CLI。
NPX_FALLBACK: List[str] = ["npx", "--yes", "netlify-cli"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="发布 WPG Web 包到 Netlify")
    parser.add_argument(
        "folder",
        nargs="?",
        default=DEFAULT_FOLDER,
        help="要上传的导出目录，默认 %s" % DEFAULT_FOLDER,
    )
    parser.add_argument(
        "--site",
        default=os.environ.get("NETLIFY_SITE_NAME", DEFAULT_SITE_NAME),
        help="只用于打印的站点名，默认 %s" % DEFAULT_SITE_NAME,
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("NETLIFY_SITE_URL", DEFAULT_URL),
        help="只用于部署后核对的正式地址，默认 %s" % DEFAULT_URL,
    )
    parser.add_argument("--message", default="", help="Netlify 部署列表里显示的备注")
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="跳过部署后的 HTTP 核对",
    )
    parser.add_argument("--retries", type=int, default=6, help="核对重试次数，默认 6")
    parser.add_argument("--delay", type=float, default=10.0, help="核对重试间隔秒数，默认 10")
    return parser.parse_args()


def resolve_folder(raw: str) -> Path:
    path = Path(raw)
    if not path.is_absolute():
        path = ROOT / path
    return path.resolve()


def find_cli() -> Optional[List[str]]:
    explicit = os.environ.get("NETLIFY_CLI", "").strip()
    if explicit:
        return explicit.split()
    found = shutil.which("netlify")
    if found:
        return [found]
    if shutil.which("npx"):
        return list(NPX_FALLBACK)
    return None


def folder_stats(folder: Path) -> tuple:
    files = [path for path in folder.rglob("*") if path.is_file()]
    total = sum(path.stat().st_size for path in files)
    biggest = max(files, key=lambda path: path.stat().st_size, default=None)
    return len(files), total, biggest


def report_size(count: int, total: int, biggest: Optional[Path]) -> None:
    emit("INFO", "文件数 %d，总计 %.1f MB" % (count, total / 1048576.0))
    if biggest is None:
        return
    size = biggest.stat().st_size
    label = "最大单文件 %s %.1f MB" % (biggest.name, size / 1048576.0)
    # Netlify 对单个文件的建议值是 10 MB 以内；Godot 的 pck / wasm 通常更大，
    # 分块上传一般能过。只有大到几乎一定被拒时才出声，免得每次部署都刷 WARN。
    if size > 100 * 1048576:
        emit("WARN", "%s，Netlify 可能拒绝这个文件" % label)
    else:
        emit("INFO", label)


def display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def deploy(cli: List[str], folder: Path, message: str) -> Outcome:
    # cwd 切到导出目录，避免仓库根的 netlify.toml 影响这次发布。
    # token / site id 靠 NETLIFY_AUTH_TOKEN / NETLIFY_SITE_ID 传入，不出现在命令行里。
    args = [*cli, "deploy", "--prod", "--dir", ".", "--message", message]
    log_path = LOG_DIR / "deploy-netlify.log"
    proc = run_cmd(args, cwd=folder, log_path=log_path, timeout=DEPLOY_TIMEOUT)
    output = proc.stdout or ""
    if proc.returncode != 0:
        tail = "\n".join(output.splitlines()[-40:])
        if tail:
            print(tail)
        return Outcome(
            "FAIL",
            "netlify deploy 失败（exit %s），日志：%s" % (proc.returncode, log_path.relative_to(ROOT)),
        )
    return Outcome("PASS", "netlify deploy --prod 成功，日志：%s" % log_path.relative_to(ROOT))


def fetch_once(url: str) -> tuple:
    request = urllib.request.Request(url, headers={"User-Agent": "wpg-deploy-netlify"})
    with urllib.request.urlopen(request, timeout=20) as response:
        status = getattr(response, "status", 0)
        body = response.read(200_000).decode("utf-8", "replace")
    return status, body


def verify_site(url: str, retries: int, delay: float, commit: str) -> Outcome:
    """确认线上真的是这一版 WPG Web 构建。

    只做核对，不决定部署成败：CDN 生效可能比 deploy 命令慢。查不到就 WARN，
    让人自己去浏览器确认，而不是把一次成功的上传改判成失败。
    """
    # 加 cache buster，否则 CDN 可能把旧 index.html 直接回给我们。
    target = "%s/?wpg_verify=%s" % (url.rstrip("/"), commit)
    last = "没有任何一次请求成功"
    for attempt in range(1, max(1, retries) + 1):
        try:
            status, body = fetch_once(target)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as error:
            last = str(error)
        else:
            if status == 200 and GAME_MARKER in body:
                return Outcome("PASS", "%s 已经返回本次构建（第 %d 次请求）" % (url, attempt))
            if status == 200:
                last = "HTTP 200，但页面没有 %s 标记（可能是旧构建或 CDN 缓存）" % GAME_MARKER
            else:
                last = "HTTP %s" % status
        if attempt < retries:
            time.sleep(delay)
    return Outcome("WARN", "部署已完成，但线上核对没通过：%s。请自己打开 %s 确认" % (last, url))


def main() -> int:
    args = parse_args()
    folder = resolve_folder(args.folder)
    if not folder.is_dir():
        emit_outcome(
            Outcome(
                "FAIL",
                "找不到 Web 导出目录：%s（先跑 python3 tools/build/export_platform.py web）" % folder,
            )
        )
        return 1
    problem = web_package_problem(folder)
    if problem is not None:
        emit_outcome(Outcome("FAIL", problem))
        return 1

    missing = [
        name
        for name in ("NETLIFY_AUTH_TOKEN", "NETLIFY_SITE_ID")
        if not os.environ.get(name, "").strip()
    ]
    if missing:
        emit_outcome(
            Outcome(
                "BLOCKED",
                "缺少环境变量 %s。本地自己 export；要在 CI 里跑就配 Repository secrets。"
                % "、".join(missing),
            )
        )
        return 2

    cli = find_cli()
    if cli is None:
        emit_outcome(Outcome("BLOCKED", "找不到 netlify CLI，也找不到 npx。请先装 Node.js 20+"))
        return 2

    count, total, biggest = folder_stats(folder)
    commit = git_commit()
    message = args.message.strip() or "WPG %s %s" % (git_branch(), commit)
    emit("INFO", "站点：%s（%s）" % (args.site, args.url))
    emit("INFO", "上传目录：%s" % display(folder))
    report_size(count, total, biggest)

    result = deploy(cli, folder, message)
    emit_outcome(result)
    if result.status != "PASS":
        return result.exit_code

    if args.no_verify:
        emit("INFO", "已跳过线上核对")
        return 0

    check = verify_site(args.url, args.retries, args.delay, commit)
    emit_outcome(check)
    print(args.url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
