extends "res://组件/状态机/状态.gd"
## 手控 —— 玩家按着键盘操作她（`Director.当前控制 == self`）。
##
## 这一段是从旧的 `宿管.gd` 的 `_physics_process` 原样搬过来的，**行为一个字没改**：
## 爬梯 / 开门 / 挥击 / 抓捕 / 跳跃 / 左右速度，顺序和早退都一样。
## 搬出来只是为了让 `宿管.gd` 能腾出位置放 AI —— 不搬的话 AI 得往同一条 if 链里插，
## 那就等于把「谁在按键」和「该不该动」两件事混成一件事。
##
## 所以：**这里以后不要再加新玩法**。手控的手感问题改这里；AI 的行为放 `待机/巡逻/追击`。

const 状态名 := preload("res://角色/宿管/状态/状态名.gd")


func 每帧(delta: float) -> void:
	var h = host

	var dir := Input.get_axis("left", "right")
	var updown := Input.get_axis("up", "down")

	# ── 爬梯：碰到梯子 + 按了上下才挂住。扛着人不能爬 ──
	if h._on_ladder and updown != 0.0 and h._carried_student == null:
		h._climbing = true
	if h._carried_student != null:
		h._climbing = false
	if h._on_ladder and h._climbing:
		h.velocity.y = updown * h.CLIMB_SPEED
		h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)
		if Input.is_action_just_pressed("jump"):
			h.velocity.y = h.CLIMB_OFF_JUMP
			h.velocity.x = dir * h.SPEED * 0.6
			h._climbing = false
		h.move_and_slide()
		return

	# ── 开门：E 键（open_door）。梯子上不开门 ──
	if Input.is_action_just_pressed("open_door"):
		h._开门()

	# ── 键位分工 ──
	#   F（interaction）→ 挥击
	#   G（grab）       → 扛人：肩上有人则放下；贴身有瘫倒的学生则按住读条后扛走
	h._更新朝向()
	if Input.is_action_just_pressed("interaction"):
		h._挥击()
	h._抓捕(delta)

	# ── 重力（三分支：定格中 / 刚到顶 / 正常下落加速）──
	if not h.is_on_floor():
		if h._hang_left > 0.0:
			h._hang_left = maxf(h._hang_left - delta, 0.0)
			if h._hang_left <= 0.0:
				h._fast_fall = true
		elif absf(h.velocity.y) < h.HANG_VY_BAND and not h._fast_fall:
			h._hang_left = h.HANG_TIME
		else:
			h.velocity.y += h.GRAVITY * (h.FALL_GRAVITY_MULT if h._fast_fall else 1.0) * delta
	else:
		h._fast_fall = false

	# ── 跳跃（土狼时间 + 按键记账）──
	h._coyote = h.COYOTE_TIME if h.is_on_floor() else maxf(h._coyote - delta, 0.0)
	# 按住抓人时不记账：抓人得站定，边跳边抓不合理
	if Input.is_action_just_pressed("jump") and h._抓捕目标 == null:
		h._buffer = h.JUMP_BUFFER
	else:
		h._buffer = maxf(h._buffer - delta, 0.0)

	if h._buffer > 0.0 and h._coyote > 0.0:
		h.velocity.y = h.JUMP_VELOCITY
		h._buffer = 0.0
		h._coyote = 0.0
		h._hang_left = 0.0
		h._fast_fall = false

	if Input.is_action_just_released("jump") and h.velocity.y < 0.0:
		h.velocity.y *= h.JUMP_CUT

	# ── 左右速度 ──
	# 三个因素影响移速：后摇站定（挥完不能动）、扛人减速、按住抓人时站定
	var 走速: float = h.SPEED
	if h._carried_student != null:
		走速 = h.SPEED * h.CARRY_SPEED_MULT
	if h._抓捕目标 != null:
		dir = 0.0
	if dir != 0.0 and h._swing_recover_left <= 0.0:
		var same_dir := signf(h.velocity.x) == signf(dir)
		if not (not h.is_on_floor() and same_dir and absf(h.velocity.x) > 走速):
			h.velocity.x = move_toward(h.velocity.x, dir * 走速, h.ACCEL * delta)
	else:
		h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)

	# 扛着学生时，把他摆到肩上（位置每帧算，和学生搬箱子同一个套路）
	if h._carried_student != null and is_instance_valid(h._carried_student):
		h._carried_student.global_position = h.global_position + Vector2(
			h._swing_dir * h.CARRY_STUDENT_OFFSET.x, h.CARRY_STUDENT_OFFSET.y)

	h.move_and_slide()


## 交给 AI 时：抓捕作废、条收掉，别留一根条挂在身上。
## 速度由 AI 状态自己接管，这里不清（清了会突然刹一下，看得见）。
func 离开(_下个: String = "") -> void:
	if host._抓捕目标 != null:
		host._取消抓捕()
