extends Object
class_name UiType

## 颜色令牌。字级（字号/字重/描边）只存在于 `ui/game_theme.tres` 的 Theme Variation 里，
## 这里不再放字号，避免第二份阶梯（2026-09-26 统一）。
## 角色 → Variation：页面标题 PageTitle / 页面说明 PageSubtitle / 舞台玩家名 ShowcaseName /
## Rail 行 RailTitle + Caption / 小节 SectionLabel / 卡片标题 OfferTitle / 卡片说明 OfferDesc /
## 正文 RunSummaryBody / 提示 RunSummaryHint / 数字 StatValue / 大数字 ModeTitle。
const INK := Color(0.96, 0.93, 0.88, 1)
const MUTED := Color(0.62, 0.58, 0.52, 1)
const STRUCTURE := Color(0.96, 0.93, 0.88, 0.35)
const PAGE_VEIL := Color(0.07, 0.06, 0.05, 0.42)
