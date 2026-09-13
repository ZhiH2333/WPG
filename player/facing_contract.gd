extends Object
class_name FacingContract

## 贴图朝向合同。SPIN 用 Body 预旋转；FLIP 只用 Sprite2D.flip_h。

const PLAYER_TEXTURE: String = "res://images/player.png"
const PLAYER_FACE_OFFSET_DEG: float = 40.0
const PLAYER_BODY_SCALE := Vector2(0.065, 0.065)

const MELEE_TEXTURE: String = "res://images/melee.png"
const RANGED_TEXTURE: String = "res://images/ranged.png"
const CHARGER_TEXTURE: String = "res://images/charger.png"
const BOSS_TEXTURE: String = "res://images/boss.png"

## 原生朝左的 FLIP 图：目标在右侧时 flip_h = true
const MELEE_NATIVE_FACES_RIGHT: bool = false
const RANGED_NATIVE_FACES_RIGHT: bool = true
const CHARGER_NATIVE_FACES_RIGHT: bool = false
const BOSS_NATIVE_FACES_RIGHT: bool = false

const MELEE_BASE_SCALE := Vector2(0.05, 0.05)
const RANGED_BASE_SCALE := Vector2(0.05, 0.05)
const CHARGER_BASE_SCALE := Vector2(0.045, 0.045)
const BOSS_BASE_SCALE := Vector2(0.10, 0.10)
## 精英复用 melee 贴图放大：0.05 × 1.75 ≈ 0.09
const ELITE_BASE_SCALE := Vector2(0.09, 0.09)
