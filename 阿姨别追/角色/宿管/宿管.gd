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

# ── 挥击 / 抓捕 / 扛人（W2D2，2026-11-04）────────────────────
# 策划案原数：挥击身前 2 米 × 120° 扇形、1 格伤害、站定才能挥、
# 后摇 0.8 秒、CD 1.2 秒；拎人移速 −40%（370 × 0.6 = 222）、不能爬梯。
# 20:01 主人改过一次：抓捕不再是「按住读条」，学生瘫痪后按 G **一键直接扛**。
# 11-05 17:30 主人又改回来：照策划案 §6 交互耗时表，「抓捕 1.2 秒」——按住不放才扛走。
#   想退回一键扛：把下面的 抓捕读条 改成 0.0，一行的事。
const SWING_RANGE: float = 200.0        # 挥击距离（像素）。2 米 × 100 像素/米
const SWING_ARC: float = 120.0          # 扇形角度（度）
const SWING_RAYS: int = 12              # 扇形里打几条射线（越多越密，12 条足够）
const SWING_RECOVER: float = 0.8        # 后摇：挥完这秒内不能再挥、不能动
const SWING_CD: float = 1.2             # 冷却：从挥出起算，隔这秒才能再挥
const 抓捕读条: float = 1.2             # 贴身按住 G 多久才把人扛上肩（策划案 §6）
const CARRY_STUDENT_OFFSET := Vector2(14, -34)  # 学生扛在肩上的相对位置
const CARRY_SPEED_MULT: float = 0.6     # 扛人时移速乘它（策划案 −40%）

var _swing_cd_left: float = 0.0         # 挥击冷却还剩几秒
var _swing_recover_left: float = 0.0    # 后摇还剩几秒（>0 时不能动）
var _swing_dir: float = 1.0             # 面朝哪边（1 右 / -1 左）。出生默认朝右，之后随方向键更新
var _carried_student: Node = null       # 正扛着哪个学生（null = 空肩）
var _抓捕进度: float = 0.0              # 这次按住 G 已经按了多久（秒）
var _抓捕目标: Node = null              # 正在按住的瘫倒学生（null = 没在抓）

var _on_ladder: bool = false
var _climbing: bool = false

# ── 通用读条（2026-11-05）────────────────────────────────────
# 按住 G 抓人这 1.2 秒得让玩家看见还剩多少，不然「按了没反应」。
# 条住在 `界面/读条/`，只负责画；「已经按了多久」还是 _抓捕进度 说了算。
const 读条 := preload("res://界面/读条/读条.gd")
var _读条条: CanvasLayer = null

var _coyote: float = 0.0
var _buffer: float = 0.0
var _hang_left: float = 0.0
var _fast_fall: bool = false


func _ready() -> void:
	# 门靠这个认出「推门的是宿管」，然后去清单里取宿管那一行的时长。
	# 这一句只说明「我是谁」，不说明「我多快」—— 多快是场景数据。
	add_to_group("keeper")
	$AnimatedSprite2D.play("待机")   # 生图只有一张朝右的姿态，朝左用水平翻转
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
	# 计时器照走，跟「现在谁被控制」无关 —— 不然切走再切回来会先僵 0.8 秒
	_swing_cd_left = maxf(_swing_cd_left - delta, 0.0)
	_swing_recover_left = maxf(_swing_recover_left - delta, 0.0)

	# 没被控制时：不吃键盘，但照常受重力，不会浮在空中
	# 2026-11-05 补：正按住 G 抓到一半被切走 → 这次抓捕作废、条收掉。
	# 不收的话这根条会一直亮在头顶：这个分支之后整个函数就早退了，
	# 再没有任何一帧会回来推进它，玩家看到的就是「进度条卡住不动」。
	if not _受控():
		if _抓捕目标 != null:
			_取消抓捕()
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	var dir := Input.get_axis("left", "right")
	var updown := Input.get_axis("up", "down")

	# ── 爬梯：碰到梯子 + 按了上下才算挂住。扛着人挂不住（策划案：拎人不能爬）──
	if _on_ladder and updown != 0.0 and _carried_student == null:
		_climbing = true
	if _carried_student != null:
		_climbing = false
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

	# ── W2D2 · 键位各管一件事（20:01 主人定的：攻击/搬运分开，搬运一键）──
	#   F（interaction）→ 只挥击（攻击）
	#   G（grab）       → 只扛人：肩上有人就放下；贴身有瘫倒的学生就**按住读条 1.2 秒**扛走
	_更新朝向()
	if Input.is_action_just_pressed("interaction"):
		_挥击()
	_抓捕(delta)

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
	# 按住抓人时不记账：抓人得站定，边跳边抓不合理
	if Input.is_action_just_pressed("jump") and _抓捕目标 == null:
		_buffer = JUMP_BUFFER
	else:
		_buffer = maxf(_buffer - delta, 0.0)

	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		_hang_left = 0.0
		_fast_fall = false

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	# ── 左右速度 ──
	# 三个状态影响移速：后摇站定（挥完那 0.8 秒）、扛人 ×0.6（策划案 −40%）、
	# 按住抓人时站定（不然能边跑边抓，这 1.2 秒读条就白设了）
	var 走速 := SPEED
	if _carried_student != null:
		走速 = SPEED * CARRY_SPEED_MULT
	if _抓捕目标 != null:
		dir = 0.0
	if dir != 0.0 and _swing_recover_left <= 0.0:
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > 走速):
			velocity.x = move_toward(velocity.x, dir * 走速, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# 扛着学生时，把他摆到肩上（位置每帧算，跟学生搬箱子同一个套路）
	if _carried_student != null and is_instance_valid(_carried_student):
		_carried_student.global_position = global_position + Vector2(_swing_dir * CARRY_STUDENT_OFFSET.x, CARRY_STUDENT_OFFSET.y)

	move_and_slide()


## 我碰到了东西，但不知道那是什么，也轮不到我猜。
## 写法和学生那份一模一样：把「感应区里有哪些东西」原样交给总管，由楼层代理认。
## 【2026-11-04 修架构】以前这里自己遍历感应区、看组名、直接调门的 press 接口，
## 和策划案 §7.6.2 第 2 条对着干（角色不该知道门在哪）。现在只上报，不判断。
func _上报交互(键: String) -> void:
	Director.report(
		# 多层时 floor_of() 会返回空字符串（已知技术债，做二楼时再修），
		# 现在只有一层，返回的就是"一楼"。
		Director.floor_of(self),
		"interact",
		{ "谁": self, "键": 键, "碰到": $PickupZone.get_overlapping_areas() }
	)


## E 键只做一件事：开/关面前那扇门。她捡不了东西，也搬不了箱子
## 注意：这里没有「宿管开门 1.5 秒」这种数字。她只是递申请，快慢由门照清单决定。
## 「面前有没有门」也不由她判断 —— 她只上报"我按了开门键"，代理去认。
func _开门() -> void:
	_上报交互("open_door")


# ============================================================
# W2D2 · 挥击 / 抓捕 / 扛人（阿姨打人那件事的宿管侧）
# ------------------------------------------------------------
# 策划案数字全在顶部常量里：2 米 × 120° / 后摇 0.8 秒 / CD 1.2 秒 /
# 抓捕读条 1.2 秒 / 扛人移速 −40%。
# 素材后面有：挥击那一下暂不播动画，学生被打中的「变红半透明」就是命中反馈。
# 朝向（18:51 主人定）：宿管**持续**记住自己面朝哪边——移动时更新，
# 挥击/扛人位置都跟着朝向走。以后做动画（左挥/右挥两套帧）直接读 _swing_dir。
# ============================================================

## 每帧更新朝向：按住方向键的哪边就面朝哪边（没按就维持上一次的）
## 贴图是百炼生成的一张**朝右**侧身像（粉底已离线抠掉），朝左就把图水平翻转。
## 要是主人看出方向反了，把下面 flip_h 那一行改成 `= d > 0.0` 即可。
func _更新朝向() -> void:
	var d := signf(Input.get_axis("left", "right"))
	if d != 0.0:
		_swing_dir = d
		$AnimatedSprite2D.flip_h = d < 0.0

## 朝面对方向挥一记扫把：站定、扇形射线扫一遍，打中学生就掉她一格血
func _挥击() -> void:
	if _swing_cd_left > 0.0:
		return   # 还在冷却，挥不出来
	# 站定才能挥：挥的那一下速度清零，后摇里也走不动（见上面移速段）
	velocity.x = 0.0
	_swing_cd_left = SWING_CD
	_swing_recover_left = SWING_RECOVER
	闪一下攻击范围()   # 让主人看见这一刀扇形有多大（19:31 要的「看到攻击范围」）
	var 打中谁 := _扇形找目标()
	if 打中谁 != null:
		打中谁.被打中()
		print("[宿管] 挥击命中：%s（剩 %d/%d 格）" % [打中谁.name, 打中谁.血量, 打中谁.MAX_HP])
	else:
		print("[宿管] 挥了个空")


## 挥击那一下闪出的范围（跟判定扇形同尺寸：200px × 120°，从胸口张开）
## 两层：① 淡金扇形 = 真实判定范围（一眼看出打得到哪）
##       ② 扩散光弧 = 打击感（程序画的：线沿扇形边缘扩张并淡出）
## 为什么不用 AI 特效图：生成的图不可控（上一版出来是白底黑涂鸦），
## 而且程序画的尺寸能跟判定 100% 对齐，还不花生图额度。
func 闪一下攻击范围() -> void:
	var 弧 := SWING_ARC * deg_to_rad(1.0)
	var 每步 := 弧 / 12.0
	var 点 := PackedVector2Array()
	点.append(Vector2.ZERO)
	for i in range(13):
		var a := -弧 * 0.5 + 每步 * i
		点.append(Vector2(_swing_dir, 0.0).rotated(a) * SWING_RANGE)

	# ① 真实判定范围：淡金扇形
	var poly := Polygon2D.new()
	poly.polygon = 点
	poly.color = Color(1.0, 0.82, 0.3, 0.28)
	poly.position = Vector2(0, -26)
	add_child(poly)

	# ② 打击感：沿扇形外缘一条光弧，向外张开 + 淡出
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(1, 0.95, 0.7, 0.95)
	var 弧点 := PackedVector2Array()
	for i in range(25):
		var a := -弧 * 0.5 + 弧 * (float(i) / 24.0)
		弧点.append(Vector2(_swing_dir, 0.0).rotated(a) * SWING_RANGE * 0.88)
	line.points = 弧点
	line.position = Vector2(0, -26)
	add_child(line)

	var tw1 := create_tween()
	tw1.tween_property(poly, "modulate:a", 0.0, 0.2).set_delay(0.05)
	tw1.tween_callback(poly.queue_free)
	var tw2 := create_tween()
	tw2.tween_property(line, "modulate:a", 0.0, 0.2)
	tw2.parallel().tween_property(line, "scale", Vector2(1.12, 1.12), 0.2)
	tw2.tween_callback(line.queue_free)


## 身前 2 米 × 120° 扇形里有没有学生？射线一把（12 条），谁近打谁
## 两个坑（无头诊断出来的）：
##   ① 射线起点若在自己脚底，会先撞进宿管自己的碰撞体——整条射线被自己吞掉
##   ② 学生的 ClimbZone/PickupZone 感应区比身体大，先撞进去射线就停在感应区上
## 对策：起点抬到胸口（出自己身体）+ exclude 自己 + 只认身体不认感应区
func _扇形找目标() -> Node:
	var 命中: Node = null
	var 最近距离 := SWING_RANGE
	var half_arc := deg_to_rad(SWING_ARC) * 0.5
	var 每步角度 := deg_to_rad(SWING_ARC / SWING_RAYS)   # 一条射线管几度
	var 起点 := global_position + Vector2(0, -26)        # 胸口：既出自己身位，也够得着学生的身体
	for i in range(SWING_RAYS):
		var 角 := -half_arc + 每步角度 * i
		var 朝向 := Vector2(_swing_dir, 0.0).rotated(角)
		var 查询 := PhysicsRayQueryParameters2D.create(
			起点, 起点 + 朝向 * SWING_RANGE)
		查询.collide_with_areas = false
		查询.collide_with_bodies = true
		查询.exclude = [self]
		var 结果 := get_world_2d().direct_space_state.intersect_ray(查询)
		if not 结果.is_empty():
			var 目标: Node = 结果["collider"]
			# 打的是学生（CharacterBody2D 且有「被打中」这个接口），不是箱子不是门
			if 目标 != self and 目标.has_method("被打中"):
				if 结果["position"].distance_to(起点) < 最近距离:
					最近距离 = 结果["position"].distance_to(起点)
					命中 = 目标
	return 命中


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


## G 的全部逻辑：肩上有人就放下；空肩就贴身按住 1.2 秒把人扛走。
## 为什么改成按住：策划案 §6 交互耗时表写着「抓捕 1.2s」。一键扛等于没有反抗窗口，
## 宿管贴到人就必抓；按住 1.2 秒给对面留一个「扔下东西就跑」的缝。
## 什么时候进度清零：松手 / 目标被别人拉起来了 / 目标被搬走了。
##   —— 这三种都是宿管自己发现自己抓不下去了，不是伸手去改别人身上的状态。
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
	# 扛人不能爬梯（策划案）；肩上有人时梯子挂不住
	_climbing = false
	print("[宿管] 抓捕完成，%s 扛上肩（移速 %.0f）" % [学生.name, SPEED * CARRY_SPEED_MULT])


## 肩上的学生放下来：摆到脚边地面上（按朝向），瘫着趴地上。
## 为什么摆脚边不摆胸口：碰撞体一恢复，重叠的身体会被物理弹开——
## 主人 18:51 验收看到的「人消失了」就是这个：学生被弹飞出画面（地图还没封边）。
func _放下学生() -> void:
	var 学生 := _carried_student
	_carried_student = null
	学生.被放下(get_parent())
	# 学生的原点在脚底（碰撞体从 -44 到 0），摆到宿管脚边、贴地面，正好不重叠
	学生.global_position = global_position + Vector2(_swing_dir * 26.0, 0.0)
	print("[宿管] 放下了 %s" % 学生.name)
