extends "res://组件/状态机/状态.gd"
## 追击 —— 察觉圈里看得见人、还没贴到身上：朝目标横坐标压过去。
##
## 与参考项目同款「先决策再走位」：每帧先问 host.decide()，
## 它要是改主意（目标丢了 / 该打该抓）就立刻交出去，不自己判断。
## 【2026-11-10 起】够得着（`挥击距离` 内）的那一段交给 `攻击.gd`，由 `抢占()` 切过去，
## 本状态只管「够不着的时候怎么压过去」。下面的 `贴身距离` 分支因此几乎走不到，
## 留着当兜底：万一攻击状态被别的原因让出去，她也不会一头撞进人身体里。

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

	# 贴到身上了（正常情况会被 `抢占()` 提前交给攻击状态）：站住，别挤进人身体里
	if absf(目标.global_position.x - h.global_position.x) <= h.贴身距离:
		h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)
		if not h.is_on_floor():
			h.velocity.y += h.GRAVITY * delta
		h.move_and_slide()
		return

	# 撞墙 / 到崖边就不再往前挤（`_朝目标走` 返回 false）。不切状态 ——
	# 目标可能就在墙那边，站住等它绕过来，比掉头乱跑更像个追人的。
	h._朝目标走(目标.global_position.x, h.追击速度, delta)
