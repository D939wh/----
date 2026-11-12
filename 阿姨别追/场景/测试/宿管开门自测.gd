extends Node2D
## 宿管开门自测 —— 「关门能不能买 1.5 秒」这件事，量给她看。
##
## 这一条是「关门买时间」能成立的前提。没有它，玩家把门一关就永久安全，
## 追逃会退化成「找门」，整关的设计全废。
##
## 三个场景，每个都自己搭一段地面 + 一扇门（**不依赖主场景**）：
##   A 普通门、关着      → 她必须停下来推开（1.5 秒），然后**穿过去继续追**
##   B 锁着的门（要钥匙）→ 她推不开，必须站在门前不动（别去傻推一扇锁着的门）
##   C 开局就开着的门    → 她必须直接走过去，**一次都不该进「开门」状态**
##
## 另外盯一条容易被写坏的东西：**她推开门之后不会把门又关回去**。
## （`press()` 是开关切换，AI 每帧问一次就会开→关→开→关地抽搐，所以走的是 `门.求开()`。）
##
## 用法：Godot --headless --path . res://场景/测试/宿管开门自测.tscn

const 宿管场景: PackedScene = preload("res://角色/宿管/宿管.tscn")
const 学生场景: PackedScene = preload("res://角色/学生/student.tscn")
const 门场景: PackedScene = preload("res://交互物/门/门.tscn")
const 状态名 := preload("res://角色/宿管/状态/状态名.gd")

var r: Dictionary = {}
var k
var s
var 门
var _地面们: Array = []


func _ready() -> void:
	await _测A_关着的门()
	await _测B_锁着的门()
	await _测C_开着的门()

	print("=== 宿管开门自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


# ── A. 普通门关着：推开 → 穿过去 ────────────────────────────
func _测A_关着的门() -> void:
	await _搭(Vector2(300, 400), Vector2(640, 400), 500.0, {})

	var 量 := await _盯(4.0)
	r["A1 关着的门"] = "末 x=%.0f（门在 500，人起点 300）｜状态「%s」｜门开度 %.2f" % [
		量["x"], 量["状态"], 门._amount]
	r["A2 推开了"] = "进过「开门」状态=%s（应 true）｜门最终开度 %.2f（应 1.00）｜花了几帧推 %d" % [
		量["进过开门"], 门._amount, 量["推门帧数"]]
	r["A3 穿过去了"] = "末 x=%.0f（应 > 520，即越过门中心）｜末状态「%s」（应 追击 / 攻击）" % [
		量["x"], 量["状态"]]
	# 她开门时走的是「只开不关」的 求开()，所以开完之后 `_target` 必须一直是 1
	r["A4 没把门关回去"] = "门的 _target=%.0f（应 1，= 没被 AI 反复开关）｜开度 %.2f" % [
		门._target, 门._amount]


# ── B. 锁着的门：推不开，站住 ───────────────────────────────
func _测B_锁着的门() -> void:
	await _搭(Vector2(300, 400), Vector2(640, 400), 500.0, { "needs_key": true })

	var 量 := await _盯(4.0)
	r["B1 锁着的门"] = "末 x=%.0f（应停在门前 460 附近，不许越过去）｜状态「%s」" % [
		量["x"], 量["状态"]]
	r["B2 结论"] = "没有去傻推=%s（应 true：一次都没进「开门」）｜门开度 %.2f（应 0.00）｜没过去=%s" % [
		not 量["进过开门"], 门._amount, 量["x"] < 480.0]


# ── C. 开局开着的门：直接走过去 ─────────────────────────────
func _测C_开着的门() -> void:
	await _搭(Vector2(300, 400), Vector2(640, 400), 500.0, { "start_open": true })

	var 量 := await _盯(2.5)
	r["C1 开着的门"] = "末 x=%.0f｜状态「%s」" % [量["x"], 量["状态"]]
	r["C2 结论"] = "直接走过去了=%s（应 true）｜没多此一举去「开门」=%s（应 true）" % [
		量["x"] > 520.0, not 量["进过开门"]]


# ── 场地 ──────────────────────────────────────────────────
## 搭一段平地面 + 一对全新的宿管/学生 + 一扇门。
##
## **每次都换新的人和新的门**：上一场的状态（血量、挥击阶段、门的开度）会带过来，
## 而且瞬移一个「还标着已落地」的 CharacterBody2D，下一帧会被物理引擎弹飞。
func _搭(姨: Vector2, 生: Vector2, 门x: float, 门配置: Dictionary) -> void:
	await _清场()

	_加地面(-400.0, 1400.0, 400.0)

	门 = 门场景.instantiate()
	门.name = "测试门"
	门.thing_id = "测试门"          # 不填会 push_warning，也算配置错误
	门.position = Vector2(门x, 400.0)
	for 键 in 门配置:
		门.set(键, 门配置[键])
	add_child(门)

	k = 宿管场景.instantiate()
	k.name = "阿姨"
	add_child(k)
	s = 学生场景.instantiate()
	s.name = "学生"
	add_child(s)
	Director.set_control(s)      # 控制权给玩家 → 阿姨彻底交给 AI
	k.global_position = 姨 + Vector2(0.0, -40.0)   # 从半空落下，别正好卡在表面上
	s.global_position = 生
	for i in 90:
		if k.is_on_floor():
			break
		await get_tree().physics_frame
	await _等(2)


func _加地面(左: float, 右: float, 顶: float) -> void:
	var 体 := StaticBody2D.new()
	体.collision_layer = 1        # 层_地板
	体.collision_mask = 0
	var 形 := CollisionShape2D.new()
	var 矩 := RectangleShape2D.new()
	矩.size = Vector2(右 - 左, 40.0)
	形.shape = 矩
	形.position = Vector2((左 + 右) * 0.5, 顶 + 20.0)
	体.add_child(形)
	add_child(体)
	_地面们.append(体)


func _清场() -> void:
	for 体 in _地面们:
		if is_instance_valid(体):
			remove_child(体)     # 立刻摘出场景树：queue_free 要到帧末才真删
			体.queue_free()
	_地面们.clear()
	for 节点 in [k, s, 门]:
		if is_instance_valid(节点):
			remove_child(节点)
			节点.queue_free()
	await _等(2)


## 盯一段时间：记「有没有进过开门状态」「推了多久」「最右走到哪」。
func _盯(秒: float) -> Dictionary:
	var 进过: bool = (k._机器.当前() == 状态名.开门)
	var 推门帧数 := 0
	var 最右: float = k.global_position.x
	for i in int(秒 * 60.0):
		await get_tree().physics_frame
		if not is_instance_valid(k):
			break
		if k._机器.当前() == 状态名.开门:
			进过 = true
			推门帧数 += 1
		最右 = maxf(最右, k.global_position.x)
	return {
		"x": k.global_position.x,
		"y": k.global_position.y,
		"最右": 最右,
		"状态": k._机器.当前(),
		"进过开门": 进过,
		"推门帧数": 推门帧数,
	}


func _等(帧: int) -> void:
	for i in 帧:
		await get_tree().physics_frame
