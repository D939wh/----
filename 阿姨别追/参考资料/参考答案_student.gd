# ============================================================
# 参考答案 · 学生（走 + 跳 + 爬 + 搬 + 负重 + 开门）· v7
# ------------------------------------------------------------
# 用途：正式版 `角色/学生/student.gd` 的「带注释镜像」。
#       【代码部分与正式版完全一致，一个字不差】（主人 2026-10-29 22:48 定的规矩）；
#       差异只在注释：这份写足比喻、调法、门诊表。
#       调手感只改正式版，改完把这份同步过来。
#
# v7（2026-11-04）同步「重量四档 + 开门 + 换人」：
#   1) 负重不再只是"空手/负重"两种状态。扛起来之后按公斤分 1~4 档，
#      罚多少去 `数据/重量档位.gd` 那张表查——这个文件一个数字都不写死。
#   2) 跳高按档位打折：初速要开平方根。因为「高度 ∝ 初速²」，
#      想砍掉一半高度，初速只需乘 √0.5（约 0.71），不是乘 0.5。
#   3) 开门：E 打门，谁按谁接管。学生手快（0.3 秒开满），宿管手慢（1.5 秒）。
#   4) F1 换人：控制权被别人拿走时，学生原地站住——不吃键盘，但重力照常。
#
# v6（2026-11-02）同步 W1D4：E = 拿起 / 放下 / 捡道具；右键 = 用道具。
#
# 前提（工程里已建好，不用改）：
#   - 输入动作名：left / right / jump / sprint / up / down / interaction(E) / use_item(Q)
#   - student.tscn 里有 ClimbZone（Area2D，mask 只认 layer 3 = 梯子）
#   - student.tscn 里有 PickupZone（Area2D，mask 只认 layer 4 = 可交互物品）
#   - 道具格独立摆在主场景里、挂在「hud」组，不挂在学生身上
#   - 挂在 CharacterBody2D（角色车身）上
# ============================================================

extends CharacterBody2D

# ---------- 一、手感旋钮（调手感只动正式版这一段；规矩：一次只动一个数） ----------
# —— 走路：骑自行车 ——
const SPEED: float = 315.0      # 快走全速（像素/秒）。嫌走得慢 → 调大；嫌太赶 → 调小
const ACCEL: float = 1400.0     # 油门（像素/秒²）：起步约 0.2 秒到全速。
								# 起步太肉 → 调大；发飘没分量 → 调小
const FRICTION: float = 1800.0  # 松脚后的刹车（像素/秒²）。
								# 停不住 → 调大；想滑更远 → 调小（重量感旋钮之一）

# —— 按住 Shift：慢走档（2026-10-30 主人定稿）——
const SLOW_SPEED: float = 200.0  # 慢走目标：按住 Shift 减到这。嫌不够慢 → 调小
const SLOW_DECEL: float = 200.0  # 减速快慢：315→200 约 0.6 秒。嫌切换突兀 → 调小
const SPRINT_TIME: float = 0.16   # 冲刺时长（爆发式冲刺已废弃，暂留）
const SPRINT_CD: float = 1.5      # 冲刺冷却（爆发式冲刺已废弃，暂留）
const SPRINT_SPEED: float = 288.0 # 冲刺速度（爆发式冲刺已废弃，暂留）

# —— 跳跃 ——
# 铁律：屏幕 Y 轴朝下！竖直速度 负=向上，正=向下。
const GRAVITY: float = 368.0         # 重力（像素/秒²）。管上升段减速。
									 # 注意：它只管上升；下落由 FALL_GRAVITY_MULT 加倍
const JUMP_VELOCITY: float = -260.0  # 起跳蹬地那一下，负=向上。
									 # 跳多高只看它，想高/矮 → 动它（别动重力）
const JUMP_CUT: float = 0.45         # 蹦床泄劲：上升中松手，剩余上冲 ×0.45。
									 # 轻点跳太矮 → 调大（试 0.6）；想逼玩家按满 → 调小
const COYOTE_TIME: float = 0.10      # 土狼宽限（秒）：走出边缘后还能跳的时限。
									 # 边缘按跳没反应 → 调大（0.15）；太大会像"空气跳"
const JUMP_BUFFER: float = 0.12      # 跳跃记账（秒）：落地前按跳先记着，落地自动补。
									 # 落地前按跳没接住 → 调大；太大会"没按却跳了"

# —— 只加快下落（不动跳高）——
const FALL_GRAVITY_MULT: float = 2   # 下落重力 = GRAVITY × 它。主人手拧 1.6→2。
									 # 嫌落得慢 → 调大；太快 → 调小。
									 # 跳高不受它影响——高度是上升段定的

# —— 顶点悬停（主人手拧 0.25→0.03，基本关掉）——
const HANG_TIME: float = 0.03      # 到顶定格几秒。嫌定格久/假 → 调小；填 0 = 整套关掉
const HANG_VY_BAND: float = 40.0   # 竖直速度小于它就算「到顶了」（一般不动）

# —— 攀爬（电梯式：按住 W 上爬 / S 下爬 / 空格蹬开）——
# 电梯类比：梯子是竖直的走廊，W/S 是上行/下行按钮；不按按钮就停原地（挂住）。
const CLIMB_SPEED: float = 70.0      # 爬梯速度（像素/秒）。嫌慢 → 调大
const CLIMB_OFF_JUMP: float = -180.0 # 梯子上蹬开的初速（比地面跳矮——
									 # 梯子跳主要是横移到旁边平台，不是用来拔高的）

# ---------- 二、"记性"（var 是活的，const 是定死的） ----------
# 攀爬的记性
var _on_ladder: bool = false  # 开关：手正摸着梯子吗（ClimbZone 碰到梯子层）
var _climbing: bool = false   # 开关：这一趟真的按过上下键在爬吗（没按过 = 不挂住）

# ── W1D4 搬运与道具（2026-11-02 新增）──
# 生活比喻：手上有没有东西，是"你这个人现在处于什么姿态"。
# 空手的你和抱着箱子的你，是两个不同的人——别的代码问你一句
# 「现在空手还是负重」就能决定"这场能不能爬梯子、跑多快"。
# 这就是状态机的种子：一个 enum（状态清单）记住"我现在是哪种人"。
enum CarryState { EMPTY, CARRYING }
var _carry_state: CarryState = CarryState.EMPTY  # 现在：空手（EMPTY=0）/ 负重（CARRYING=1）
var _carried: Area2D = null             # 正扛着的那个箱子（空手时是 null）

# 箱子挂在哪儿？两个位置看重量档：轻的抱胸前，重的拖脚边。
# 为什么不用一个数：抱在胸口的箱子如果按拖地的位置摆，会插进人身体里。
const CARRY_OFFSET := Vector2(14, -30)  # 抱在胸前的相对位置（1、2 档）
const DRAG_OFFSET := Vector2(18, -8)    # 拖在脚边的相对位置（3、4 档）

# ── W3 负重（2026-11-03）────────────────────────────────────
# 扛起来之后，人被这件东西的重量拖住：走得慢、跳不高、爬不了梯。
# 「多重算哪一档、每档罚多少」全在 `数据/重量档位.gd` 那张表里，
# 这个文件只负责照表执行 —— 想调手感去改表，别改这里。
# 为什么把表单独放一个文件：以后给"蹲地的队友""床板"定重量，
# 不用复制一遍罚款规则；改一次表，全场所有东西跟着变。
# 每帧要用的数在拿起/放下时算好存下来，跑起来就不用反复查表了。
const 重量档位 := preload("res://数据/重量档位.gd")

var _负重公斤: float = 0.0        # 扛着的东西多重（空手 = 0）
var _负重档名: String = "空手"    # "1 档" / "2 档" / "3 档" / "4 档" / "空手"
var _移速倍率: float = 1.0        # 目标速度乘它（1 档 0.9 / 2 档 0.6 / 3 档 0.45 / 4 档 0.3）
var _跳跃高度倍率: float = 1.0    # 跳跃「高度」乘它。注意是先算高度、再开根变成初速
var _可否慢走: bool = true        # 2 档以上禁 Shift（走得本来就慢，再慢就没法玩了）
var _可否攀爬: bool = true        # 2 档以上爬不了梯（双手抱着货，抓不住梯子）
var _拖行: bool = false           # 只能拖在地上走（决定箱子挂胸前还是脚边）

# 道具格：null = 身上没东西；有图 = 有道具（右下角格子亮）
# 为什么用"图"当开关：格子亮不亮完全由数据说了算——
# 有图就亮、没图就灭，不是"提前藏一张固定的图再显示出来"（那是作弊写法）
var _item_icon: Texture2D = null

# 移动的老记性
var _coyote: float = 0.0       # 秒表① 土狼：离地后还能跳的宽限还剩多少
var _buffer: float = 0.0       # 秒表② 缓冲："想跳"这笔账还能记多久
var _sprint_left: float = 0.0  # 秒表③ 冲刺：这一下还剩多久（废弃冲刺遗留）
var _sprint_dir: float = 0.0   # 方向记性：这一下朝哪边（废弃冲刺遗留）
var _sprint_cd: float = 0.0    # 秒表④ 喘气：归 0 才能再冲（废弃冲刺遗留）
var _hang_left: float = 0.0    # 秒表⑤ 定格：顶点停滞还剩多久（0=没在定格）
var _fast_fall: bool = false   # 开关：定格结束后正处于快落中

# ---------- 手感门诊表：哪里不舒服 → 拧哪个旋钮 ----------
# （规矩：一次只动一个数，改完跑一遍记一句感受，再动下一个）
#   起步太肉 ............ ACCEL ↑
#   说停停不住 .......... FRICTION ↑
#   走太慢 .............. SPEED ↑
#   慢走不够慢 .......... SLOW_SPEED ↓
#   按 Shift 切换太突兀 .. SLOW_DECEL ↓
#   跳太矮 .............. JUMP_VELOCITY ↑（别动重力）
#   轻点跳太矮 .......... JUMP_CUT ↑
#   出边缘跳没反应 ...... COYOTE_TIME ↑
#   落地前按跳没接住 .... JUMP_BUFFER ↑
#   下落还是慢/拖 ....... FALL_GRAVITY_MULT ↑
#   落得太狠像砸 ........ FALL_GRAVITY_MULT ↓
#   顶点定格太久/嫌假 ... HANG_TIME ↓（0=整套关掉）
#   爬梯太慢 ............ CLIMB_SPEED ↑
#   梯子上蹬跳太矮 ...... CLIMB_OFF_JUMP ↑（负更多）
#   箱子挂在身前太远/太近 CARRY_OFFSET 的 x ↑↓
#   扛东西走得太快/太慢 .. 改 数据/重量档位.gd 的「移速倍率」，别改这里
#   扛东西还能跳 ......... 改 数据/重量档位.gd 的「跳跃高度倍率」= 0
#   扛东西还能爬梯 ....... 改 数据/重量档位.gd 的「可否攀爬」= false
# ----------------------------------------------------------------

func _ready() -> void:
	# 抓梯感应区：ClimbZone（Area2D）碰到梯子层（layer 3）就算「摸到梯子」。
	# 信号 = 电话铃：ClimbZone 一碰/一离开，就打给下面两个接电话的函数。
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)
	# 向总管报到：我可以被玩家控制。
	# 学生先出生，所以开局的控制权默认落在他身上（谁后报到谁接管）。
	# 这就是 F1 换人能工作的原因——学生不关心谁在按，只管报个到。
	Director.register_controllable(self)

func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子（还不算挂着，要看有没有按上下键）

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false   # 离开梯子，爬的记性清零

func _physics_process(delta: float) -> void:
	# ---- 开发者模式（2026-11-03）：F1 把控制权交给别人时，学生原地站住 ----
	# 两条路：要么被宿管接管，要么以后被"被抓/剧情"接管，都走这一段。
	# 注意这里**不吃键盘**（没读 Input），但重力照常加：
	#   - 不读键盘 → 别人在按方向键，学生不会跟着走
	#   - 重力照常 → 不会浮在半空，该掉还是掉
	# 正常单人玩的时候，当前控制永远是自己，这段一次都不会进来。
	if Director.当前控制 != null and Director.当前控制 != self:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	var dir := Input.get_axis("left", "right")  # 方向盘：右=1 左=-1 不按=0
	var sprint_held := Input.is_action_pressed("sprint")  # 按住 Shift？（按住=慢走）
	var updown := Input.get_axis("up", "down")  # 竖梯的方向盘：W=+1 上 S=-1 下

	# ---- 0. 攀爬分支：整个梯子世界，走完就 return，跳过下面全部 ----
	# 贴在梯子上 + 按了上下 → 开始爬（按过才挂住；没按过不会吸在梯子上）
	# 第三个条件是负重：2 档以上 _可否攀爬 = false，双手抱着货抓不住梯子。
	if _on_ladder and updown != 0.0 and _可否攀爬:
		_climbing = true
	# 已经在梯子上，但中途有人往怀里塞了个重箱子 → 当场挂不住，滑下来。
	# 为什么要单独判一次：上面那个 if 只在新按上下键时才跑，
	# 人可能贴在梯子上不动，这时候状态已经变了，得当场纠正。
	if _climbing and not _可否攀爬:
		_climbing = false
	if _on_ladder and _climbing:
		velocity.y = updown * CLIMB_SPEED   # 电梯：W 升 S 降；不按键 = 0 = 挂住
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 爬梯时左右刹住，别荡秋千
		# 跳蹬开：从梯子上跳走。不给土狼宽限——不然贴着梯子每帧都"能跳"，会乱
		if Input.is_action_just_pressed("jump"):
			velocity.y = CLIMB_OFF_JUMP       # 蹬一下（比地面跳矮）
			velocity.x = dir * SPEED * 0.6    # 顺按住的方向横移（0.6 = 别荡太远）
			_climbing = false                 # 跳走这一瞬手松开梯子
		move_and_slide()
		return  # 这一帧到梯子为止：不走下面的重力/跳跃/左右——梯子上没重力

	# ---- W1D4：交互（E 拿起/放下/开门、右键用道具）----
	# 为什么放在攀爬之后：梯子上不做交互（双手抓着梯子），
	# 这也是和 D3 一样的"两个世界"分界——攀爬分支上面 return 了，走不到这
	_update_interaction()

	# ---- 1. 重力（三分支：定格中 / 刚到顶 / 正常）----
	# 抛橡皮的弧线升级版：冲上去 → 顶点定格一拍（重力归零）→ 倍数快落砸下来
	if not is_on_floor():
		if _hang_left > 0.0:
			# 定格中：重力归零，飘在顶点把秒表⑤走完
			_hang_left = maxf(_hang_left - delta, 0.0)
			if _hang_left <= 0.0:
				_fast_fall = true             # 定格结束：这一跳剩下的路全按快落走
		elif absf(velocity.y) < HANG_VY_BAND and not _fast_fall:
			_hang_left = HANG_TIME            # 刚到顶：定格开始
		else:
			# 正常上升/下落；快落中重力翻倍
			velocity.y += GRAVITY * (FALL_GRAVITY_MULT if _fast_fall else 1.0) * delta
	else:
		_fast_fall = false                    # 落地：开关复位，下一跳从头来

	# ---- 2. 四只老秒表：在地上/刚按下就回满，否则每帧减到 0 为止 ----
	_coyote = COYOTE_TIME if is_on_floor() else maxf(_coyote - delta, 0.0)
	_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else maxf(_buffer - delta, 0.0)
	_sprint_cd = maxf(_sprint_cd - delta, 0.0)

	# ---- 3. 起跳：账上有"想跳"（②>0）且宽限还在（①>0）→ 蹬地！----
	# 第三个条件是负重：4 档的「跳跃高度倍率」= 0，直接跳不起来。
	if _buffer > 0.0 and _coyote > 0.0 and _跳跃高度倍率 > 0.0:
		# 为什么要开根号：高度 h ∝ 初速 v²（物理公式，跑不掉）。
		# 想让高度变成原来的一半，v 要乘 √0.5 ≈ 0.71，不是乘 0.5。
		# 乘 0.5 的话高度只剩四分之一——跳起来像脚被粘住了，手感会很怪。
		velocity.y = JUMP_VELOCITY * sqrt(_跳跃高度倍率)
		_buffer = 0.0
		_coyote = 0.0
		_hang_left = 0.0    # 新跳清掉上一跳的定格/快落
		_fast_fall = false  # （不清的话：上一跳的快落会把这一跳拽矮）

	# ---- 4. 可变跳高：上升中松开空格 → 蹦床泄劲，矮跳 ----
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	# ---- 5. 冲刺起手（已废弃：点按爆发删掉了，三常量暂留备复活）----
	# if Input.is_action_just_pressed("sprint") and _sprint_cd <= 0.0 and dir != 0.0:
	# 	_sprint_left = SPRINT_TIME
	# 	_sprint_dir = dir
	# 	_sprint_cd = SPRINT_CD

	# ---- 6. 左右速度：冲刺段(废弃，空转) > 慢走 > 快走 > 刹停 ----
	if _sprint_left > 0.0:
		_sprint_left -= delta
		velocity.x = _sprint_dir * SPRINT_SPEED       # 冲刺：直接满速（现在永远走不到这）
	elif dir != 0.0:
		# 按住 Shift = 慢走；松手 = 快走。
		# 慢走还要三个条件：踩在地上（空中不许减速）、负重允许（2 档以上禁）。
		var slow_ok := sprint_held and is_on_floor() and _可否慢走
		# 目标速度 = 基础速度 × 负重倍率。扛着 80kg 纸箱：315 × 0.3 = 94.5
		var target := (SLOW_SPEED if slow_ok else SPEED) * _移速倍率
		var accel := SLOW_DECEL if slow_ok else ACCEL
		# 空中保留助跑：起跳时多快就保持多快，不往回拽（只放行同向超速）
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > target):
			velocity.x = move_toward(velocity.x, dir * target, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 松脚：滑行

	# ---- 7. 挂挡 ----
	move_and_slide()

# ============================================================
# 搬运与道具（W1D4）+ 负重与开门（W3）
# ------------------------------------------------------------
# 交互键 E 一件事分四步走（先看手上有没有东西、再依次看门前有什么）：
#   1) 正扛着箱子 → 放下
#   2) 附近有门     → 推门（谁按谁接管，学生快、宿管慢）
#   3) 附近有箱子   → 扛起来（状态变 CARRYING，同时按重量罚）
#   4) 附近有道具   → 捡进右下角格子
# 右键单独管"用道具"：消耗掉、格子变空。今天用掉没有任何效果。
# ============================================================

func _update_interaction() -> void:
	# 扛着的箱子跟着人走。
	# 箱子已经"认人做爹"了（reparent 到学生节点下），
	# 这里每帧把它的相对位置摆回去——人走到哪，箱子跟到哪。
	# 位置不是写死的：问 _扛着的位置()，它会看当前档位是"抱"还是"拖"。
	if _carry_state == CarryState.CARRYING and is_instance_valid(_carried):
		_carried.position = _扛着的位置()

	if Input.is_action_just_pressed("interaction"):
		_interact()

	# 右键用道具：只有身上真带着东西才响应（_item_icon != null）
	if Input.is_action_just_pressed("use_item") and _item_icon != null:
		_use_item()

# E 键：按上面四步走
func _interact() -> void:
	# 第一步：手上正扛着 → 放下（不管旁边有什么，先把手腾出来）
	if _carry_state == CarryState.CARRYING:
		_drop_box()
		return

	# 第二步：门排在最前——门挡着路的时候先处理门。
	# 为什么门比箱子优先：扛着东西本来就走不快，要是被门卡住还开不了，
	# 玩家会觉得"这游戏坏了"。所以门永远第一个响应。
	# 谁按谁接管这扇门。开多快不归我管，也不挂在人身上 ——
	# 门的时长写在 数据/楼层清单.gd（每扇门可以不一样），门自己查表、自己开。
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("door"):
			var door: Node = area.get_parent()
			# 不写死节点类型，只问"你会不会 press"——以后加个电闸箱、快递柜，
			# 只要它有 press 方法，这一个循环就能用，不用改这里。
			if door != null and door.has_method("press"):
				door.press(self)
			return

	# 第三步/第四步：空手时看感应区里有什么
	# get_overlapping_areas() = "现在圈里有哪些东西"（名单现查，不用自己维护）
	# 先找可搬运的：箱子优先（箱子是大事，道具是小事）
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("carryable"):
			_pick_up_box(area)
			return
	# 再找可使用的：身上已经带着道具就不收了（一格只能放一个）
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("usable_item") and _item_icon == null:
			_pick_up_item(area)
			return

# 扛起箱子：变成箱子的父节点，位置摆在身前（超重的拖在地上）
# 从这一行开始，人就被它的重量拖住了——具体罚多少去问表，这里不算数。
func _pick_up_box(box: Area2D) -> void:
	_carried = box
	_carry_state = CarryState.CARRYING   # 状态切换：空手 → 负重（这就是"两个状态"）
	# 问箱子多重。为什么不写 box.取重量()：万一遇到没这个方法的物件（比如以后
	# 一个能搬的凳子忘了写），has_method 兜一下，当 0 公斤处理，不至于整个游戏崩掉。
	_应用负重(box.取重量() if box.has_method("取重量") else 0.0)
	if box.has_method("设被扛着"):
		box.设被扛着(true)                # 告诉它：别自己往下掉了
	_climbing = false                     # 双手被占，梯子爬不了
	box.reparent(self, false)             # 认人做爹：从此跟着人走
	box.position = _扛着的位置()          # 摆到胸前 / 脚边

# 放下箱子：还回场景里，落在脚边，然后它自己受重力落到地面
func _drop_box() -> void:
	var box := _carried
	_carried = null
	_carry_state = CarryState.EMPTY      # 状态切换：负重 → 空手
	box.reparent(get_parent(), false)    # 交还给场景（不再跟着人走）
	# 学生自己的原点就在脚底（碰撞体从 -44 到 0），所以这里减一个箱子的半高就贴地了。
	# 减多了箱子会沉进地板，减少了会浮在半空再掉一下。
	box.global_position = global_position + Vector2(18, -12)
	if box.has_method("设被扛着"):
		box.设被扛着(false)               # 从这里开始它自己受重力
	_应用负重(0.0)                        # 人轻松了，速度/跳跃全恢复

# 按公斤把重量换成"这一趟会被罚成什么样"。
# 拿起/放下各算一次，跑起来只读缓存 —— 每帧查表虽然也不慢，但没必要。
func _应用负重(公斤: float) -> void:
	_负重公斤 = 公斤
	# 档位全名：给人看的，会带「档」字（"4 档"）；纯数字档号给程序判断用。
	_负重档名 = "空手" if 公斤 <= 0.0 else 重量档位.档位全名(公斤)
	# 空手不是"没有档"，是一张全部 1 倍的虚拟档。
	# 这样下面的代码不用先判"有没有扛东西"，直接读表就行，少一层 if。
	var 档: Dictionary = 重量档位.空手() if 公斤 <= 0.0 else 重量档位.取(公斤)
	_移速倍率 = float(档["移速倍率"])
	_跳跃高度倍率 = float(档["跳跃高度倍率"])
	_可否慢走 = bool(档["可否慢走"])
	_可否攀爬 = bool(档["可否攀爬"])
	_拖行 = bool(档["拖行"])

# 抱在胸前还是拖在脚边？看档位表里的「拖行」。
# 1、2 档抱着（还能走能动），3、4 档拖着（贴着地面，蹭出声）。
func _扛着的位置() -> Vector2:
	return DRAG_OFFSET if _拖行 else CARRY_OFFSET

# 给左上角调试面板看的：现在扛着几公斤、被罚成什么样。
# 这一行是"人话版"的档位表：扛 80kg 会显示
#   「4 档 80kg｜速度 30%｜不能跳｜不能爬梯」
# 调试面板每帧调它一次，所以这里只做字符串拼接，不做任何判断副作用。
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
	item.queue_free()                  # 真消耗：地上的东西没了（不是藏起来）
	_refresh_item_slot()

# 用道具：今天没有任何效果，只负责消耗掉
func _use_item() -> void:
	_item_icon = null                  # 图没了 = 道具没了
	_refresh_item_slot()

# 道具格的亮/灭，只看 _item_icon 这一个数据
# 有图 → 显示；没图 → 隐藏。改道具系统时只动这一个数据，UI 自己会跟
#
# 【2026-11-02 搬家】道具格不再长在学生身上（那是搭错了：UI 属于界面，不属于角色）。
# 现在道具格独立摆在主场景里，学生只朝「hud」组喊一嗓子（广播站喊话）：
#   拿到/用掉了什么我不管你怎么显示——hud 组里的界面听到，自己亮格/灭格。
# 铁律「发的人不知道谁在听」：学生不认识界面，界面也不认识学生。
# 换布局、加宿管的危险度环，学生这行代码一个字不用动。
func _refresh_item_slot() -> void:
	get_tree().call_group("hud", "set_item", _item_icon)
