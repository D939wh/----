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
# 后摇 0.8 秒、CD 1.2 秒；抓捕贴身长按 1.2 秒读条，被打断则重置。
# 学生拎人移速 −40% 不变（370 × 0.6 = 222）、不能爬梯。
# 素材后面有，挥击动画先用现有帧占位（打中那一下学生变红半透明）。
const SWING_RANGE: float = 200.0        # 挥击距离（像素）。2 米 × 100 像素/米
const SWING_ARC: float = 120.0          # 扇形角度（度）
const SWING_RAYS: int = 12              # 扇形里打几条射线（越多越密，12 条足够）
const SWING_RECOVER: float = 0.8        # 后摇：挥完这秒内不能再挥、不能动
const SWING_CD: float = 1.2             # 冷却：从挥出起算，隔这秒才能再挥
const GRAB_TIME: float = 1.2            # 抓捕读条总时长（秒）
const GRAB_RANGE: float = 40.0          # 多近算「贴身」（像素）
const CARRY_STUDENT_OFFSET := Vector2(14, -34)  # 学生扛在肩上的相对位置
const CARRY_SPEED_MULT: float = 0.6     # 扛人时移速乘它（策划案 −40%）

var _swing_cd_left: float = 0.0         # 挥击冷却还剩几秒
var _swing_recover_left: float = 0.0    # 后摇还剩几秒（>0 时不能动）
var _swing_dir: float = 1.0             # 面朝哪边（1 右 / -1 左）。出生默认朝右，之后随方向键更新
var _grabbing: bool = false             # 正在长按读条抓人？
var _grab_target: Node = null           # 读条目标是哪个学生
var _grab_progress: float = 0.0         # 读条进度（0~1）
var _carried_student: Node = null       # 正扛着哪个学生（null = 空肩）

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
	$AnimatedSprite2D.play("朝右")   # 出生默认面朝右（贴图两个动画：朝右/朝左）
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

	# ── W2D2 · 键位各管一件事（18:51 主人验收定的：攻击/搬运分开）──
	#   F（interaction）→ 只挥击（攻击）
	#   G（grab）       → 只扛人：扛着就放下；贴身有瘫痪学生就按住读条扛上肩
	_更新朝向()
	if Input.is_action_just_pressed("interaction"):
		_挥击()
	if Input.is_action_just_pressed("grab"):
		if _carried_student != null:
			_放下学生()
		elif _贴身瘫痪学生() != null:
			_grabbing = true
			_grab_target = _贴身瘫痪学生()
			_grab_progress = 0.0
			print("[宿管] 开始抓捕读条（按住 G 别松）")

	# ── 读条推进：按住 G 且目标还在贴身范围内，1.2 秒满 → 扛上肩 ──
	if _grabbing:
		if not Input.is_action_pressed("grab") or _grab_target == null \
				or not is_instance_valid(_grab_target) \
				or global_position.distance_to(_grab_target.global_position) > GRAB_RANGE * 1.5:
			print("[宿管] 抓捕被打断，进度清零")
			_grabbing = false
			_grab_target = null
			_grab_progress = 0.0
		else:
			_grab_progress += delta / GRAB_TIME
			if _grab_progress >= 1.0:
				_扛起(_grab_target)
				_grabbing = false
				_grab_target = null
				_grab_progress = 0.0

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
	# 三个状态影响移速：后摇站定（挥完那 0.8 秒）、扛人 ×0.6（策划案 −40%）、读条时站定
	var 走速 := SPEED
	if _carried_student != null:
		走速 = SPEED * CARRY_SPEED_MULT
	if dir != 0.0 and _swing_recover_left <= 0.0 and not _grabbing:
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > 走速):
			velocity.x = move_toward(velocity.x, dir * 走速, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# ── 挥击冷却/后摇计时（每帧减一点）──
	_swing_cd_left = maxf(_swing_cd_left - delta, 0.0)
	_swing_recover_left = maxf(_swing_recover_left - delta, 0.0)

	# 扛着学生时，把他摆到肩上（位置每帧算，跟学生搬箱子同一个套路）
	if _carried_student != null and is_instance_valid(_carried_student):
		_carried_student.global_position = global_position + Vector2(_swing_dir * CARRY_STUDENT_OFFSET.x, CARRY_STUDENT_OFFSET.y)

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
## 贴图切两个动画：朝右 / 朝左（百炼生图，黑底已离线抠掉）。
## 要是主人看出两边反了，把下面两行的「朝右」「朝左」对调即可。
func _更新朝向() -> void:
	var d := signf(Input.get_axis("left", "right"))
	if d != 0.0 and d != _swing_dir:
		_swing_dir = d
		$AnimatedSprite2D.play("朝右" if d > 0.0 else "朝左")

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
## 两层一起闪：① 淡金扇形 = 真实判定范围（一眼看出打得到哪）
##             ② 百炼生成的弧光图（白底已离线抠掉）= 好看的部分
## 挥完 0.18 秒淡出消失。图是「随便先做一点」的占位，主人看效果再定。
func 闪一下攻击范围() -> void:
	var 弧 := SWING_ARC * deg_to_rad(1.0)
	var 每步 := 弧 / 12.0
	var 点 := PackedVector2Array()
	点.append(Vector2.ZERO)
	for i in range(13):
		var a := -弧 * 0.5 + 每步 * i
		点.append(Vector2(_swing_dir, 0.0).rotated(a) * SWING_RANGE)

	# ① 真实判定范围：一层淡金扇形
	var poly := Polygon2D.new()
	poly.polygon = 点
	poly.color = Color(1.0, 0.82, 0.3, 0.30)
	poly.position = Vector2(0, -26)
	add_child(poly)

	# ② 弧光图：缩到 400px 宽、胸口居中
	var spr := Sprite2D.new()
	spr.texture = 预载特效图
	var 缩放 := 400.0 / float(spr.texture.get_width())
	spr.scale = Vector2(缩放, 缩放)
	spr.position = Vector2(0, -26)
	spr.modulate = Color(1, 1, 1, 0.95)
	add_child(spr)

	var tw := create_tween()
	tw.tween_property(poly, "modulate:a", 0.0, 0.18).set_delay(0.06)
	tw.tween_property(spr, "modulate:a", 0.0, 0.18).set_delay(0.06)
	tw.tween_callback(func() -> void:
		poly.queue_free()
		spr.queue_free()
	)

## 特效贴图只载一次（所有挥击共用这张图）
var 预载特效图: Texture2D = load("res://素材/生图/挥击特效_透明.png")


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
