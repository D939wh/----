# ============================================================
# 参考答案 · 学生（走 + 跳 + 爬 + 搬 + 负重 + 开门 + 三层上报）· v8
# ------------------------------------------------------------
# ⚠️ 本文是 2026-11-04 的存档镜像，**物理层号已经过时**（这里还写着「瘫痪 = 第 2 层」，
#    那是旧层序；2026-11-06 主人重排为：1 地板 / 2 可以穿过的地板 / 3 瘫痪 / 4 梯子 / 5 交互物，
#    位掩码 1 / 2 / 4 / 8 / 16）。
#    **层号一律以 `数据/通用规则.gd` 的五行常量为准，别照这份抄。** 其余逻辑仍可参考。
# ------------------------------------------------------------
# 用途：正式版 `角色/学生/student.gd` 的「带注释镜像」。
#       规矩（主人 2026-10-29 22:48 定）：【代码部分与正式版一致，差异只在注释】。
#       这份写足比喻、调法、门诊表，方便自己照着学；
#       调手感只改正式版，改完把这份同步过来。
#
# ── v8（2026-11-04）这次同步的是「三层架构接线」 ──
#   以前这个文件干了一件错事：角色自己去感应区里翻，看见组名是 door 就直接推门。
#   策划案 §7.6.2 第 2 条点名禁止这种写法，理由是「角色不该知道门在哪」。
#   现在改成：角色只上报「我碰了东西 + 我身边有这些东西」，认东西是楼层代理的事。
#     角色 ──▶ 总管 ──▶ 楼层代理 ──▶ 门自己开 / 箱子被扛起
#   所以这份文件里现在**一个组名都没有**，也**没有门的接口**。
#
# ── 这份文件同时也是「历史书」：下面每一段都标了是哪一版加的 ──
#   v1~v5：走、跳、爬（W1）
#   v6（11-02）：搬箱子、捡道具（W1D4）
#   v7（11-03~04）：重量四档、开门归属场景、F1 换人（W2/W3 起步）
#   v8（11-04）：三层上报（本次）+ 血量瘫痪（W2D2 阿姨打人那件事的学生侧）
#
# 前提（工程里已建好，不用改）：
#   - 输入动作名：left / right / jump / sprint / up / down / open_door(E) / interaction(F) / use_item(Q) / grab(G)
#   - student.tscn 里有 ClimbZone（Area2D，mask 只认 layer 3 = 梯子）
#   - student.tscn 里有 PickupZone（Area2D，mask 只认 layer 4 = 可交互物品，
#     也就是门/箱子/道具都摆在 layer 4 上，感应区才看得见它们）
#   - 道具格独立摆在主场景里、挂在「hud」组，不挂在学生身上
#   - 挂在 CharacterBody2D（角色车身）上
#   - 全局单例 Director（`单例/场景总管.gd`）必须在 project.godot 里登记为 autoload
# ============================================================

extends CharacterBody2D

# ---------- 一、手感旋钮（调手感只动正式版这一段；规矩：一次只动一个数） ----------
# —— 走路：骑自行车 ——
const SPEED: float = 315.0     #速度（常走）
								# 快走全速（像素/秒）。嫌走得慢 → 调大；嫌太赶 → 调小
const ACCEL: float = 1400.0     # 油门（像素/秒²）：起步约 0.2 秒到全速。
								# 起步太肉 → 调大；发飘没分量 → 调小
const FRICTION: float = 1800.0  # 松脚后的刹车（像素/秒²）。
								# 停不住 → 调大；想滑更远 → 调小（重量感旋钮之一）

# —— 按住 Shift：慢走档（2026-10-30 主人定稿）——
# 为什么按住才慢、松手就快：追人的时候"按住才快"会让玩家一直绷着手指，
# 反过来"按住才慢"更符合"潜行"这个动作——紧张的时候你自己就会按住。
const SLOW_SPEED: float = 200.0  # 慢走目标速度。嫌不够慢 → 调小
const SLOW_DECEL: float = 200.0  # 减速快慢：315→200 约 0.6 秒。嫌切换突兀 → 调小
const SPRINT_TIME: float = 0.16   # 冲刺时长（爆发式冲刺已废弃，暂留）
const SPRINT_CD: float = 1.5      # 冲刺冷却（爆发式冲刺已废弃，暂留）
const SPRINT_SPEED: float = 288.0 # 冲刺速度（爆发式冲刺已废弃，暂留）

# —— 跳跃 ——
# 铁律：屏幕 Y 轴朝下！竖直速度 负=向上，正=向下。
# 记不住就记一句："往上跳要给负数"，第一次写跳都会写反这一个。
const GRAVITY: float = 368.0   #跳
								# 重力（像素/秒²）。管上升段减速；
								# 下落由 FALL_GRAVITY_MULT 加倍，别在这里加
const JUMP_VELOCITY: float = -260.0 # 起跳蹬地那一下，负=向上。
									# 跳多高只看它，想高/矮 → 动它（别动重力）
const JUMP_CUT: float = 0.45   # 蹦床泄劲：上升中松手，剩余上冲 ×0.45。
								# 轻点跳太矮 → 调大（试 0.6）；想逼玩家按满 → 调小
const COYOTE_TIME: float = 0.10 # 土狼宽限（秒）：走出平台边缘后还能跳的时限。
								# 边缘按跳没反应 → 调大（0.15）；太大会像"空气跳"
const JUMP_BUFFER: float = 0.12 # 跳跃记账（秒）：落地前按跳先记着，落地自动补。
								# 落地前按跳没接住 → 调大；太大会"没按却跳了"

# 下落专用
# —— 只加快下落（不动跳高）——
const FALL_GRAVITY_MULT: float = 2  # 下落重力 = GRAVITY × 它。主人手拧 1.6→2。
									# 嫌落得慢 → 调大；太快 → 调小。
									# 跳高不受它影响——高度是上升段定的

# 顶点悬停
# —— 顶点悬停（主人手拧 0.25→0.03，基本关掉）——
const HANG_TIME: float = 0.03      # 到顶定格几秒。嫌定格久/假 → 调小；填 0 = 整套关掉
const HANG_VY_BAND: float = 40.0   # 竖直速度小于它就算「到顶了」（一般不动）

# —— 攀爬（电梯式：按住 W 上爬 / S 下爬 / 空格蹬开）——
# 电梯类比：梯子是竖直的走廊，W/S 是上行/下行按钮；不按按钮就停原地（挂住）。
const CLIMB_SPEED: float = 70.0      # 爬梯速度（像素/秒）。嫌慢调大
const CLIMB_OFF_JUMP: float = -180.0 # 梯子上蹬开的初速（比地面跳矮——
									 # 梯子跳主要是横移到旁边平台，不是用来拔高的）

# ---------- 二、"记性"（var 是活的，const 是定死的） ----------
# const = 刻在石头上的数，跑起来改不了；var = 白板上的数，随时擦掉重写。
# 判断该用哪个：这个数一局里会变吗？会变就用 var。
# 攀爬状态：碰到梯子=true；没按过上下键不算挂住
var _on_ladder: bool = false  # 开关：手正摸着梯子吗（ClimbZone 碰到梯子层）
var _climbing: bool = false   # 开关：这一趟真的按过上下键在爬吗（没按过 = 不挂住）

# ── 门（2026-11-04）：开门属于场景，我只负责说一句「我要推它」 ──────
# 我身上**没有**「开门要几秒」这个数，也不需要门回话给我。
# 门的时长在 数据/通用规则.gd 里按「这扇门 + 谁在推」配好；
# 门开够了自己撤掉挡路的碰撞体，我走过去了 —— 这就是我得到的全部反馈。
# 大白话：我不是"自己把门拧开"，我是"按了一下开门的按钮"，剩下的归门。
# 所以这个文件从今天起，连"门"这个字都只在注释里出现，代码里一次不碰。

# ── W2D2 · 血量与瘫痪（2026-11-04）────────────────────────────
# 策划案：学生 2 格血；被挥击打中掉 1 格；两格打空 → 瘫痪（蹲地）。
# 瘫痪的学生：不能动、不能交互，能被宿管按 G 扛起来搬走。
# 扛在宿管肩上时：不吃键盘（宿管替我按方向键）、跟着走、位置由宿管定。
# 素材后面会换，现在「瘫痪」先用 变红+半透明 占位（红得像被打青了一样）。
const MAX_HP: int = 2                      # 血量上限（格子数，不是小数）
const 瘫痪变色 := Color(1.0, 0.35, 0.35, 0.6)  # 占位色：红 + 半透明，等美术素材
## 瘫痪时身体换到第 2 层：宿管身体只认第 1 层，跨得过去不会被她绊住；
## 但宿管的感应区（mask 11 = 1+2）照样能看见她，好按 G 扛起来。
## 什么叫"层"：可以想成地板上叠着的两张透明纸，谁都站在纸上，
## 但只看得见自己那张纸上的东西。瘫痪的人抽到第 2 张纸——从此不挡路，但还摸得着。
const 正常碰撞层: int = 1
const 瘫痪碰撞层: int = 2

var 血量: int = MAX_HP                     # 现在还剩几格
var 瘫痪: bool = false                     # 两格打空了？瘫了不能动
var 被扛着: bool = false                    # 现在正被宿管扛在肩上？


# ── W1D4 搬运与道具 ─────────────────────────────────────────
# 角色状态只分两种：空手 / 负重。别的代码问一句「你现在搬着没」就能分支。
# 以后 W3 加「被逮/蹲地」就往这个 enum 里加值，不用到处加 if。
# 什么叫 enum：给"状态"起名字的清单。EMPTY=0、CARRYING=1，
# 写代码时用名字（好读），机器存的是数字（好算）。
enum CarryState { EMPTY, CARRYING }
var _carry_state: CarryState = CarryState.EMPTY
var _carried: Area2D = null             # 正扛着的那个箱子（空手时是 null）

# 箱子挂在哪儿？两个位置看重量档：轻的抱胸前，重的拖脚边。
# 为什么不用一个数：抱在胸口的箱子如果按拖地的位置摆，会插进人身体里。
const CARRY_OFFSET := Vector2(14, -30)  # 抱在胸前的相对位置（1、2 档）
const DRAG_OFFSET := Vector2(18, -8)    # 拖在脚边的相对位置（3、4 档）

# ── W3 负重（2026-11-03）────────────────────────────────────
# 扛起来之后，人被这件东西的重量拖住：走得慢、跳不高、爬不了梯。
# 「多重算哪一档、每档罚多少」**全在 `数据/重量档位.gd` 那张表里**，
# 这个文件只负责照表执行 —— 想调手感去改表，别改这里。
# 为什么把表单独放一个文件：以后给"蹲地的队友""床板"定重量，
# 不用复制一遍罚款规则；改一次表，全场所有东西跟着变。
# 每帧要用的四个数在拿起/放下时算好存下来，跑起来就不用反复查表了。
const 重量档位 := preload("res://数据/重量档位.gd")

var _负重公斤: float = 0.0        # 扛着的东西多重（空手 = 0）
var _负重档名: String = "空手"    # "1 档" / "2 档" / "3 档" / "4 档" / "空手"
var _移速倍率: float = 1.0        # 目标速度乘它（1 档 0.9 / 2 档 0.6 / 3 档 0.45 / 4 档 0.3）
var _跳跃高度倍率: float = 1.0    # 跳跃**高度**乘它（初速要开根，见起跳那段）
var _可否慢走: bool = true        # 负重时禁 Shift（走得本来就慢，再慢没法玩）
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
	# 向总管报到：我可以被玩家控制。学生先出生，所以默认控制权默认在他身上
	# 这就是 F1 换人能工作的原因——学生不关心谁在按，只管报个到。
	#
	# 【为什么不在这里上报"我碰了东西"】（2026-11-04 踩过的坑）
	#   实测启动顺序是「角色先报到、楼层代理后登记」。在这儿上报，
	#   总管会发现"这一层还没人管"，只能把话退回来（控制台一句黄字警告）。
	#   所以只有按键那一刻上报是安全的 —— 那时候早就过了一帧，代理都在了。
	Director.register_controllable(self)

func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子（还不算挂着，要看有没有按上下键）

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false   # 离开梯子，爬的记性清零

func _physics_process(delta: float) -> void:
	# ── W2D2 · 瘫痪 / 被扛：这两种情况都不吃键盘 ──────────────
	# 瘫痪 = 蹲在地上动不了；被扛 = 宿管替我走。共同点：不能操作。
	# 但被扛着的时候位置由宿管每帧摆，这里什么都不用做，直接退出。
	#
	# 顺序很关键：这一段必须在"读键盘"之前。放后面就等于先让人走了一步、
	# 再宣布她动不了——玩家会看到瘫在地上的人还在滑。
	if 被扛着:
		return
	if 瘫痪:
		# 瘫了：不吃输入、不能交互，但重力照常——被放下/被搬到空中会自己落到地上
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		else:
			velocity.y = 0.0
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

	var dir := Input.get_axis("left", "right")  #左右移动
	var sprint_held := Input.is_action_pressed("sprint")  # 按住 Shift（按住=慢走）
	var updown := Input.get_axis("up", "down")  # W/S：上爬 / 下爬

	# 攀爬：碰到梯子 + 按了上下 → 开始爬（按过才挂住；没按过不会吸在梯子上）
	# 负重爬不了梯：2 档以上一律上不去（`数据/重量档位.gd` 里的「可否攀爬」）
	if _on_ladder and updown != 0.0 and _可否攀爬:
		_climbing = true
	# 已经在梯子上，但中途有人往怀里塞了个重箱子 → 当场挂不住，滑下来。
	# 为什么要单独判一次：上面那个 if 只在新按上下键时才跑，
	# 人可能贴在梯子上不动，这时候状态已经变了，得当场纠正。
	if _climbing and not _可否攀爬:
		_climbing = false   # 手上扛着货，就算已经在梯子上也挂不住
	if _on_ladder and _climbing:
		velocity.y = updown * CLIMB_SPEED   # W 升 S 降；不按键 = 0 = 挂住
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 爬梯时左右刹住，别荡秋千
		# 跳蹬开：从梯子上跳走。不给土狼宽限——不然贴着梯子每帧都"能跳"，会乱
		if Input.is_action_just_pressed("jump"):
			velocity.y = CLIMB_OFF_JUMP
			velocity.x = dir * SPEED * 0.6
			_climbing = false
		move_and_slide()
		return  # 这一帧到梯子为止：不走下面的重力/跳跃/左右——梯子上没重力

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
		# 目标速度 = 基础速度 × 负重倍率。扛着 80kg 纸箱：315 × 0.3 = 94.5
		var target := (SLOW_SPEED if slow_ok else SPEED) * _移速倍率
		var accel := SLOW_DECEL if slow_ok else ACCEL
		# 空中保留助跑：起跳时多快就保持多快，不往回拽（只放行同向超速）
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > target):
			velocity.x = move_toward(velocity.x, dir * target, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 松脚：滑行

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
#
# 为什么当初要拆：一个键干四件事，玩家想"我就想放下箱子"的时候，
# 站位稍偏就会改成推门——不是玩家的错，是一个键背了太多意思。
# ============================================================

# 扛着的箱子跟着人走（轻的抱在胸前，重的拖在脚边）
func _update_interaction() -> void:
	# 箱子已经"认人做爹"了（reparent 到学生节点下），
	# 这里每帧把它的相对位置摆回去——人走到哪，箱子跟到哪。
	# 位置不是写死的：问 _扛着的位置()，它会看当前档位是"抱"还是"拖"。
	if _carry_state == CarryState.CARRYING and is_instance_valid(_carried):
		_carried.position = _扛着的位置()

	if Input.is_action_just_pressed("open_door"):
		_open_door()

	if Input.is_action_just_pressed("interaction"):
		_pick_or_drop()

	# 用道具：只有身上真带着东西才响应（_item_icon != null）
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
#
# 用生活里的话说：
#   以前我是"看见红色的东西就拉"的门卫——你得先教会我认红色；
#   现在我是"喊一嗓子'门口有东西'"的传话人——认东西的人是楼长，
#   楼长换人、加新东西，我都不用重新培训。
# ============================================================

## 我碰到了东西，但不知道那是什么，也轮不到我猜。
## 我把「感应区里有哪些东西」原样交给总管，由楼层代理认。
## 注意：只在按键那一刻上报。_ready 里不能报 —— 那时楼层代理还没登记好，
## 报上去会因为"没这一层"被退回（实测过的坑）。
##
## 这个函数只干三件事，都是"照抄"而不是"判断"：
##   1. 问总管我在哪一层
##   2. 说一句"我按了交互键"
##   3. 把感应区里的东西原样打包（我自己一个都不看）
func _上报交互(键: String) -> void:
	Director.report(
		# 我在哪一层：问总管。单层地图直接就是那层；多层按「层带」查，
		# 掉在两层之间时给最近的一层 —— 不会返回空串（详见 场景总管.gd 的 floor_of）。
		Director.floor_of(self),
		"interact",
		{ "谁": self, "键": 键, "碰到": $PickupZone.get_overlapping_areas() }
	)
	# get_overlapping_areas() = "现在圈里有哪些东西"（名单现查，不用自己维护）
	# 注意：它交出去的是"一堆东西"，不是"一个门"。判断权在代理手里。

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
#
# 为什么改名字：以前叫 _pick_up_box，_ 开头的意思是"只有我自己能用"。
# 现在真正喊这句话的人变成了代理，所以名字要去掉 _，
# 顺便换成中文「扛起」——这个文件里凡是给自己看的活都写中文，
# 一眼就知道是游戏里的动作，不是引擎的概念。
func 扛起(box: Area2D) -> void:
	_carried = box
	_carry_state = CarryState.CARRYING   # 状态切换：空手 → 负重（这就是"两个状态"）
	# 问箱子多重。为什么不写 box.取重量()：万一遇到没这个方法的物件（比如以后
	# 一个能搬的凳子忘了写），has_method 兜一下，当 0 公斤处理，不至于整个游戏崩掉。
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
	_carry_state = CarryState.EMPTY      # 状态切换：负重 → 空手
	box.reparent(get_parent(), false)     # 交还给场景
	# 学生自己的原点就在脚底（碰撞体从 -44 到 0），所以这里减一个箱子的半高就贴地了
	# 减多了箱子会沉进地板，减少了会浮在半空再掉一下。
	box.global_position = global_position + Vector2(18, -12)
	if box.has_method("设被扛着"):
		box.设被扛着(false)               # 从这里开始它自己受重力
	_应用负重(0.0)                        # 人轻松了，速度/跳跃全恢复

# 按公斤把重量换成"这一趟会被罚成什么样"。拿起/放下各算一次，跑起来只读缓存
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

# 抱在胸前还是拖在脚边？看档位表里的「拖行」
# 1、2 档抱着（还能走能动），3、4 档拖着（贴着地面，蹭出声）。
func _扛着的位置() -> Vector2:
	return DRAG_OFFSET if _拖行 else CARRY_OFFSET

# 给左上角调试面板看的：现在扛着几公斤、被罚成什么样
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
# 【谁调它】楼层代理：代理认出"这是 usable_item"之后才喊这一句。
# 返回 true = 收下了；false = 没手拿（身上已经有一个了）或者这东西没图。
# 为什么"收不下"不报错：玩家对着一个已经拿过道具的人再按一次 F 是很正常的操作，
# 不是故障。让代理拿到 false，以后想加"手上满了"的提示音就有地方接了。
#
# 【返回值是什么，为什么要有】大白话：函数干完活，回头告诉你一句"成了没"。
#   以前它什么都不说（-> void），代理只能猜；
#   现在它会回答 true / false，代理就能决定要不要"叮"一声提示玩家。
#   加了返回值不会弄坏别的地方：不想听答案的人（比如原来那个直接调用的写法）
#   照样能不理它——答案说了，听不听是调用方的自由。
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
	_item_icon = null                  # 图没了 = 道具没了
	_refresh_item_slot()

# 道具格的亮/灭，只看 _item_icon 这一个数据
# 有图 → 显示；没图 → 隐藏。改道具系统时只动这一个数据，UI 自己会跟
#
# 【2026-11-02 搬家】道具格不再长在学生身上（那是搭错了：UI 属于界面，不属于角色）。
# 现在道具格独立摆在主场景里，学生只朝「hud」组喊一嗓子（广播站喊话）：
#   拿到/用掉了什么我不管你怎么显示——hud 组里的界面听到，自己亮格/灭格。
# 铁律「发的人不知道谁在听」：学生不认识界面，界面也不认识学生。
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
#
# 【为什么这一段这次没改成"上报"】（2026-11-04 决定）
#   这一段是"角色对角色"（谁打了我、谁扛起我），不是"角色碰场景"（门/箱子/道具）。
#   三层架构要收编它，得先有"事件中枢"，那时候再统一改。
#   现在动它，会把刚验收过的打人系统弄崩——优先级要分清楚。
# ============================================================

## 被挥击打中：掉一格血；两格打空 → 瘫痪（蹲地，素材后面换）
func 被打中() -> void:
	if 瘫痪 or 被扛着:
		return   # 已经瘫了就别再打了；扛着的时候打不着
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
