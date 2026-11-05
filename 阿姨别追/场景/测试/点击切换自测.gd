extends Node2D
## 开发者模式（点击换人）自测（2026-11-05）
##
## 为什么要有这个测试：点击换人涉及三个肉眼看不出来的坑——
##   ① 屏幕坐标 → 世界坐标（相机是会动的，算错就会点东切西）
##   ② 点的是「角色本体」还是「它身上的感应区」/ 「地皮」（查错层就永远点不中）
##   ③ 瘫痪学生换了碰撞层（1 → 2），漏查一层就点不到躺着的人
## 所以这里不直接调 Director.set_control，而是**真的造一个鼠标事件塞进视口**，
## 走完整条链路：视口 → 面板 _unhandled_input → 物理拾取 → 总管换人。
##
## 跑法：godot --headless --path <工程> res://场景/测试/点击切换自测.tscn

var 主场景: Node
var 学生1: Node
var 学生2: Node
var 宿管: Node
var 结果: Dictionary = {}


func _ready() -> void:
	主场景 = load("res://场景/主场景.tscn").instantiate()
	add_child(主场景)
	await _等(0.2)

	学生1 = 主场景.get_node("student")
	学生2 = 主场景.get_node("student2")
	宿管 = 主场景.get_node("keeper")

	# 把三个人挪到相机附近：相机默认跟着学生1，隔太远的目标会跑到屏幕外，
	# 屏幕外的坐标点不到，那就变成在测「相机」而不是测「点击」了。
	宿管.global_position = Vector2(1000, 178)
	学生2.global_position = Vector2(940, 178)
	await _等(0.3)
	_对准相机()

	结果["① 名单里几个人"] = "%d 个（%s）" % [Director._controllables.size(), _名字们()]
	结果["② 初始控制谁"] = Director.当前控制.name

	# ── 点宿管 → 应切到宿管 ──
	_点(宿管)
	await _等(0.15)
	结果["③ 点宿管"] = Director.当前控制.name

	# ── 相机已经换成宿管的，重新对准，再点学生2 ──
	_对准相机()
	_点(学生2)
	await _等(0.15)
	结果["④ 点学生2"] = Director.当前控制.name

	# ── 点空处 → 不该换人 ──
	_对准相机()
	var 点前 := Director.当前控制.name
	_点世界坐标(Vector2(300, 60))   # 半空处，那里没人
	await _等(0.15)
	结果["⑤ 点空处"] = "%s → %s（应不变）" % [点前, Director.当前控制.name]

	# ── 瘫痪的学生也要点得到（碰撞层从 1 变 2）──
	# 先把控制权交给学生1，否则「点瘫倒的学生2」时本来就是她，测不出有没有点中
	学生2.血量 = 1
	学生2.被打中()
	await _等(0.2)
	Director.set_control(学生1)
	_对准相机()
	var 点瘫前 := Director.当前控制.name
	_点(学生2)
	await _等(0.15)
	结果["⑥ 点瘫痪的学生"] = "%s → %s（瘫痪=%s）" % [点瘫前, Director.当前控制.name, 学生2.瘫痪]

	# ── 非角色节点不能被接管（防御：乱点不该崩、也不该换错人）──
	结果["⑦ 指定箱子"] = "返回 %s（应为 false）" % str(Director.set_control(主场景.get_node("CarryableBox")))

	# ── F1 轮换还能用（老办法不能改坏）──
	var F1前 := Director.当前控制.name
	Director.switch_control()
	await _等(0.1)
	结果["⑧ F1 轮换"] = "%s → %s" % [F1前, Director.当前控制.name]

	# ── 相机换算往返（点得准全靠它）──
	_对准相机()
	var 目标世界点: Vector2 = 学生1.global_position + Vector2(0, -22)
	var 屏幕点: Vector2 = get_viewport().get_canvas_transform() * 目标世界点
	var 反算: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * 屏幕点
	结果["⑨ 屏幕↔世界往返"] = "%.0f,%.0f → %.0f,%.0f" % [目标世界点.x, 目标世界点.y, 反算.x, 反算.y]

	_打印()
	get_tree().quit()


## 等若干秒（真时间，让物理和相机跑起来）
func _等(秒: float) -> void:
	await get_tree().create_timer(秒).timeout


## 让相机立刻到位，别在平滑途中算坐标（平滑中算出来的屏幕点会差几十像素）
func _对准相机() -> void:
	if Director.当前控制 == null:
		return
	var cam := Director.当前控制.get_node_or_null("Camera2D")
	if cam != null:
		cam.reset_smoothing()


## 朝某个角色的身体中心点一下
## 为什么不是 global_position：角色根节点在**脚底**，碰撞盒（20×44）在脚底往上 22 像素处。
## 玩家点的是身体，不是脚底线；这里照玩家的实际点法来。
func _点(who: Node) -> void:
	_点世界坐标(who.global_position + Vector2(0, -22))


## 朝世界坐标发一次「鼠标左键按下」
## 走 push_input(in_local_coords=true)：事件坐标已经是视口坐标，别再让引擎缩放一次。
## 为什么强调：项目 stretch mode=viewport，真机上引擎会把窗口坐标缩放到 640×360 再送来；
## 测试里造事件若不加这个 true，坐标会被再乘一次缩放比（实测 502 → 5015），点哪都不中。
func _点世界坐标(世界点: Vector2) -> void:
	get_viewport().push_input(_造事件(世界点), true)


## 造一个「鼠标左键按下」，坐标按当前相机换算成屏幕坐标
func _造事件(世界点: Vector2) -> InputEventMouseButton:
	var 屏幕点: Vector2 = get_viewport().get_canvas_transform() * 世界点
	var 事件 := InputEventMouseButton.new()
	事件.button_index = MOUSE_BUTTON_LEFT
	事件.pressed = true
	事件.position = 屏幕点
	return 事件


func _名字们() -> String:
	var 名: Array[String] = []
	for one in Director._controllables:
		名.append(str(one.name))
	return ", ".join(名)


func _打印() -> void:
	print("")
	print("================ 开发者模式 · 点击换人自测 ================")
	for k in 结果:
		print("  %-16s %s" % [k, 结果[k]])
	print("=========================================================")
