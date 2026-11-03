extends Node
## 一次性验证：箱子受重力落地 + 角色受负重影响
## 用法：复制到工程根，配一个临时 .tscn，无头跑一遍，看完删掉。

var _主场景: Node


func _ready() -> void:
	_主场景 = load("res://场景/主场景.tscn").instantiate()
	add_child(_主场景)
	for i in 40:
		await get_tree().physics_frame

	var 学生: Node2D = _主场景.get_node("student")
	var 箱子: Area2D = _主场景.get_node("CarryableBox")

	# ── ① 箱子悬空会自己掉下来 ───────────────────────────
	箱子.global_position = Vector2(1010, 60)
	await get_tree().physics_frame
	var 起点 := 箱子.global_position.y
	for i in 120:
		await get_tree().physics_frame
	var 落点 := 箱子.global_position.y
	print("① 箱子：从 y=%.1f 掉到 y=%.1f（下落 %.1f 像素），站住了=%s" % [
		起点, 落点, 落点 - 起点, 箱子.get("_站住了")])

	# 站住之后再把它搬回空中：应该会被复查发现、重新掉下来
	箱子.global_position = Vector2(1010, 40)
	for i in 90:
		await get_tree().physics_frame
	print("   再搬到空中 y=40 → 又落回 y=%.1f" % 箱子.global_position.y)

	# ── ② 空手的常走速度 ────────────────────────────────
	Input.action_press("right")
	for i in 40:
		await get_tree().physics_frame
	var 空手速度: float = 学生.velocity.x
	Input.action_release("right")
	for i in 40:
		await get_tree().physics_frame

	# ── ③ 扛起箱子：档位、速度、跳跃全被压住 ─────────────
	学生._pick_up_box(箱子)
	await get_tree().physics_frame
	print("③ 扛起后：%s" % 学生.负重说明())

	Input.action_press("right")
	for i in 40:
		await get_tree().physics_frame
	var 负重速度: float = 学生.velocity.x
	Input.action_release("right")
	for i in 40:
		await get_tree().physics_frame

	# 扛着重物按跳：应该跳不起来
	var 起跳前y := 学生.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var 最高 := 起跳前y
	for i in 30:
		await get_tree().physics_frame
		最高 = minf(最高, 学生.global_position.y)
	print("④ 负重按跳：抬升 %.2f 像素（空手约 92）" % [起跳前y - 最高])

	# ── ⑤ 放下：速度恢复、箱子自己落地 ───────────────────
	学生._drop_box()
	await get_tree().physics_frame
	print("⑤ 放下后：%s" % 学生.负重说明())

	Input.action_press("right")
	for i in 40:
		await get_tree().physics_frame
	var 恢复速度: float = 学生.velocity.x
	Input.action_release("right")
	for i in 40:
		await get_tree().physics_frame
	print("   速度：空手 %.1f → 负重 %.1f → 放下后 %.1f" % [空手速度, 负重速度, 恢复速度])

	# 箱子放下后是不是落回地面了
	for i in 60:
		await get_tree().physics_frame
	print("   箱子放在 y=%.1f（学生脚底 y=%.1f，箱子半高 12）" % [
		箱子.global_position.y, 学生.global_position.y])


	# ── ⑥ 四档重量边界 ──────────────────────────────────
	var 档表 = preload("res://数据/重量档位.gd")
	print("⑥ 重量分档：")
	for 公斤 in [10.0, 20.0, 20.5, 30.0, 40.0, 55.0, 70.0, 80.0]:
		var 档: Dictionary = 档表.取(公斤)
		print("   %5.1f kg → %-3s 速度 %3d%%｜%s｜%s" % [
			公斤, 档表.档名(公斤), roundi(float(档["移速倍率"]) * 100.0),
			"能跳" if float(档["跳跃高度倍率"]) > 0.0 else "不能跳",
			"能爬" if bool(档["可否攀爬"]) else "不能爬"])

	# ── ⑦ 扛着箱子上不了梯子 ─────────────────────────────
	学生.global_position = Vector2(439, 208)
	for i in 20:
		await get_tree().physics_frame
	Input.action_press("up")
	for i in 30:
		await get_tree().physics_frame
	var 空手爬 := 208.0 - 学生.global_position.y
	Input.action_release("up")
	for i in 20:
		await get_tree().physics_frame

	学生.global_position = Vector2(439, 208)
	学生._pick_up_box(箱子)
	for i in 20:
		await get_tree().physics_frame
	var 起y: float = 学生.global_position.y
	Input.action_press("up")
	for i in 30:
		await get_tree().physics_frame
	var 负重爬 := 起y - 学生.global_position.y
	Input.action_release("up")
	print("⑦ 爬梯：空手抬升 %.1f 像素｜扛 80kg 抬升 %.1f 像素" % [空手爬, 负重爬])

	get_tree().quit()
