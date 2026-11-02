extends Node
## 门规则的逻辑验证（不测性能，只测"谁推多快"和"抢"）
## 用临时场景方式跑，这样 autoload 的总管才会在

func _ready() -> void:
	var main: Node = load("res://场景/主场景.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var agent: Node = main.get_node("FloorAgent")
	var door = agent.get_door("1-走廊东")
	if door == null:
		print("!! 没找到门")
		get_tree().quit()
		return
	print("门位置: ", door.position)

	var player := Node2D.new()
	player.add_to_group("players")
	get_tree().root.add_child(player)
	var keeper := Node2D.new()
	keeper.add_to_group("keeper")
	get_tree().root.add_child(keeper)

	print("--- 1. 学生按一次：0.3 秒应该开完 ---")
	door.press(player)
	await get_tree().create_timer(0.45).timeout
	print("   开合度 = %.2f   期望 1.00" % door._amount)

	print("--- 2. 学生再按一次：0.3 秒应该关回 ---")
	door.press(player)
	await get_tree().create_timer(0.45).timeout
	print("   开合度 = %.2f   期望 0.00" % door._amount)

	print("--- 3. 换宿管按：0.5 秒只走三分之一（慢） ---")
	door.press(keeper)
	await get_tree().create_timer(0.5).timeout
	print("   开合度 = %.2f   期望约 0.33" % door._amount)

	print("--- 4. 学生冲过来抢：门立刻掉头，学生手快 ---")
	door.press(player)
	await get_tree().create_timer(0.4).timeout
	print("   开合度 = %.2f   期望 0.00" % door._amount)

	print("--- 5. 宿管重新抢回去：往开的方向慢慢走 ---")
	door.press(keeper)
	await get_tree().create_timer(0.5).timeout
	print("   开合度 = %.2f   期望约 0.33（宿管慢，抢回来也慢）" % door._amount)

	get_tree().quit()
