extends CharacterBody2D

## 学生 —— 玩家操作的角色。
##
## 本文件只放：物理常量、状态机拼装、跨状态延续的记性、对外接口。
## 每个行为模式的具体逻辑在 `角色/学生/状态/` 下，一个状态一个脚本。

## 全工程规则（物理层位掩码、下穿时长、开门用时等）。
## 放在文件最前面：下面的常量要引用它的位掩码，GDScript 常量从上往下求值。
const 规则 := preload("res://数据/通用规则.gd")

# ── 状态机 ───────────────────────────────────────────────────
# 状态名常量集中在 状态名.gd（拼错就报红，不会运行时才崩）。
const 状态名 := preload("res://角色/学生/状态/状态名.gd")
const 状态机 := preload("res://组件/状态机/状态机.gd")
const 正常状态 := preload("res://角色/学生/状态/正常.gd")
const 攀爬状态 := preload("res://角色/学生/状态/攀爬.gd")
const 插钥匙状态 := preload("res://角色/学生/状态/插钥匙中.gd")
const 救人状态 := preload("res://角色/学生/状态/救人中.gd")
const 瘫痪状态 := preload("res://角色/学生/状态/瘫痪.gd")
const 被拎状态 := preload("res://角色/学生/状态/被拎.gd")
const 旁观状态 := preload("res://角色/学生/状态/旁观.gd")

## 状态机本体。`_ready` 里建，状态对象也在那儿注册。
## 下划线开头：供状态脚本通过 `host._机器` 取用。
var _机器

# ── 手感 ─────────────────────────────────────────────────────
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

var 被扛着: bool = false                    # 现在正被宿管扛在肩上？（宿管每帧摆我的位置）
var 被钉住: bool = false                    # 正被钉在原地插钥匙（锁口说钉住就钉住）

var _救人目标: Node = null                 # 正被拉着的瘫倒队友（null = 没在拉）
var _救人进度: float = 0.0                 # 这次按住 H 已经按了多久（秒）
var _自救进度: float = 0.0                 # 瘫在地上按住 H 自己爬了多久


# ── 通用读条 ─────────────────────────────────────────────────
# 读条节点住在 `界面/读条/`，只负责显示；进度由本文件的
# `_救人进度` / `_自救进度` 持有。
const 读条 := preload("res://界面/读条/读条.gd")
var _读条条: CanvasLayer = null


# ── 搬运与道具 ───────────────────────────────────────────────
# 空手 / 负重两种状态；负重是修饰参数，不是状态机里的状态。
enum CarryState { EMPTY, CARRYING }
var _carry_state: CarryState = CarryState.EMPTY
var _carried: Area2D = null             # 正扛着的那个箱子（空手时是 null）

const CARRY_OFFSET := Vector2(14, -30)  # 抱在胸前的相对位置（1、2 档）
const DRAG_OFFSET := Vector2(18, -8)    # 拖在脚边的相对位置（3、4 档）

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
	$PickupZone.collision_mask = 规则.层_瘫痪 | 规则.层_交互物  # 感应区认：瘫倒的人 + 可搬的东西
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)
	# 向总管报到：可被玩家控制
	Director.register_controllable(self)
	# 换人时道具格是全场共用的，切回自己要把身上的道具再播报一次。
	Director.control_changed.connect(_on_control_changed)
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
	_机器.加(状态名.被拎, 被拎状态.new())
	_机器.加(状态名.旁观, 旁观状态.new())
	_机器.启动(状态名.正常)


func _on_control_changed(who: Node) -> void:
	if who == self:
		# 延后一帧再播报：道具格换人时会先清空格子，等它清完再补上。
		_refresh_item_slot.call_deferred()


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
	# 下穿倒计时放在所有状态之前：任何状态下都要把掩码挂回去。
	_推进下穿(delta)
	_机器.跑(delta)


## 抢占：按优先级回答「现在该待在哪个状态」。
## 行序即优先级；返回空串表示不需要切换。
func 抢占(现在: String) -> String:
	if 被扛着:
		return 状态名.被拎            # 位置由宿管每帧摆，我什么都不做
	if 瘫痪:
		return 状态名.瘫痪            # 两格血打空，蹲地
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


## 是否该进入攀爬。已经在爬时直接返回 true，避免松手后掉下去。
func _该攀爬() -> bool:
	if not _on_ladder or not _可否攀爬:
		return false
	if _机器 != null and _机器.当前() == 状态名.攀爬:
		return true
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
## 只在按键那一刻调用；_ready 时物件还没登记完，不能调。
func _上报交互(键: String) -> void:
	Director.交互(self, 键, $PickupZone.get_overlapping_areas())


# E 键：开门。扛着东西时不开。
func _open_door() -> void:
	if 正搬着():
		return
	_上报交互("open_door")

# F 键：扛着东西时放下，空手时尝试拾取或扛起身边的东西。
func _pick_or_drop() -> void:
	if 正搬着():
		_drop_box()
		return
	_上报交互("interaction")

# R 键：把手上搬着的东西往锁口里插。空手时不响应。
func _insert_key() -> void:
	if not 正搬着():
		return
	_上报交互("insert_key")


## 手上是否搬着东西。供状态脚本判断按键分支。
func 正搬着() -> bool:
	return _carry_state == CarryState.CARRYING


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
	_carried = box
	_carry_state = CarryState.CARRYING
	_应用负重(box.取重量() if box.has_method("取重量") else 0.0)
	if box.has_method("设被扛着"):
		box.设被扛着(true)                # 告诉它：别自己往下掉了
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

# 按公斤换算出这一档的移动/跳跃限制。拿起和放下时各算一次。
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
	if not 正搬着():
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

## 身边是否躺着可救的队友。排除自己和已被扛走的。
func _贴身瘫痪队友() -> Node:
	for body in $PickupZone.get_overlapping_bodies():
		if body != self and body.has_method("拉起") and body.瘫痪 and not body.被扛着:
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
func 被打中() -> void:
	if 瘫痪 or 被扛着:
		return   # 已经瘫了就别再打了；扛着的时候打不着
	_取消救人()   # 正在拉人的时候挨了一下 → 手上的劲散了，读条作废
	血量 -= 1
	if 血量 <= 0:
		_瘫了()

## 两格血打空：换成瘫痪颜色，此后不能移动和交互。
## 不直接写 `瘫痪 = true`，该值是 `血量 <= 0` 派生出来的。
func _瘫了() -> void:
	velocity = Vector2.ZERO
	collision_layer = 瘫痪碰撞层   # 瘫在地上，别人能跨过去（不然整条走廊被她堵死）
	$AnimatedSprite2D.modulate = 瘫痪变色
	print("[学生] 我瘫了（%d/%d 格）" % [血量, MAX_HP])

## 被宿管扛起：挂到宿管名下并禁用自身碰撞体，避免两人互相挤压。
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

## 调试/恢复用：把血量补满，瘫痪随之自动解除。
func 拉起() -> void:
	血量 = MAX_HP
	collision_layer = 正常碰撞层   # 站起来又能挡人了
	$AnimatedSprite2D.modulate = Color.WHITE
	print("[学生] 恢复了（%d/%d 格）" % [血量, MAX_HP])
