extends Node2D
## 宿管跨坎自测 —— 「前面只有一颗小石子，她也站住不动」这件事，量给她看。
##
## 四个场景，每个都自己搭一段地面（StaticBody2D，碰撞层 1 = 地板），**不依赖主场景**，
## 这样「台阶多高、落差多深」是写死的，读数可以拿来说话：
##   A 一格 16px 的坎（就是主人说的「一颗小石子」） → 必须跳过去、追到人
##   B 三格 48px 的坎                              → 也必须跳上去
##   C 160px 落差、人在下面                         → 必须跟着跳下去（追人本来就该追下楼）
##   D 320px 落差、人不在下面                       → 必须停在崖边，不许跳楼
##
## 改之前的样子（记在这里，免得以后又改回去）：
##   `_前方有墙` 只在膝高 22px 探一条 18px 的射线。16px 的台阶从这条线底下过 → 判成平地，
##   她就一直顶着台阶推；`_前方是崖` 只往下探 10px，于是**往下走一格**也被当成崖边。
##   一个漏一个过，合起来就是「撞到小石子不动、走到小坑也不动」。
##
## 用法：Godot --headless --path . res://场景/测试/宿管跨坎自测.tscn

const 宿管场景: PackedScene = preload("res://角色/宿管/宿管.tscn")
const 学生场景: PackedScene = preload("res://角色/学生/student.tscn")
const 状态名 := preload("res://角色/宿管/状态/状态名.gd")

var r: Dictionary = {}
var k                      # 不加类型：要直接摸 _机器 / _跳冷却 / _前方障碍高
var s
var _地面们: Array = []


func _ready() -> void:
	await _测A_一格小坎()
	await _测B_三格台阶()
	await _测C_落差有人在下()
	await _测D_落差没人在下()

	print("=== 宿管跨坎自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


# ── A. 一格 16px 的坎：主人说的「一颗小石子」────────────────
func _测A_一格小坎() -> void:
	# 地面 400 高，坎在 500~548、顶面 384（正好一格），坎后继续走 384
	await _搭([
		[-400.0, 500.0, 400.0],
		[500.0, 548.0, 384.0],
		[548.0, 1400.0, 384.0],
	], Vector2(380, 400), Vector2(700, 384))

	var 量 := await _盯(2.4)
	r["A1 一格小坎（16px）"] = "末位置 x=%.0f y=%.0f｜状态「%s」" % [量["x"], 量["y"], 量["状态"]]
	r["A2 结论"] = "越过去了、追到人了=%s（应 true）｜最高跳到 y=%.0f（地面 400，应明显高于它）" % [
		量["x"] > 560.0 and 量["y"] < 400.0, 量["最高"]]


# ── B. 三格 48px 的台阶 ────────────────────────────────────
func _测B_三格台阶() -> void:
	await _搭([
		[-400.0, 500.0, 400.0],
		[500.0, 548.0, 352.0],
		[548.0, 1400.0, 352.0],
	], Vector2(380, 400), Vector2(700, 352))

	var 量 := await _盯(2.4)
	r["B1 三格台阶（48px）"] = "末位置 x=%.0f y=%.0f｜状态「%s」" % [量["x"], 量["y"], 量["状态"]]
	r["B2 结论"] = "上去了=%s（应 true）｜y=%.0f（应 ≈352：台阶顶那一层）｜最高 y=%.0f" % [
		量["x"] > 560.0 and 量["y"] < 400.0, 量["y"], 量["最高"]]


# ── C. 160px 落差，人就在下面 ───────────────────────────────
func _测C_落差有人在下() -> void:
	await _搭([
		[-400.0, 500.0, 400.0],
		[500.0, 1400.0, 560.0],
	], Vector2(380, 400), Vector2(650, 560))

	# 【2026-11-13 窗口 2.6→4.5 秒】本测试是「小石子」那轮写的，当时她开局
	# 直接巡逻；后来视野改造给她加了「待机 2 秒起步」，下崖时刻从 ~1.5s 推到
	# ~3.1s（探针实测：t=2.17 看见人 → 走下崖沿 → t≈3.1 落到 560 层）。
	# 旧窗口 2.6s 会正好掐在她坠落途中（末 y=436），读成「没跟下去」的假阳性。
	var 量 := await _盯(4.5)
	r["C1 落差 160、人在下面"] = "末位置 x=%.0f y=%.0f｜状态「%s」" % [量["x"], 量["y"], 量["状态"]]
	# 阈值放宽到 480：她追到人以后会贴上去，两个 CharacterBody2D 会互相碰，
	# 她经常是「站在对方身上」量到的（比地面高约 40px）。这里只问「有没有下到下一层」。
	r["C2 结论"] = "跟下去了=%s（应 true）｜y=%.0f（下一层是 560，比 400 低就说明下去了）" % [
		量["y"] > 480.0, 量["y"]]


# ── D. 320px 落差，人不在下面 ───────────────────────────────
func _测D_落差没人在下() -> void:
	await _搭([
		[-400.0, 500.0, 400.0],
		[500.0, 1400.0, 720.0],
	], Vector2(380, 400), Vector2(1300, 720))
	# 学生在 1300（隔着 920px，远超察觉半径 360），让她自己巡逻：
	# 起点 380 + 半径 200 = 580，正好够走到崖边（500）
	k._机器.切(状态名.巡逻)
	await _等(1)

	var 量 := await _盯(2.6)
	r["D1 落差 320、人不在下"] = "最远走到 x=%.0f（崖在 500）｜末 y=%.0f｜末 x=%.0f｜状态「%s」" % [
		量["最右"], 量["y"], 量["x"], 量["状态"]]
	# 「最右」会稍微越过 500 一点点（她 24px 宽，半个身子还能踩在崖沿上），
	# 所以看两件事：**没有一路掉下去**（y 还是 400 那一层）+ 最后已经回头了（x 退回左边）。
	r["D2 结论"] = "没跳楼=%s（应 true：最右 %.0f 只越过崖沿一点点，末 y %.0f 还在原地那层）｜回头了=%s" % [
		量["最右"] < 520.0 and 量["y"] < 460.0, 量["最右"], 量["y"], 量["x"] < 400.0]


# ── 场地 ──────────────────────────────────────────────────
## 搭一段地面 + 一对全新的宿管和学生。
##
## **每次都换新的人**，不是图省事：上一场的血量、瘫痪、挥击阶段、落地标记全都会带过来，
## 而且瞬移一个「还标着已落地」的 CharacterBody2D，下一帧会被物理引擎弹飞
## （实测 vy 能到 -1400，查了很久）。新建一个、让她自己从半空落到地上，什么状态都是干净的。
func _搭(段们: Array, 姨: Vector2, 生: Vector2) -> void:
	await _清地面()
	for 段 in 段们:
		_加地面(段[0], 段[1], 段[2])
	if is_instance_valid(k):
		remove_child(k)
		k.queue_free()
	if is_instance_valid(s):
		remove_child(s)
		s.queue_free()
	await _等(1)

	k = 宿管场景.instantiate()
	k.name = "阿姨"
	add_child(k)
	s = 学生场景.instantiate()
	s.name = "学生"
	add_child(s)
	Director.set_control(s)      # 控制权给学生 → 阿姨彻底交给 AI
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


func _清地面() -> void:
	for 体 in _地面们:
		if is_instance_valid(体):
			remove_child(体)     # 立刻摘出场景树：queue_free 要到帧末才真删，
			体.queue_free()      # 不摘的话新旧地面会重叠，她会被两块地板挤
	_地面们.clear()
	await _等(2)


## 盯一段时间，返回终点与极值。y 越小 = 跳得越高。
func _盯(秒: float) -> Dictionary:
	var 最高: float = k.global_position.y
	var 最右: float = k.global_position.x
	for i in int(秒 * 60.0):
		await get_tree().physics_frame
		最高 = minf(最高, k.global_position.y)
		最右 = maxf(最右, k.global_position.x)
	return {
		"x": k.global_position.x,
		"y": k.global_position.y,
		"最高": 最高,
		"最右": 最右,
		"状态": k._机器.当前(),
	}


func _等(帧: int) -> void:
	for i in 帧:
		await get_tree().physics_frame
