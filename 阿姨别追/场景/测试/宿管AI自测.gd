extends Node
## 宿管 AI 自测：验证「没人按键时会自己动、会追人」，以及「按了键还是原来那套」。
## 用法：Godot --headless 场景/测试/宿管AI自测.tscn
##
## 用「实例化真场景 + 正常游戏循环」而不是 --script：autoload（Director）要活着，
## 因为 `_受控()` 判的是 `Director.当前控制`。

var r := {}
var k: CharacterBody2D
var s: CharacterBody2D
var s2: CharacterBody2D


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景3.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	s = scene.get_node("student")
	s2 = scene.get_node("student2")
	k = scene.get_node("宿管")

	# ── A. 有人按键时：她必须交给手控，姿态与原来一致 ──
	Director.set_control(k)
	k.global_position = Vector2(900, 320)
	await _wait(0.3)
	r["A1 控制权给宿管后状态"] = k._机器.当前() + "（应 手控）"

	# 按住右方向键 0.4 秒，她应该往右走（原 if 链的走速 370）
	Input.action_press("right")
	await _wait(0.4)
	Input.action_release("right")
	r["A2 按右键后走了"] = "%.0f px（应 > 60）" % (k.global_position.x - 900.0)
	await _wait(0.2)

	# ── B. 学生离开察觉圈 → AI 接管，进待机或巡逻，自己会动 ──
	Director.set_control(s)          # 控制权交给学生，宿管没人按了
	s.global_position = Vector2(200, 320)
	s2.global_position = Vector2(220, 320)
	k.global_position = Vector2(900, 320)
	await _wait(0.5)
	var 起始横: float = k.global_position.x
	await _wait(2.6)                 # 待机最长 2 秒，之后必须起身巡逻
	r["B1 没人按时状态"] = k._机器.当前() + "（应 巡逻 或 待机）"
	r["B2 她有没有自己动"] = "%.0f px（应 > 0）" % absf(k.global_position.x - 起始横)
	r["B3 有没有拿到目标"] = str(k._看得见的目标())
	r["B4 她还在楼板上"] = str(k.is_on_floor())

	# ── C. 学生走进察觉圈 → 必须切追击并朝学生靠拢 ──
	k.global_position = Vector2(900, 320)
	s.global_position = Vector2(620, 320)    # 距离 280 < 察觉半径 360
	s2.global_position = Vector2(200, 320)   # 另一个学生远在圈外
	await _wait(0.4)
	r["C1 学生进圈后状态"] = k._机器.当前() + "（应 追击）"
	var 追前: float = absf(k.global_position.x - s.global_position.x)
	await _wait(0.6)
	var 追后: float = absf(k.global_position.x - s.global_position.x)
	r["C2 距离有没有缩短"] = "%.0f → %.0f（应变小）" % [追前, 追后]
	r["C3 追击用的是追击速度"] = "%.0f" % k.追击速度

	# ── D. 学生跑出圈 → 必须脱战（回待机 / 巡逻）──
	# 注意：场上还有 student2，必须两个人一起挪远，否则她追的还是 student2
	s.global_position = Vector2(100, 320)
	s2.global_position = Vector2(-900, 320)
	await _wait(0.6)
	r["D1 目标跑掉后状态"] = k._机器.当前() + "（应 待机 或 巡逻）"
	r["D2 目标已丢失"] = str(k._看得见的目标())

	# ── E. 贴身不再往前挤（这轮不撞人、不打人）──
	k.global_position = Vector2(700, 320)
	s.global_position = Vector2(720, 320)    # 差 20 < 贴身距离 30
	await _wait(0.5)
	r["E1 贴身时状态"] = k._机器.当前() + "（应 追击）"
	var 贴前: float = absf(k.global_position.x - s.global_position.x)
	await _wait(0.5)
	var 贴后: float = absf(k.global_position.x - s.global_position.x)
	r["E2 贴身距离不再缩"] = "%.0f → %.0f（应基本不变）" % [贴前, 贴后]
	r["E3 学生血量没掉"] = "%d（应 2，这轮不打人）" % s.血量

	print("=== 宿管 AI 自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
