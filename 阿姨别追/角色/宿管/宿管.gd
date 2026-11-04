extends CharacterBody2D
## 宿管阿姨 —— 2026-11-03 这版只做四件事：能走、能跳、能爬梯、能开门
##
## 追人、挥扫把、抓人、手电、听声辨位，全是 W6 的事，今天一行都不做。
## 所以如果现在 F1 切到她身上，她除了走和开门什么都干不了 —— 这是故意的。
##
## 她跟学生的三个不同：
##   1. 走得更快：370 vs 315（策划案 5.4 : 4.6 m/s，按学生的 315 反算）
##   2. 不捡东西、不搬箱子 —— 她的 E 只用来开门，捡不起来任何东西
##   3. 她在 "keeper" 组里。门看到这个组，就去清单里取「宿管」那一行的时长
##      （1.5 秒，学生是 0.3 秒）—— 数字在 数据/楼层清单.gd，不在这个文件里，也不在门里
##
## 改动手感：只改下面带「←调这里」的那几行，改完存盘 F5 立刻见效。

# ── 走 ────────────────────────────────────────────────────
const SPEED: float = 370.0        # 走速（像素/秒）。←调这里
const ACCEL: float = 1400.0       # 提速快慢
const FRICTION: float = 1800.0    # 松手后减速快慢

# ── 跳（跟学生同一套，宿管不搞特殊）────────────────────────
const GRAVITY: float = 368.0
const JUMP_VELOCITY: float = -260.0
const JUMP_CUT: float = 0.45      # 松手小跳：松手瞬间竖直速度乘这个数
const COYOTE_TIME: float = 0.10   # 走出平台边缘后还能跳的宽限
const JUMP_BUFFER: float = 0.12   # 落地前提前按跳，记这么久
const FALL_GRAVITY_MULT: float = 2.0   # 下落时重力翻倍，落得干脆
const HANG_TIME: float = 0.03          # 到顶定格
const HANG_VY_BAND: float = 40.0

# ── 爬梯 ─────────────────────────────────────────────────
const CLIMB_SPEED: float = 70.0
const CLIMB_OFF_JUMP: float = -180.0

var _on_ladder: bool = false
var _climbing: bool = false

var _coyote: float = 0.0
var _buffer: float = 0.0
var _hang_left: float = 0.0
var _fast_fall: bool = false


func _ready() -> void:
	# 门靠这个认出「推门的是宿管」，然后去清单里取宿管那一行的时长。
	# 这一句只说明「我是谁」，不说明「我多快」—— 多快是场景数据。
	add_to_group("keeper")
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)
	Director.register_controllable(self)   # 向总管报到：我可以被玩家控制


func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true


func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false


## 现在玩家控制的是不是我？（F1 切走之后就归 false）
func _受控() -> bool:
	return Director.当前控制 == self or Director.当前控制 == null


func _physics_process(delta: float) -> void:
	# 没被控制时：不吃键盘，但照常受重力，不会浮在空中
	if not _受控():
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	var dir := Input.get_axis("left", "right")
	var updown := Input.get_axis("up", "down")

	# ── 爬梯：碰到梯子 + 按了上下才算挂住 ──
	if _on_ladder and updown != 0.0:
		_climbing = true
	if _on_ladder and _climbing:
		velocity.y = updown * CLIMB_SPEED
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if Input.is_action_just_pressed("jump"):
			velocity.y = CLIMB_OFF_JUMP
			velocity.x = dir * SPEED * 0.6
			_climbing = false
		move_and_slide()
		return

	# ── 开门：E 键（W2D2 按键分开后，宿管也读 open_door）。梯子上不开门 ──
	if Input.is_action_just_pressed("open_door"):
		_开门()

	# ── 重力 ──
	if not is_on_floor():
		if _hang_left > 0.0:
			_hang_left = maxf(_hang_left - delta, 0.0)
			if _hang_left <= 0.0:
				_fast_fall = true
		elif absf(velocity.y) < HANG_VY_BAND and not _fast_fall:
			_hang_left = HANG_TIME
		else:
			velocity.y += GRAVITY * (FALL_GRAVITY_MULT if _fast_fall else 1.0) * delta
	else:
		_fast_fall = false

	# ── 跳跃（土狼时间 + 按键记账）──
	_coyote = COYOTE_TIME if is_on_floor() else maxf(_coyote - delta, 0.0)
	_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else maxf(_buffer - delta, 0.0)

	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		_hang_left = 0.0
		_fast_fall = false

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	# ── 左右速度 ──
	if dir != 0.0:
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > SPEED):
			velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	move_and_slide()


## E 键只做一件事：开/关面前那扇门。她捡不了东西，也搬不了箱子
## 注意：这里没有「宿管开门 1.5 秒」这种数字。她只是递申请，快慢由门照清单决定。
func _开门() -> void:
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("door"):
			var door: Node = area.get_parent()
			if door != null and door.has_method("press"):
				door.press(self)   # 说完这一句就没我的事了，门自己慢慢开
			return
