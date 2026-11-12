extends Node2D
## 关卡4 走位自测 —— 改完地图之后，先确认「这条路真的能走通」。
##
## 不做手感判断，只回答三个是/否：
##   A 从出生点能不能一路走到出口（中途要开门、要穿过原来被柱子堵死的那一段）
##   B 扛着钥匙（25kg = 2 档）能不能爬上上层平台 —— **应该不能**
##   C 空手能不能爬上去 —— **应该能**（否则上层是死路）
##
## 用法：Godot --headless --path . res://场景/测试/关卡4走位自测.tscn

var r: Dictionary = {}
var 图
var 生
var 钥匙


func _ready() -> void:
	图 = load("res://场景/主场景4.tscn").instantiate()
	add_child(图)
	await _等(3)
	生 = 图.get_node("student")
	钥匙 = 图.get_node("KeyPlate1")
	Director.set_control(生)
	# 关掉剧情触发：这里只测地形，召唤出来的阿姨会把走位搅乱
	var 判 = 图.get_node("判定区")
	if 判 != null:
		判.已触发 = true

	# 顺序有讲究：**走通放最后** —— 走到出口会触发「已逃出」，之后这个学生就不再吃键盘了，
	# 后面的爬梯测试会全部假失败（第一次跑就是这么被坑的）。
	await _测C_空手爬梯()
	await _测B_扛着爬梯()
	生.交出搬运物()
	await _等(4)
	await _测A_走通()

	print("=== 关卡4 走位自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


# ── A. 从出生点走到出口 ────────────────────────────────────
func _测A_走通() -> void:
	# 先送回出生点，让这条测试自己站得住（不依赖前两条测完把人留在哪）
	生.global_position = Vector2(468, 270)
	生.velocity = Vector2.ZERO
	for i in 60:
		if 生.is_on_floor():
			break
		await get_tree().physics_frame
	await _等(2)

	# 把大门解锁（等于钥匙已经插好），否则它本来就在 2290 挡着
	var 门4 = 图.get_node("Door4")
	门4.on_report("unlock", {})

	var 起x: float = 生.global_position.x
	var 最右: float = 起x
	var 卡住: float = 0.0
	var 秒: float = 0.0
	var 开了几次: int = 0
	Input.action_press("right")
	while 秒 < 60.0:
		await get_tree().physics_frame
		秒 += 1.0 / 60.0
		var x: float = 生.global_position.x
		if x > 最右 + 0.5:
			最右 = x
			卡住 = 0.0
		else:
			卡住 += 1.0 / 60.0
			if 卡住 > 0.35:
				# 撞到东西了：先按一下 E（可能是关着的门），再跳一下（可能是 16px 的小台阶）。
				# 两个都试，因为这一步只想知道「路能不能走通」，不想区分是哪种障碍。
				Input.action_press("open_door")
				await get_tree().physics_frame
				Input.action_release("open_door")
				Input.action_press("jump")
				await _等(30)      # 按够 0.5 秒才是满跳（松手早了会被 JUMP_CUT 削成小跳）
				Input.action_release("jump")
				开了几次 += 1
				卡住 = 0.0
				await get_tree().physics_frame
		if x > 2300.0 or 生.已逃出:
			break
	Input.action_release("right")
	await _等(30)

	r["A 走到哪了"] = "x %.0f → %.0f（出口中心 2365）｜用时 %.1f 秒｜中途按了 %d 次 E" % [
		起x, 生.global_position.x, 秒, 开了几次]
	r["A 结论"] = "整条路走得通=%s（应 true：走到 2300 以后 / 已触发逃出）" % (
		生.global_position.x > 2300.0 or 生.已逃出)


# ── B. 扛着钥匙爬梯子：应该爬不上去 ─────────────────────────
func _测B_扛着爬梯() -> void:
	await _摆到梯子下()
	生.扛起(钥匙)
	await _等(2)
	var 起y: float = 生.global_position.y
	var 档: String = 生.负重说明()
	Input.action_press("up")
	await _等(90)
	Input.action_release("up")
	await _等(20)
	r["B 扛着钥匙爬梯"] = "档位「%s」｜y %.0f → %.0f（平台顶 208，上去应该到 208）" % [
		档, 起y, 生.global_position.y]
	r["B 结论"] = "爬不上去=%s（应 true：2 档不能爬梯）" % (生.global_position.y > 起y - 20.0)


# ── C. 空手爬梯子：应该能上 ─────────────────────────────────
func _测C_空手爬梯() -> void:
	生.交出搬运物()          # 上一条测完钥匙还在手上，不放下的话 C 也爬不动（2 档不能爬梯）
	await _等(4)
	await _摆到梯子下()
	var 起y: float = 生.global_position.y
	Input.action_press("up")
	await _等(110)
	Input.action_release("up")
	await _等(20)
	r["C 空手爬梯"] = "y %.0f → %.0f（平台顶 208）｜手上=%s" % [
		起y, 生.global_position.y, str(生.手上扛着())]
	r["C 结论"] = "爬上去了=%s（应 true）" % (生.global_position.y < 260.0)


# ── 摆位 ──────────────────────────────────────────────────
## 站到梯子正下方。抬 12px 放下来，别正好卡在「已落地」的标记上（那样下一帧会被物理弹飞）。
func _摆到梯子下() -> void:
	生.global_position = Vector2(1488, 340)
	生.velocity = Vector2.ZERO
	for i in 40:
		if 生.is_on_floor():
			break
		await get_tree().physics_frame
	await _等(2)


func _等(帧: int) -> void:
	for i in 帧:
		await get_tree().physics_frame
