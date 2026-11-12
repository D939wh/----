extends Node2D
## 宿管视野自测 —— 「她到底能看见什么」量给她看。
##
## 起因（主人 2026-11-13 原话）：「全图 365 度全视角范围扫射太离谱了」。
## 旧逻辑 = 360px 的圆里最近的人就是「看见了」：**穿墙、无死角、不分朝向**，
## 于是「绕背后」「躲墙后」「扔东西引开」三条战术全部作废，玩家只剩跑。
##
## 现在要同时满足三件事才算看见：在半径内 + 在视野锥里 + 中间没墙。
## 八个场景逐条钉住：
##   A 正前方 300px、无遮挡   → 看得见
##   B 正后方 200px           → **看不见**（这就是这次修的东西）
##   C 正后方但贴身 40px      → 看得见（贴到身上还看不见就是穿模）
##   D 正前方 300px、中间有墙 → **看不见**（墙体遮挡）
##   E 看见之后人跑没影        → 状态「搜索」，朝**最后看见的位置**走，不是立刻回头巡逻
##   F 记忆过期                → 回到「巡逻」
##   G 记忆还在时丢个箱子（3 档）→ **视觉记忆被冲掉**，改去声源（调虎离山成立）
##   H 只有脚步声（1 档）      → 不冲掉视觉记忆（不然她自己走路都能把自己拽走）
##
## 用法：Godot --headless --path . res://场景/测试/宿管视野自测.tscn

const 宿管场景: PackedScene = preload("res://角色/宿管/宿管.tscn")
const 学生场景: PackedScene = preload("res://角色/学生/student.tscn")
const 状态名 := preload("res://角色/宿管/状态/状态名.gd")
const 声音表 := preload("res://数据/声音表.gd")

var r: Dictionary = {}
var k
var s
var _地面们: Array = []


func _ready() -> void:
	await _测A_正前方()
	await _测B_正后方()
	await _测C_背后贴身()
	await _测D_中间有墙()
	await _测E_跑没影了()
	await _测F_记忆过期()
	await _测G_丢箱子引开()
	await _测H_脚步不冲记忆()

	print("=== 宿管视野自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


# ── A. 正前方、无遮挡 ──────────────────────────────────────
func _测A_正前方() -> void:
	await _搭(Vector2(300, 400), Vector2(600, 400), -1.0)
	k._面朝(1.0)
	await _等(6)
	r["A 正前方 300px"] = "看得见=%s（应 true）｜状态「%s」" % [
		str(k._看得见的目标() != null), k._机器.当前()]


# ── B. 正后方 200px ───────────────────────────────────────
func _测B_正后方() -> void:
	await _搭(Vector2(600, 400), Vector2(400, 400), -1.0)
	k._面朝(1.0)
	await _等(6)
	r["B 正后方 200px"] = "看得见=%s（应 **false**：旧版会看见）｜状态「%s」" % [
		str(k._看得见的目标() != null), k._机器.当前()]


# ── C. 背后贴身 40px ──────────────────────────────────────
func _测C_背后贴身() -> void:
	await _搭(Vector2(600, 400), Vector2(560, 400), -1.0)
	k._面朝(1.0)
	await _等(6)
	r["C 背后贴身 40px"] = "看得见=%s（应 true：近距离不看朝向）" % str(k._看得见的目标() != null)


# ── D. 正前方、中间一堵墙 ─────────────────────────────────
func _测D_中间有墙() -> void:
	await _搭(Vector2(300, 400), Vector2(600, 400), 450.0)
	k._面朝(1.0)
	await _等(6)
	r["D 正前方有墙"] = "看得见=%s（应 **false**：墙挡住就等于没看见）｜距离 %.0f（在 360 半径内）" % [
		str(k._看得见的目标() != null),
		k.global_position.distance_to(s.global_position)]


# ── E. 看见之后人跑没影 → 去最后看见的位置找 ────────────────
func _测E_跑没影了() -> void:
	await _搭(Vector2(300, 400), Vector2(600, 400), -1.0)
	k._面朝(1.0)
	await _等(10)
	var 见过: bool = k._看得见的目标() != null
	var 记的位置: Vector2 = k._视线目标
	# 把人挪到 2000（远超 360 半径），相当于「转过墙角跑了」
	s.global_position = Vector2(2000, 400)
	await _等(6)
	var 状态: String = k._机器.当前()
	var 起始x: float = k.global_position.x
	await _等(30)
	r["E 跑没影了"] = "刚才看见过=%s｜记的位置 x=%.0f" % [str(见过), 记的位置.x]
	r["E 结论"] = "状态「%s」（应 搜索，不是立刻回头巡逻）｜朝哪边走 x %.0f → %.0f（应往右，去 %.0f）" % [
		状态, 起始x, k.global_position.x, 记的位置.x]


# ── F. 记忆过期 → 回巡逻 ──────────────────────────────────
func _测F_记忆过期() -> void:
	await _搭(Vector2(300, 400), Vector2(600, 400), -1.0)
	k._面朝(1.0)
	await _等(10)
	s.global_position = Vector2(2000, 400)
	# 3.5 秒记忆 + 到点后张望 1.8 秒 ≈ 5.3 秒，留 7 秒余量
	await _等(420)
	r["F 记忆过期"] = "7 秒后状态「%s」（应 巡逻 / 待机）｜视觉记忆 %.2f（应 0.00）" % [
		k._机器.当前(), k._视线剩余]


# ── G. 记忆还在时丢个箱子 ─────────────────────────────────
func _测G_丢箱子引开() -> void:
	await _搭(Vector2(300, 400), Vector2(600, 400), -1.0)
	k._面朝(1.0)
	await _等(10)
	s.global_position = Vector2(2000, 400)
	await _等(6)
	var 记忆前: float = k._视线剩余
	# 在右边 800 丢个箱子（3 档「很大」，半径 600）
	Events.发声(Vector2(800, 400), 声音表.档_很大, 声音表.来源_丢物)
	await _等(4)
	r["G 丢箱子引开"] = "丢之前视觉记忆 %.2f 秒 → 之后 %.2f（应被冲成 0）｜听觉剩余 %.2f" % [
		记忆前, k._视线剩余, k._听觉剩余]
	await _等(40)
	r["G 结论"] = "改去声源=%s（应 true：往右朝 800 走）｜现在 x=%.0f" % [
		str(k.global_position.x > 330.0), k.global_position.x]


# ── H. 只有脚步声，不该冲掉记忆 ───────────────────────────
func _测H_脚步不冲记忆() -> void:
	await _搭(Vector2(300, 400), Vector2(600, 400), -1.0)
	k._面朝(1.0)
	await _等(10)
	s.global_position = Vector2(2000, 400)
	await _等(6)
	var 记忆前: float = k._视线剩余
	Events.发声(Vector2(800, 400), 声音表.档_很轻, 声音表.来源_脚步)
	await _等(4)
	r["H 脚步不冲记忆"] = "视觉记忆 %.2f → %.2f（应还在，只是自然倒计时）｜听觉剩余 %.2f" % [
		记忆前, k._视线剩余, k._听觉剩余]


# ── 场地 ──────────────────────────────────────────────────
## 搭地面 +（可选）一堵墙 + 一对全新的宿管 / 学生。
## `墙x` < 0 = 不搭墙。墙 16 宽、200 高，从地面往上长。
func _搭(姨: Vector2, 生: Vector2, 墙x: float) -> void:
	await _清场()
	_加地面(-400.0, 2400.0, 400.0)
	if 墙x >= 0.0:
		_加墙(墙x, 400.0)

	k = 宿管场景.instantiate()
	k.name = "阿姨"
	add_child(k)
	s = 学生场景.instantiate()
	s.name = "学生"
	add_child(s)
	Director.set_control(s)
	k.global_position = 姨 + Vector2(0.0, -40.0)
	s.global_position = 生
	for i in 90:
		if k.is_on_floor():
			break
		await get_tree().physics_frame
	await _等(2)


func _加地面(左: float, 右: float, 顶: float) -> void:
	var 体 := StaticBody2D.new()
	体.collision_layer = 1
	体.collision_mask = 0
	var 形 := CollisionShape2D.new()
	var 矩 := RectangleShape2D.new()
	矩.size = Vector2(右 - 左, 40.0)
	形.shape = 矩
	形.position = Vector2((左 + 右) * 0.5, 顶 + 20.0)
	体.add_child(形)
	add_child(体)
	_地面们.append(体)


func _加墙(x: float, 地面y: float) -> void:
	var 体 := StaticBody2D.new()
	体.collision_layer = 1
	体.collision_mask = 0
	var 形 := CollisionShape2D.new()
	var 矩 := RectangleShape2D.new()
	矩.size = Vector2(16.0, 200.0)
	形.shape = 矩
	形.position = Vector2(x, 地面y - 100.0)
	体.add_child(形)
	add_child(体)
	_地面们.append(体)


func _清场() -> void:
	for 体 in _地面们:
		if is_instance_valid(体):
			remove_child(体)
			体.queue_free()
	_地面们.clear()
	for 节点 in [k, s]:
		if is_instance_valid(节点):
			remove_child(节点)
			节点.queue_free()
	await _等(2)


func _等(帧: int) -> void:
	for i in 帧:
		await get_tree().physics_frame
