#!/usr/bin/env python3
"""全项目 i18n 审计：玩家可见文本是否全部接入翻译，翻译表是否完整。

    python3 tools/i18n/audit.py            # 打印摘要，写 build/i18n/coverage.{json,md}
    python3 tools/i18n/audit.py --strict   # 有任何未接入 / 缺译 / 未解释白名单就返回非 0

检查范围（见 SCAN_*）：
  * 所有 .tscn：text / placeholder_text / tooltip_text / header_text / caption / button_text。
  * 所有 .tres：display_name / title / description 等字符串属性。
  * 所有 .gd（游戏代码，不含 tests/ tools/ addons/ prototypes/）：
      - 文本出口（.text = / placeholder_text / tooltip_text / add_item / set_item_text / set_label_text …）
        里的字面量必须经 tr() / WpgI18n.t() / TranslationServer.translate()，或是翻译 key，或在白名单里；
      - UI 层文件里其余带语言内容的字面量按启发式再扫一遍（Tier 2），同样要么接入、要么白名单。
  * project.godot：application/config/name 等字符串。
  * locale/wpg.csv：key 唯一 / 非空 / 各语言占位符一致 / 疑似未翻译 / 命名规范 / 未被引用的 key。

白名单（WHITELIST_*）每一项都必须写明原因；没有原因的条目会让审计失败。
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = ROOT / "locale" / "wpg.csv"
OUT_DIR = ROOT / "build" / "i18n"

# 不属于「随游戏发给玩家」的目录：测试、构建工具、编辑器插件、构建产物、Godot 缓存。
# prototypes/ 是独立的 WebRTC 原型，主场景与任何游戏场景都不引用它（见 check_prototypes_unreferenced）。
SCAN_EXCLUDE_PREFIXES = (
    "tests/", "tools/", "addons/", "prototypes/", "build/", "artifacts/", "android/", ".godot/", "docs/",
)
# 其中 prototypes/ 必须真的无人引用，否则不能排除。
PROTOTYPE_PREFIX = "prototypes/"

TSCN_TEXT_PROPS = ("text", "placeholder_text", "tooltip_text", "header_text", "caption", "button_text")
TRES_TEXT_PROPS = ("display_name", "title", "description", "text", "label", "caption", "hint")

# 文本出口：这些调用 / 赋值里的字面量会直接出现在界面上。
SINK_PATTERNS = (
    re.compile(r"\.(text|placeholder_text|tooltip_text|title|dialog_text)\s*="),
    re.compile(r"\b(set_text|add_item|set_item_text|set_label_text|present_toast|present_modal|add_separator)\s*\("),
    re.compile(r"^\s*(const|var)\s+\w*(TEXT|TITLE|CAPTION|SUBTITLE|HINT)\w*\s*(:[^=]*)?=", re.I),
)
# 翻译调用。
TR_CALL = re.compile(r"(?<![\w.])(?:tr|atr)\(\s*\"((?:[^\"\\]|\\.)*)\"|WpgI18n\.t\(\s*\"((?:[^\"\\]|\\.)*)\"|TranslationServer\.translate\(\s*\"((?:[^\"\\]|\\.)*)\"")
# tr("PREFIX_%s" % x) 这类动态 key。
TR_DYNAMIC = re.compile(r"(?<![\w.])(?:tr|atr)\(\s*\"([A-Z][A-Z0-9_]*)%s\"\s*%")

FORMAT_SPEC = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdfxXcio]")
KEY_RE = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$")
CJK_RE = re.compile(r"[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]")

# Tier 2：这些文件里出现的带语言内容字面量也要核对（玩家界面层）。
TIER2_PREFIXES = ("ui/", "debug/", "data/shop_card.gd", "data/save_ui_projection.gd", "lobby/room.gd")

# ---------------------------------------------------------------------------
# 白名单。(文件前缀或精确路径, 字面量或 None=整类, 原因)。原因不能为空。
# ---------------------------------------------------------------------------
WHITELIST_LITERALS: List[Tuple[str, Optional[str], str]] = [
    # --- 专有名词 / 人名 / 链接 ---
    ("ui/credits_overlay.tscn", "FM Studio", "工作室品牌名，不翻译"),
    ("ui/credits_overlay.tscn", "@ZhiH2333", "作者账号名"),
    ("ui/credits_overlay.tscn", "github.com/ZhiH2333", "仓库链接"),
    ("ui/credits_overlay.tscn", "Godot 4.6", "引擎名称与版本号"),
    ("ui/credits_overlay.tscn", "@", "制作名单里的账号 / 昵称列表（人名，不翻译）"),
    # --- 技术标识 / 协议名 ---
    # 说明：单个字母 / 符号（A B X Y Q E × → 2x 4x 8x）、URL、纯格式串不含「语言内容」，扫描器本身不会把它们当文案。
    # lobby_manager.gd 里的 "HOST" / "Player %02d" 是玩家昵称默认值（用户数据），不在文本出口与 UI 层扫描范围内。
    ("ui/lan_overlay.tscn", "IPv4", "协议名，输入框占位符"),
    ("ui/mobile/touch_controls.tscn", "A0", "触屏技能按钮编号，脚本运行时覆盖为 A%d + 状态"),
    ("ui/mobile/touch_controls.tscn", "A1", "触屏技能按钮编号，脚本运行时覆盖为 A%d + 状态"),
    ("ui/mobile/touch_action_button.gd", "ACTION", "@export 默认值；touch_controls.tscn 的 9 个实例全部显式设置 button_text，不会显示"),
    ("ui/settings_overlay.gd", "touch manual fire button aim stick", "设置搜索关键字（set_meta 索引，不显示；匹配时另会比对翻译后的可见文本）"),
    # --- 玩家数据 / 持久化默认值（不是界面文案）---
    ("ui/player_profile.gd", "Player", "玩家昵称默认值：持久化、经网络同步的用户数据（界面占位走 PROFILE_NAME_DEFAULT）"),
    ("ui/main_menu.gd", "Player", "未被引用的遗留常量 PLACEHOLDER_NAME（无引用，仅登记）"),
    # --- 模板 / 编辑器占位 ---
    ("ui/settings_section.tscn", "Section", "模板场景占位文字，settings_section.gd:_ready 会用 header_text 覆盖"),
    ("ui/settings_section.gd", "Section", "@export 默认值；settings_overlay.tscn 的 4 个实例全部显式设置 header_text"),
    ("ui/settings_nav_button.gd", "Audio", "@export 默认值；settings_overlay.tscn 的 4 个实例全部显式设置 caption"),
    ("debug/debug_overlay.tscn", "DebugOverlay", "仅 OS.is_debug_build() 且按 F9 才显示的开发者调试层（debug_overlay.gd 第 48 行）"),
    ("debug/debug_overlay.gd", None, "整份调试层文本：_unhandled_input 在非 debug 构建直接 return（OS.is_debug_build() 门禁），发布包玩家看不到"),
    ("ui/wpg_i18n.gd", "CSV_MISSING", "诊断码，仅返回给测试 / 日志，不显示给玩家"),
    ("ui/wpg_i18n.gd", "LOCALE_COLUMN_MISSING", "诊断码，仅返回给测试 / 日志，不显示给玩家"),
]

# 行级忽略规则：这些语境里的字面量是标识符 / 日志 / 路径，不会进入界面。
IGNORE_LINE_RULES: List[Tuple[re.Pattern, str]] = [
    (re.compile(r"\.name\s*="), "节点名称"),
    (re.compile(r"theme_type_variation|add_theme_|get_theme_|has_theme_|theme_override"), "主题类型 / 主题项名称"),
    (re.compile(r"get_node(_or_null)?\(|has_node\(|find_child\(|find_children\(|\$[A-Za-z%\"]"), "节点路径 / 查找名"),
    (re.compile(r"\b(push_warning|push_error|print|printerr|print_debug|assert)\("), "日志 / 断言（不进界面）"),
    (re.compile(r"\b(set_meta|get_meta|has_meta)\("), "元数据键 / 搜索索引关键字（不显示）"),
    (re.compile(r"\b(preload|load|ResourceLoader\.\w+|FileAccess\.\w+|DirAccess\.\w+)\("), "资源 / 文件路径"),
    (re.compile(r"\b(add_to_group|call_group|is_in_group|connect|emit_signal|get_tree\(\)\.call_group)\b"), "分组 / 信号名"),
    (re.compile(r"Input\.|InputMap\.|is_action|get_action"), "输入动作名"),
    (re.compile(r"ProjectSettings|OS\.get_environment|ConfigFile|cfg\.(get|set)_value|\.get\(\"|\.has\("), "配置键 / 字典键"),
    (re.compile(r"^\s*(\"[^\"]*\"|&\"[^\"]*\")\s*:"), "字典键 / match 分支 / 原因码"),
    (re.compile(r"^\s*match\b|^\s*\"[^\"]*\"(,\s*\"[^\"]*\")*\s*:\s*$"), "match 分支（状态码）"),
    (re.compile(r"_log_lan\(|_reject_reason_name|outcome_name|kind_name|KIND_NAMES|checkpoint_kind"), "网络 / 存档状态码与日志"),
    (re.compile(r"settings_search|_build_choice_row\(|\.bus\s*=|bus_index|_apply_bus_volume|AudioServer"), "音频总线 / 设置搜索关键字（不显示）"),
    (re.compile(r"JoinInvite|parts\.append|begins_with\(|\.split\(|\.join\(|regex|RegEx"), "协议 / URI 拼装与解析"),
    (re.compile(r"\bnetwork_failed\.emit|notify_ticket_rejected|\"start_block_reason\""), "稳定的原因码（UI 层统一翻译，见 lan_overlay._reason_text / _start_button_text）"),
    (re.compile(r"return\s+\"(no room|no peer|pending|started|need %d|no host|not ready|connecting|full|guest|invalid|reserved)\""), "状态码返回值（UI 层翻译）"),
]
# 整行忽略的更精确规则放在 WHITELIST_LINES: (文件, 正则, 原因)
WHITELIST_LINES: List[Tuple[str, str, str]] = [
    ("ui/lan_overlay.gd", r'"need 2":|"not ready":|"connecting", "no peer":|"pending":|"started":', "start_block_reason 状态码分支，显示文案在分支体内走 tr()"),
    ("ui/lan_overlay.gd", r'"bind failed":|"refused":|"Version mismatch", "version_mismatch":|"ticket rejected", "ticket_rejected":|"host closed":|"no room":|"connect_timeout":|"connection_failed":|"socket_error":', "network_failed 原因码分支，显示文案在分支体内走 tr()"),
    ("ui/lan_overlay.gd", r'JoinInvite\.SCHEME|"%s://"', "邀请 URI 协议头解析"),
    ("ui/lan_overlay.gd", r'"%d/%d"|"%s  ·  %s"|"%s  ·  %s  ·  %s"|"%d/%d  ·  %s  ·  %s"', "纯格式串（数字 / 已翻译片段拼接）"),
    ("ui/lan_overlay.gd", r'"\\n"\.join|split\("\\n"', "换行拼接"),
    ("ui/record_card.gd", r'status != "NEW"|%s  ·  ', "状态码比较 / 已翻译片段拼接"),
    ("ui/game_record.gd", r'"NEW"|"IN_PROGRESS"', "存档状态枚举名（持久化格式）"),
    ("ui/save_ui_projection.gd", r'STATUS_(NEW|IN_PROGRESS|CLEARED|FAILED)\s*:=|STATUS_\w+ := "', "存档状态枚举名（持久化格式）"),
    ("ui/save_ui_projection.gd", r'"%s  ·  %s"|"%d / %d"|"%d  ·  XP|"%s %s"|"—"|"%d"', "纯格式串 / 破折号"),
    ("ui/hud.gd", r'"%s %s"|"%s %s  %s"|"%d/%d"|"   "\.join|"%\.1f"|ProgressBarLow', "纯格式串 / 主题样式名"),
    ("ui/main_menu.gd", r'"%02d:%02d', "时钟格式串"),
    ("ui/pause_overlay.gd", r'"%02d:%02d', "时钟格式串"),
    ("ui/winner_page.gd", r'"#%d"', "名次序号格式串"),
    ("ui/shop_offer.gd", r'"%d/%d"|"%d" % cost', "纯数字格式串"),
    ("ui/profile_overlay.gd", r'"%d" %', "纯数字格式串"),
    ("ui/save_row.gd", r'"%02d" % index', "纯数字格式串"),
    ("ui/settings_overlay.gd", r'"\.\.\."', "按键监听占位省略号"),
    ("ui/settings_overlay.gd", r'"%s is|"IN USE"', "已翻译（见 SETTINGS_* key），此行为 tr 调用的一部分"),
]

# project.godot 里允许出现的字符串。
WHITELIST_PROJECT: List[Tuple[str, str]] = [
    ('config/name="WPG"', "游戏品牌名"),
]


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def tracked_or_all(suffix: str) -> List[Path]:
    """git 跟踪的 + 未跟踪但未被忽略的文件（不扫 build/ .godot/ 等产物）。"""
    global _FILE_LIST
    if _FILE_LIST is None:
        out = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=ROOT, text=True)
        _FILE_LIST = sorted({line for line in out.splitlines() if line and (ROOT / line).is_file()})
    return [ROOT / f for f in _FILE_LIST if f.endswith(suffix)]


_FILE_LIST: Optional[List[str]] = None


def is_excluded(r: str) -> bool:
    return r.startswith(SCAN_EXCLUDE_PREFIXES)


def has_language(text: str) -> bool:
    """去掉格式占位符和转义后，是否还含有语言内容（字母单词或 CJK）。"""
    stripped = FORMAT_SPEC.sub("", text)
    stripped = stripped.replace("\\n", " ").replace("\\t", " ")
    return bool(re.search(r"[A-Za-z]{2,}", stripped) or CJK_RE.search(stripped))


def placeholders(text: str) -> List[str]:
    return [m.group(0) for m in FORMAT_SPEC.finditer(text.replace("%%", ""))]


# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------
def load_csv() -> Tuple[List[str], Dict[str, List[str]], List[str], List[str]]:
    with CSV_PATH.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))
    header = rows[0]
    locales = [h.strip() for h in header[1:]]
    table: Dict[str, List[str]] = {}
    order: List[str] = []
    dupes: List[str] = []
    for row in rows[1:]:
        if not row or not row[0].strip():
            continue
        key = row[0]
        values = [row[i + 1] if i + 1 < len(row) else "" for i in range(len(locales))]
        if key in table:
            dupes.append(key)
        table[key] = values
        order.append(key)
    return locales, table, order, dupes


# ---------------------------------------------------------------------------
# GDScript 词法：逐行取字符串字面量，跳过注释
# ---------------------------------------------------------------------------
def gd_literals(line: str, in_triple: bool) -> Tuple[List[Tuple[int, str]], bool]:
    """返回 [(列, 字面量内容)]，以及行尾是否仍在三引号字符串里。"""
    lits: List[Tuple[int, str]] = []
    i, n = 0, len(line)
    while i < n:
        if in_triple:
            end = line.find('"""', i)
            if end < 0:
                lits.append((i, line[i:]))
                return lits, True
            lits.append((i, line[i:end]))
            i = end + 3
            in_triple = False
            continue
        ch = line[i]
        if ch == "#":
            break
        if line.startswith('"""', i):
            in_triple = True
            i += 3
            continue
        if ch in "\"'":
            quote = ch
            j = i + 1
            buf = []
            while j < n:
                if line[j] == "\\" and j + 1 < n:
                    buf.append(line[j:j + 2])
                    j += 2
                    continue
                if line[j] == quote:
                    break
                buf.append(line[j])
                j += 1
            lits.append((i, "".join(buf)))
            i = j + 1
            continue
        i += 1
    return lits, in_triple


def is_stringname(line: str, col: int) -> bool:
    return col > 0 and line[col - 1] == "&"


def is_key_or_index(line: str, col: int) -> bool:
    """字典下标 / .get("x") / .has("x") 里的字面量是键名，不是文案。"""
    before = line[:col].rstrip()
    return before.endswith("[") or bool(re.search(r"\.(get|has|erase)\($", before))


def covered_by_tr(line: str, col: int) -> bool:
    """该字面量是否正好是 tr( / WpgI18n.t( / translate( 的第一个参数。"""
    before = line[:col].rstrip()
    return bool(re.search(r"(?<![\w.])(?:tr|atr)\($|WpgI18n\.t\($|TranslationServer\.translate\($", before))


_USED_WHITELIST: set = set()


def whitelisted_literal(r: str, text: str) -> Optional[str]:
    for index, (path, lit, reason) in enumerate(WHITELIST_LITERALS):
        if not (r == path or r.startswith(path)):
            continue
        if lit is None or text == lit or (lit == "@" and text.startswith("@")):
            _USED_WHITELIST.add(index)
            return reason
    return None


def whitelisted_line(r: str, line: str) -> Optional[str]:
    for path, pattern, reason in WHITELIST_LINES:
        if r == path and re.search(pattern, line):
            return reason
    for pattern, reason in IGNORE_LINE_RULES:
        if pattern.search(line):
            return reason
    return None


# ---------------------------------------------------------------------------
# 扫描
# ---------------------------------------------------------------------------
class Item:
    def __init__(self, file: str, line: int, kind: str, text: str, status: str, key: str = "", note: str = ""):
        self.file, self.line, self.kind, self.text = file, line, kind, text
        self.status, self.key, self.note = status, key, note

    def as_dict(self) -> dict:
        return {"file": self.file, "line": self.line, "kind": self.kind, "text": self.text,
                "status": self.status, "key": self.key, "note": self.note}


def scan_tscn_source(r: str, source: str, keys: set, items: List[Item]) -> None:
    pat = re.compile(r'^\s*(' + "|".join(TSCN_TEXT_PROPS) + r') = "((?:[^"\\]|\\.)*)"\s*$')
    for number, line in enumerate(source.splitlines(), 1):
        m = pat.match(line)
        if not m:
            continue
        prop, value = m.groups()
        if not value:
            continue
        if value in keys:
            items.append(Item(r, number, "tscn:" + prop, value, "wired", value))
            continue
        reason = whitelisted_literal(r, value)
        if reason:
            items.append(Item(r, number, "tscn:" + prop, value, "whitelisted", note=reason))
            continue
        if has_language(value):
            items.append(Item(r, number, "tscn:" + prop, value, "untranslated"))


def scan_tscn(keys: set, items: List[Item]) -> int:
    count = 0
    for path in tracked_or_all(".tscn"):
        r = rel(path)
        if is_excluded(r):
            continue
        count += 1
        scan_tscn_source(r, path.read_text(encoding="utf-8"), keys, items)
    return count


def scan_tres(keys: set, items: List[Item]) -> int:
    count = 0
    pat = re.compile(r'^(' + "|".join(TRES_TEXT_PROPS) + r') = "((?:[^"\\]|\\.)*)"\s*$')
    for path in tracked_or_all(".tres"):
        r = rel(path)
        if is_excluded(r):
            continue
        count += 1
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = pat.match(line)
            if not m:
                continue
            prop, value = m.groups()
            if not value:
                continue
            if value in keys:
                items.append(Item(r, number, "tres:" + prop, value, "wired", value))
            elif has_language(value):
                reason = whitelisted_literal(r, value)
                items.append(Item(r, number, "tres:" + prop, value, "whitelisted" if reason else "untranslated", note=reason or ""))
    return count


def scan_gd_source(r: str, text: str, keys: set, items: List[Item], referenced: set,
                   dyn_prefixes: set, tr_sites: List[Tuple[str, int, str]]) -> None:
    in_triple = False
    lines = text.splitlines()
    tier2 = r.startswith(TIER2_PREFIXES)
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        lits, in_triple = gd_literals(line, in_triple)
        # tr / t / translate 调用点
        for m in TR_CALL.finditer(line):
            key = next(g for g in m.groups() if g is not None)
            if "%" in key:
                ## tr("PREFIX_%s" % x)：动态 key，按家族另行校验。
                dyn_prefixes.add(key.split("%")[0])
                tr_sites.append((r, number, ""))
                continue
            tr_sites.append((r, number, key))
            referenced.add(key)
        if stripped.startswith("#") or not lits:
            continue
        for col, lit in lits:
            if lit in keys:
                referenced.add(lit)
        is_sink = any(p.search(line) for p in SINK_PATTERNS)
        if not (is_sink or tier2):
            continue
        for col, lit in lits:
            if is_stringname(line, col) or is_key_or_index(line, col) or not lit:
                continue
            if lit in keys or covered_by_tr(line, col):
                continue
            if lit.startswith(("res://", "user://", "uid://", "http://", "https://")):
                continue
            if not has_language(lit):
                continue
            if re.fullmatch(r"[A-Z][A-Z0-9]*_%s", lit):
                continue
            reason = whitelisted_literal(r, lit)
            kind = "gd:sink" if is_sink else "gd:ui"
            if reason:
                items.append(Item(r, number, kind, lit, "whitelisted", note=reason))
                continue
            reason = whitelisted_line(r, line)
            if reason:
                items.append(Item(r, number, kind, lit, "ignored", note=reason))
                continue
            # Tier 2 只管「像人话」的字面量：含空格 / CJK / 全大写词；单个小写标识符不算。
            if not is_sink:
                looks_like_prose = (" " in lit.strip()) or CJK_RE.search(lit) or re.search(r"[A-Z]{3,}", lit)
                if not looks_like_prose:
                    continue
            items.append(Item(r, number, kind, lit, "untranslated"))


def scan_gd(keys: set, items: List[Item], referenced: set, dyn_prefixes: set, tr_sites: List[Tuple[str, int, str]]) -> int:
    count = 0
    for path in tracked_or_all(".gd"):
        r = rel(path)
        if is_excluded(r):
            continue
        count += 1
        scan_gd_source(r, path.read_text(encoding="utf-8"), keys, items, referenced, dyn_prefixes, tr_sites)
    return count


def check_prototypes_unreferenced() -> List[str]:
    problems: List[str] = []
    needle = PROTOTYPE_PREFIX
    for suffix in (".gd", ".tscn", ".tres", ".cfg"):
        for path in tracked_or_all(suffix):
            r = rel(path)
            if r.startswith(needle) or r.startswith(("tests/", "tools/", "docs/")):
                continue
            if needle in path.read_text(encoding="utf-8", errors="replace"):
                problems.append("%s 引用了 prototypes/，不能整体排除该目录" % r)
    return problems


def scan_project_godot(items: List[Item]) -> None:
    path = ROOT / "project.godot"
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.startswith("config/name="):
            reason = dict(WHITELIST_PROJECT).get(line.strip())
            items.append(Item("project.godot", number, "project", line.strip(), "whitelisted" if reason else "untranslated", note=reason or ""))


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def run() -> dict:
    locales, table, order, dupes = load_csv()
    keys = set(table)
    items: List[Item] = []
    referenced: set = set()
    dyn_prefixes: set = set()
    tr_sites: List[Tuple[str, int, str]] = []

    n_tscn = scan_tscn(keys, items)
    n_tres = scan_tres(keys, items)
    n_gd = scan_gd(keys, items, referenced, dyn_prefixes, tr_sites)
    scan_project_godot(items)
    for item in items:
        if item.status == "wired":
            referenced.add(item.key)
    # 动态 key 家族：CHECKPOINT_%s -> RunCheckpoint.KIND_NAMES 的每个枚举名都必须有 key。
    family_errors: List[str] = []
    for prefix in sorted(dyn_prefixes):
        members = [k for k in keys if k.startswith(prefix)]
        referenced.update(members)
        if prefix == "CHECKPOINT_":
            src = (ROOT / "data" / "run_checkpoint.gd").read_text(encoding="utf-8")
            names = re.findall(r'Kind\.\w+:\s*"(\w+)"', src)
            for name in names:
                if prefix + name not in keys:
                    family_errors.append("动态 key 缺失：%s%s" % (prefix, name))
            if not names:
                family_errors.append("读不到 RunCheckpoint.KIND_NAMES，无法校验 CHECKPOINT_ 家族")
        elif prefix == "SETTINGS_LANGUAGE_":
            for locale in locales:
                if prefix + locale.upper() not in keys:
                    family_errors.append("动态 key 缺失：%s%s（语言选项需要该语言的自称）" % (prefix, locale.upper()))
        else:
            family_errors.append("未登记校验规则的动态 key 家族：%s" % prefix)

    errors: List[str] = []
    warnings: List[str] = []
    errors.extend(family_errors)
    errors.extend(check_prototypes_unreferenced())

    for d in dupes:
        errors.append("重复 key：%s" % d)
    for key in order:
        if not KEY_RE.match(key):
            errors.append("key 命名不规范（应为 UPPER_SNAKE）：%s" % key)

    # 每个 tr() 引用的 key 必须存在。
    missing_refs = sorted({(f, ln, k) for f, ln, k in tr_sites if k and k not in keys})
    for f, ln, k in missing_refs:
        errors.append("%s:%d tr() 引用了表里不存在的 key：%s" % (f, ln, k))

    # 每种语言：缺失 / 空值 / 占位符 / 疑似未翻译。
    per_locale: Dict[str, dict] = {}
    base = locales[0] if locales else "en"
    base_idx = locales.index(base)
    same_allowed = {
        "SETTINGS_LANGUAGE_EN": "语言自称（endonym），本就应保持原样",
        "SETTINGS_LANGUAGE_ZH_CN": "语言自称（endonym），本就应保持原样",
    }
    for idx, locale in enumerate(locales):
        empty = [k for k in order if not table[k][idx].strip()]
        suspicious: List[str] = []
        ph_bad: List[str] = []
        for k in order:
            value = table[k][idx]
            if not value.strip():
                continue
            if idx != base_idx:
                en = table[k][base_idx]
                if placeholders(value) != placeholders(en):
                    ph_bad.append("%s: %s != %s" % (k, placeholders(en), placeholders(value)))
                if value.count("\\n") != en.count("\\n"):
                    ph_bad.append("%s: 换行数不一致" % k)
                same = value.strip().lower() == en.strip().lower()
                if (same or not CJK_RE.search(value)) and locale.startswith("zh") and k not in same_allowed:
                    suspicious.append(k)
        per_locale[locale] = {
            "keys": len(order),
            "valid": len(order) - len(empty),
            "empty": empty,
            "suspicious_untranslated": suspicious,
            "placeholder_mismatch": ph_bad,
        }
        for k in empty:
            errors.append("%s 缺译 / 空值：%s" % (locale, k))
        for k in suspicious:
            errors.append("%s 疑似未翻译（与英文相同或无 CJK）：%s" % (locale, k))
        for msg in ph_bad:
            errors.append("%s 占位符不一致：%s" % (locale, msg))

    unused = sorted(k for k in order if k not in referenced)
    for k in unused:
        errors.append("未被任何场景 / 脚本 / 资源引用的 key：%s" % k)

    untranslated = [i for i in items if i.status == "untranslated"]
    whitelisted = [i for i in items if i.status == "whitelisted"]
    ignored = [i for i in items if i.status == "ignored"]
    ignored_by_reason: Dict[str, int] = {}
    for i in ignored:
        ignored_by_reason[i.note] = ignored_by_reason.get(i.note, 0) + 1
    wired_items = [i for i in items if i.status == "wired"]
    for i in untranslated:
        errors.append("%s:%d [%s] 未接入翻译：%r  -> 请改成 tr(\"KEY\") 并在 locale/wpg.csv 增加 key；若确属不需翻译，请加入白名单并写明原因" % (i.file, i.line, i.kind, i.text))
    for index, (path, lit, reason) in enumerate(WHITELIST_LITERALS):
        if not reason.strip():
            errors.append("白名单缺少原因：%s %r" % (path, lit))
        if index not in _USED_WHITELIST:
            errors.append("白名单条目已无命中（对应文本已删除或已接入翻译，请移除）：%s %r" % (path, lit))
    for path, pattern, reason in WHITELIST_LINES:
        if not reason.strip():
            errors.append("白名单缺少原因：%s %r" % (path, pattern))

    wired_total = len(wired_items) + len(tr_sites)
    visible_total = wired_total + len(untranslated)
    coverage = 100.0 if visible_total == 0 else round(100.0 * wired_total / visible_total, 2)
    wl_by_reason: Dict[str, int] = {}
    for i in whitelisted:
        wl_by_reason[i.note] = wl_by_reason.get(i.note, 0) + 1

    report = {
        "scanned": {"tscn": n_tscn, "gd": n_gd, "tres": n_tres, "project.godot": 1, "csv": 1,
                    "total_files": n_tscn + n_gd + n_tres + 2},
        "locales": locales,
        "default_locale": "en（GameSettings 无存档时按系统语言：zh* -> zh_CN，其余 en）",
        "keys_total": len(order),
        "per_locale": per_locale,
        "visible_texts": {
            "wired_static_properties": len(wired_items),
            "wired_tr_call_sites": len(tr_sites),
            "wired_total": wired_total,
            "untranslated": len(untranslated),
            "total": visible_total,
            "coverage_percent": coverage,
        },
        "whitelist": {"count": len(whitelisted), "by_reason": wl_by_reason,
                      "entries": [i.as_dict() for i in whitelisted]},
        "ignored_context": {"count": len(ignored), "by_reason": ignored_by_reason},
        "untranslated_items": [i.as_dict() for i in untranslated],
        "unused_keys": unused,
        "errors": errors,
        "warnings": warnings,
        "items": [i.as_dict() for i in items],
    }
    return report


def write_report(report: dict) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "coverage.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    vt = report["visible_texts"]
    lines = [
        "# WPG i18n 覆盖报告",
        "",
        "- 扫描文件：%(total_files)d（tscn %(tscn)d / gd %(gd)d / tres %(tres)d / project.godot / csv）" % report["scanned"],
        "- 语言：%s；默认：%s" % (", ".join(report["locales"]), report["default_locale"]),
        "- 翻译 key 总数：%d" % report["keys_total"],
        "- 玩家可见文本：%d；已接入：%d（静态属性 %d + tr 调用点 %d）；未接入：%d；覆盖率 **%.2f%%**"
        % (vt["total"], vt["wired_total"], vt["wired_static_properties"], vt["wired_tr_call_sites"], vt["untranslated"], vt["coverage_percent"]),
        "- 显式白名单条目：%d；按语境忽略（节点名 / 日志 / 路径 / 状态码 / 纯格式串等，不是界面文案）：%d"
        % (report["whitelist"]["count"], report["ignored_context"]["count"]),
        "",
        "## 各语言",
        "",
        "| 语言 | key 总数 | 有效翻译 | 空值 | 疑似未翻译 | 占位符不一致 |",
        "|---|---|---|---|---|---|",
    ]
    for locale, info in report["per_locale"].items():
        lines.append("| %s | %d | %d | %d | %d | %d |" % (
            locale, info["keys"], info["valid"], len(info["empty"]),
            len(info["suspicious_untranslated"]), len(info["placeholder_mismatch"])))
    lines += ["", "## 白名单（按原因）", ""]
    for reason, count in sorted(report["whitelist"]["by_reason"].items(), key=lambda kv: -kv[1]):
        lines.append("- %d × %s" % (count, reason))
    lines += ["", "## 按语境忽略的字面量（按规则）", ""]
    for reason, count in sorted(report["ignored_context"]["by_reason"].items(), key=lambda kv: -kv[1]):
        lines.append("- %d × %s" % (count, reason))
    lines += ["", "## 未接入文本", ""]
    if not report["untranslated_items"]:
        lines.append("无。")
    for item in report["untranslated_items"]:
        lines.append("- `%s:%d` %r" % (item["file"], item["line"], item["text"]))
    lines += ["", "## 错误", ""]
    if not report["errors"]:
        lines.append("无。")
    for err in report["errors"]:
        lines.append("- " + err)
    (OUT_DIR / "coverage.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="WPG i18n 审计")
    parser.add_argument("--strict", action="store_true", help="有任何错误就返回非 0")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(list(argv) if argv is not None else None)
    report = run()
    write_report(report)
    vt = report["visible_texts"]
    if not args.quiet:
        print("[INFO] 扫描 %d 个文件；key %d；语言 %s" % (report["scanned"]["total_files"], report["keys_total"], ",".join(report["locales"])))
        print("[INFO] 玩家可见文本 %d：已接入 %d，未接入 %d，覆盖率 %.2f%%；显式白名单 %d；语境忽略 %d"
              % (vt["total"], vt["wired_total"], vt["untranslated"], vt["coverage_percent"],
                 report["whitelist"]["count"], report["ignored_context"]["count"]))
        for locale, info in report["per_locale"].items():
            print("[INFO] %s：key %d，有效 %d，空 %d，疑似未翻译 %d，占位符不一致 %d"
                  % (locale, info["keys"], info["valid"], len(info["empty"]), len(info["suspicious_untranslated"]), len(info["placeholder_mismatch"])))
    for err in report["errors"]:
        print("[FAIL] " + err)
    if report["errors"]:
        print("[FAIL] i18n 审计未通过：%d 项问题（报告：build/i18n/coverage.md）" % len(report["errors"]))
        return 1 if args.strict else 0
    print("[PASS] i18n 审计通过（覆盖率 %.2f%%，报告：build/i18n/coverage.md）" % vt["coverage_percent"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
