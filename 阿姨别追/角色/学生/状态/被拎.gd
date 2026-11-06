extends "res://组件/状态机/状态.gd"
## 被拎 —— 被宿管扛在肩上。
##
## 位置由宿管每帧设置，碰撞体已禁用，因此本状态没有每帧逻辑。
## reparent 与碰撞体开关在 `student.gd` 的 `被扛起()` / `被放下()` 里完成。

func 每帧(_delta: float) -> void:
	pass
