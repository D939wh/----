extends "res://组件/状态机/状态.gd"
## 攀爬 —— 挂在梯子上。W 上爬 / S 下爬 / 空格蹬开。
##
## 进出条件统一由 `student.gd` 的 `抢占()` 判断，本状态不写进入/退出判断。

const 状态名 := preload("res://角色/学生/状态/状态名.gd")


func 每帧(delta: float) -> void:
	var h = host
	var 上下 := Input.get_axis("up", "down")

	# 不按键 = 0 = 挂在梯子上不动（这就是「扒着梯子」的表现）
	h.velocity.y = 上下 * h.CLIMB_SPEED
	h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)

	# 空格蹬开：比地面跳矮（CLIMB_OFF_JUMP = -180，地面是 -260）
	if Input.is_action_just_pressed("jump"):
		h.velocity.y = h.CLIMB_OFF_JUMP
		h.velocity.x = Input.get_axis("left", "right") * h.SPEED * 0.6
		# 硬切回正常：本帧到此为止的「状态语义」已经到了，但下面那句
		# move_and_slide 还得跑 —— 不跑的话这一帧蹬开的速度不会生效，人看着像卡了一下。
		机器().切(状态名.正常)

	h.move_and_slide()
