extends "res://组件/状态机/状态.gd"
## 已逃出 —— 这个学生已经从大门跑出去了，本局他本人已经赢了。
##
## 进入后：不听键盘、不挡路、不再被出口和宿管感应到，原地站住。
## 优先级最高（`抢占()` 第一行），任何输入都抢不回来 —— 他已经出去了。

func 进入(_上个: String = "") -> void:
	var h = host
	h.velocity = Vector2.ZERO
	# 手上 / 肩上还拿着东西就先放下：人已经出门，东西没跟出去
	if h.正扛着人():
		h.放下同学()
	if h.正搬着():
		h._drop_box()
	h._取消蓄力()
	h._取消救人()
	h._收读条()
	# 碰撞层清 0：出口 / 宿管 / 队友的感应区都看不见他，也不挡路；
	# 掩码不动，所以他仍然踩得住地板，不会往下掉。
	h.collision_layer = 0
	print("[学生] %s 已经逃出去了" % h.name)


func 每帧(delta: float) -> void:
	var h = host
	h.velocity.x = 0.0
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	else:
		h.velocity.y = 0.0
	h.move_and_slide()
