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

const CARRY_OFFSET := Vector2(14, -30)  # 抱在胸前的相对位置（1、2 档）
const DRAG_OFFSET := Vector2(18, -8)    # 拖在脚边的相对位置（3、4 档）

# ── W3 负重（2026-11-03）────────────────────────────────────
# 扛起来之后，人被这件东西的重量拖住：走得慢、跳不高、爬不了梯。
# 「多重算哪一档、每档罚多少」**全在 `数据/重量档位.gd` 那张表里**，
# 这个文件只负责照表执行 —— 想调手感去改表，别改这里。
# 每帧要用的四个数在拿起/放下时算好存下来，跑起来就不用反复查表了。
const 重量档位 := preload("res://数据/重量档位.gd")

var _负重公斤: float = 0.0        # 扛着的东西多重（空手 = 0）
var _负重档名: String = "空手"    # "1 档" / "2 档" / "3 档" / "4 档" / "空手"
var _移速倍率: float = 1.0        # 目标速度乘它
var _跳跃高度倍率: float = 1.0    # 跳跃**高度**乘它（初速要开根，见起跳那段）
var _可否慢走: bool = true        # 负重时禁 Shift
var _可否攀爬: bool = true        # 2 档以上爬不了梯
var _拖行: bool = false           # 只能拖在地上走（决定箱子挂在胸前还是脚边）


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
	# 负重爬不了梯：2 档以上一律上不去（`数据/重量档位.gd` 里的「可否攀爬」）
	if _on_ladder and updown != 0.0 and _可否攀爬:
		_climbing = true
	if _climbing and not _可否攀爬:
		_climbing = false   # 手上扛着货，就算已经在梯子上也挂不住
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

	#起跳（太重就跳不起来：档位表里「跳跃高度倍率」= 0 = 禁用）
	# 注意乘的是「高度」的平方根：高度 h ∝ v²，想让高度减半，初速要乘 √0.5
	if _buffer > 0.0 and _coyote > 0.0 and _跳跃高度倍率 > 0.0:
		velocity.y = JUMP_VELOCITY * sqrt(_跳跃高度倍率)
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
		#按住 Shift = 慢走；松手 = 快走（负重时禁慢走）
		var slow_ok := sprint_held and is_on_floor() and _可否慢走
		var target := (SLOW_SPEED if slow_ok else SPEED) * _移速倍率
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
	# 扛着的箱子跟着人走（轻的抱在胸前，重的拖在脚边）
	if _carry_state == CarryState.CARRYING and is_instance_valid(_carried):
		_carried.position = _扛着的位置()

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

# 扛起箱子：变成箱子的父节点，位置摆在身前（超重的拖在地上）
# 从这一行开始，人就被它的重量拖住了 —— 具体罚多少问 `数据/重量档位.gd`
func _pick_up_box(box: Area2D) -> void:
	_carried = box
	_carry_state = CarryState.CARRYING
	_应用负重(box.取重量() if box.has_method("取重量") else 0.0)
	if box.has_method("设被扛着"):
		box.设被扛着(true)                # 告诉它：别自己往下掉了
	_climbing = false                     # 双手被占，梯子爬不了
	box.reparent(self, false)             # 认人做爹：从此跟着人走
	box.position = _扛着的位置()

# 放下箱子：还回场景里，落在脚边，然后它自己受重力落到地面
func _drop_box() -> void:
	var box := _carried
	_carried = null
	_carry_state = CarryState.EMPTY
	box.reparent(get_parent(), false)     # 交还给场景
	# 学生自己的原点就在脚底（碰撞体从 -44 到 0），所以这里减一个箱子的半高就贴地了
	box.global_position = global_position + Vector2(18, -12)
	if box.has_method("设被扛着"):
		box.设被扛着(false)               # 从这里开始它自己受重力
	_应用负重(0.0)                        # 人轻松了，速度/跳跃全恢复

# 按公斤把重量换成"这一趟会被罚成什么样"。拿起/放下各算一次，跑起来只读缓存
func _应用负重(公斤: float) -> void:
	_负重公斤 = 公斤
	_负重档名 = "空手" if 公斤 <= 0.0 else 重量档位.档位全名(公斤)
	var 档: Dictionary = 重量档位.空手() if 公斤 <= 0.0 else 重量档位.取(公斤)
	_移速倍率 = float(档["移速倍率"])
	_跳跃高度倍率 = float(档["跳跃高度倍率"])
	_可否慢走 = bool(档["可否慢走"])
	_可否攀爬 = bool(档["可否攀爬"])
	_拖行 = bool(档["拖行"])

# 抱在胸前还是拖在脚边？看档位表里的「拖行」
func _扛着的位置() -> Vector2:
	return DRAG_OFFSET if _拖行 else CARRY_OFFSET

# 给左上角调试面板看的：现在扛着几公斤、被罚成什么样
func 负重说明() -> String:
	if _carry_state == CarryState.EMPTY:
		return "空手"
	return "%s %.0fkg｜速度 %d%%｜%s｜%s" % [
		_负重档名,
		_负重公斤,
		roundi(_移速倍率 * 100.0),
		"能跳" if _跳跃高度倍率 >= 1.0 else ("跳一半高" if _跳跃高度倍率 > 0.0 else "不能跳"),
		"能爬梯" if _可否攀爬 else "不能爬梯",
	]

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
