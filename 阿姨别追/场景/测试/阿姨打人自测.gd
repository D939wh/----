extends Node
## 阿姨打人全流程自测节点
## 挂在测试场景里跑：进场景就自动把整套流程打一遍，打完打印结果并退出。
## 不用 --script：那种方式下 autoload（Director）不会加载，走「实例化主场景 + 正常游戏循环」。
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
	# 主场景的第二个学生正好站在 960，会和测试布景重叠：挪到走廊另一头
	scene.get_node("student2").global_position = Vector2(1500, 208)

	# —— 布景：宿管控制，学生站她右边 60px ——
	# 场上有第二个学生，F1 轮换第一下不一定是宿管：直接点名
	Director.set_control(k)
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

	# —— 抓捕读条（策划案 §6 的 1.2 秒）：先试「按一下就松」→ 不该扛起来 ——
	await _wait(1.0)
	k.global_position = Vector2(940, 208)
	await _wait(0.1)
	Input.action_press("grab")
	await _wait(0.4)                 # 只按 0.4 秒，不到 1.2
	# 读条期间宿管头顶必须挂出一根「抓捕 还剩几秒」的可见反馈
	r["抓捕条·按住中"] = "宿管条可见=%s / 文字「%s」" % [
		_条可见(k), _条文字(k)]
	Input.action_release("grab")
	await _wait(0.2)
	r["读条不足不扛"] = "宿管扛着人=%s（应 false）/ 剩余进度 %.2f（应 0）" % [
		k._carried_student != null, k._抓捕进度]
	# 松手之后条必须消失，不能留在头顶说「还在按」
	r["抓捕条·松手后"] = "宿管条可见=%s（应 false）" % _条可见(k)

	# —— 按住读条期间按着右方向键也不该走（抓人得站定）；1.2 秒后扛上肩 ——
	var 抓前x := k.global_position.x
	Input.action_press("grab")
	Input.action_press("right")
	await _wait(1.0)                 # 只到 1.0 秒，还在读条里（1.2 才满）
	Input.action_release("right")    # 先松方向键，免得「扛着走」把位移混进来
	r["抓人站定"] = "读条中按右的位移 %.0f（应 0）" % (k.global_position.x - 抓前x)
	r["抓捕条·快满时"] = "宿管条可见=%s / 文字「%s」（应剩 0.2 上下）" % [
		_条可见(k), _条文字(k)]
	await _wait(0.35)                # 剩下 0.2 秒跑满读条
	Input.action_release("grab")
	await _wait(0.2)
	r["按住1.2秒扛起"] = "宿管扛着人=%s / 学生被扛=%s / 学生父节点=%s" % [
		k._carried_student != null, s.被扛着, s.get_parent().name]
	# 扛上肩就算读条结束，条不能还挂在头上
	r["抓捕条·扛起后"] = "宿管条可见=%s（应 false）" % _条可见(k)

	# —— 扛着人走：移速应 370×0.6=222，0.5 秒走约 100+px ——
	var before := k.global_position.x
	Input.action_press("right")
	await _wait(0.5)
	Input.action_release("right")
	r["扛人走"] = "0.5 秒位移 %.0f（222 速应 100+）" % (k.global_position.x - before)
	r["学生跟身"] = "间距 %.0f（<40 算跟上）" % abs(s.global_position.x - k.global_position.x)

	# —— 再按 G：放下。学生该落在宿管脚边地面上（不能消失/弹飞）——
	await _wait(0.3)
	await _tap_g()
	await _wait(0.4)
	r["放下后"] = "宿管空肩=%s / 学生不被扛=%s / 还瘫痪=%s / 父节点=%s" % [
		k._carried_student == null, s.被扛着 == false, s.瘫痪, s.get_parent().name]
	r["放下位置"] = "学生在 (%.0f, %.0f)，宿管在 (%.0f, %.0f)（脚边±26px、同一地面为对）" % [
		s.global_position.x, s.global_position.y, k.global_position.x, k.global_position.y]
	var 在脚边: bool = abs(s.global_position.x - k.global_position.x) <= 40.0
	var 在地面: bool = absf(s.global_position.y - k.global_position.y) < 8.0
	r["放下判in"] = "在脚边=%s / 在地面=%s" % [在脚边, 在地面]


	# —— 朝向验证：宿管先向左走（面朝左），学生对齐到她左侧，按 F 应朝左命中 ——
	await _wait(1.3)   # 等挥击 CD
	s.拉起()           # 学生恢复，重摆位置再打
	await get_tree().physics_frame
	Input.action_press("left")
	await _wait(0.3)
	Input.action_release("left")
	await _wait(0.2)
	k.global_position = Vector2(940, 208)
	s.global_position = Vector2(880, 208)   # 学生在宿管左边 60px
	await _wait(0.1)
	await _tap_f()
	r["朝左挥"] = "宿管朝向 %.0f（应 -1）/ 学生血量 %d（应 1）" % [k._swing_dir, s.血量]

	# ── 互救：复制一个学生当队友，打瘫它，另一个按住 H 4 秒拉起来 ──
	# 主场景只有一个学生，互救要两个人：复制一个当队友（策划案 §7.6）
	s.拉起()
	s.global_position = Vector2(700, 208)
	k.global_position = Vector2(1500, 208)   # 宿管挪远，别在救援时捣乱
	await _wait(0.2)

	var 队友: CharacterBody2D = s.duplicate()
	scene.add_child(队友)
	队友.global_position = Vector2(730, 208)   # 感应区 96 宽，30px 稳在里头
	Director.当前控制 = s                      # 复制品也会向总管报到，把控制权夺回来
	await _wait(0.2)
	队友.血量 = 0
	队友._瘫了()
	await _wait(0.1)
	r["互救前"] = "队友瘫痪=%s / 间距 %.0f（感应区 96 宽）" % [
		队友.瘫痪, abs(队友.global_position.x - s.global_position.x)]

	Input.action_press("self_rescue")
	await _wait(1.0)                           # 先按 1 秒，看条有没有出来
	r["救人条·按住中"] = "学生条可见=%s / 文字「%s」（应剩 3.0 上下）" % [
		_条可见(s), _条文字(s)]
	await _wait(3.3)                           # 补满策划案：拉起读条 4 秒
	Input.action_release("self_rescue")
	await _wait(0.2)
	r["互救4秒后"] = "队友还瘫着=%s（应 false）/ 队友血量 %d（应 2）" % [队友.瘫痪, 队友.血量]
	r["救人条·拉完"] = "学生条可见=%s（应 false）" % _条可见(s)

	# ── 自救：自己瘫了，按住 H 2 秒爬起来 ──
	# 队友不删：总管没有注销接口，删了之后换人时会摸到已释放的节点；留着不吃键盘也不挡路
	s.血量 = 0
	s._瘫了()
	await _wait(0.1)
	Input.action_press("self_rescue")
	await _wait(1.0)                           # 先按 1 秒，看自救条有没有出来
	r["自救条·按住中"] = "学生条可见=%s / 文字「%s」（应剩 1.0 上下）" % [
		_条可见(s), _条文字(s)]
	await _wait(1.3)                           # 补满 2 秒
	Input.action_release("self_rescue")
	await _wait(0.2)
	r["自救2秒后"] = "还瘫着=%s（应 false）/ 血量 %d（应 2）" % [s.瘫痪, s.血量]
	r["自救条·爬起后"] = "学生条可见=%s（应 false）" % _条可见(s)

	# ── 读条到一半被切走（F1 / 点击换人），条必须自己收掉 ──
	# 换人后脚本走「不受控」分支直接早退，没人推进读条：不主动取消，条会永久挂在头顶
	# 宿管侧：按住 G 抓到一半，把控制权抢给学生
	s.血量 = 0
	s._瘫了()
	k.global_position = Vector2(760, 208)
	s.global_position = Vector2(790, 208)
	Director.set_control(k)
	await _wait(0.2)
	Input.action_press("grab")
	await _wait(0.5)
	r["切人前·宿管条"] = "可见=%s / 文字「%s」" % [_条可见(k), _条文字(k)]
	Director.set_control(s)                 # 半路把控制权抢走
	await _wait(0.2)
	Input.action_release("grab")
	r["切人后·宿管条"] = "可见=%s（应 false）/ 抓捕进度 %.2f（应 0）" % [
		_条可见(k), k._抓捕进度]

	# 学生侧：按住 H 拉队友拉到一半，把控制权抢去宿管
	s.拉起()
	队友.拉起()
	s.global_position = Vector2(700, 208)
	队友.global_position = Vector2(730, 208)
	队友.血量 = 0
	队友._瘫了()
	Director.set_control(s)
	await _wait(0.2)
	Input.action_press("self_rescue")
	await _wait(0.6)
	r["切人前·学生条"] = "可见=%s / 文字「%s」" % [_条可见(s), _条文字(s)]
	Director.set_control(k)
	await _wait(0.2)
	Input.action_release("self_rescue")
	r["切人后·学生条"] = "可见=%s（应 false）/ 救人进度 %.2f（应 0）" % [
		_条可见(s), s._救人进度]
	队友.拉起()

	# —— 恢复现场：控制权还给学生，血量拉起 ——
	Director.set_control(s)
	s.拉起()

	print("=== 阿姨打人全流程自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## 这个人头顶有没有挂着一根正在显示的读条
func _条可见(谁: Node) -> bool:
	var 条 = 谁.get("_读条条")
	return 条 != null and is_instance_valid(条) and 条.在显示中()


## 那根条上写着什么（一个字都没有就回 "-"，方便一眼看出「条根本没建」）
func _条文字(谁: Node) -> String:
	var 条 = 谁.get("_读条条")
	if 条 == null or not is_instance_valid(条):
		return "-"
	return 条.get_node("框/文字").text


## 模拟「按一下 F」：press → 两个物理帧 → release → 稳定 0.15 秒
func _tap_f() -> void:
	Input.action_press("interaction")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("interaction")
	await _wait(0.15)


## 模拟「按一下 G」：press → 两个物理帧 → release → 稳定 0.15 秒
func _tap_g() -> void:
	Input.action_press("grab")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("grab")
	await _wait(0.15)
