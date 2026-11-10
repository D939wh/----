extends "res://组件/状态机/状态.gd"
## 攻击 —— 已经够得着了：站定，一棍接一棍地挥（前摇 → 扫 → 后摇，时序在 `宿管.gd` 里）。
##
## 【与「追击」只差一个距离】够得着就挥，够不着才追。
## 这里**不判断「这一下能不能打中」**：手抬起来就挥出去，扫不扫得到由棍子决定
## （主人 2026-11-10 定：不是检测范围内有没有敌人再攻击，是直接挥手直接攻击，
##  只是前摇后摇比较大）。所以下面没有任何「先找目标再决定打不打」的分支。
##
## 【为什么不边追边挥】挥棍全程站定（`_推进挥击` 会把水平速度按住），
## 走位归追击、出手归攻击，两件事分开才读得清。

const 状态名 := preload("res://角色/宿管/状态/状态名.gd")


func 每帧(delta: float) -> void:
	var h = host
	var 目标 = h._看得见的目标()

	# 人没了（跑出察觉圈 / 被扛走）→ 交回决策：该巡逻巡逻，该待机待机
	if 目标 == null:
		机器().切(h.decide())
		return

	# 站定，重力照常
	h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	h.move_and_slide()

	# 面朝目标：只转身，不挪步
	var 横向差: float = 目标.global_position.x - h.global_position.x
	if absf(横向差) > 1.0:
		h._面朝(signf(横向差))

	# 目标跑出棍长 → 交回追击。用 `挥击距离`（棍长留一成余量）而不是 `贴身距离`，
	# 否则会出现「已经站在棍子够得着的地方，她却还在往前顶」。
	if h.global_position.distance_to(目标.global_position) > h.挥击距离:
		机器().切(状态名.追击)
		return

	# 够得着就抬手。能不能打中不归这里管：`_挥击` 内部只管前摇/冷却在不在，
	# 有人没人都照样把棍子挥出去。
	h._挥击()
