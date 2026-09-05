extends Object
class_name GameCollisionLayers

## 与 project.godot [layer_names] 2d_physics 对齐的 1-based 层号。
const LAYER_PLAYER: int = 1
const LAYER_ENEMY: int = 2
const LAYER_PLAYER_BULLET: int = 3
const LAYER_ENEMY_BULLET: int = 4
const LAYER_WALL: int = 5

## collision_layer / collision_mask 使用的位掩码，禁止在业务脚本里写 1/2/4/8。
const MASK_NONE: int = 0
const MASK_PLAYER: int = 1 << (LAYER_PLAYER - 1)
const MASK_ENEMY: int = 1 << (LAYER_ENEMY - 1)
const MASK_PLAYER_BULLET: int = 1 << (LAYER_PLAYER_BULLET - 1)
const MASK_ENEMY_BULLET: int = 1 << (LAYER_ENEMY_BULLET - 1)
const MASK_WALL: int = 1 << (LAYER_WALL - 1)
