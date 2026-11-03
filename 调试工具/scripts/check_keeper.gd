extends Node
## 临时验证脚本（不参与游戏，跑完就删）
## 验证四件事：控制权切换、相机跟随、切换后没被控制的人会不会自己跑、宿管开门是不是 1.5 秒

func _ready() -> void:
	var main: Node = load("res://场景/主场景.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var s: Node2D = main.get_node("student")
	var k: Node2D = main.get_node("keeper")

	print("=== 1. 刚开始谁在控制 ===")
	print("  当前控制：", Director.当前控制.name if Director.当前控制 else "null")
	print("  学生相机开：", s.get_node("Camera2D").enabled, "   宿管相机开：", k.get_node("Camera2D").enabled)

	print("=== 2. 按一次 F1 ===")
	Director.switch_control()
	await get_tree().process_frame
	print("  当前控制：", Director.当前控制.name)
	print("  学生相机开：", s.get_node("Camera2D").enabled, "   宿管相机开：", k.get_node("Camera2D").enabled)

	print("=== 3. 控制宿管时按右，看谁在动 ===")
	var s0: float = s.global_position.x
	var k0: float = k.global_position.x
	Input.action_press("right")
	for i in 20:
		await get_tree().physics_frame
	Input.action_release("right")
	print("  学生位移：%.1f 像素（应该接近 0）" % (s.global_position.x - s0))
	print("  宿管位移：%.1f 像素（应该明显大于 0）" % (k.global_position.x - k0))

	print("=== 4. 按第二次 F1，换回学生，再按右 ===")
	Director.switch_control()
	await get_tree().process_frame
	s0 = s.global_position.x
	k0 = k.global_position.x
	Input.action_press("right")
	for i in 20:
		await get_tree().physics_frame
	Input.action_release("right")
	print("  当前控制：", Director.当前控制.name)
	print("  学生位移：%.1f 像素（应该明显大于 0）" % (s.global_position.x - s0))
	print("  宿管位移：%.1f 像素（应该接近 0）" % (k.global_position.x - k0))

	print("=== 5. 宿管开门要几秒（应该是 1.5）===")
	var agent: Node = main.get_node("FloorAgent")
	var door: Node = agent.get_door("1-走廊东")
	door.press(k)
	var t: float = 0.0
	while door._amount < 0.95 and t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("  宿管推开门用了 %.2f 秒，开度 %.2f" % [t, door._amount])

	print("=== 6. 学生中途抢这扇门（应该很快关回去）===")
	door.press(s)
	t = 0.0
	while door._amount > 0.05 and t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	print("  学生关回去用了 %.2f 秒，开度 %.2f" % [t, door._amount])

	get_tree().quit()
