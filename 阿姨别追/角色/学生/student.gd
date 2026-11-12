extends CharacterBody2D

## 学生 —— 玩家操作的角色。
##
## 本文件只放：物理常量、状态机拼装、跨状态延续的记性、对外接口。
## 每个行为模式的具体逻辑在 `角色/学生/状态/` 下，一个状态一个脚本。

## 全工程规则（物理层位掩码、下穿时长、开门用时等）。
## 放在文件最前面：下面的常量要引用它的位掩码，GDScript 常量从上往下求值。
const 规则 := preload("res://数据/通用规则.gd")
## 声音档位与半径表（主人 2026-11-09 定：四档）。
## 发声音只传「第几档」，半径由表算 —— 别在这里另写一个数。
const 声音表 := preload("res://数据/声音表.gd")

# ── 状态机 ───────────────────────────────────────────────────
# 状态名常量集中在 状态名.gd（拼错就报红，不会运行时才崩）。
const 状态名 := preload("res://角色/学生/状态/状态名.gd")
const 状态机 := preload("res://组件/状态机/状态机.gd")
const 正常状态 := preload("res://角色/学生/状态/正常.gd")
const 攀爬状态 := preload("res://角色/学生/状态/攀爬.gd")
const 插钥匙状态 := preload("res://角色/学生/状态/插钥匙中.gd")
const 救人状态 := preload("res://角色/学生/状态/救人中.gd")
const 瘫痪状态 := preload("res://角色/学生/状态/瘫痪.gd")
const 被搬运状态 := preload("res://角色/学生/状态/被搬运.gd")
const 旁观状态 := preload("res://角色/学生/状态/旁观.gd")
const 已逃出状态 := preload("res://角色/学生/状态/已逃出.gd")

## 状态机本体。`_ready` 里建，状态对象也在那儿注册。
## 下划线开头：供状态脚本通过 `host._机器` 取用。
var _机器

# ── 手感 ─────────────────────────────────────────────────────
const SPEED: float = 260.0     #速度（常走）
const ACCEL: float = 1400.0
const FRICTION: float = 1800.0

# 按住 Shift：减速档（按住=慢走，松手=快走）
const SLOW_SPEED: float = 150.0  # 慢走目标速度。嫌不够慢 → 调小
const SLOW_DECEL: float = 100.0  # 减速快慢。嫌切太突兀 → 调小
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

# ── 攀爬 ─────────────────────────────────────────────────────
# 只记「碰到梯子没有」这一个物理事实；「是否在爬」由当前状态判断。
var _on_ladder: bool = false

# ── 下穿薄板：按 S 从「可以穿过的地板」落下去 ─────────────────
# 把「可以穿过的地板」这一层从自身碰撞掩码里摘掉一小段时间，倒计时结束挂回。
# 层位掩码和时长都在 `数据/通用规则.gd`，这里只引用。

## 还要过多久把掩码挂回去（秒）。0 = 现在没在放。
var _下穿剩余: float = 0.0

# ── 门 ───────────────────────────────────────────────────────
# 开门由场景侧处理；角色只发「我要推这扇门」的请求，不等待回执。

# ── 血量与瘫痪 ───────────────────────────────────────────────
# 学生 2 格血，被打中掉 1 格；两格打空进入瘫痪：不能动、不能交互，可被扛走。
const MAX_HP: int = 2                      # 血量上限（格子数，不是小数）
const 瘫痪变色 := Color(1.0, 0.35, 0.35, 0.6)  # 瘫痪时的身体颜色（红 + 半透明）
const 拉起读条: float = 4.0                 # 拉队友起来要按住多久（秒）
const 自救读条: float = 2.0                 # 自己爬起来的时长（秒）
## 站立 / 瘫痪时身体所在的物理层。瘫痪时换到「瘫痪」层，
## 好让其他角色能跨过去，同时感应区仍然能找到。
## 具体位掩码只在 `数据/通用规则.gd` 定义，这里引用。
const 正常碰撞层: int = 规则.层_地板
const 瘫痪碰撞层: int = 规则.层_瘫痪

var 血量: int = MAX_HP                     # 现在还剩几格

## 是否处于瘫痪。由 `血量` 派生，不单独存储。
var 瘫痪: bool:
	get:
		return 血量 <= 0

var 被扛着: bool = false                    # 现在正被别人扛着 / 拖着？（扛我的人每帧摆我的位置）
## 正扛着我的是谁（宿管 / 队友；null = 没被扛）。
## 「队友拖着能按跳挣开、被宿管扛着挣不开」全靠它分辨 ——
## 别拿「是不是瘫痪」代替：队友也扛得动站着的，宿管将来也可能扛站着的。
var _扛我的人: Node = null
## 我刚被放下 / 刚挣开，还有几秒别人搬不动我（秒）。0 = 现在可以被搬。
## 【2026-11-11 加】时长在 `数据/通用规则.gd` 的 `搬运保护时长`（主人定 0.3 秒）。
## 等于给「搬运」这个状态加了个 CD：刚脱手的东西 0.3 秒内谁都不能再搬。
## 计时是真时间，从脱手那一刻起一直走 —— 跳在空中 / 被扔出去也照走。
var _搬运保护剩余: float = 0.0
var 被钉住: bool = false                    # 正被钉在原地插钥匙（锁口说钉住就钉住）
var 已逃出: bool = false                    # 这一局我已经从大门跑出去了（出口上报账本后置位）

var _救人目标: Node = null                 # 正被拉着的瘫倒队友（null = 没在拉）
var _救人进度: float = 0.0                 # 这次按住 H 已经按了多久（秒）
var _自救进度: float = 0.0                 # 瘫在地上按住 H 自己爬了多久


# ── 被击退 ───────────────────────────────────────────────────
# 被棍子打中 → 顺着被打的方向飞出去一小段，这期间身体不听自己指挥
# （不能走、不能跳、不能交互、不能自救），速度被摩擦吃掉后自动把身体交还。
## 【2026-11-09 20:05 加，主人定：击退手感照「代号宝石」里的小怪】
## 关键是「一大步」而不是「抖一下」：初速给足、摩擦中等，落在 1.5 个身位左右，
## 正好把人从棍子范围里推出去，阿姨得再追一步 —— 追逐的节奏就是这么来的。
const 击退初速: float = 480.0        # 挨打瞬间被推开的速度（像素/秒）
const 击退摩擦: float = 1600.0       # 水平速度衰减快慢（越大滑得越短）
const 击退硬直: float = 0.28         # 这段时间内不吃输入（秒）；到点就交还身体
const 击退上挑: float = 0.0          # 竖直初速。想让「被打飞一下」，给个负数（如 -90）

## 击退还剩几秒。>0 = 现在被冲量按着，状态机整段跳过。
var _击退剩余: float = 0.0


# ── 脚下出声 ─────────────────────────────────────────────────
# 主人 2026-11-09 20:23 定的分档：**Shift 慢走 = 1 档（很轻）**，
# 正常跑动 = 2 档（较大）。不在这张表里的动作（丢东西 / 开关门 / 合闸）
# 由那三个地方自己发，别都塞进这里。
## 隔多久响一脚（秒）。慢走稀疏、跑动密 —— 但不是每帧，不然满屏都是脚步。
const 脚步间隔_慢走: float = 0.5
const 脚步间隔_跑动: float = 0.3

var _脚步计时: float = 0.0


## 每帧由 `正常.gd` 调一次：站在地上、真的在走，就按间隔发一脚。
## `慢走` = 按着 Shift 慢慢挪（1 档，只传 200px）；其余都是 2 档（400px）。
## 停下、跳起来、被击退飞出去，都不发 —— 那时候脚没沾地。
func 走出动静(delta: float, 慢走: bool) -> void:
	if not is_on_floor() or absf(velocity.x) < 20.0:
		_脚步计时 = 0.0       # 脚停了：下一脚重新计时，不用等满间隔
		return
	_脚步计时 -= delta
	if _脚步计时 > 0.0:
		return
	_脚步计时 = 脚步间隔_慢走 if 慢走 else 脚步间隔_跑动
	if 慢走:
		Events.发声(global_position, 声音表.档_很轻, 声音表.来源_脚步)
	else:
		Events.发声(global_position, 声音表.档_较大, 声音表.来源_跑动)


# ── 通用读条 ─────────────────────────────────────────────────
# 读条节点住在 `界面/读条/`，只负责显示；进度由本文件的
# `_救人进度` / `_自救进度` 持有。
const 读条 := preload("res://界面/读条/读条.gd")
var _读条条: CanvasLayer = null

# ── 被抛出 ───────────────────────────────────────────────────
# 被队友扔出去时，飞行交给 `组件/抛投/` —— 和箱子是同一份代码、同一个重力。
# 落地后自己恢复碰撞体，下一帧抢占会把我接回正常 / 瘫痪。
const 抛投 := preload("res://组件/抛投/抛投.gd")
var _抛投 = 抛投.new()


# ── 搬运与道具 ───────────────────────────────────────────────
# 空手 / 负重两种状态；负重是修饰参数，不是状态机里的状态。
enum CarryState { EMPTY, CARRYING }
var _carry_state: CarryState = CarryState.EMPTY
var _carried: Area2D = null             # 正扛着的那个箱子（空手时是 null）
var _扛着的人: Node = null              # 正扛着的队友（站着、瘫着都算；null = 没扛人）

const CARRY_OFFSET := Vector2(14, -30)  # 抱在胸前的相对位置（1、2 档）
const DRAG_OFFSET := Vector2(18, -8)    # 拖在脚边的相对位置（3、4 档）

# ── 抛投：按住 F 蓄力，松手按蓄力长短扔出去 ───────────────────
# 短按 = 原地放下（距离 0）；按满 = 这一档的极限距离。
# 极限距离按档位递减，每重一档少一个身位：1 档 4 身位 / 2 档 3 / 3 档 2 / 4 档 1。
# 「攒了多大力」交给 `组件/蓄力/`（它只计时，不认识箱子也不认识人），
# 「飞一条抛物线」交给 `组件/抛投/`，本文件只决定「这一档最远几像素」。
const 蓄力 := preload("res://组件/蓄力/蓄力.gd")
var _蓄力 = 蓄力.new()

const 满蓄力时长: float = 0.8        # 按住多久到满力（秒）
const 身位: float = 44.0             # 学生碰撞体 20×44 —— 身高就是一个身位
const 最轻档身位: float = 4.0        # 1 档满蓄力的极限距离（身位）

var _蓄力朝向: float = 1.0           # 往哪边扔：+1 右 / -1 左
var _档号: int = 0                   # 手上这件东西在第几档（空手 = 0）

# ── 搬同学 ───────────────────────────────────────────────────
# 站着的、瘫着的队友都按 3 档算（策划案 §3.2：队友 40–60 kg）。
# 重量走同一张档位表，所以「搬人减速 / 不能跳 / 不能爬」不用另写一套规则。
const 队友重量: float = 45.0
const 扛人偏移 := Vector2(18, -8)       # 拖在脚边的相对位置（3 档是拖行姿势）

# ── 负重 ─────────────────────────────────────────────────────
# 每档罚多少全在 `数据/重量档位.gd` 那张表里，本文件只照表执行。
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

# ── 跨状态延续的记性 ─────────────────────────────────────────
# 土狼时间、跳跃记账、顶点定格这些手感记忆需要跨状态保持，所以在角色身上。
var _coyote: float = 0.0
var _buffer: float = 0.0
var _sprint_left: float = 0.0
var _sprint_dir: float = 0.0
var _sprint_cd: float = 0.0
var _hang_left: float = 0.0   # 顶点定格还剩几秒（0=没在定格）
var _fast_fall: bool = false  # 定格结束后处于快落中


func _ready() -> void:
	# ── 碰撞层按规则表设置 ───────────────────────────────────
	# `.tscn` 里的数值是备份；这里以规则表为准，出生时统一纠正一次。
	collision_layer = 正常碰撞层                              # 站立时占「地板」层，别人能撞见我
	collision_mask = 规则.人站的地面                           # 认：地板 + 可以穿过的地板（踩得住）
	$ClimbZone.collision_mask = 规则.层_梯子                   # 攀爬感应区只认梯子
	# 感应区认三层：站着的人（地板层）+ 瘫倒的人（瘫痪层）+ 可搬的东西（交互物层）。
	# 站着的人要能被搬，就必须认地板层；门 / 墙虽然也在这层，但没「拉起」接口，会被 _贴身队友 筛掉。
	$PickupZone.collision_mask = 规则.层_地板 | 规则.层_瘫痪 | 规则.层_交互物
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)
	# 被抛出时的飞行参数：原点就在脚底，所以底半高是 0；碰撞体 20 宽 → 半宽 10
	_抛投.底半高 = 0.0
	_抛投.半宽 = 10.0
	_抛投.地面层 = 规则.人站的地面
	# 蓄力参数：满力时长照手感表，力条上的字是「抛投」
	_蓄力.满蓄时长 = 满蓄力时长
	_蓄力.读条标题 = "抛投"
	# 逃出判定只认 student 组（宿管不在这组）
	add_to_group("student")
	# 向总管报到：可被玩家控制
	Director.register_controllable(self)
	# 换人时道具格是全场共用的，切回自己要把身上的道具再播报一次。
	Director.control_changed.connect(_on_control_changed)
	# 账本说「有人逃出去了」：如果是自己，切进「已逃出」
	Match.door_escaped.connect(_on_escaped)
	_搭状态机()


## 建状态机、注册全部状态、进第一个状态。
func _搭状态机() -> void:
	_机器 = 状态机.new()
	_机器.host = self
	_机器.加(状态名.正常, 正常状态.new())
	_机器.加(状态名.攀爬, 攀爬状态.new())
	_机器.加(状态名.插钥匙中, 插钥匙状态.new())
	_机器.加(状态名.救人中, 救人状态.new())
	_机器.加(状态名.瘫痪, 瘫痪状态.new())
	_机器.加(状态名.被搬运, 被搬运状态.new())
	_机器.加(状态名.旁观, 旁观状态.new())
	_机器.加(状态名.已逃出, 已逃出状态.new())
	_机器.启动(状态名.正常)


func _on_control_changed(who: Node) -> void:
	if who == self:
		# 延后一帧再播报：道具格换人时会先清空格子，等它清完再补上。
		_refresh_item_slot.call_deferred()
		return
	# 控制权被拿走：手上的力条、救援读条都得当场收掉。
	# 这两件事本来就有两道保险（`正常.离开` 收力条、`旁观.进入` 收读条），
	# 这里在信号里再做一次 —— 全是置空操作，重复做是幂等的，不会互相打架。
	_取消蓄力()
	_取消救人()


## 对局账本说「有人逃出去了」。是自己就把标记立起来，
## 下一帧 `抢占()` 会把我接进「已逃出」
func _on_escaped(谁: Node) -> void:
	if 谁 == self:
		已逃出 = true


func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子（是否开始爬由抢占判断）

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	# 离开梯子时若仍在攀爬状态，立即切回正常状态。
	if _机器 != null and _机器.当前() == 状态名.攀爬:
		_机器.切(状态名.正常)


# ============================================================
# 每帧：推进下穿倒计时 → 跑状态机（内部先问抢占）→ 状态内部 move_and_slide
# ============================================================
func _physics_process(delta: float) -> void:
	# 搬运保护的秒表放在最前面：被击退 / 被扛 / 飞在空中，它都该照常算（空中不算，见函数里）
	_推进搬运保护(delta)
	# 下穿倒计时放在所有状态之前：任何状态下都要把掩码挂回去。
	_推进下穿(delta)
	# 被击退的这小半秒里，身体由冲量做主：状态机整段跳过，
	# 输入 / 交互 / 自救全部停摆，滑停后下一帧自动交还。
	if _推进击退(delta):
		return
	_机器.跑(delta)


## 抢占：按优先级回答「现在该待在哪个状态」。
## 行序即优先级；返回空串表示不需要切换。
## 【2026-11-11】「旁观」保留（曾经试过删掉、让「正常」自己判 `受控()`，
## 后来按主人要求改回来）：它除了屏蔽键盘，还兼着「切人时把救援读条收掉」这类收尾，
## 拆散容易漏。
func 抢占(现在: String) -> String:
	if 已逃出:
		return 状态名.已逃出         # 已经跑出大门：最高优先级，任何输入都抢不回来
	if 被扛着 or _抛投.在飞:
		return 状态名.被搬运          # 身体不由我做主：被扛着走，或被扔在空中
	if 瘫痪:
		return 状态名.瘫痪            # 两格血打空，趴地上（能蹭着挪）
	if 被钉住:
		return 状态名.插钥匙中        # 锁孔前那几秒，钉住
	if Director.当前控制 != null and Director.当前控制 != self:
		return 状态名.旁观            # 玩家把控制权切给别人了
	# 已经在救人：继续救，收尾由 救人中.gd 自己处理。
	if 现在 == 状态名.救人中:
		return 状态名.救人中
	if _该攀爬():
		return 状态名.攀爬
	return 状态名.正常


## 此刻键盘归我吗？玩家手里控制的是不是我（没人控制时也当作归我，单人也能跑）。
## 主要是给 `瘫痪.gd` 用的：瘫痪的优先级高于「旁观」，所以瘫着又没被操控的人
## 会留在瘫痪状态里 —— 得靠这一句挡住键盘，不然玩家按方向键所有瘫痪的人一起爬。
func 受控() -> bool:
	return Director.当前控制 == null or Director.当前控制 == self


## 是否该进入攀爬。已经在爬时直接返回 true，避免松手后掉下去。
func _该攀爬() -> bool:
	if not _on_ladder or not _可否攀爬:
		return false
	if _机器 != null and _机器.当前() == 状态名.攀爬:
		return true
	if not 受控():
		return false               # 第二道门：切人的那一帧状态机还没切进旁观，别被人顺手骗上梯子
	return Input.get_axis("up", "down") != 0.0


## 摘掉「可以穿过的地板」这一层，稍后由 `_推进下穿` 挂回。
## 给一点向下初速，避免摘层当帧看起来像没反应。
func _开始下穿() -> void:
	collision_mask &= ~规则.层_可穿过地板
	_下穿剩余 = 规则.下穿放开时长
	velocity.y = 20.0


## 每帧推进倒计时，到点把掩码挂回去。
func _推进下穿(delta: float) -> void:
	if _下穿剩余 <= 0.0:
		return
	_下穿剩余 -= delta
	if _下穿剩余 <= 0.0:
		_下穿剩余 = 0.0
		collision_mask |= 规则.层_可穿过地板

# ============================================================
# 交互上报：把感应区原样交给总管，角色不判断目标是什么
# ============================================================

## 把感应区里的东西原样交给总管，由总管解析编号并分发。
## 返回 true = 有东西接下了这个键（每件东西只认自己那个键）。
## 只在按键那一刻调用；_ready 时物件还没登记完，不能调。
func _上报交互(键: String) -> bool:
	return Director.交互(self, 键, $PickupZone.get_overlapping_areas())


## F 键按下：搬运相关的交互收在这一个键里，顺序即优先级，谁先接手就到此为止。
##   1 肩上有队友 → 开始蓄力，松手按蓄力长短把人扔出去
##   2 手上有箱子 → 开始蓄力，松手才扔（见 `_松开交互`）
##   3 环境 → 箱子、道具（"interaction"）
##   4 身边的人 → 扛起最近的队友（站着、瘫着都算）
## 门不在这条链里：门走 E（见 `_open_door`），这样门口堆着箱子也开得掉门。
## 人和箱子走同一条蓄力路：短按 = 原地放下，按住越久扔越远。
func _交互键() -> void:
	if 正扛着人() or 正搬着():
		_开始蓄力()
		return
	if _上报交互("interaction"):
		return
	var 目标 := _贴身队友(false)
	if 目标 != null:
		扛起同学(目标)
		return
	print("[学生] 身边没有可以交互的东西")


## 手上有东西（箱子或队友）：按住 F 开始蓄力，等松手才决定扔多远。短按 = 原地放下。
## 计时和力条都由 `组件/蓄力/` 负责，这里只管「能不能蓄」和「朝哪边」。
func _开始蓄力() -> void:
	if not 正搬着() and not 正扛着人():
		return
	_蓄力朝向 = _当前朝向()
	_蓄力.读条条 = _我的读条()
	_蓄力.开始(self)


## 每帧推进蓄力。按住左/右可以改扔的方向，松手才落地。
func _推进蓄力(delta: float) -> void:
	if not _蓄力.在蓄力():
		return
	_蓄力.推进(delta)
	var 按 := Input.get_axis("left", "right")
	if 按 != 0.0:
		_蓄力朝向 = signf(按)


## 松开 F：按蓄力比例把东西扔出去。比例 0 = 原地放下，比例 1 = 这一档的极限距离。
## 箱子和队友走同一个比例、同一张档位表（队友固定 45kg = 3 档）。
func _松开交互() -> void:
	if not _蓄力.在蓄力():
		return
	var 比例 := _蓄力.松开()
	var 朝向 := _蓄力朝向
	if 正搬着():
		_抛出箱子(朝向, 比例)
	elif 正扛着人():
		_抛出同学(朝向, 比例)


## 蓄力作废：东西还在手上，力条收掉。被打断 / 切状态 / 被扛走都走这里，可以重复调。
func _取消蓄力() -> void:
	_蓄力.取消()


## 蓄力中。状态脚本靠它决定「其他键一律不接」。
func 蓄力中() -> bool:
	return _蓄力.在蓄力()


## 往哪边扔：先看玩家现在按着哪个方向，再看他正在往哪走，最后默认朝右。
func _当前朝向() -> float:
	var 按 := Input.get_axis("left", "right")
	if 按 != 0.0:
		return signf(按)
	if absf(velocity.x) > 1.0:
		return signf(velocity.x)
	return 1.0


## 这一档满蓄力能扔多远（像素）。每重一档少一个身位：4 / 3 / 2 / 1。
## 箱子、队友共用这一条 —— 各写一份的话，以后调手感必然漏掉一边。
func _这一档极限距离() -> float:
	return maxf(最轻档身位 - float(maxi(_档号, 1) - 1), 1.0) * 身位


## 把箱子按蓄力比例扔出去。极限距离见 `_这一档极限距离()`。
func _抛出箱子(朝向: float, 比例: float) -> void:
	var box := _carried
	if box == null or not is_instance_valid(box):
		_drop_box()
		return
	var 起点 := _扛着的位置()      # 得在 _drop_box 之前取：放下后负重清零，姿势会变
	# 身位是从「人」量起的，不是从「手的出手点」量起 —— 把出手点那一小段先扣掉
	var 距离 := maxf(_这一档极限距离() * 比例 - absf(起点.x), 0.0)
	_drop_box()                    # 交还场景 + 恢复负重 + 收掉蓄力
	box.global_position = global_position + Vector2(absf(起点.x) * 朝向, 起点.y)
	if box.has_method("抛"):
		# 第三个参数是「脚下的地面在多高」：学生原点就在脚底，站着扔时它就是地面
		box.抛(Vector2(朝向, 0.0), 距离, global_position.y)


## 把肩上的队友按蓄力比例扔出去。极限距离和箱子用同一条公式 ——
## 队友固定 45kg（3 档），所以最多 2 个身位，最轻的箱子是 4 个。
## 短按（距离 ≈ 0）不扔，直接走 `放下同学()` 的老摆位：放在脚边。
func _抛出同学(朝向: float, 比例: float) -> void:
	var 人 := _扛着的人
	if 人 == null or not is_instance_valid(人):
		放下同学()
		return
	var 起点 := 扛人偏移            # 得在放下之前取：放下后负重清零，姿势会变
	# 身位从「人」量起，不是从出手点量起 —— 先把出手点那一小段扣掉
	var 距离 := maxf(_这一档极限距离() * 比例 - absf(起点.x), 0.0)
	放下同学()                      # 交还场景 + 恢复负重 + 收掉蓄力
	if 距离 <= 2.0:
		return                      # 短按 = 原地放下，摆位用 `放下同学` 那一套
	人.global_position = global_position + Vector2(absf(起点.x) * 朝向, 起点.y)
	if 人.has_method("抛出去"):
		# 第三个参数同样是「脚下的地面在多高」，我脚底就是那块地
		人.抛出去(朝向, 距离, global_position.y)


# E 键：开门。双手占着（搬箱子或扛人）时不开 —— 得先按 F 放下东西。
func _open_door() -> void:
	if 正搬着() or 正扛着人():
		print("[学生] 手上占着，先按 F 放下才能开门")
		return
	_上报交互("open_door")

# R 键：把手上搬着的东西往锁口里插。空手时不响应。
func _insert_key() -> void:
	if not 正搬着():
		return
	_上报交互("insert_key")


## 手上是否搬着东西。供状态脚本判断按键分支。
func 正搬着() -> bool:
	return _carry_state == CarryState.CARRYING


## 肩上是否扛着队友。和 `正搬着()` 分开：箱子和人走两条路，但都占手。
func 正扛着人() -> bool:
	return _扛着的人 != null and is_instance_valid(_扛着的人)


## 扛起一名队友：挂到自身名下、关掉他的碰撞体，按 3 档负重。
## 站着的和瘫着的走同一套 —— 被扛的人自己进「被搬运」状态，不再吃输入。
func 扛起同学(谁: Node) -> void:
	if 谁 == null or not is_instance_valid(谁) or 谁 == self:
		return
	if 正搬着() or 正扛着人():
		return                    # 双手已经被箱子或另一个队友占住
	if 谁.has_method("可被搬运") and not 谁.可被搬运():
		print("[学生] %s 刚脱手，搬运保护中，先别捡" % 谁.name)
		return                    # 刚被放下 / 刚跳脱出来的那几秒，谁都搬不动他
	_扛着的人 = 谁
	谁.被扛起(self)                # 学生那边自己 reparent + 关碰撞 + 切「被搬运」
	_应用负重(队友重量)            # 3 档：拖在脚边，走不快、跳不了、爬不了
	谁.position = 扛人偏移
	print("[学生] 扛起同学：%s" % 谁.name)


## 放下队友：交还场景，摆到脚边。他自己的状态（瘫着还是站着）原样保留。
func 放下同学() -> void:
	_取消蓄力()                    # 人脱手了，头顶那根力条也得收掉
	var 人 := _扛着的人
	_扛着的人 = null
	if 人 == null or not is_instance_valid(人):
		_应用负重(0.0)
		return
	人.被放下(get_parent())
	# 两人原点都在脚底，摆在脚边同一高度正好贴地，不会叠在一起被物理弹开
	人.global_position = global_position + Vector2(26.0, 0.0)
	_应用负重(0.0)                 # 人放下了，速度/跳跃/攀爬全恢复
	# 把肩上的人撂下也是 3 档：一个人砸在地上，比丢箱子只响不轻
	Events.发声(global_position, 声音表.档_很大, 声音表.来源_丢物)
	print("[学生] 放下同学：%s" % 人.name)


## 我现在扛着什么？空手返回 null。给锁口用：它要知道插进来的是哪块板子
func 手上扛着() -> Node:
	if not 正搬着():
		return null
	return _carried


## 把搬着的东西交出，不落回场景。锁口插上钥匙时使用。
func 交出搬运物() -> Node:
	if not 正搬着():
		return null
	var 货 := _carried
	_carried = null
	_carry_state = CarryState.EMPTY
	_应用负重(0.0)
	return 货


## 钉住 / 松开。钉住期间不接收移动与交互输入，由锁口在插钥匙期间调用。
func 钉住(开: bool) -> void:
	被钉住 = 开
	if 开:
		velocity.x = 0.0


# 扛起箱子：把箱子设为自身子节点，位置摆在身前（重物拖在脚边）。
# 由箱子在确认按键归属后调用。
func 扛起(box: Area2D) -> void:
	if 正扛着人() or 正搬着():
		return                        # 双手已经占满：必须先把旧的放下，才能扛下一个
	if box.has_method("可被搬运") and not box.可被搬运():
		return                        # 刚脱手的东西：它自己那边也会挡，这里再兜一道
	_carried = box
	_carry_state = CarryState.CARRYING
	_应用负重(box.取重量() if box.has_method("取重量") else 0.0)
	if box.has_method("设被扛着"):
		box.设被扛着(true)                # 告诉它：别自己往下掉了
	box.reparent(self, false)             # 认人做爹：从此跟着人走
	box.position = _扛着的位置()

# 放下箱子：还回场景里，落在脚边，然后它自己受重力落到地面
func _drop_box() -> void:
	_取消蓄力()                          # 东西脱手了，蓄力自然作废
	var box := _carried
	var 手上真有东西: bool = box != null and is_instance_valid(box)
	_carried = null
	_carry_state = CarryState.EMPTY
	_应用负重(0.0)                        # 先恢复负重：箱子就算已经失效，人也不能一直被压着
	if not 手上真有东西:
		return
	# 3 档：把东西丢下来是「很大」的声音（主人定）。挨打脱手掉东西也走这里，一样响。
	Events.发声(global_position, 声音表.档_很大, 声音表.来源_丢物)
	box.reparent(get_parent(), false)     # 交还给场景
	# 学生自己的原点就在脚底（碰撞体从 -44 到 0），所以这里减一个箱子的半高就贴地了
	box.global_position = global_position + Vector2(18, -12)
	if box.has_method("设被扛着"):
		box.设被扛着(false)               # 从这里开始它自己受重力

# 按公斤换算出这一档的移动/跳跃限制。拿起和放下时各算一次。
func _应用负重(公斤: float) -> void:
	_负重公斤 = 公斤
	_负重档名 = "空手" if 公斤 <= 0.0 else 重量档位.档位全名(公斤)
	var 档: Dictionary = 重量档位.空手() if 公斤 <= 0.0 else 重量档位.取(公斤)
	_档号 = int(档["档号"])               # 抛投的极限距离按它算（4 / 3 / 2 / 1 身位）
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
	if not 正搬着() and not 正扛着人():
		return "空手"
	return "%s %.0fkg｜速度 %d%%｜%s｜%s" % [
		_负重档名,
		_负重公斤,
		roundi(_移速倍率 * 100.0),
		"能跳" if _跳跃高度倍率 >= 1.0 else ("跳一半高" if _跳跃高度倍率 > 0.0 else "不能跳"),
		"能爬梯" if _可否攀爬 else "不能爬梯",
	]

# 捡道具：图记进道具格，地上的物件消失。
# 由道具在确认按键归属后调用。返回 true = 收下，false = 手上已有道具或该物件没有贴图。
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
# 被打 / 瘫痪 / 被扛的对外接口。宿管直接调用这些方法。
# ============================================================

## 身边最近的队友：站着、瘫着都算；排除自己、排除已经被别人扛走的、排除还飞在空中的。
## `只找瘫的` = true 时只认瘫倒的 —— 拉起（H）要的就是这个筛法。
func _贴身队友(只找瘫的 := true) -> Node:
	for body in $PickupZone.get_overlapping_bodies():
		if body == self or not body.has_method("拉起"):
			continue
		if body.被扛着 or body.在飞() or (只找瘫的 and not body.瘫痪):
			continue
		return body
	return null


## 本角色的读条节点，首次使用时创建。
func _我的读条() -> CanvasLayer:
	if _读条条 == null or not is_instance_valid(_读条条):
		_读条条 = 读条.新建(self)
	return _读条条


## 公开的读条入口，供锁口等外部对象借用同一根读条。
func 借读条() -> CanvasLayer:
	return _我的读条()


## 收起读条。没建过则跳过。
func _收读条() -> void:
	if _读条条 != null and is_instance_valid(_读条条):
		_读条条.收()


## 清掉本次救援：进度归零、颜色还原、读条收起。可重复调用。
func _取消救人() -> void:
	_救人目标 = null
	_救人进度 = 0.0
	_收读条()
	换色(Color.WHITE)


## 换身体颜色（瘫痪变红、拉人变黄、恢复变白）。
## 状态脚本统一走这里，不直接访问身体节点。
func 换色(色: Color) -> void:
	$AnimatedSprite2D.modulate = 色


## 被挥击打中：掉一格血；两格打空 → 瘫痪（蹲地，素材后面换）
## `来自方向` = 要把我往哪边推：+1 右 / -1 左 / 0 原地不动。
## 宿管挥棍时按「她在我哪边」算；不传参的调用方行为跟以前一样（只掉血）。
func 被打中(来自方向: float = 0.0) -> void:
	if 瘫痪 or 被扛着:
		return   # 已经瘫了就别再打了；扛着的时候打不着
	_取消救人()   # 正在拉人的时候挨了一下 → 手上的劲散了，读条作废
	# 正在锁孔前插钥匙（被钉住）时挨了一下：钉住必须当场解除。
	# 不解除的话 `抢占()` 永远返回「插钥匙中」，人会一直钉在原地 ——
	# 明明被打飞出去 68px、手上也空了，却还挂着插钥匙的读条。
	# 锁口那边会看到「人不在钉住状态了」而把这次插孔作废（见 锁口.gd 的 `_process`），
	# 所以牌子不会在他离手之后被悄悄吞掉。
	钉住(false)
	if 正扛着人():
		放下同学()   # 肩上的人跟着落地（策划案：被挥击命中即掉落）
	if 正搬着():
		_drop_box()  # 手上的东西一样脱手，不能挨了打还端着
	_取消蓄力()      # 正在掂量扔多远，一棍打散
	血量 -= 1
	if 血量 <= 0:
		_瘫了()
	被击退(来自方向)   # 放在最后：就算这一棍把他打瘫，也要照样飞出去


## 被击退的物理推进。返回 true = 这一帧身体归冲量管，状态机别跑。
## 只做三件事：摩擦吃掉水平速度、空中照常下落、move_and_slide 撞墙。
## 到点就交还 —— 落地时把横向速度清零，免得恢复操控后自己又滑一段。
func _推进击退(delta: float) -> bool:
	if _击退剩余 <= 0.0:
		return false
	_击退剩余 -= delta
	velocity.x = move_toward(velocity.x, 0.0, 击退摩擦 * delta)
	if not is_on_floor():
		var 重力倍: float = FALL_GRAVITY_MULT if velocity.y > 0.0 else 1.0
		velocity.y += GRAVITY * 重力倍 * delta
	move_and_slide()
	if _击退剩余 <= 0.0:
		_击退剩余 = 0.0
		if is_on_floor():
			velocity.x = 0.0
	return true


## 挨了一记：顺着 `方向`（+1 右 / -1 左）被推开，`击退硬直` 秒内不吃输入。
## 已经瘫了、被扛着、正被扔在天上的，都不再推 —— 那几种状态身体本来就不归自己。
func 被击退(方向: float) -> void:
	if 被扛着 or _抛投.在飞:
		return
	if 方向 != 0.0:
		velocity.x = signf(方向) * 击退初速
	velocity.y = 击退上挑 if not is_on_floor() else 0.0
	_击退剩余 = 击退硬直

## 两格血打空：换成瘫痪颜色，此后不能移动和交互。
## 不直接写 `瘫痪 = true`，该值是 `血量 <= 0` 派生出来的。
func _瘫了() -> void:
	velocity = Vector2.ZERO
	collision_layer = 瘫痪碰撞层   # 瘫在地上，别人能跨过去（不然整条走廊被她堵死）
	$AnimatedSprite2D.modulate = 瘫痪变色
	print("[学生] 我瘫了（%d/%d 格）" % [血量, MAX_HP])

## 被扛起（宿管或队友都走这里）：挂到对方名下并禁用自身碰撞体，避免两人互相挤压。
func 被扛起(谁: Node2D) -> void:
	if 正扛着人():
		放下同学()   # 自己被抬走时，不能把肩上的同学一起带走
	if 正搬着():
		_drop_box()  # 手上的东西也一样，抬走之前先落地
	_抛投.在飞 = false   # 被人从半空接住：飞行作废，从此交给扛我的人
	被扛着 = true
	_扛我的人 = 谁        # 记下是谁扛的我：+1 队友 / 宿管，决定我能不能按跳挣开
	velocity = Vector2.ZERO
	reparent(谁, false)
	_set_collision_disabled(true)

## 被放下：交还给场景。站着还是瘫着，原样保留。
## 一落地就套上搬运保护（见 `_搬运保护剩余`）——不然「放下 → 立刻再抓」就是个死循环。
func 被放下(原父节点: Node) -> void:
	被扛着 = false
	_扛我的人 = null
	reparent(原父节点, false)
	_set_collision_disabled(false)
	_给搬运保护()
	print("[学生] 被放下了")


# ── 搬运保护：刚脱手的人，短时间内谁都不能再搬 ────────────────
# 时长在 `数据/通用规则.gd` 的 `搬运保护时长`（人和箱子共用同一个数，别在这里另写一份）。
# 用途是掐死两个死循环：「放下 → 立刻捡回来」和「从队友手里跳脱 → 立刻被抓回去」。

## 套保护。被放下 / 挣脱都走这里（挣脱本身就是一次「被放下」）。
func _给搬运保护() -> void:
	_搬运保护剩余 = 规则.搬运保护时长

## 保护的秒表：从脱手那一刻起**按真时间走**，人在空中 / 被扔出去也照走
## （常识：时间不会因为你跳起来就停）。走到 0 就解禁，不管有没有落地。
func _推进搬运保护(delta: float) -> void:
	if _搬运保护剩余 <= 0.0:
		return
	_搬运保护剩余 = maxf(_搬运保护剩余 - delta, 0.0)

## 现在能不能把我搬起来？保护期内不行。学生扛人、宿管抓人都问这一句。
func 可被搬运() -> bool:
	return _搬运保护剩余 <= 0.0


## 正被「队友」拖着走？宿管扛着不算 —— 被她扛走只能等她放下。
## 认人只认组：学生自己在 `_ready` 里进了 "student" 组，宿管不在组里。
func 被同伴扛着() -> bool:
	return 被扛着 and _扛我的人 != null and is_instance_valid(_扛我的人) \
			and _扛我的人.is_in_group("student")


## 挣开：被队友拖着走时按跳，两边一起脱手。
## 只做两件事：
##   ① 走扛我那个人的「放下」正规流程 —— 他清负重、收力条、把我交还场景并摆到脚边，
##      他那边从此不再算「扛着人」（速度 / 跳跃 / 爬梯全恢复）。
##   ② 给一个正常起跳初速 —— 按的是跳，人就该跳出来。
## 注意：跳起来的这半秒只是两人自然拉开一点距离，**不是「不可再被抓」的保护** ——
## 落地后对方照样能按 F 把我捡回去。要「刚挣脱的短时间内抓不回来」得另外加冷却。
## 瘫着挣不开（站不起来），被宿管扛着也挣不开。返回 true = 真挣开了。
func 挣脱() -> bool:
	if not 被同伴扛着():
		return false
	if 瘫痪:
		return false
	var 人: Node = _扛我的人
	if 人.has_method("放下同学"):
		人.放下同学()
	else:
		# 兜底：扛我的人没这套接口，也得把我放回场景，别卡在他身上。
		# 注意交还的是「他的父节点」（场景），不是我现在的父节点 —— 我现在正挂在他身上。
		被放下(人.get_parent())
	velocity = Vector2(0.0, JUMP_VELOCITY)
	print("[学生] 从队友手里挣开了：%s" % 人.name)
	return true


# ============================================================
# 被队友扔出去 —— 和箱子走同一个组件、同一个重力
# ============================================================

## 是否正被扔在空中。要找队友扛 / 拉之前先看这一句：空中接人不算。
func 在飞() -> bool:
	return _抛投.在飞


## 被队友扔出去。抛物线全在 `组件/抛投/`；我这里只负责「起飞前关碰撞、
## 落地后把碰撞挂回去」——位置一路上由组件改，不走 move_and_slide。
## 落地之后下一帧抢占会把我接回正常 / 瘫痪，原状态原样保留。
func 抛出去(方向: float, 平抛距离: float, 地面y: float) -> void:
	if not _抛投.起飞(self, 方向, 平抛距离, 地面y):
		return
	velocity = Vector2.ZERO
	_set_collision_disabled(true)
	print("[学生] 我被扔出去了：%.0fpx" % 平抛距离)


## 空中每帧推进一次（由 `被搬运.gd` 调）。返回时若落地，碰撞体已经挂回去了。
func _飞(delta: float) -> void:
	if not _抛投.在飞:
		return
	if _抛投.推进(self, delta):
		velocity = Vector2.ZERO
		_set_collision_disabled(false)
		# 【2026-11-13】人砸在地上也一样要响，且响在**落点**（同箱子）——
		# 扔队友当诱饵这条战术，声纹上得看得出「人落在哪」。
		Events.发声(global_position, 声音表.档_很大, 声音表.来源_丢物)
		print("[学生] 落地了")


## 肩上/落地切换碰撞体。扛着时禁用（不挡宿管的路），放下时恢复（又能被撞见）
func _set_collision_disabled(禁用: bool) -> void:
	var col := get_node_or_null("CollisionShape2D")
	if col != null:
		col.set_deferred("disabled", 禁用)

## 调试/恢复用：把血量补满，瘫痪随之自动解除。
func 拉起() -> void:
	血量 = MAX_HP
	collision_layer = 正常碰撞层   # 站起来又能挡人了
	$AnimatedSprite2D.modulate = Color.WHITE
	print("[学生] 恢复了（%d/%d 格）" % [血量, MAX_HP])
