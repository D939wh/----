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

	# —— 挥击 1：应掉到 1 格，并被击退一大步 ——
	await _tap_f()
	r["一挥后"] = "血量 %d / 瘫痪 %s" % [s.血量, s.瘫痪]
	await _wait(0.3)                 # 判定在 0.35s，_tap_f 只等到 0.55s：击退还在滑
	r["击退"] = "学生被推开 %.0fpx（应 ≈70，朝右）/ 硬直已结束=%s" % [
		s.global_position.x - 960.0, s._击退剩余 <= 0.0]

	# —— 等 CD（1.2 秒）再挥：应 0 格 + 瘫痪 + 变色 ——
	# 这一棍之前要把学生摆回来：上一棍的击退把她推出去 70px，
	# 已经出了 67px 的棍长（手控的宿管不会自己追）。相当于「她追上去补一棍」。
	# 直接搬人必须手动抹掉击退余速，否则下一帧冲量又把她推走。
	await _wait(1.0)
	s.velocity.x = 0.0
	s._击退剩余 = 0.0
	s.global_position = Vector2(960, 208)
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
	# 观察窗口要短于后摇（0.55 秒）：这一棍按下 F 后 0.55 秒才判完，后摇还在走。
	var 学生原位 := s.global_position.x
	Input.action_press("right")
	await _wait(0.3)
	Input.action_release("right")
	r["瘫了走不动"] = "宿管位移 %.0f（收棍中，应 <5）/ 读数时还在挥=%s" % [
		k.global_position.x - 900.0, k._挥击中()]

	# —— 抓捕读条（策划案 §6 的 1.2 秒）：先试「按一下就松」→ 不该扛起来 ——
	# 打瘫她的那一棍同样带击退：她已经滑到 1028 附近了。抓人前把人摆回脚边。
	await _wait(1.0)
	s.velocity.x = 0.0
	s._击退剩余 = 0.0
	s.global_position = Vector2(960, 208)
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
	await _wait(0.3)
	# 击退方向得跟「她在哪一边」走：站我左边挨打，就该被我往左推出去
	r["击退方向"] = "学生 x 880 → %.0f（应更小，被推向左边）" % s.global_position.x

	# —— 棍子本身：平时就得看得见，长度 = 攻击距离（判定框就是这根棍子）——
	var 棍 = k._棍子
	var 棍长 := -1.0
	if 棍 != null and 棍.points.size() >= 2:
		棍长 = 棍.points[0].distance_to(棍.points[1])
	r["棍子"] = "有棍=%s / 可见=%s / 棍长 %.0f（应 %.0f）/ 粗细 %.0f（应 %.0f）" % [
		棍 != null, 棍 != null and 棍.visible, 棍长, k.SWING_RANGE,
		棍.width if 棍 != null else -1.0, k.棍宽]

	# —— 前摇：按 F 后 0.2 秒还在抬手，学生不该掉血，棍子已经抬到头顶 ——
	# 老实现在这一帧就掉血了；现在判定被推到 0.35 秒之后，这一条会替主人盯住「别又变回瞬发」。
	await _wait(0.9)                 # 等上一棍的后摇走完
	s.拉起()
	k.global_position = Vector2(940, 208)
	s.global_position = Vector2(1000, 208)
	await _按方向("right")
	Input.action_press("interaction")
	await get_tree().physics_frame
	Input.action_release("interaction")
	await _wait(0.2)
	var 棍尖y := -999.0
	if k._棍子 != null and k._棍子.points.size() >= 2:
		棍尖y = k._棍子.points[1].y
	r["前摇中"] = "0.2 秒时学生血量 %d（应 2，还没判）/ 棍尖 y %.0f（待机约 -14，抬起应 < -60）" % [
		s.血量, 棍尖y]

	# —— 超出棍长：学生站 260px 外（远大于 67 的棍长），这一棍扫不到，血量不该变 ——
	# 判定框就是那根棍子，不是「圈内必中」。
	await _wait(1.3)                 # 这一棍走完 + 过 CD
	s.global_position = Vector2(k.global_position.x - 260.0, 208)
	await _wait(0.1)
	var 打前血: int = s.血量
	await _tap_f()
	r["超出棍长"] = "血量 %d → %d（应不变）" % [打前血, s.血量]

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

	# —— AI 主动打人：把控制权交出去，阿姨看见人该自己走过去挥棍 ——
	# 学生放在 200px（棍长边缘、刚出 `挥击距离`）：她得先追一小步，再站定抬手。
	# 这一条同时验证「抢占」把 追击 → 攻击 的那一步接上了。
	# 那个复制出来的队友要挪走：它还瘫在 730，比 1000 的学生近得多，
	# 阿姨会一直去捶它（瘫了打不动），于是「学生血量没变」看起来像 AI 不会打人。
	队友.global_position = Vector2(1600, 208)
	Director.set_control(s)
	s.拉起()
	k.global_position = Vector2(800, 208)
	s.global_position = Vector2(1000, 208)
	await _wait(0.2)
	var 打前血AI: int = s.血量
	await _wait(2.5)
	# 采样这一刻她可能在「攻击」也可能在「追击」：打中一棍会把学生击退 70px，
	# 正好推出 60px 的挥击距离，她就得再追上去 —— 这正是要的节奏。
	# 所以这一条只认「血量变少」，状态只作参考，不作判据。
	r["AI主动打人"] = "学生血量 %d → %d（应变少）/ 阿姨状态「%s」（攻击或追击都正常）" % [
		打前血AI, s.血量, k._机器.当前()]

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


## 模拟「按一下 F」，并等这一棍真的挥完（前摇 0.35 + 扫 0.14 + 一点余量）。
## 挥击改成三段式后不能按下就读血量了：按下那一帧还在抬手，判定发生在 0.35 秒之后。
func _tap_f() -> void:
	Input.action_press("interaction")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("interaction")
	await _wait(0.55)


## 按一下方向键，把宿管的朝向定好（按住两个物理帧，位移小到可以忽略）
func _按方向(键: String) -> void:
	Input.action_press(键)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(键)
	await _wait(0.1)


## 模拟「按一下 G」：press → 两个物理帧 → release → 稳定 0.15 秒
func _tap_g() -> void:
	Input.action_press("grab")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("grab")
	await _wait(0.15)
