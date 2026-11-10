extends CharacterBody2D
## 宿管：能走、能跳、能爬梯、开门、挥击、抓捕、扛人；没人按键时自己会巡逻和追人。
## 与学生的区别：走得更快；不捡东西不搬箱子（E 只开门）；在 keeper 组，门按宿管时长开关
##
## 【2026-11-09 拆过一次】原来 `_physics_process` 里那条 90 行的 if 链整段搬进了
## `角色/宿管/状态/手控.gd`，本文件只剩：常量、服务函数、`抢占()`、`_搭状态机()`。
## 理由和学生拆状态机一样 —— 想加一种行为模式（这里是 AI 的待机/巡逻/追击）
## 只新建一个状态脚本，不用往一条越来越长的 if 链里插。
##
## 【这轮只做「能动 + 能追人」】挥击 / 抓捕 / 扛人原样留在手控状态里，
## AI 状态不碰它们（主人 2026-11-09 定：打人留到后面单独优化）。想给 AI 加打人，
## 新建 `攻击.gd` 并在 `抢占()` 里补一行，别改这三个 AI 状态。
##
## 【2026-11-10 打人重做】上面那句「打人留到后面」现在做了，按原计划走：
## 新建 `状态/攻击.gd` + `状态名.攻击` + `抢占()` 一行，待机/巡逻/追击一个字没动。
## 挥击本身也从「按下瞬间射线找目标」改成了「抬手 → 棍子扫过 → 收棍」三段式，
## 棍子用 Line2D 程序画出来，判定框就是这根棍子（见下面挥击段的常量）。

## 全工程规则（物理层位掩码等）。放最前面：下面的常量要引用它。
const 规则 := preload("res://数据/通用规则.gd")
## 声音表：四档半径 + 距离衰减 + 反应阈值，全在那一张表里。
const 声音表 := preload("res://数据/声音表.gd")

# ── 状态机 ───────────────────────────────────────────────────
# 状态名常量集中在 状态名.gd（拼错就报红，不会运行时才崩）。
const 状态名 := preload("res://角色/宿管/状态/状态名.gd")
const 状态机 := preload("res://组件/状态机/状态机.gd")
const 手控状态 := preload("res://角色/宿管/状态/手控.gd")
const 待机状态 := preload("res://角色/宿管/状态/待机.gd")
const 巡逻状态 := preload("res://角色/宿管/状态/巡逻.gd")
const 追击状态 := preload("res://角色/宿管/状态/追击.gd")
const 攻击状态 := preload("res://角色/宿管/状态/攻击.gd")
const 搜索状态 := preload("res://角色/宿管/状态/搜索.gd")

## 状态机本体。`_ready` 里建，状态对象也在那儿注册。
## 下划线开头：供状态脚本通过 `host._机器` 取用。
var _机器

# ── 听觉（听声辨位）────────────────────────────────────────────
# 主人 2026-11-09 定：先把声音做出来，视觉察觉的视野限制后面再做。
# 她现在只能「听见」，拿到的是一个**坐标**，不是一个人 ——
# 所以听到之后去的是 `搜索`（到那儿看看），不是 `追击`（她追的是人）。
## 最后听到的那一声在哪儿。
var _听觉目标 := Vector2.ZERO
## 那一声传到她耳朵里有多响（0~1）。越响走得越快：轻响慢慢摸过去，巨响直接冲。
var _听觉音量: float = 0.0
## 这声还记得多久（秒）。归零 = 忘了，回去巡逻。
var _听觉剩余: float = 0.0

# ── 走 ────────────────────────────────────────────────────
const SPEED: float = 370.0        # 走速（像素/秒）
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

# ── 挥击（棍子）────────────────────────────
## 【2026-11-10 重写，主人定的】原来的挥击是「按下那一瞬间用 12 条射线扇形找目标，
#  找到就打」——等于先检测范围内有没有人再决定打不打得着。主人说这不对：
#  阿姨该是抬手就挥，棍子扫过谁算谁，前摇后摇都给得大。
## 现在拆成三段：前摇（抬手，站定、不判定）→ 判定期（棍子扫过扇形，扫到就打）→ 后摇（收棍）。
## 棍子是一根 Line2D，程序画出来，判定框就是这根棍子本身（棍长 × 棍宽 的窄条），
## 看得见的线和打人的框是同一个东西，不会出现「看着够不着却打中」。
## 【2026-11-09 20:05 削到三分之一，主人定的】原来是 200（2 米），现在 66.7。
## 削的是这一根常量，棍子长度、判定条长度、AI 的 `挥击距离` 会一起跟着变——
## 想再调，只改这一个数，别去别处补。
const SWING_RANGE: float = 200.0 / 3.0  # 棍长 = 攻击距离（像素）。原 200，现三分之一
const SWING_WINDUP: float = 0.35        # 前摇：抬手用时，期间站定、不判定
const SWING_SWEEP: float = 0.14         # 判定期：棍子从抬到位扫到底的用时
const SWING_RECOVER: float = 0.55       # 后摇：收棍用时，期间站定、不能再挥
const SWING_CD: float = 1.2             # 冷却：从起手算，隔这秒才能再挥
const SWING_ARC: float = 120.0          # 扫过的扇形角度（度）
const SWING_START_ANGLE: float = -SWING_ARC * 0.5   # 抬手角度（相对面朝方向，负数=往上抬）
const SWING_END_ANGLE: float = SWING_ARC * 0.5      # 扫到底的角度
const SWING_IDLE_ANGLE: float = 10.0    # 不挥的时候棍子斜指前下方的角度
const 棍宽: float = 8.0                 # 棍子粗细，同时就是判定条的宽度
const 握棍点 := Vector2(0, -26)         # 手握的位置（相对脚底原点，胸口高度）
const 握棍前伸: float = 6.0             # 手往前伸几像素，免得棍子从身体里长出来
## 够得着的距离：比棍长留一成余量，免得「刚进范围就起手、扫到时人已经出框」。
const 挥击距离: float = SWING_RANGE * 0.9

# 挥击阶段。0 = 没在挥，其余三档见上面常量。
const 挥_空 := 0
const 挥_前摇 := 1
const 挥_判定 := 2
const 挥_后摇 := 3

const 抓捕读条: float = 1.2             # 贴身按住 G 多久才把人扛上肩（秒）
const CARRY_STUDENT_OFFSET := Vector2(14, -34)  # 学生扛在肩上的相对位置
const CARRY_SPEED_MULT: float = 0.6     # 扛人时移速乘它

# ── AI（这轮只用到前五条）─────────────────────────────────
## 察觉半径（像素）。DetectZone 的圆半径照它设，改这里要同步改 .tscn。
## 策划案的「视野 9 米 / 听觉 2.6 米」是目标形态；这一轮先用一个圆形察觉圈，
## 因为它只需要回答「附近有没有人」，不需要视野锥和墙体遮挡。
const 察觉半径: float = 360.0
## 巡逻速度：比走速慢一截，免得她在楼道里跑得像在追人。
const 巡逻速度: float = SPEED * 0.6
## 追击速度：直接吃走速。策划案「追击 5.4 / 常走 4.6 米每秒」比例 ≈ 1.17，
## 这里 370 对 315 也正好 ≈ 1.17，和学生那套比例对得上，别再单独编一个数。
const 追击速度: float = SPEED
## 巡逻半径：从出生点往左右各走多远（像素）。主场景3 的楼板不长，先给 200。
const 巡逻半径: float = 200.0
## 贴身距离：横坐标差小于它就算「已经贴上了」，追击状态不再往前挤。
const 贴身距离: float = 30.0
## 待机最多站多久（秒）。超过就起身巡逻，免得她像根柱子插在楼道里。
const 待机最长: float = 2.0

# ── 脚步出声（2026-11-10 加）────────────────────────────────
# 巡逻速度 222 → 1 档很轻（学生得贴到 200px 内才听得见她）；
# 追击 / 手控 370 → 2 档较大（400px 内可闻）。搜索状态速度按音量在
# 222~370 之间插值，步子会随速度线在两档间切换，属正常现象。
# 步频是「行为」参数，跟着宿管走，不进声音表 —— 那里只管多响，不管多久一步。
const 跑动判定线: float = 300.0       # |velocity.x| 超过它就算跑（发 2 档）
const 脚步间隔_慢走: float = 0.5      # 巡逻速度的步频（秒/步）
const 脚步间隔_跑动: float = 0.3      # 追击/手控速度的步频（秒/步）

var _脚步计时: float = 0.0

## 巡逻用：起点与当下朝哪边走（+1 右 / -1 左）。由 `巡逻.gd` 维护。
var _巡逻起点 := Vector2.ZERO
var _巡逻方向: int = 1

var _swing_cd_left: float = 0.0         # 挥击冷却还剩几秒
## 挥击阶段（挥_空 / 前摇 / 判定 / 后摇）与这个阶段已经走了几秒
var _挥阶段: int = 挥_空
var _挥计时: float = 0.0
var _挥朝向: float = 1.0                # 这一棍朝哪边挥：起手时锁死，扫的过程不跟着转身
var _本棍已打中 := {}                   # 这一棍已经扫到过的目标（同一棍不重复打）
var _棍子: Line2D = null                # 程序画出来的那根棍子
var _swing_dir: float = 1.0             # 面朝哪边（1 右 / -1 左）。出生默认朝右，之后随方向键更新
var _carried_student: Node = null       # 正扛着哪个学生（null = 空肩）
var _抓捕进度: float = 0.0              # 这次按住 G 已经按了多久（秒）
var _抓捕目标: Node = null              # 正在按住的瘫倒学生（null = 没在抓）

var _on_ladder: bool = false
var _climbing: bool = false

# ── 通用读条 ────────────────────────────────────────────
# 读条只负责画，进度由 _抓捕进度 决定
const 读条 := preload("res://界面/读条/读条.gd")
var _读条条: CanvasLayer = null

var _coyote: float = 0.0
var _buffer: float = 0.0
var _hang_left: float = 0.0
var _fast_fall: bool = false


func _ready() -> void:
	# ── 碰撞层照规则表设一遍 ──────
	# 真源是 数据/通用规则.gd，.tscn 里的数字只当备份
	collision_layer = 规则.层_地板
	collision_mask = 规则.人站的地面
	$ClimbZone.collision_mask = 规则.层_梯子
	# 感应区认三层：站着的人（地板层）+ 瘫倒的人（瘫痪层）+ 可搬的东西（交互物层）
	$PickupZone.collision_mask = 规则.层_地板 | 规则.层_瘫痪 | 规则.层_交互物
	# 察觉圈只认人：站着的人 + 瘫倒的人。箱子门板那些不该让她「看见」。
	$DetectZone.collision_mask = 规则.层_地板 | 规则.层_瘫痪
	# 门靠这个组认出「推门的是宿管」，开门时长由门照清单决定
	add_to_group("keeper")
	$AnimatedSprite2D.play("待机")   # 生图只有一张朝右的姿态，朝左用水平翻转
	_棍子 = _建棍子()                # 棍子先握在手里（平时半透明，一眼看得出攻击距离）
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)
	Director.register_controllable(self)   # 向总管报到：我可以被玩家控制
	# 耳朵：声音从「事件中枢」广播出来，她只订阅，不去问学生
	Events.noise_made.connect(_听见声音)
	_搭状态机()


## 建状态机、注册全部状态、进第一个状态。
func _搭状态机() -> void:
	_机器 = 状态机.new()
	_机器.host = self
	_机器.加(状态名.手控, 手控状态.new())
	_机器.加(状态名.待机, 待机状态.new())
	_机器.加(状态名.巡逻, 巡逻状态.new())
	_机器.加(状态名.追击, 追击状态.new())
	_机器.加(状态名.攻击, 攻击状态.new())
	_机器.加(状态名.搜索, 搜索状态.new())
	_机器.启动(状态名.待机)


func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true


func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false


## 现在玩家控制的是不是我？（F1 切走之后就归 false）
func _受控() -> bool:
	return Director.当前控制 == self or Director.当前控制 == null


## 每帧：计时器往前推 → 推进挥击动作 → 跑状态机（状态机内部先问 `抢占()`）。
func _physics_process(delta: float) -> void:
	# 计时器照走，跟「现在谁在按键盘」无关
	_swing_cd_left = maxf(_swing_cd_left - delta, 0.0)
	# 耳朵的记性也在走：听见过的那一声，过一会儿就该忘掉
	_听觉剩余 = maxf(_听觉剩余 - delta, 0.0)
	# 挥击动作挂在这里而不是状态里：挥出去就得挥完，不因为状态被抢走而半截停住
	_推进挥击(delta)
	_机器.跑(delta)
	# 脚步出声放在状态机之后：这一帧走没走、走多快此时才定案；
	# 挥击 / 抓捕期间速度被按成 0，自然不响，不用挨个写特判
	_走出动静(delta)
	# 棍子不挥的时候跟着平时的朝向摆（一转身，握棍的那只手也跟着换边）
	if not _挥击中():
		_挥朝向 = _swing_dir
		_摆棍(SWING_IDLE_ANGLE, 0.42)


# ============================================================
# 抢占：优先级只写在这里一处。行序即优先级，返回空串 = 不用切。
# ============================================================
func 抢占(现在: String) -> String:
	# ① 玩家手里握着她 → 吃键盘，原来的 if 链原样跑（回归基线靠这一条保住）
	if _受控():
		return 状态名.手控
	# ② 没人按她：看见人就是最高优先。够得着就站住挥棍，够不着才压过去。
	#    注意这里**不返回「现在」**：待机/巡逻/追击之间怎么走由它们自己算（
	#    待机站够了会切巡逻，巡逻看不见人就掉头），抢占只管「看见人必须动手」。
	var 目标 := _看得见的目标()
	if 目标 != null:
		if global_position.distance_to(目标.global_position) <= 挥击距离:
			return 状态名.攻击
		return 状态名.追击
	# ③ 看不见人，但耳朵还记得一声响 → 去那个坐标看看。
	#    「看见」永远压过「听见」：眼睛是最可靠的信息，别让一声脚步把她从人身上拽走。
	#    记住的声音会过期（`_听觉剩余`），过期后她自己回去巡逻。
	if _听觉剩余 > 0.0:
		return 状态名.搜索
	# ④ 什么都没有：手控要退回 AI，其余交给状态自己
	if 现在 == 状态名.手控:
		return 状态名.待机
	return ""


# ============================================================
# AI 的服务函数 —— 状态脚本从这里取「看见了谁」「该不该走」，自己不做判断
# ============================================================

## 察觉圈里最近的那个人。没有就返回 null。
## 只认「有被打中接口的」——学生有，箱子没有；墙和门根本不在察觉圈认的层里。
## 瘫在地上的人也算：她要把人扛走这轮不做，但「已经追到了」得算得出来。
func _看得见的目标() -> Node:
	var 最近: Node = null
	var 最近距离 := 察觉半径
	for body in $DetectZone.get_overlapping_bodies():
		if body == self or not body.has_method("被打中"):
			continue
		var d: float = global_position.distance_to(body.global_position)
		if d < 最近距离:
			最近距离 = d
			最近 = body
	return 最近


## 听到一声响（事件中枢广播过来的）。她只知道两件事：**在哪儿、多响**。
##   ① 传不到她这儿（距离 ≥ 半径）→ 没听见。
##   ② 传到了但太轻（音量 < 最低反应音量）→ 耳朵没接住，不算。
##   ③ 正在惦记一件更大的事 → 小动静盖不掉它。
## 手控时照听（切回 AI 时她还记得刚才那声），但抢占里手控优先，不会抢操作。
func _听见声音(位置: Vector2, 半径: float, 来源: int) -> void:
	# 自己刚迈的这一步不算「听见了动静」：脚步就发在自己脚下（global_position），
	# 同帧同步回调、位置还没来得及变，距离必然 ≈ 0 —— 按 <4px 一刀切掉。
	# 不切的话她每迈一步都会把自己钩进「搜索」，永远走不出巡逻。
	# 代价：发在她脚边 4px 内的别的声也一起听不见 —— 那个距离上人早已在
	# 察觉圈（360px）里被看见，眼睛压过耳朵，没有实际损失。
	if global_position.distance_to(位置) < 4.0:
		return
	var 距离 := global_position.distance_to(位置)
	var 音量 := 声音表.音量(距离, 半径)
	if 音量 < 声音表.最低反应音量:
		return
	if _听觉剩余 > 0.0 and 音量 < _听觉音量:
		return
	_听觉目标 = 位置
	_听觉音量 = 音量
	_听觉剩余 = 声音表.记忆时长
	print("[宿管] 听见%s：距 %.0f / 半径 %.0f → 音量 %.2f（记住 %.0f 秒）" % [
		声音表.来源文字(来源), 距离, 半径, 音量, 声音表.记忆时长])


## 走路出声（仿 student.走出动静）：站在地上、真的在走，才按步频发一脚。
## 由 `_physics_process` 每帧调 —— 四个会走路的状态（手控/巡逻/追击/搜索）
## 共用这一份，塞进某个状态里其余的就会漏。空中 / 站定时脚没沾地或没在动，
## 自然不响。
func _走出动静(delta: float) -> void:
	if not is_on_floor() or absf(velocity.x) < 20.0:
		_脚步计时 = 0.0       # 脚停了：下一脚重新计时，不用等满间隔
		return
	_脚步计时 -= delta
	if _脚步计时 > 0.0:
		return
	var 跑 := absf(velocity.x) > 跑动判定线
	_脚步计时 = 脚步间隔_跑动 if 跑 else 脚步间隔_慢走
	if 跑:
		Events.发声(global_position, 声音表.档_较大, 声音表.来源_跑动)
	else:
		Events.发声(global_position, 声音表.档_很轻, 声音表.来源_脚步)


## 决策：现在该待在哪个状态。形状照参考项目的 `decide()`，但只留这轮要用的分支。
## 看见人 → 追击；看不见 → 巡逻。打人 / 抓捕 / 搜索都还没进来（主人要求后面再优化）。
func decide() -> String:
	if _看得见的目标() == null:
		return 状态名.巡逻
	return 状态名.追击


## 朝某个横坐标走一步。返回值 = 这一步走顺了吗（撞墙 / 到崖边为 false）。
##
## 两条探针（照参考项目膝高探法的路数，也是学生抛投探墙同一套）：
##   ① 前方膝高有墙 → 停下（这轮不蹦台阶，主场景3 没台阶要跨）
##   ② 前方脚下没地面 → 停下（别走下楼层，掉下去就不叫「追人」了）
## 两条射线都要 exclude 自己：宿管本体站在地板层上，不排除会先量到自己（静默错误）。
func _朝目标走(目标横坐标: float, 速度: float, delta: float) -> bool:
	var 方向 := signf(目标横坐标 - global_position.x)
	if 方向 == 0.0:
		方向 = float(_巡逻方向)
	_面朝(方向)

	var 走顺 := true
	if is_on_floor():
		if _前方有墙(方向):
			走顺 = false
		elif _前方是崖(方向):
			走顺 = false

	if 走顺:
		velocity.x = move_toward(velocity.x, 方向 * 速度, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# 重力：AI 自己不会跳，只要别浮在空中
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	move_and_slide()
	return 走顺


## 转向 + 翻转贴图。生图只有一张朝右的姿态。
## 手控时朝向由 `_更新朝向()` 按方向键管，AI 不抢。
func _面朝(方向: float) -> void:
	if 方向 == 0.0:
		return
	_swing_dir = 方向
	if not _受控():
		$AnimatedSprite2D.flip_h = 方向 < 0.0


## 膝高往前 18px 有没有墙（地板层）。
func _前方有墙(方向: float) -> bool:
	var 膝 := global_position + Vector2(0, -22)
	var 查询 := PhysicsRayQueryParameters2D.create(
		膝, 膝 + Vector2(18.0 * 方向, 0.0), 规则.层_地板)
	查询.collide_with_areas = false
	查询.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_ray(查询).is_empty()


## 脚前 14px 往下探 10px 有没有地面。探不到 = 崖边。
func _前方是崖(方向: float) -> bool:
	var 起步 := global_position + Vector2(14.0 * 方向, -2.0)
	var 查询 := PhysicsRayQueryParameters2D.create(
		起步, 起步 + Vector2(0.0, 10.0), 规则.人站的地面)
	查询.collide_with_areas = false
	查询.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(查询).is_empty()


## 把感应区原样交给总管，由它解析编号并分发。写法与学生一致。
func _上报交互(键: String) -> void:
	Director.交互(self, 键, $PickupZone.get_overlapping_areas())


## E 键只做一件事：开/关面前那扇门。开门耗时由门按清单决定。
func _开门() -> void:
	_上报交互("open_door")


# ============================================================
# 挥击 / 抓捕 / 扛人。数值全部在文件顶部的常量里。
# ============================================================

## 每帧更新朝向：按住方向键时更新，未按时保持上一次朝向。
## 朝右为默认贴图，朝左时水平翻转。
func _更新朝向() -> void:
	var d := signf(Input.get_axis("left", "right"))
	if d != 0.0:
		_swing_dir = d
		$AnimatedSprite2D.flip_h = d < 0.0

## 抬手挥一记棍子。**不看面前有没有人**：手抬起来就挥出去，扫到谁算谁。
## 三段时序全在 `_推进挥击` 里走，前摇后摇期间站定（主人要的「前摇后摇比较大」）。
func _挥击() -> void:
	if _挥击中() or _swing_cd_left > 0.0:
		return   # 这一棍还没走完 / 还在冷却，挥不出来
	velocity.x = 0.0
	_swing_cd_left = SWING_CD
	_挥阶段 = 挥_前摇
	_挥计时 = 0.0
	_挥朝向 = _swing_dir    # 起手锁方向：扫的过程不跟着转身，也不被 AI 的面朝改掉
	_本棍已打中.clear()
	_摆棍(SWING_IDLE_ANGLE, 1.0)


## 是不是正在挥（前摇 / 判定 / 后摇任意一段）。手控与 AI 都拿它锁移动。
func _挥击中() -> bool:
	return _挥阶段 != 挥_空


## 挥击动作推进：前摇抬手 → 棍子扫过扇形（只有这段判定）→ 收棍。
## 全程按住水平速度：挥棍时不能挪步，是「站定挥」而不是「边走边扫」。
func _推进挥击(delta: float) -> void:
	if _挥阶段 == 挥_空:
		return
	_挥计时 += delta
	velocity.x = 0.0

	match _挥阶段:
		挥_前摇:
			var 抬手 := clampf(_挥计时 / SWING_WINDUP, 0.0, 1.0)
			抬手 = 1.0 - (1.0 - 抬手) * (1.0 - 抬手)   # 先快后慢：起手利落，抬到位顿一下
			_摆棍(lerpf(SWING_IDLE_ANGLE, SWING_START_ANGLE, 抬手), lerpf(0.5, 1.0, 抬手))
			if _挥计时 >= SWING_WINDUP:
				_挥计时 = 0.0
				_挥阶段 = 挥_判定
				闪一下攻击范围()   # 淡金扇形：这一棍会扫过的范围，一眼看出打得到哪
		挥_判定:
			var 扫完 := clampf(_挥计时 / SWING_SWEEP, 0.0, 1.0)
			var 扫前 := clampf((_挥计时 - delta) / SWING_SWEEP, 0.0, 1.0)
			var 本角 := lerpf(SWING_START_ANGLE, SWING_END_ANGLE, 扫完)
			# 只量「这一帧扫过的那一小段」：上一帧的角度 → 这一帧的角度
			棍扫判定(lerpf(SWING_START_ANGLE, SWING_END_ANGLE, 扫前), 本角)
			_摆棍(本角, 1.0)
			if _挥计时 >= SWING_SWEEP:
				_挥计时 = 0.0
				_挥阶段 = 挥_后摇
		挥_后摇:
			var 收 := clampf(_挥计时 / SWING_RECOVER, 0.0, 1.0)
			_摆棍(lerpf(SWING_END_ANGLE, SWING_IDLE_ANGLE, 收), lerpf(1.0, 0.42, 收))
			if _挥计时 >= SWING_RECOVER:
				_挥阶段 = 挥_空
				_挥计时 = 0.0
				_摆棍(SWING_IDLE_ANGLE, 0.42)


## 棍子这一帧从 `起角` 扫到 `止角`（度）。切成不超过 6° 的小段逐段量，
## 帧率再低也不会从人身上一跳而过 —— 这是「扫过谁算谁」能站得住的关键。
func 棍扫判定(起角: float, 止角: float) -> void:
	var 段数 := maxi(2, int(ceil(absf(止角 - 起角) / 6.0)))
	for i in range(段数):
		棍子打一记(lerpf(起角, 止角, float(i + 1) / float(段数)))


## 用棍子这一刻的位置量一次：把棍子当作 棍长 × 棍宽 的窄条去撞人。
## 判定形状和 Line2D 画出来的那根棍子同长同角度 —— 看得见的就是打得到的。
func 棍子打一记(角: float) -> void:
	var 手 := global_position + 握棍点 + Vector2(握棍前伸 * _挥朝向, 0.0)
	var 朝向 := _棍方向(角)
	var 形 := RectangleShape2D.new()
	形.size = Vector2(SWING_RANGE, 棍宽)
	var 查询 := PhysicsShapeQueryParameters2D.new()
	查询.shape = 形
	查询.transform = Transform2D(朝向.angle(), 手 + 朝向 * (SWING_RANGE * 0.5))
	查询.collision_mask = 规则.层_地板 | 规则.层_瘫痪
	查询.collide_with_areas = false
	查询.exclude = [get_rid()]
	for 结果 in get_world_2d().direct_space_state.intersect_shape(查询, 16):
		var 目标 = 结果.get("collider")
		if 目标 == null or 目标 == self or not 目标.has_method("被打中"):
			continue      # 墙、门、箱子不归棍子管
		if _本棍已打中.has(目标):
			continue      # 同一棍只在扫到它的第一下算数，别一棍打出两格血
		_本棍已打中[目标] = true
		# 推的方向按「目标在我哪一边」算，不按棍子挥到哪一段算 ——
		# 站在我身后被扫到的人，也该被我这一棍往外推，而不是往回吸。
		var 推 := signf(目标.global_position.x - global_position.x)
		if 推 == 0.0:
			推 = _挥朝向      # 正好站在头顶的极端情况：按我面朝的方向推
		目标.被打中(推)
		print("[宿管] 棍子扫中：%s（剩 %d/%d 格）" % [目标.name, 目标.血量, 目标.MAX_HP])


## 棍子这一刻朝哪边指。传进来的 `角` 是**度**（跟常量一个单位），这里再转弧度。
## 先按「朝右」算，再把 x 整体镜像到朝向 —— 直接拿 (-1, 0) 去 rotated() 会跨过
## 180° 转反（朝左时抬手变成往下扫），这个坑很容易踩。
func _棍方向(角: float) -> Vector2:
	var 弧度 := deg_to_rad(角)
	var 方向 := Vector2(cos(弧度), sin(弧度))
	方向.x *= _挥朝向
	return 方向


## 建那根棍子。程序画一条线，宽度 = 棍宽，平时半透明握在手里。
func _建棍子() -> Line2D:
	var 线 := Line2D.new()
	线.name = "棍子"
	线.width = 棍宽
	线.antialiased = false
	线.begin_cap_mode = Line2D.LINE_CAP_ROUND
	线.end_cap_mode = Line2D.LINE_CAP_ROUND
	线.z_index = 2      # 盖在身体贴图上面，站在暗处也看得见
	add_child(线)
	return 线


## 把棍子摆到某个角度：手柄在胸前，棍尖沿 `角` 方向伸出 SWING_RANGE。
## `亮` 是透明度：待机 0.42（看得见是根棍子又不抢戏），挥击 1.0。
func _摆棍(角: float, 亮: float) -> void:
	if _棍子 == null or not is_instance_valid(_棍子):
		return
	var 手 := 握棍点 + Vector2(握棍前伸 * _挥朝向, 0.0)
	_棍子.points = PackedVector2Array([手, 手 + _棍方向(角) * SWING_RANGE])
	_棍子.default_color = Color(1.0, 0.9, 0.55, 亮)


## 挥击时把这一棍会扫过的扇形淡影闪一下：淡金填充 = 覆盖范围，外缘光弧 = 打击感。
## 棍子本身已经把「打得到哪」画出来了，这层扇形只是让范围更一眼可见，0.2 秒就淡掉。
func 闪一下攻击范围() -> void:
	var 点 := PackedVector2Array()
	点.append(Vector2.ZERO)
	for i in range(13):
		var a := lerpf(SWING_START_ANGLE, SWING_END_ANGLE, float(i) / 12.0)
		点.append(_棍方向(a) * SWING_RANGE)

	# ① 真实判定范围：淡金扇形
	var poly := Polygon2D.new()
	poly.polygon = 点
	poly.color = Color(1.0, 0.82, 0.3, 0.22)
	poly.position = 握棍点
	add_child(poly)

	# ② 打击感：沿扇形外缘一条光弧，向外张开 + 淡出
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(1, 0.95, 0.7, 0.95)
	var 弧点 := PackedVector2Array()
	for i in range(25):
		var a := lerpf(SWING_START_ANGLE, SWING_END_ANGLE, float(i) / 24.0)
		弧点.append(_棍方向(a) * SWING_RANGE * 0.88)
	line.points = 弧点
	line.position = 握棍点
	add_child(line)

	var tw1 := create_tween()
	tw1.tween_property(poly, "modulate:a", 0.0, 0.2).set_delay(0.05)
	tw1.tween_callback(poly.queue_free)
	var tw2 := create_tween()
	tw2.tween_property(line, "modulate:a", 0.0, 0.2)
	tw2.parallel().tween_property(line, "scale", Vector2(1.12, 1.12), 0.2)
	tw2.tween_callback(line.queue_free)


## 【2026-11-10 撤掉】这里原来有个 `_扇形找目标()`：挥击时先打 12 条射线在扇形里
## 找一个目标，找到再打 —— 那正是主人说不对的「先检测范围内有没有敌人」。
## 现在判定换成了「棍子扫过谁算谁」（`棍扫判定` / `棍子打一记`），本函数已无调用方。

## 贴身 40px 内有没有瘫痪的学生？抓捕读条的对象从这里来
func _贴身瘫痪学生() -> Node:
	for body in $PickupZone.get_overlapping_bodies():
		if body != self and body.has_method("被打中") and body.瘫痪:
			return body
	return null


## 我这根读条。第一次真要用了才建（那时场景已经搭好，挂哪儿不会错）
func _我的读条() -> CanvasLayer:
	if _读条条 == null or not is_instance_valid(_读条条):
		_读条条 = 读条.新建(self)
	return _读条条


## 收条。没建过就不建 —— 不能为了「收一根还不存在的条」反而去造一根
func _收读条() -> void:
	if _读条条 != null and is_instance_valid(_读条条):
		_读条条.收()


## G 键：肩上有人就放下；空肩时贴身按住 `抓捕读条` 秒把人扛走。
## 松开按键、目标被救起或目标被移走时进度清零。
func _抓捕(delta: float) -> void:
	# 肩上有人：G 只管放下，不进读条
	if _carried_student != null:
		if Input.is_action_just_pressed("grab"):
			_放下学生()
		return

	# 刚按下：就近找一个瘫倒的学生，开始计时
	if Input.is_action_just_pressed("grab"):
		_抓捕目标 = _贴身瘫痪学生()
		_抓捕进度 = 0.0
		if _抓捕目标 != null:
			print("[宿管] 按住 G 开始抓捕 %s（%.1f 秒）" % [_抓捕目标.name, 抓捕读条])
			_我的读条().开始(self, "抓捕", 抓捕读条)
		else:
			print("[宿管] 身边没有瘫倒的学生")

	# 松手 / 本来就没抓到人 → 清零
	if _抓捕目标 == null or not Input.is_action_pressed("grab"):
		_取消抓捕()
		return

	# 按着的这一秒里，目标被别人拉起来了、或者被搬走了 → 抓不下去了
	if not is_instance_valid(_抓捕目标) or not _抓捕目标.瘫痪 or _抓捕目标.被扛着:
		print("[宿管] 抓捕中断：%s 已经不在原地瘫着了" % _抓捕目标.name)
		_取消抓捕()
		return

	_抓捕进度 += delta
	_我的读条().推进(_抓捕进度)   # 条跟着走：填到几分、还剩几秒
	velocity.x = 0.0   # 按住抓人的时候站定（跟挥击一样，抓人不是边跑边抓）
	if _抓捕进度 >= 抓捕读条:
		var 目标 := _抓捕目标
		_取消抓捕()      # 先清读条、收条，再扛 —— _扛起 里会改 _carried_student
		_扛起(目标)


## 清掉这次抓捕：进度归零、目标松手、条收起。不打印，打印由调用方决定说哪一句
func _取消抓捕() -> void:
	_抓捕目标 = null
	_抓捕进度 = 0.0
	_收读条()


## 读条满了：把学生扛上肩。单向接口，学生那边自己 reparent + 清速度
func _扛起(学生: Node) -> void:
	_carried_student = 学生
	学生.被扛起(self)
	# 扛人期间不能爬梯
	_climbing = false
	print("[宿管] 抓捕完成，%s 扛上肩（移速 %.0f）" % [学生.name, SPEED * CARRY_SPEED_MULT])


## 肩上的学生放下来：摆到脚边地面上（按朝向）。
## 摆在脚边而非胸口，避免碰撞体恢复后两个身体重叠被物理弹开。
func _放下学生() -> void:
	var 学生 := _carried_student
	_carried_student = null
	学生.被放下(get_parent())
	# 学生的原点在脚底（碰撞体从 -44 到 0），摆到宿管脚边、贴地面，正好不重叠
	学生.global_position = global_position + Vector2(_swing_dir * 26.0, 0.0)
	print("[宿管] 放下了 %s" % 学生.name)
