extends "res://组件/状态机/状态.gd"
## 追击 —— 察觉圈里看得见人、还没贴到身上：朝目标横坐标压过去。
##
## 与参考项目同款「先决策再走位」：每帧先问 host.decide()，
## 它要是改主意（目标丢了 / 该打该抓）就立刻交出去，不自己判断。
## 贴到 `贴身距离` 内本状态也不动手 —— 打人与抓人不在这轮范围里（主人 2026-11-09 定：
## 先只做能动 + 能追人），所以此刻只是站住不再往前挤，等人跑开再继续追。

const 状态名 := preload("res://角色/宿管/状态/状态名.gd")


func 每帧(delta: float) -> void:
	var h = host
	var 目标 = h._看得见的目标()
	var 下一步: String = h.decide()
	if 下一步 != 状态名.追击:
		机器().切(下一步)
		return

	if 目标 == null:
		return

	# 已经贴到身上：站住不动。这一轮不做挥击 / 抓捕（下一轮再加）。
	if absf(目标.global_position.x - h.global_position.x) <= h.贴身距离:
		h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)
		if not h.is_on_floor():
			h.velocity.y += h.GRAVITY * delta
		h.move_and_slide()
		return

	# 撞墙 / 到崖边就不再往前挤（`_朝目标走` 返回 false）。不切状态 ——
	# 目标可能就在墙那边，站住等它绕过来，比掉头乱跑更像个追人的。
	h._朝目标走(目标.global_position.x, h.追击速度, delta)
