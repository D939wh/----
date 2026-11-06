extends "res://组件/状态机/状态.gd"
## 正常 —— 站着/走着/跳着，未被钉住、未瘫痪、未被拎。
##
## 顺序：交互 → 重力 → 秒表 → 起跳 → 松手小跳 → 左右速度 → move_and_slide。
## 负重通过倍率参数生效，不额外拆状态。

const 状态名 := preload("res://角色/学生/状态/状态名.gd")


func 每帧(delta: float) -> void:
	var h = host

	# ── H：拉队友 ─────────────────────────────────────────
	# 站着按 H = 拉身边瘫倒的队友。自救由 瘫痪.gd 处理。
	if Input.is_action_just_pressed("self_rescue"):
		var 目标 = h._贴身瘫痪队友()
		if 目标 != null:
			h._救人目标 = 目标
			机器().切(状态名.救人中)
			return
		print("[学生] 身边没有瘫倒的队友")

	# ── E / F / Q / R / S ─────────────────────────────────
	_处理按键(h)

	# ── 重力（三分支：定格中 / 刚到顶 / 正常下落加速）──────
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

	# ── 秒表：土狼宽限、跳跃记账、冲刺冷却 ────────────────
	h._coyote = h.COYOTE_TIME if h.is_on_floor() else maxf(h._coyote - delta, 0.0)
	h._buffer = h.JUMP_BUFFER if Input.is_action_just_pressed("jump") else maxf(h._buffer - delta, 0.0)
	h._sprint_cd = maxf(h._sprint_cd - delta, 0.0)

	# ── 起跳（跳跃高度倍率为 0 时禁止起跳）──────────────
	# 高度 h ∝ v²，要让高度减半，初速乘 √0.5
	if h._buffer > 0.0 and h._coyote > 0.0 and h._跳跃高度倍率 > 0.0:
		h.velocity.y = h.JUMP_VELOCITY * sqrt(h._跳跃高度倍率)
		h._buffer = 0.0
		h._coyote = 0.0
		h._hang_left = 0.0    # 新跳清掉上一跳的定格/快落
		h._fast_fall = false

	# ── 松手小跳 ──────────────────────────────────────────
	if Input.is_action_just_released("jump") and h.velocity.y < 0.0:
		h.velocity.y *= h.JUMP_CUT

	# ── 左右速度 ──────────────────────────────────────────
	var dir := Input.get_axis("left", "right")
	var sprint_held := Input.is_action_pressed("sprint")   # 按住 Shift = 慢走
	if h._sprint_left > 0.0:
		h._sprint_left -= delta
		h.velocity.x = h._sprint_dir * h.SPRINT_SPEED
	elif dir != 0.0:
		var slow_ok: bool = sprint_held and h.is_on_floor() and h._可否慢走
		var target: float = (h.SLOW_SPEED if slow_ok else h.SPEED) * h._移速倍率
		var accel: float = h.SLOW_DECEL if slow_ok else h.ACCEL
		var same_dir := signf(h.velocity.x) == signf(dir)
		if not (not h.is_on_floor() and same_dir and absf(h.velocity.x) > target):
			h.velocity.x = move_toward(h.velocity.x, dir * target, accel * delta)
	else:
		h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)

	h.move_and_slide()


## 按键分工：
##   E open_door    开门（搬着东西时不开）
##   F interaction  搬东西：搬着则放下，否则拾取
##   Q use_item     使用道具
##   R insert_key   把手上的东西插进锁口
##   S down         从脚下可穿过的地板落下
func _处理按键(h) -> void:
	# 扛着的箱子跟着人走（轻的抱在胸前，重的拖在脚边）
	if h.正搬着() and is_instance_valid(h._carried):
		h._carried.position = h._扛着的位置()

	if Input.is_action_just_pressed("open_door"):
		h._open_door()

	if Input.is_action_just_pressed("interaction"):
		h._pick_or_drop()

	if Input.is_action_just_pressed("use_item") and h._item_icon != null:
		h._use_item()

	if Input.is_action_just_pressed("insert_key"):
		h._insert_key()

	# S 键：摘掉「可以穿过的地板」层，由 student.gd 的 _推进下穿 挂回。
	if Input.is_action_just_pressed("down") and h.is_on_floor():
		h._开始下穿()
