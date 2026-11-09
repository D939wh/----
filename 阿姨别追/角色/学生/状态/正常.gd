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
	# 蓄力中不接：正在掂量扔多远，不该被一按就拽走
	if not h.蓄力中() and Input.is_action_just_pressed("self_rescue"):
		var 目标 = h._贴身队友()
		if 目标 != null:
			h._救人目标 = 目标
			机器().切(状态名.救人中)
			return
		print("[学生] 身边没有瘫倒的队友")

	# ── E / F / Q / R / S ─────────────────────────────────
	_处理按键(h, delta)

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
##   E open_door    开门（手上占着时不开，得先按 F 放下）
##   F interaction  搬东西 / 搬人。手上有东西：按住蓄力、松手抛出（短按 = 原地放下）；
##                  空手：依次试箱子·道具 → 扛队友
##   Q use_item     使用道具
##   R insert_key   把手上的东西插进锁口
##   S down         从脚下可穿过的地板落下
func _处理按键(h, delta: float) -> void:
	# 扛着的箱子跟着人走（轻的抱在胸前，重的拖在脚边）
	if h.正搬着() and is_instance_valid(h._carried):
		h._carried.position = h._扛着的位置()

	# 扛着的队友跟着走（3 档拖在脚边，位置每帧算一次，和箱子同一个套路）
	if h.正扛着人():
		h._扛着的人.position = h.扛人偏移

	# 蓄力中：只认「松开 F」和左右方向，其他键一律不接 ——
	# 半路去开门 / 用道具会把「扔多远」这件事搅乱，也会让头顶的力条突然消失
	if h.蓄力中():
		h._推进蓄力(delta)
		if Input.is_action_just_released("interaction"):
			h._松开交互()
		return

	# E：开门。独立一个键，门口堆着箱子也不会被 F 抢走
	if Input.is_action_just_pressed("open_door"):
		h._open_door()

	# F：搬箱子 / 搬人。手上有东西先蓄力，否则按优先级挑一件
	if Input.is_action_just_pressed("interaction"):
		h._交互键()

	if Input.is_action_just_pressed("use_item") and h._item_icon != null:
		h._use_item()

	if Input.is_action_just_pressed("insert_key"):
		h._insert_key()

	# S 键：摘掉「可以穿过的地板」层，由 student.gd 的 _推进下穿 挂回。
	if Input.is_action_just_pressed("down") and h.is_on_floor():
		h._开始下穿()


## 切走（瘫了 / 被扛 / 被切控制权）时蓄力作废：
## 东西还留在手上，头顶那根力条必须收掉，否则会一直挂在身上。
func 离开(_下个: String = "") -> void:
	host._取消蓄力()
