#!/usr/bin/env python3
"""生成测试版提示页用的中文字体子集。

为什么要自带字体：Godot 的 Web 导出渲染不了系统字体里的中文，系统字体回退在网页上
不生效（godotengine/godot#78921），仓库里又一个字体文件都没有。不处理的话，
`ui/test_build_notice.tscn` 上的中文在网页版里就是空白。

为什么是子集：完整 Noto Sans SC 有 17 MB，Web 包现在才 74 MB，为了一个提示页塞
17 MB 不划算。这里只保留提示页真正用到的那几十个字，产物不到 100 KB。

字形集合直接从 `ui/test_build_notice.tscn` / `ui/test_build_notice.gd` 的字符串里
扫出来，所以：**改文案之后要重跑本脚本**，否则新字在网页上是空白。

    python3 -m pip install fonttools
    python3 tools/fonts/subset_notice_font.py

产物（提交进仓库，构建时不再联网）：

    ui/fonts/wpg_notice_cjk_regular.ttf
    ui/fonts/wpg_notice_cjk_bold.ttf
    ui/fonts/OFL.txt
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
import urllib.request
from pathlib import Path
from typing import List, Set

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wpg_common import ROOT, Outcome, emit, emit_outcome  # noqa: E402

SOURCE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
SOURCE_SHA256 = "a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da"
SOURCE_FILENAME = "NotoSansSC[wght].ttf"
LICENSE_URL = "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt"

FONT_DIR = ROOT / "ui/fonts"
CACHE_DIR = ROOT / "build/fonts"
# 文案来源：只这些文件里的字符串算「界面会显示的字」。
TEXT_SOURCES = (
    "ui/test_build_notice.tscn",
    "ui/test_build_notice.gd",
)
# 子集永远带上整段可打印 ASCII：提示页里混着 WPG / Bug / 邮箱地址，
# 而且以后在同一个 Label 上加个英文词不该再重跑一次。
ASCII_PRINTABLE = "".join(chr(code) for code in range(0x20, 0x7F))
# 两种字重 -> 产物文件名 + 子族名。标题用 bold，正文用 regular。
WEIGHTS = (
    (400, "wght_notice_regular", "Regular", "wpg_notice_cjk_regular.ttf"),
    (700, "wght_notice_bold", "Bold", "wpg_notice_cjk_bold.ttf"),
)
QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"')
# 改过字形就要跟着改的名字。OFL 要求保留版权与许可证信息（name ID 0 / 13 / 14 不动），
# 但这是子集，名字必须让人看出来它不是原版 Noto。
FAMILY_NAME = "WPG Notice CJK"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="生成提示页中文字体子集")
    parser.add_argument(
        "--keep-cache",
        action="store_true",
        help="保留 build/fonts 里下载的完整字体（默认保留，这个开关只是写明语义）",
    )
    return parser.parse_args()


def require_fonttools() -> bool:
    try:
        import fontTools  # noqa: F401
    except ImportError:
        emit_outcome(
            Outcome(
                "BLOCKED",
                "缺少 fontTools。先跑 python3 -m pip install fonttools",
            )
        )
        return False
    return True


def collect_text() -> str:
    """把界面会用到的字符串全部收集起来（含注释里被引号包住的都没关系，多收几个字）。"""
    parts: List[str] = []
    for rel in TEXT_SOURCES:
        path = ROOT / rel
        if not path.is_file():
            raise SystemExit("[FAIL] 缺少文案来源：%s" % rel)
        parts.extend(QUOTED.findall(path.read_text(encoding="utf-8")))
    return "\n".join(parts)


def characters_for_subset() -> str:
    chars: Set[str] = set(ASCII_PRINTABLE)
    for char in collect_text():
        if char in "\n\r\t":
            continue
        chars.add(char)
    # 排序保证同样的文案产出同样的字节，diff 才干净。
    return "".join(sorted(chars))


def source_font() -> Path:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    path = CACHE_DIR / SOURCE_FILENAME
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_SHA256:
        emit("INFO", "下载 %s" % SOURCE_URL)
        urllib.request.urlretrieve(SOURCE_URL, path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != SOURCE_SHA256:
            raise SystemExit("[FAIL] 源字体 sha256 不符：%s" % digest)
        emit("PASS", "源字体 sha256 校验通过")
    else:
        emit("INFO", "复用缓存 %s" % path.relative_to(ROOT))
    return path


def write_license() -> None:
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    target = FONT_DIR / "OFL.txt"
    emit("INFO", "下载 %s" % LICENSE_URL)
    with urllib.request.urlopen(LICENSE_URL, timeout=60) as response:
        target.write_bytes(response.read())
    emit("PASS", "许可证 -> %s" % target.relative_to(ROOT))


def _set_name(font, name_id: int, value: str) -> None:
    """Windows 与 Mac 两套名字都改，否则编辑器里看到的还是原版 Noto 的名字。"""
    table = font["name"]
    for platform_id, plat_enc_id, lang_id in ((3, 1, 0x409), (1, 0, 0)):
        table.setName(value, name_id, platform_id, plat_enc_id, lang_id)


def rename(font, style: str) -> None:
    full: str = "%s %s" % (FAMILY_NAME, style)
    _set_name(font, 1, FAMILY_NAME)
    _set_name(font, 2, style)
    _set_name(font, 4, full)
    _set_name(font, 6, "%s-%s" % (FAMILY_NAME.replace(" ", ""), style))
    _set_name(font, 16, FAMILY_NAME)
    _set_name(font, 17, style)


def build_weight(source: Path, weight: int, style: str, filename: str, text: str) -> Path:
    from fontTools import subset
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    FONT_DIR.mkdir(parents=True, exist_ok=True)
    static = CACHE_DIR / ("static-%d.ttf" % weight)
    font = TTFont(source)
    instancer.instantiateVariableFont(font, {"wght": weight}, inplace=True)
    font.save(static)

    target = FONT_DIR / filename
    options = subset.Options()
    # 只要字形和 cmap：丢 hinting / 布局特性 / 竖排表，控制体积。
    options.layout_features = []
    options.hinting = False
    options.desubroutinize = True
    options.drop_tables += ["DSIG"]
    # 名字表留着：字体名和许可证信息不丢。
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=text)
    loaded = TTFont(static)
    subsetter.subset(loaded)
    rename(loaded, style)
    loaded.save(target)
    # 静态中间产物没必要留，源码缓存 + 产物就够了。
    static.unlink(missing_ok=True)
    return target


def main() -> int:
    parse_args()
    if not require_fonttools():
        return 2
    text = characters_for_subset()
    emit("INFO", "字形集合 %d 个字符" % len(text))
    source = source_font()
    write_license()
    for weight, _key, style, filename in WEIGHTS:
        target = build_weight(source, weight, style, filename, text)
        size_kb = target.stat().st_size / 1024.0
        emit("PASS", "%s（wght %d，%.1f KB）" % (target.relative_to(ROOT), weight, size_kb))
    emit("INFO", "改过提示页文案就要重跑本脚本，否则新字在网页版上是空白")
    emit_outcome(Outcome("PASS", "字体子集已生成，记得跑一次 godot --headless --import"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
