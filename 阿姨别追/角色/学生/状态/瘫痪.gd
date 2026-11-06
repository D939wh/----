extends "res://组件/状态机/状态.gd"
## 瘫痪 —— 两格血打空，蹲在地上。不吃输入、不能交互，但能按 H 自己爬起来。
##
## `瘫痪` 由 `血量 <= 0` 派生，不单独存储。
## 被拎走时本状态仍成立，放下后自动回到这里。

const 状态名 := preload("res://角色/学生/状态/状态名.gd")


func 每帧(delta: float) -> void:
	var h = host
	# 瘫了：不吃输入、不能交互，但重力照常 —— 被放下/被搬到空中会自己落到地上
	h.velocity.x = 0.0
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	else:
		h.velocity.y = 0.0

	# 只有当前被玩家操作时才响应 H 自救，避免一次按键让所有瘫痪角色同时起身。
	if Director.当前控制 == null or Director.当前控制 == h:
		_推进自救(h, delta)

	h.move_and_slide()


## 瘫痪时按住 H：自己爬起来。条走满 `自救读条` 秒站起，颜色由红变白。
func _推进自救(h, delta: float) -> void:
	if not Input.is_action_pressed("self_rescue"):
		h._自救进度 = 0.0
		h._收读条()
		if not h.被扛着:
			h.换色(h.瘫痪变色)
		return

	# 刚按下（进度还在 0）：开一根条。之后每帧只报进度，不重复开
	if h._自救进度 <= 0.0:
		h._我的读条().开始(h, "自救", h.自救读条)

	h._自救进度 += delta
	h._我的读条().推进(h._自救进度)
	h.换色(h.瘫痪变色.lerp(Color.WHITE, minf(h._自救进度 / h.自救读条, 1.0)))

	if h._自救进度 >= h.自救读条:
		h._自救进度 = 0.0
		h._收读条()
		h.换色(Color.WHITE)
		h.拉起()                     # 血量补满 → 瘫痪 getter 自动变 false → 下一帧抢占切回正常
		print("[学生] 自救成功，自己爬起来了")
