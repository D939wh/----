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

# ── 门（2026-11-04）：开门属于场景，我只负责说一句「我要推它」 ──────
# 我身上**没有**「开门要几秒」这个数，也不需要门回话给我。
# 门的时长在 数据/楼层清单.gd 里按「这扇门 + 谁在推」配好；
# 门开够了自己撤掉挡路的碰撞体，我走过去了 —— 这就是我得到的全部反馈。

# ── W2D2 · 血量与瘫痪（2026-11-04）────────────────────────────
# 策划案：学生 2 格血；被挥击打中掉 1 格；两格打空 → 瘫痪（蹲地）。
# 瘫痪的学生：不能动、不能交互，能被宿管按住 G 读条 1.2 秒扛起来搬走。
# 扛在宿管肩上时：不吃键盘（宿管替我按方向键）、跟着走、位置由宿管定。
# 素材后面会换，现在「瘫痪」先用 变红+半透明 占位（红得像被打青了一样）。
const MAX_HP: int = 2                      # 血量上限（格子数，不是小数）
const 瘫痪变色 := Color(1.0, 0.35, 0.35, 0.6)  # 占位色：红 + 半透明，等美术素材
const 拉起读条: float = 4.0                 # 拉队友起来要按住多久（策划案 §5：拉起 4s）
const 自救读条: float = 2.0                 # 自己爬起来的时长（11-05 主人定，单机没人救时的兜底）
## 瘫痪时身体换到第 2 层：宿管身体只认第 1 层，跨得过去不会被她绊住；
## 但宿管的感应区（mask 11 = 1+2）照样能看见她，好按 G 扛起来。
## 同学的感应区 mask 也补了 2（从 8 改成 10），所以同学也能看见她、拉她起来。
const 正常碰撞层: int = 1
const 瘫痪碰撞层: int = 2

var 血量: int = MAX_HP                     # 现在还剩几格
var 瘫痪: bool = false                     # 两格打空了？瘫了不能动
var 被扛着: bool = false                    # 现在正被宿管扛在肩上？
var _救人目标: Node = null                 # 正被拉着的瘫倒队友（null = 没在拉）
var _救人进度: float = 0.0                 # 这次按住 H 已经按了多久（秒）
var _自救进度: float = 0.0                 # 瘫在地上按住 H 自己爬了多久


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
	# 场上不止一个学生之后（2026-11-05 加了 student2），道具格是全场共用的一个格子，
	# 谁最后广播就显示谁的。所以「换成我操作」时要主动把**我身上的道具**再喊一遍，
	# 不然点回自己，右下角还挂着上一个人捡的东西。
	Director.control_changed.connect(_on_control_changed)

func _on_control_changed(who: Node) -> void:
	if who == self:
		# 延后一帧再喊：换人时 HUD 会先把格子清空（见 道具格.gd），
		# 我这一嗓子必须在它清完之后到，否则刚补上又被清掉。
		_refresh_item_slot.call_deferred()

func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子（还不算挂着，要看有没有按上下键）

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false   # 离开梯子，爬的记性清零

func _physics_process(delta: float) -> void:
	# ── W2D2 · 瘫痪 / 被扛：这两种情况都不吃键盘 ──────────────
	# 瘫痪 = 蹲在地上动不了；被扛 = 宿管替我走。共同点：不能操作。
	# 但被扛着的时候位置由宿管每帧摆，这里什么都不用做，直接退出。
	if 被扛着:
		return
	if 瘫痪:
		# 瘫了：不吃输入、不能交互，但重力照常——被放下/被搬到空中会自己落到地上
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		else:
			velocity.y = 0.0
		# 只有「玩家现在正在操作我」时才响应 H 自救。
		# 为什么必须判：同屏有第二个学生时（测试复制出来的、将来的 AI 队友），
		# 玩家按一下 H，所有躺着的都会自己爬起来 —— 那就不是自救了，是全体起立。
		if Director.当前控制 == null or Director.当前控制 == self:
			_推进自救(delta)
		move_and_slide()
		return

	# 开发者模式（2026-11-03）：F1 切到宿管身上时，学生原地站住。
	# 不吃键盘，但重力照常 —— 不会浮在半空，也不会自己走路。
	# 这一整段只在「有人接管了控制权」时才起作用，正常单人玩永远是 false。
	if Director.当前控制 != null and Director.当前控制 != self:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	# ── H：救 ──────────────────────────────────────────────
	# 站着按 H = 拉身边瘫倒的队友（按住 4 秒）；瘫着按 H = 自己爬（2 秒，在上面的瘫痪分支里）。
	# 读条期间自己不能动（策划案 §5：拉起期间双方均不可移动）——被拉的那个本来就瘫着动不了。
	if _推进救人(delta):
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		else:
			velocity.y = 0.0
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
# W1D4 · 搬运与道具（W2D2 起按 E/F 分键，见下一段）
# ------------------------------------------------------------

# ============================================================
# W2D2 · 按键分开（2026-11-04）
# ------------------------------------------------------------
# E 和 F 从此各管一件事，不再一个键四件事：
#   E（open_door）   → 只开门。扛着东西不开门（手上没空）
#   F（interaction） → 只搬东西：扛着就放下 → 否则找箱子 → 再找道具
#   Q（use_item）    → 用掉手上的道具（不变）
# 拆开后两件事互不干扰：抱着箱子路过门，按 F 不会误触门，
# 对着门按 F 也不会把箱子举起来。
# ============================================================

# 扛着的箱子跟着人走（轻的抱在胸前，重的拖在脚边）
func _update_interaction() -> void:
	if _carry_state == CarryState.CARRYING and is_instance_valid(_carried):
		_carried.position = _扛着的位置()

	if Input.is_action_just_pressed("open_door"):
		_open_door()

	if Input.is_action_just_pressed("interaction"):
		_pick_or_drop()

	if Input.is_action_just_pressed("use_item") and _item_icon != null:
		_use_item()

# ============================================================
# 【2026-11-04 修架构】我碰了东西，但我不猜那是什么
# ------------------------------------------------------------
# 以前这里写的是「遍历感应区 → 看它在不在 door/carryable 组 → 直接调它的方法」。
# 策划案 §7.6.2 第 2 条点名禁止这种写法，因为它让角色知道了门在哪、箱子长什么样：
#   以后加快递柜、加电闸箱，这个文件就得跟着改一次；
#   以后开第二层楼，同一个文件还要再判断"这是哪层的东西"。
#
# 现在改成：我只把「我身边碰到了哪些东西」原样交出去，一个字都不判断。
# 谁认、谁动手，是楼层代理的事。
#   我 ──"我碰到东西了"+一堆东西──▶ 总管 ──▶ 这一层的代理 ──▶ 门自己开/箱子被扛起
# 从此我的脚本里既没有组名，也没有门的接口；加一百种新家具，我一个字不用改。
# ============================================================

## 我碰到了东西，但不知道那是什么，也轮不到我猜。
## 我把「感应区里有哪些东西」原样交给总管，由楼层代理认。
## 注意：只在按键那一刻上报。_ready 里不能报 —— 那时楼层代理还没登记好，
## 报上去会因为"没这一层"被退回（实测过的坑）。
func _上报交互(键: String) -> void:
	Director.report(
		# 多层时 floor_of() 会返回空字符串（已知技术债，做二楼时再修），
		# 现在只有一层，返回的就是"一楼"。
		Director.floor_of(self),
		"interact",
		{ "谁": self, "键": 键, "碰到": $PickupZone.get_overlapping_areas() }
	)

# E 键：只开门。扛着东西时不开 —— 手上没空（保持拆分前原行为）
# 「扛着东西」是我自己的状态，只有我知道，所以这一句我自己判断；
# 至于"前面到底有没有门"，我不看，交给代理。
func _open_door() -> void:
	if _carry_state == CarryState.CARRYING:
		return
	_上报交互("open_door")

# F 键：只管搬。手上有没有货决定干哪件事：
#   1) 正扛着箱子 → 放下（纯自己的状态 + 换父节点，不涉及"我碰到了什么"）
#   2) 空手 → 把身边的东西报上去，是箱子还是道具由代理认
func _pick_or_drop() -> void:
	if _carry_state == CarryState.CARRYING:
		_drop_box()
		return
	_上报交互("interaction")

# 扛起箱子：变成箱子的父节点，位置摆在身前（超重的拖在地上）
# 从这一行开始，人就被它的重量拖住了 —— 具体罚多少问 `数据/重量档位.gd`
# 【谁调它】楼层代理：代理认出"这是 carryable"之后才喊这一句。
# 学生自己不再调用它，所以从私有（_开头）改成公开。
func 扛起(box: Area2D) -> void:
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
# 【谁调它】楼层代理：代理认出"这是 usable_item"之后才喊这一句。
# 返回 true = 收下了；false = 没手拿（身上已经有一个了）或者这东西没图。
# 为什么"收不下"不报错：玩家对着一个已经拿过道具的人再按一次 F 是很正常的操作，
# 不是故障。让代理拿到 false，以后想加"手上满了"的提示音就有地方接了。
func 收起道具(item: Area2D) -> bool:
	if _item_icon != null:
		return false   # 身上已经有一个了，一格只能放一个
	# 从物件身上找 Sprite2D 取图（不写死子节点名，换个叫法也不会崩）
	var spr := item.get_node_or_null("Sprite2D")
	if spr == null:
		for child in item.get_children():
			if child is Sprite2D:
				spr = child
				break
	if spr == null:
		return false   # 没图就不收，免得收个空道具
	_item_icon = spr.texture
	item.queue_free()                  # 真消耗：地上的东西没了
	_refresh_item_slot()
	return true

# 用道具：今天没有任何效果，只负责消耗掉
func _use_item() -> void:
	_item_icon = null
	_refresh_item_slot()

# 道具格的亮/灭，只看 _item_icon 这一个数据
# 学生只朝「hud」组喊一嗓子（拿到/用掉了什么）；格子怎么亮、摆哪，学生一概不知
func _refresh_item_slot() -> void:
	get_tree().call_group("hud", "set_item", _item_icon)


# ============================================================
# W2D2 · 被打 / 瘫痪 / 被扛（阿姨打人那件事的学生侧）
# ------------------------------------------------------------
# 接口全走「宿管喊一句 → 学生照办」的单向模式（跟门一样）：
#   宿管挥击命中   → 学生.被打中()
#   宿管按 F 扛人  → 学生.被扛起(宿管)
#   宿管再按 F 放下 → 学生.被放下()
# 学生不认识宿管，宿管也不给回执 —— 「我瘫了」「我被扛走了」学生自己知道就够了。
# ============================================================

# ── W2D3 · 救援（2026-11-05）──────────────────────────────────
# 一个键 H 管两件事，按「我自己是什么状态」分：
#   站着 → 拉身边瘫倒的队友（4 秒，策划案 §5）
#   瘫着 → 自己爬起来（2 秒，主人定的兜底：单机没人来救也不能一直躺着）
#
# 为什么救援不走楼层代理：代理管的是「场景里的东西」（门、箱子、电闸箱），
# 而队友是「人」。宿管扛人、挥击也一直是角色直连，这里跟它保持一致。
# 将来「事件中枢」建好了要统一收编，那时再一起搬。
# 策划案 §7.6 那条「不许直接伸手去改别人身上的状态」：这里只对自己和自己的读条动手，
# 被救的那个人由它自己的 拉起() 处理 —— 不是我改它，是它自己站起来。
# ============================================================

## 身边有没有瘫倒的队友。自己不算，被宿管扛在肩上的也不算（那已经不是「在原地瘫着」）
func _贴身瘫痪队友() -> Node:
	for body in $PickupZone.get_overlapping_bodies():
		if body != self and body.has_method("拉起") and body.瘫痪 and not body.被扛着:
			return body
	return null


## 站着按住 H 拉队友。返回「我现在正忙着读条」——调用方据此把人钉在原地
func _推进救人(delta: float) -> bool:
	# 刚按下：就近找一个瘫倒的队友
	if _救人目标 == null:
		if Input.is_action_just_pressed("self_rescue"):
			_救人目标 = _贴身瘫痪队友()
			_救人进度 = 0.0
			if _救人目标 != null:
				print("[学生] 开始拉 %s（按住 %.0f 秒）" % [_救人目标.name, 拉起读条])
			else:
				print("[学生] 身边没有瘫倒的队友")
		if _救人目标 == null:
			return false

	# 松手 → 清零重来
	if not Input.is_action_pressed("self_rescue"):
		_取消救人()
		return false

	# 拉着拉着他没了/不瘫了/被扛走了 → 拉不下去
	if not is_instance_valid(_救人目标) or not _救人目标.瘫痪 or _救人目标.被扛着:
		print("[学生] 救人中断：目标已经不在原地瘫着了")
		_取消救人()
		return false

	_救人进度 += delta
	# 淡黄 = 正在用力拉（没有 HUD 进度条，这是唯一的肉眼反馈）
	$AnimatedSprite2D.modulate = Color(1.0, 1.0, 0.75)
	if _救人进度 >= 拉起读条:
		var 目标 := _救人目标
		_取消救人()      # 先清自己的读条，再让对方站起来
		目标.拉起()
		print("[学生] 拉起来了：%s" % 目标.name)
	return true


## 清掉这次救援：进度归零、颜色还原。不打印，说哪句话由调用方定
func _取消救人() -> void:
	_救人目标 = null
	_救人进度 = 0.0
	$AnimatedSprite2D.modulate = Color.WHITE


## 瘫痪时按住 H：自己爬起来。颜色从「红」慢慢变白就是读条进度
func _推进自救(delta: float) -> void:
	if not Input.is_action_pressed("self_rescue"):
		_自救进度 = 0.0
		if not 被扛着:
			$AnimatedSprite2D.modulate = 瘫痪变色
		return
	_自救进度 += delta
	$AnimatedSprite2D.modulate = 瘫痪变色.lerp(Color.WHITE, minf(_自救进度 / 自救读条, 1.0))
	if _自救进度 >= 自救读条:
		_自救进度 = 0.0
		$AnimatedSprite2D.modulate = Color.WHITE
		拉起()
		print("[学生] 自救成功，自己爬起来了")


## 被挥击打中：掉一格血；两格打空 → 瘫痪（蹲地，素材后面换）
func 被打中() -> void:
	if 瘫痪 or 被扛着:
		return   # 已经瘫了就别再打了；扛着的时候打不着
	_取消救人()   # 正在拉人的时候挨了一下 → 手上的劲散了，读条作废
	血量 -= 1
	if 血量 <= 0:
		_瘫了()

## 两格血打空：变红半透明（占位），从此不能动、不能交互
func _瘫了() -> void:
	瘫痪 = true
	velocity = Vector2.ZERO
	collision_layer = 瘫痪碰撞层   # 瘫在地上，别人能跨过去（不然整条走廊被她堵死）
	$AnimatedSprite2D.modulate = 瘫痪变色
	print("[学生] 我瘫了（%d/%d 格）" % [血量, MAX_HP])

## 被宿管扛起来。宿管喊这一句时，学生 reparent 到宿管名下跟着走。
## 碰撞体一并禁用：不然肩上的学生和宿管两个身体在物理里互相挤，把宿管顶飞。
## 名字写「被扛起」不写「被抓」，因为抓捕读条是宿管那边的事，学生只管被扛起来的结果。
func 被扛起(谁: Node2D) -> void:
	被扛着 = true
	reparent(谁, false)
	_set_collision_disabled(true)

## 被放下：交还给场景，瘫的状态保留（还瘫着，趴在地上）
func 被放下(原父节点: Node) -> void:
	被扛着 = false
	reparent(原父节点, false)
	_set_collision_disabled(false)
	print("[学生] 被放下了（还瘫着）")

## 肩上/落地切换碰撞体。扛着时禁用（不挡宿管的路），放下时恢复（又能被撞见）
func _set_collision_disabled(禁用: bool) -> void:
	var col := get_node_or_null("CollisionShape2D")
	if col != null:
		col.set_deferred("disabled", 禁用)

## 调试/恢复用：把血量补满、解除瘫痪（值班室关押流程出来时用）
func 拉起() -> void:
	血量 = MAX_HP
	瘫痪 = false
	collision_layer = 正常碰撞层   # 站起来又能挡人了
	$AnimatedSprite2D.modulate = Color.WHITE
	print("[学生] 恢复了（%d/%d 格）" % [血量, MAX_HP])
