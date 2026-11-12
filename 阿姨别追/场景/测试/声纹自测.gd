extends Node
## 声纹自测 —— 数据层：位置对得上、越响越高、太轻不显示、换人跟随、会消失。
## 用法：Godot --headless 场景/测试/声纹自测.tscn
## 逐项断言打印 PASS/FAIL，和 声音圈自测/声音自测 一个套路。
##
## 【为什么不数像素】波包里的浪一直在滚，同一个位置的高度每帧都在变。
## 所以断言只问「峰在哪」「峰多高」，用 峰值() 扫一遍找最高点，
## 不去硬编码某个坐标上的高度值 —— 那种断言会被相位摇死。

const 声音表 := preload("res://数据/声音表.gd")

var _过: int = 0
var _败: int = 0
var 面: Control


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var s: CharacterBody2D = scene.get_node("student")
	var k: CharacterBody2D = scene.get_node("keeper")
	scene.get_node("student2").global_position = Vector2(200, 208)   # 挪出戏
	# 宿管关掉处理再测：不关她会自己追着学生打，一路脚步全被画成波，
	# 断言里就分不清「我这一声」和「她走路那一声」（第一版就是这么挂的）。
	# 关掉处理不影响她当听者 —— 听者只是读 global_position。
	k.process_mode = Node.PROCESS_MODE_DISABLED
	Director.set_control(s)
	await _wait(0.1)

	var 纹场景: PackedScene = load("res://界面/声纹/声纹.tscn")
	var 纹: CanvasLayer = 纹场景.instantiate()
	scene.add_child(纹)
	await get_tree().process_frame
	面 = 纹.get_node("画面")

	# ── 1. 基线钉在视口正中偏下，不随镜头 ──
	var 底: Vector2 = 面.基线()
	断言("1 基线在视口正中偏下",
		底 == Vector2(320.0, 326.0),
		"基线 (%.0f, %.0f)（应 320,326 = 640×360 正中、离底 34）" % [底.x, 底.y])

	# ── 2. 没人出声时只是一条静线（呼吸不超过 2px）──
	var 静: Dictionary = 面.峰值()
	断言("2 静息时贴线", float(静["高"]) < 2.0,
		"静息峰值 %.2f px（应 < 2，只剩 ±1 的呼吸）" % float(静["高"]))

	# ── 3. 左边的声 → 峰在左边 ──
	s.global_position = Vector2(1000, 208)
	await _wait(0.1)
	Events.发声(Vector2(900, 208), 声音表.档_很大, 声音表.来源_丢物)   # 左 100px，音量 0.83
	await _wait(0.08)
	var 峰左: Dictionary = 面.峰值()
	断言("3 左边的声在左边", float(峰左["位置"]) < -0.15,
		"峰位置 %.2f（应 < -0.15）/ 峰高 %.1f px" % [float(峰左["位置"]), float(峰左["高"])])

	# ── 4. 右边的声 → 峰在右边 ──
	await _wait(1.6)
	Events.发声(Vector2(1100, 208), 声音表.档_很大, 声音表.来源_丢物)   # 右 100px
	await _wait(0.08)
	var 峰右: Dictionary = 面.峰值()
	断言("4 右边的声在右边", float(峰右["位置"]) > 0.15,
		"峰位置 %.2f（应 > 0.15）/ 峰高 %.1f px" % [float(峰右["位置"]), float(峰右["高"])])

	# ── 5. 越响顶得越高（同一侧，近 vs 远）──
	await _wait(1.6)
	Events.发声(Vector2(600, 208), 声音表.档_很大, 声音表.来源_丢物)   # 左 400px，音量 0.33
	await _wait(0.08)
	var 远高: float = float(面.峰值()["高"])
	await _wait(1.6)
	Events.发声(Vector2(900, 208), 声音表.档_很大, 声音表.来源_丢物)   # 左 100px，音量 0.83
	await _wait(0.08)
	var 近高: float = float(面.峰值()["高"])
	断言("5 越响越高", 近高 > 远高 + 2.0,
		"远处(音量0.33) %.1f px < 近处(音量0.83) %.1f px" % [远高, 近高])

	# ── 6. 低于阈值的声音不画 ──
	await _wait(1.6)
	Events.发声(Vector2(1500, 208), 声音表.档_很轻, 声音表.来源_脚步)   # 右 500px > 半径 200
	await get_tree().process_frame
	断言("6 太轻不显示", 面.波数() == 0, "波数 %d（应 0）" % 面.波数())

	# ── 7. 换听者：新一声按新耳朵算 ──
	Director.set_control(k)
	k.global_position = Vector2(1000, 208)
	await _wait(0.1)
	Events.发声(Vector2(900, 208), 声音表.档_很大, 声音表.来源_丢物)   # 宿管左边 100px
	await _wait(0.08)
	断言("7 换人后位置对", float(面.峰值()["位置"]) < -0.15,
		"峰位置 %.2f（应 < -0.15，宿管的左边）" % float(面.峰值()["位置"]))

	# ── 8. 波会自己消失 ──
	var 有: int = 面.波数()
	await _wait(1.6)
	断言("8 声过去了就收线", 有 >= 1 and 面.波数() == 0,
		"1.5 秒前 %d 道波 → 现在 %d 道（应 0）" % [有, 面.波数()])

	# ── 9. 多声并存，不去重 ──
	k.global_position = Vector2(1000, 208)
	k.velocity = Vector2.ZERO
	await get_tree().physics_frame
	for i in range(3):
		Events.发声(Vector2(900 + i * 200.0, 208), 声音表.档_较大, 声音表.来源_跑动)
	await get_tree().process_frame
	断言("9 三声并存", 面.波数() >= 3, "波数 %d（应 >= 3）" % 面.波数())

	print("")
	print("=== 声纹自测：%d 过 / %d 败 ===" % [_过, _败])
	get_tree().quit(0 if _败 == 0 else 1)


func 断言(名: String, 通过: bool, 细节: String) -> void:
	print("  %s: %s —— %s" % [名, "PASS" if 通过 else "FAIL", 细节])
	if 通过:
		_过 += 1
	else:
		_败 += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
