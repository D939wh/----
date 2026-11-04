extends Node
## 诊断：无头下从宿管朝学生直打一条射线，看到底撞到什么

func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var s := scene.get_node("student") as CharacterBody2D
	var k := scene.get_node("keeper") as CharacterBody2D
	k.global_position = Vector2(900, 208)
	s.global_position = Vector2(960, 208)
	await get_tree().create_timer(0.2).timeout

	print("=== 诊断开始 ===")
	print("宿管 pos=", k.global_position, " layer=", k.collision_layer, " mask=", k.collision_mask)
	print("学生 pos=", s.global_position, " layer=", s.collision_layer, " mask=", s.collision_mask)
	var space := k.get_world_2d().direct_space_state

	# 1. 全开（bodies + areas）
	var q1 := PhysicsRayQueryParameters2D.create(k.global_position, s.global_position)
	q1.collide_with_bodies = true
	q1.collide_with_areas = true
	var h1 := space.intersect_ray(q1)
	if h1.is_empty():
		print("全开射线：没打中任何东西")
	else:
		print("全开射线：撞到 ", h1["collider"].name, " (", h1["collider"].get_class(), ") at ", h1["position"])

	# 2. 只开 bodies
	var q2 := PhysicsRayQueryParameters2D.create(k.global_position, s.global_position)
	q2.collide_with_bodies = true
	q2.collide_with_areas = false
	var h2 := space.intersect_ray(q2)
	if h2.is_empty():
		print("只bodies射线：没打中任何东西")
	else:
		print("只bodies射线：撞到 ", h2["collider"].name, " (", h2["collider"].get_class(), ") at ", h2["position"])

	# 3. 学生身体中点（y-22）为目标（避开脚底同水平线问题）
	var q3 := PhysicsRayQueryParameters2D.create(
		k.global_position + Vector2(0, -22), s.global_position + Vector2(0, -22))
	q3.collide_with_bodies = true
	q3.collide_with_areas = false
	var h3 := space.intersect_ray(q3)
	if h3.is_empty():
		print("中点射线：没打中任何东西")
	else:
		print("中点射线：撞到 ", h3["collider"].name, " (", h3["collider"].get_class(), ") at ", h3["position"])

	# 4. 学生碰撞体形状与位置
	var col := s.get_node("CollisionShape2D") as CollisionShape2D
	print("学生 CollisionShape2D: global=", col.global_position, " shape=", col.shape, " disabled=", col.disabled)
	if col.shape is RectangleShape2D:
		print("  矩形尺寸=", (col.shape as RectangleShape2D).size)

	get_tree().quit(0)
