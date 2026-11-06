extends "res://组件/状态机/状态.gd"
## 旁观 —— 玩家把控制权切到别人身上（F1 或点击，开发期功能），本角色原地站住。
##
## 进入条件：`Director.当前控制` 不是自己。只屏蔽键盘输入，物理照常计算。

func 进入(_上个: String = "") -> void:
	# 正拉到一半被切走 → 这次救援作废、条收掉。
	# 不收的话这根条会一直亮在头顶：这个状态之后不会再去推进它，
	# 玩家看到的就是「进度条卡住不动」，而且再也回不来。
	host._取消救人()


func 每帧(delta: float) -> void:
	var h = host
	# 摩擦减速，不是瞬间归零 —— 切人的一瞬间人会滑一小段，比急刹自然
	h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	h.move_and_slide()
