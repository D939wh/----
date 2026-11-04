extends Node
## 回归测试：G 一键扛人 + F1 切人不卡 + 瘫痪学生不挡路
## 跑法：Godot --headless 场景/测试/切人卡死诊断.tscn

var r := {}
var s: Node
var k: Node

func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	s = scene.get_node("student")
	k = scene.get_node("keeper")

	Director.switch_control()
	k.global_position = Vector2(900, 208)
	s.global_position = Vector2(960, 208)
	await _w(0.2)

	# 打两下 → 瘫痪
	await _tap("interaction")
	await _w(1.3)
	await _tap("interaction")
	await _w(0.2)
	r["1_打瘫"] = "血量 %d / 瘫痪 %s / 碰撞层 %d（应 2）" % [s.血量, s.瘫痪, s.collision_layer]

	# 先验证「瘫痪不挡路」：等挥击后摇过去，宿管从 900 往右走 0.5 秒应越过 960
	await _w(0.9)   # 后摇 0.8 秒，等它走完
	var x0: float = k.global_position.x
	Input.action_press("right")
	await _w(0.5)
	Input.action_release("right")
	r["2_跨过瘫痪"] = "位移 %.0f（应 >120，不被 960 处的学生挡住）" % (k.global_position.x - x0)

	# 走回学生身边，按一下 G（不按住）→ 应该直接扛起
	k.global_position = Vector2(940, 208)
	s.global_position = Vector2(960, 208)
	await _w(0.2)
	await _tap("grab")
	await _w(0.2)
	r["3_一键扛起"] = "扛着=%s（应 true） / 学生被扛=%s / 学生父节点=%s" % [
		k._carried_student != null, s.被扛着, s.get_parent().name]

	# F1 切到学生再切回，宿管应该还能走
	Director.switch_control()
	await _w(0.2)
	var 中途 = Director.当前控制.name
	Director.switch_control()
	await _w(0.2)
	r["4_切人"] = "切到 %s → 切回 %s" % [中途, Director.当前控制.name]

	var x1: float = k.global_position.x
	Input.action_press("right")
	await _w(0.5)
	Input.action_release("right")
	r["5_切回能走"] = "位移 %.0f（应 >60，扛人 222 速）" % (k.global_position.x - x1)

	# 放下 → 学生落回地面、还瘫着、碰撞层仍是 2
	await _tap("grab")
	await _w(0.4)
	r["6_放下"] = "空肩=%s / 还瘫痪=%s / 父节点=%s / 层 %d" % [
		k._carried_student == null, s.瘫痪, s.get_parent().name, s.collision_layer]

	print("=== 一键扛人 + 切人回归 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


func _w(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await _w(0.1)
