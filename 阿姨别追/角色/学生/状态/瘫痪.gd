extends "res://组件/状态机/状态.gd"
## 瘫痪 —— 两格血打空，趴在地上。不能跳、不能爬、不能交互，但能**蹭着慢慢挪**，
## 也能按住 H 自己爬起来。
##
## 【2026-11-11 主人定】瘫了不是钉死在地上：相当于背上压着一件**隐形 4 档搬运物** ——
## 速度、跳跃、攀爬的限制照 `数据/重量档位.gd` 的第 4 档执行（30% 速度、不能跳、不能爬）。
## 这里只用到「移速倍率」那一条，因为瘫着本来就没有跳和爬的代码 —— 想让爬得更快/更慢，
## 改档位表里 4 档的 `移速倍率`，别在这里另写一个数。
##
## `瘫痪` 由 `血量 <= 0` 派生，不单独存储。
## 被搬运走时本状态仍成立，放下后自动回到这里。

const 状态名 := preload("res://角色/学生/状态/状态名.gd")
## 重量档位表：「背上那个隐形重物」的唯一数据来源
const 重量档位 := preload("res://数据/重量档位.gd")
const 爬行档名 := "4"


func 每帧(delta: float) -> void:
	var h = host
	# 键盘归不归我（没被操控时不能因为别人按方向键就自己爬）
	var 受控: bool = h.受控()

	# ── 爬行：4 档速度（隐形重物唯一露在外面的表现）───────
	var dir: float = Input.get_axis("left", "right") if 受控 else 0.0
	if dir != 0.0:
		var 目标速度: float = h.SPEED * float(重量档位.表[爬行档名]["移速倍率"])
		h.velocity.x = move_toward(h.velocity.x, dir * 目标速度, h.ACCEL * delta)
	else:
		h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)

	# 重力照常 —— 被放下 / 被搬到空中会自己落到地上
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	else:
		h.velocity.y = 0.0

	# 只有当前被玩家操作时才响应 H 自救，避免一次按键让所有瘫痪角色同时起身。
	if 受控:
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
