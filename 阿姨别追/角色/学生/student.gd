extends CharacterBody2D

const SPEED: float = 315.0     #速度（常走）
const ACCEL: float = 1400.0
const FRICTION: float = 1800.0

# 按住 Shift：减速档（按住=慢走，松手=快走）
const SLOW_SPEED: float = 200.0  # 慢走目标速度。嫌不够慢 → 调小
const SLOW_DECEL: float = 200.0  # 减速快慢。嫌切太突兀 → 调小
const SPRINT_TIME: float = 0.16   # 冲刺时长（废弃，暂留）
const SPRINT_CD: float = 1.5     # 冲刺冷却（废弃，暂留）
const SPRINT_SPEED: float = 288.0  # 冲刺速度（废弃，暂留）

const GRAVITY: float = 368.0   #跳
const JUMP_VELOCITY: float = -260.0
const JUMP_CUT: float = 0.45
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER: float = 0.12

# 下落专用
const FALL_GRAVITY_MULT: float = 2  # 下落重力 = GRAVITY × 它。嫌落得慢 → 调大（2.0）；太快 → 调小（1.2）

# 顶点悬停
const HANG_TIME: float = 0.03      # 到顶定格几秒。嫌定格久 → 调小；填 0 = 整套关掉
const HANG_VY_BAND: float = 40.0   # 竖直速度小于它就算「到顶了」（一般不动）

# 攀爬（按住 W 上爬 / S 下爬 / 空格蹬开）
const CLIMB_SPEED: float = 70.0     # 爬梯速度（像素/秒）。嫌慢调大
const CLIMB_OFF_JUMP: float = -180.0  # 梯子上蹬开跳的初速（比地面跳矮）

# 攀爬状态：碰到梯子=true；没按过上下键不算挂住
var _on_ladder: bool = false
var _climbing: bool = false  # 这一趟真的按过上下键在爬了吗（没按过=不挂）

# ── W1D4 搬运与道具 ─────────────────────────────────────────
# 角色状态只分两种：空手 / 负重。别的代码问一句「你现在搬着没」就能分支。
# 以后 W3 加「被逮/蹲地」就往这个 enum 里加值，不用到处加 if。
enum CarryState { EMPTY, CARRYING }
var _carry_state: CarryState = CarryState.EMPTY
var _carried: Area2D = null             # 正扛着的那个箱子（空手时是 null）

const CARRY_OFFSET := Vector2(14, -30)  # 扛着时箱子挂在身前的相对位置

# 道具格：null = 身上没东西；有图 = 有道具（右下角格子亮）
var _item_icon: Texture2D = null

var _coyote: float = 0.0
var _buffer: float = 0.0
var _sprint_left: float = 0.0
var _sprint_dir: float = 0.0
var _sprint_cd: float = 0.0
var _hang_left: float = 0.0   # 顶点定格还剩几秒（0=没在定格）
var _fast_fall: bool = false  # 定格结束后处于快落中

func _ready() -> void:
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)
	# 向总管报到：我可以被玩家控制。学生先出生，所以默认控制权默认在他身上
	Director.register_controllable(self)

func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子（还不算挂着，要看有没有按上下键）

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false   # 离开梯子，爬的记性清零

func _physics_process(delta: float) -> void:
	# 开发者模式（2026-11-03）：F1 切到宿管身上时，学生原地站住。
	# 不吃键盘，但重力照常 —— 不会浮在半空，也不会自己走路。
	# 这一整段只在「有人接管了控制权」时才起作用，正常单人玩永远是 false。
	if Director.当前控制 != null and Director.当前控制 != self:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	var dir := Input.get_axis("left", "right")  #左右移动
	var sprint_held := Input.is_action_pressed("sprint")  # 按住 Shift（按住=慢走）
	var updown := Input.get_axis("up", "down")  # W/S：上爬 / 下爬

	# 攀爬：碰到梯子 + 按了上下 → 开始爬（按过才挂住；没按过不会吸在梯子上）
	if _on_ladder and updown != 0.0:
		_climbing = true
	if _on_ladder and _climbing:
		velocity.y = updown * CLIMB_SPEED   # W 升 S 降；不按键 = 0 = 挂住
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if Input.is_action_just_pressed("jump"):
			velocity.y = CLIMB_OFF_JUMP
			velocity.x = dir * SPEED * 0.6
			_climbing = false
		move_and_slide()
		return

	# ── W1D4：交互（E 拿起/放下、右键用道具）──
	# 放在攀爬之后：梯子上不做交互，这又是"两个世界"的分界
	_update_interaction()

	#重力（三分支：定格中 / 刚到顶 / 正常下落加速）
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

	#秒表：土狼宽限、跳跃记账、冲刺冷却
	_coyote = COYOTE_TIME if is_on_floor() else maxf(_coyote - delta, 0.0)
	_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else maxf(_buffer - delta, 0.0)
	_sprint_cd = maxf(_sprint_cd - delta, 0.0)

	#起跳
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		_hang_left = 0.0    # 新跳清掉上一跳的定格/快落
		_fast_fall = false

	#松手小跳
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	#冲刺（废弃：点按爆发已删，三常量暂留）
	# if Input.is_action_just_pressed("sprint") and _sprint_cd <= 0.0 and dir != 0.0:
	# 	_sprint_left = SPRINT_TIME
	# 	_sprint_dir = dir
	# 	_sprint_cd = SPRINT_CD

	#左右速度
	if _sprint_left > 0.0:
		_sprint_left -= delta
		velocity.x = _sprint_dir * SPRINT_SPEED
	elif dir != 0.0:
		#按住 Shift = 慢走；松手 = 快走
		var slow_ok := sprint_held and is_on_floor()
		var target := SLOW_SPEED if slow_ok else SPEED
		var accel := SLOW_DECEL if slow_ok else ACCEL
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > target):
			velocity.x = move_toward(velocity.x, dir * target, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	move_and_slide()  #挂挡

# ============================================================
# W1D4 · 搬运与道具
# ------------------------------------------------------------
# 交互键 E 一件事分三步走（先看手上有没有东西）：
#   1) 正扛着箱子 → 放下
#   2) 空手 + 附近有箱子 → 扛起来（状态变 CARRYING）
#   3) 空手 + 附近有道具 → 捡进右下角格子
# 右键单独管"用道具"：消耗掉、格子变空。今天用掉没有任何效果。
# ============================================================

func _update_interaction() -> void:
	# 扛着的箱子跟着人走（挂在身前）
	if _carry_state == CarryState.CARRYING and is_instance_valid(_carried):
		_carried.position = CARRY_OFFSET

	if Input.is_action_just_pressed("interaction"):
		_interact()

	if Input.is_action_just_pressed("use_item") and _item_icon != null:
		_use_item()

# E 键：按上面三步走
func _interact() -> void:
	if _carry_state == CarryState.CARRYING:
		_drop_box()
		return

	# 门排最前：门挡着路的时候，先处理门 —— 扛着东西时不开门（手上没空）
	# 谁按谁接管这扇门，学生手快（0.3秒），宿管手慢（1.5秒）
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("door"):
			var door: Node = area.get_parent()
			if door != null and door.has_method("press"):
				door.press(self)
			return

	# 感应区里现在有哪些东西？先找可搬运的，再找可使用的
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("carryable"):
			_pick_up_box(area)
			return
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("usable_item") and _item_icon == null:
			_pick_up_item(area)
			return

# 扛起箱子：变成箱子的父节点，位置摆在身前
func _pick_up_box(box: Area2D) -> void:
	_carried = box
	_carry_state = CarryState.CARRYING
	box.reparent(self, false)          # 认人做爹：从此跟着人走
	box.position = CARRY_OFFSET

# 放下箱子：还回场景里，落在脚边
func _drop_box() -> void:
	var box := _carried
	_carried = null
	_carry_state = CarryState.EMPTY
	box.reparent(get_parent(), false)  # 交还给场景
	box.global_position = global_position + Vector2(18, -8)  # 放身前脚边

# 捡道具：图记进道具格，地上的物件消失
func _pick_up_item(item: Area2D) -> void:
	# 从物件身上找 Sprite2D 取图（不写死子节点名，换个叫法也不会崩）
	var spr := item.get_node_or_null("Sprite2D")
	if spr == null:
		for child in item.get_children():
			if child is Sprite2D:
				spr = child
				break
	if spr == null:
		return   # 没图就不收，免得收个空道具
	_item_icon = spr.texture
	item.queue_free()                  # 真消耗：地上的东西没了
	_refresh_item_slot()

# 用道具：今天没有任何效果，只负责消耗掉
func _use_item() -> void:
	_item_icon = null
	_refresh_item_slot()

# 道具格的亮/灭，只看 _item_icon 这一个数据
# 学生只朝「hud」组喊一嗓子（拿到/用掉了什么）；格子怎么亮、摆哪，学生一概不知
func _refresh_item_slot() -> void:
	get_tree().call_group("hud", "set_item", _item_icon)
