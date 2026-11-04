extends Node
## 阿姨打人全流程自测节点（W2D2 第 3 件）
## 挂在测试场景里跑：进场景就自动把整套流程打一遍，打完打印结果并退出。
## 为什么不用 --script：那种方式下 autoload（Director）不会加载，
## 游戏玩法必须经过总管，所以走「实例化主场景 + 正常游戏循环」这条路。
## 用法：Godot --headless 场景/测试/阿姨打人自测.tscn

var r := {}          # 结果汇总
var s: CharacterBody2D
var k: CharacterBody2D

func _ready() -> void:
	# 把主场景整个实例化进来（学生宿管地图门全都在，autoload 也照常跑）
	# call_deferred：_ready 里父节点还在搭，直接 add_child 会被拒绝
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	s = scene.get_node("student")
	k = scene.get_node("keeper")

	# —— 布景：宿管控制，学生站她右边 60px ——
	Director.switch_control()
	k.global_position = Vector2(900, 208)
	s.global_position = Vector2(960, 208)
	await _wait(0.2)
	r["起始"] = "血量 %d / 瘫痪 %s" % [s.血量, s.瘫痪]

	# —— 挥击 1：应掉到 1 格 ——
	await _tap_f()
	r["一挥后"] = "血量 %d / 瘫痪 %s" % [s.血量, s.瘫痪]

	# —— 等 CD（1.2 秒）再挥：应 0 格 + 瘫痪 + 变色 ——
	await _wait(1.3)
	await _tap_f()
	await _wait(0.2)
	r["二挥后"] = "血量 %d / 瘫痪 %s / 颜色(%d,%d,%d,%d)" % [
		s.血量, s.瘫痪,
		s.get_node("AnimatedSprite2D").modulate.r8,
		s.get_node("AnimatedSprite2D").modulate.g8,
		s.get_node("AnimatedSprite2D").modulate.b8,
		s.get_node("AnimatedSprite2D").modulate.a8]

	# —— 瘫痪的学生走不动（控制权在宿管手上，学生本来就不吃键盘；
	#    这里推一把学生的速度，看她自己会不会恢复移动 —— 不该恢复）——
	var 学生原位 := s.global_position.x
	Input.action_press("right")
	await _wait(0.4)
	Input.action_release("right")
	r["瘫了走不动"] = "宿管位移 %.0f（后摇中应为 0）" % (k.global_position.x - 900.0)

	# —— CD 过去，贴身（20px）按住 F 读条 1.2 秒 → 扛上肩 ——
	await _wait(1.0)
	k.global_position = Vector2(940, 208)
	await _wait(0.1)
	Input.action_press("interaction")
	await _wait(1.4)
	r["读完条"] = "宿管扛着人=%s / 学生被扛=%s / 学生父节点=%s" % [
		k._carried_student != null, s.被扛着, s.get_parent().name]
	Input.action_release("interaction")

	# —— 扛着人走：移速应 370×0.6=222，0.5 秒走约 100+px ——
	var before := k.global_position.x
	Input.action_press("right")
	await _wait(0.5)
	Input.action_release("right")
	r["扛人走"] = "0.5 秒位移 %.0f（222 速应 100+）" % (k.global_position.x - before)
	r["学生跟身"] = "间距 %.0f（<40 算跟上）" % abs(s.global_position.x - k.global_position.x)

	# —— 再按 F：放下，学生还瘫着、回到场景名下 ——
	await _wait(0.3)
	await _tap_f()
	await _wait(0.3)
	r["放下后"] = "宿管空肩=%s / 学生不被扛=%s / 还瘫痪=%s / 父节点=%s" % [
		k._carried_student == null, s.被扛着 == false, s.瘫痪, s.get_parent().name]

	# —— 打断验证：再按住 F 读条，读到一半走开 → 进度清零、扛不成 ——
	await _wait(1.3)   # 等挥击 CD 过去
	k.global_position = Vector2(940, 208)
	await _wait(0.1)
	Input.action_press("interaction")
	await _wait(0.6)                       # 读到一半（0.6 < 1.2）
	k.global_position = Vector2(1140, 208)  # 宿管瞬移走开（超 60px 判定线）
	await _wait(0.3)
	Input.action_release("interaction")
	r["打断验证"] = "读条进度 %.2f（应清零为 0）/ 扛着人=%s（应 false）" % [
		k._grab_progress, k._carried_student != null]

	# —— 恢复现场：控制权还给学生，血量拉起 ——
	Director.switch_control()
	s.拉起()

	print("=== 阿姨打人全流程自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## 模拟「按一下 F」：press → 两个物理帧 → release → 稳定 0.15 秒
func _tap_f() -> void:
	Input.action_press("interaction")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("interaction")
	await _wait(0.15)
