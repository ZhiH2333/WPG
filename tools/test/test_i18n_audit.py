#!/usr/bin/env python3
"""i18n 静态审计的回归测试。

两部分：
  1. 反例：喂给扫描器的「硬编码文本」必须被抓出来；已接入翻译的必须放行。
     （证明审计不是形同虚设：没有靠忽略整个目录 / 忽略全部英文来通过。）
  2. 真实仓库：tools/i18n/audit.py 对当前工作区必须零问题。

    python3 tools/test/test_i18n_audit.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "i18n"))

import audit  # noqa: E402

KEYS = {"MENU_PLAY", "HUD_GOLD", "SETTINGS_LANGUAGE"}
failures = []


def check(name: str, ok: bool) -> None:
    if ok:
        print("[PASS] %s" % name)
    else:
        print("[FAIL] %s" % name)
        failures.append(name)


def gd_items(path: str, source: str):
    items, referenced, dyn, sites = [], set(), set(), []
    audit.scan_gd_source(path, source, KEYS, items, referenced, dyn, sites)
    return items, referenced, dyn, sites


def tscn_items(path: str, source: str):
    items = []
    audit.scan_tscn_source(path, source, KEYS, items)
    return items


def statuses(items):
    return sorted(i.status for i in items)


def main() -> int:
    # --- tscn
    check("tscn 硬编码英文被抓", statuses(tscn_items("ui/x.tscn", 'text = "Hello world"\n')) == ["untranslated"])
    check("tscn 硬编码中文被抓", statuses(tscn_items("ui/x.tscn", 'text = "你好"\n')) == ["untranslated"])
    check("tscn placeholder_text 硬编码被抓", statuses(tscn_items("ui/x.tscn", 'placeholder_text = "type here"\n')) == ["untranslated"])
    check("tscn tooltip_text 硬编码被抓", statuses(tscn_items("ui/x.tscn", 'tooltip_text = "Settings"\n')) == ["untranslated"])
    check("tscn header_text 硬编码被抓", statuses(tscn_items("ui/x.tscn", 'header_text = "Audio"\n')) == ["untranslated"])
    check("tscn key 放行", statuses(tscn_items("ui/x.tscn", 'text = "MENU_PLAY"\n')) == ["wired"])
    check("tscn 纯数字 / 符号放行", tscn_items("ui/x.tscn", 'text = "00:00"\ntext = "-"\ntext = "1 / 2 / 3"\n') == [])
    check("tscn 未登记 key（拼错）被抓", statuses(tscn_items("ui/x.tscn", 'text = "MENU_PLAYY"\n')) == ["untranslated"])

    # --- gd 文本出口
    items, _, _, _ = gd_items("ui/x.gd", '\tlabel.text = "Hello world"\n')
    check("gd .text 硬编码被抓", statuses(items) == ["untranslated"])
    items, _, _, sites = gd_items("ui/x.gd", '\tlabel.text = tr("MENU_PLAY")\n')
    check("gd tr(key) 放行并计入调用点", items == [] and sites == [("ui/x.gd", 1, "MENU_PLAY")])
    items, _, _, sites = gd_items("data/x.gd", '\treturn WpgI18n.t("HUD_GOLD") % 3\n')
    check("gd WpgI18n.t(key) 计入调用点", sites == [("data/x.gd", 1, "HUD_GOLD")])
    items, _, _, _ = gd_items("lobby/x.gd", '\t_status.text = "no room"\n')
    check("非 ui 目录的 .text 赋值同样被抓", statuses(items) == ["untranslated"])
    items, _, _, _ = gd_items("ui/x.gd", '\tbutton.add_item("AUTO")\n')
    check("add_item 硬编码被抓", statuses(items) == ["untranslated"])
    items, _, _, _ = gd_items("ui/x.gd", '\tbutton.add_item(tr("MENU_PLAY"))\n')
    check("add_item(tr()) 放行", items == [])
    items, _, _, _ = gd_items("ui/x.gd", '\tlabel.text = "%d/%d" % [a, b]\n')
    check("纯格式串放行", items == [])
    items, _, _, _ = gd_items("ui/x.gd", '\t# label.text = "Hello world"\n')
    check("注释里的文本不算", items == [])
    items, _, _, _ = gd_items("ui/x.gd", '\tlabel.text = "Hello world"  # 注释\n')
    check("行尾注释不影响判定", statuses(items) == ["untranslated"])
    items, _, _, _ = gd_items("ui/x.gd", 'const TITLE_TEXT := "Pick a gun"\n')
    check("TEXT / TITLE 常量里的硬编码被抓", statuses(items) == ["untranslated"])
    items, _, _, _ = gd_items("ui/x.gd", 'const TITLE_TEXT := "MENU_PLAY"\n')
    check("TEXT / TITLE 常量里放 key 放行", items == [])
    items, _, _, _ = gd_items("ui/x.gd", '\tvar who: String = "Some Player Name"\n')
    check("Tier 2：ui/ 下像人话的字面量被抓", statuses(items) == ["untranslated"])
    items, _, _, _ = gd_items("combat/x.gd", '\tvar who: String = "Some Player Name"\n')
    check("非 ui 层且不在文本出口的字面量不误报", items == [])
    items, _, _, _ = gd_items("ui/x.gd", '\tnode.name = "Seat Header Row"\n')
    check("节点名称语境忽略", statuses(items) == ["ignored"])
    items, _, _, _ = gd_items("ui/x.gd", '\tpush_warning("something went wrong")\n')
    check("日志语境忽略", statuses(items) == ["ignored"])
    items, _, dyn, sites = gd_items("ui/x.gd", '\tlabel.text = tr("CHECKPOINT_%s" % kind)\n')
    check("动态 key 记录家族前缀", dyn == {"CHECKPOINT_"} and items == [])
    items, ref, _, _ = gd_items("ui/x.gd", 'const BACK_TEXT: String = "MENU_PLAY"\n')
    check("常量里的 key 字面量算被引用", "MENU_PLAY" in ref)

    # --- 白名单必须有原因
    check("所有显式白名单都写了原因", all(reason.strip() for _, _, reason in audit.WHITELIST_LITERALS))
    check("所有行级白名单都写了原因", all(reason.strip() for _, _, reason in audit.WHITELIST_LINES))
    check("所有语境忽略规则都写了原因", all(reason.strip() for _, reason in audit.IGNORE_LINE_RULES))

    # --- 工具函数
    check("占位符提取", audit.placeholders("a %d b %.1fs c %s %%") == ["%d", "%.1f", "%s"])
    check("has_language：纯格式串不是语言", not audit.has_language("%d/%d") and not audit.has_language("%.1fs"))
    check("has_language：单词是语言", audit.has_language("gold  %d") and audit.has_language("金币"))

    # --- 真实仓库
    report = audit.run()
    for err in report["errors"]:
        print("[FAIL] 仓库审计：" + err)
    check("当前工作区 i18n 审计零问题", not report["errors"])
    vt = report["visible_texts"]
    check("玩家可见文本接入率 100%", vt["untranslated"] == 0 and vt["total"] > 0)
    for locale, info in report["per_locale"].items():
        check("%s 有效翻译 100%%（%d/%d）" % (locale, info["valid"], info["keys"]), info["valid"] == info["keys"])

    if failures:
        print("[FAIL] i18n 审计测试失败：%d 项" % len(failures))
        return 1
    print("[PASS] i18n 审计测试：全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
