extends "res://组件/状态机/状态.gd"
## 救人中 —— 站着按住 H 拉身边瘫倒的队友，需要按住 `拉起读条` 秒。
##
## `正常.gd` 先填好 `_救人目标` 再切到本状态；本状态不重复查找目标。
## 任何方式离开都会调用 `_取消救人()`，保证读条被收起。

const 状态名 := preload("res://角色/学生/状态/状态名.gd")


func 进入(_上个: String = "") -> void:
	var h = host
	h._救人进度 = 0.0
	print("[学生] 开始拉 %s（按住 %.0f 秒）" % [h._救人目标.name, h.拉起读条])
	h._我的读条().开始(h, "拉队友", h.拉起读条)


func 每帧(delta: float) -> void:
	var h = host

	# 松手 → 这次作废，进度清零
	if not Input.is_action_pressed("self_rescue"):
		h._取消救人()
		机器().切(状态名.正常)
		return

	# 拉着拉着他没了 / 不瘫了 / 被扛走了 → 拉不下去
	if not is_instance_valid(h._救人目标) or not h._救人目标.瘫痪 or h._救人目标.被扛着:
		print("[学生] 救人中断：目标已经不在原地瘫着了")
		h._取消救人()
		机器().切(状态名.正常)
		return

	h._救人进度 += delta
	h._我的读条().推进(h._救人进度)          # 条跟着走：填到几分、还剩几秒
	h.换色(Color(1.0, 1.0, 0.75))          # 淡黄 = 正在用力拉

	if h._救人进度 >= h.拉起读条:
		var 目标 = h._救人目标
		h._取消救人()                        # 先收自己的条，再让对方站起来
		目标.拉起()
		print("[学生] 拉起来了：%s" % 目标.name)
		机器().切(状态名.正常)
		return

	# 读条期间站着不动，但重力照常
	h.velocity.x = 0.0
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	else:
		h.velocity.y = 0.0
	h.move_and_slide()


func 离开(_下个: String = "") -> void:
	# 无论怎么离开，都把这次救援收干净（进度归零、颜色还原、条收起）。
	# 已经收过再收一次是幂等的（_取消救人 里全是置空操作），不用另外判。
	host._取消救人()
