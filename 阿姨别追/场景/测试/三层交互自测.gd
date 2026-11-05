extends Node
## 三层交互链路自测（2026-11-04 修架构那件事的验收工具）
##
## 它验的不是"门能不能开"，而是【链路方向对不对】：
##   角色按键 → 总管 → 楼层代理 → 代理自己去推门/搬箱子/收道具
##
## 为什么不用 --script 跑：那种方式下 autoload（Director）不会加载，
## 而这次验的正是 autoload 那条线。所以走「实例化主场景 + 正常游戏循环」这条路。
##
## 用法：
##   Godot_v4.7.2 的 console 版 --headless --path <工程> res://场景/测试/三层交互自测.tscn
##
## 看到下面这两行同时出现，才算真的改对了：
##   [代理·一楼] 收到：interact        ← 代理真的接到了角色的上报
##   [门] 1-走廊东 已打开（求生者 推的）  ← 代理真的把门推开了
## 只看到门开了、没有代理那一行 → 角色还在自己干活，没改对。

var r := {}
var 通过数 := 0
var 失败数 := 0


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var s: CharacterBody2D = scene.get_node("student")
	var k: CharacterBody2D = scene.get_node("keeper")
	# 11-05：主场景多了第二个学生，挪到走廊尽头，别混进这一轮的感应区
	scene.get_node("student2").global_position = Vector2(1500, 178)
	var agent: Node = scene.get_node("FloorAgent")
	var 东门: Node = agent.get_door("1-走廊东")
	var 西门: Node = agent.get_door("1-走廊西")

	# ── ① 学生 E 开门：链路应走「学生 → 总管 → 代理 → 门」──
	# 门在 (760,178)，站 (810,178)：站在门右边，身体（半宽 10）不撞门板（门板右边缘 792），
	# 但感应区（学生 96 宽 / 门 88 宽）一定重叠 —— 这就是"够得着"的姿势。
	# 为什么站右边不站两扇门中间：西门在 620，两扇门的感应区中间只剩 52px 空隙，
	# 站中间会同时够到两扇门，代理取哪一个就不确定了（第一次跑就撞上了这个坑）。
	s.global_position = Vector2(810, 178)
	await _wait(0.2)   # 等物理帧把"感应区里有谁"算出来
	_记("① 学生感应区里有门", _感应区里有(s, "door"))

	await _tap("open_door")
	await _wait(0.5)   # 学生 0.3 秒开满，给足余量
	_记("① 门真的开了", 东门._amount >= 0.99)
	_记("① 推门的人记成了学生", 东门._user == s)

	# ── ② 学生 E 关门（同一扇门）：证明按下报的是"我碰了"，不是"永久开"──
	await _tap("open_door")
	await _wait(0.5)
	_记("② 再按一次关上了", 东门._amount <= 0.01)

	# ── ③ 学生 F 搬箱子：箱子在 (1010,186)，站 (980,178) ──
	s.global_position = Vector2(980, 178)
	await _wait(0.2)
	_记("③ 感应区里有箱子", _感应区里有(s, "carryable"))
	await _tap("interaction")
	await _wait(0.2)
	_记("③ 箱子扛起来了", s._carry_state == s.CarryState.CARRYING)
	_记("③ 箱子认人做爹（跟着人走）", s._carried != null and s._carried.get_parent() == s)

	# ── ④ 学生 F 放下箱子（纯自身状态，不经过代理）──
	await _tap("interaction")
	await _wait(0.2)
	_记("④ 箱子放下了", s._carry_state == s.CarryState.EMPTY)
	_记("④ 箱子还给场景", s._carried == null)

	# ── ⑤ 学生 F 捡道具：钥匙在 (1230,182)，站 (1200,178) ──
	s.global_position = Vector2(1200, 178)
	await _wait(0.2)
	_记("⑤ 感应区里有道具", _感应区里有(s, "usable_item"))
	await _tap("interaction")
	await _wait(0.2)
	_记("⑤ 道具进了格子", s._item_icon != null)

	# ── ⑥ 宿管的 E 也走同一条链路（1.5 秒慢开，所以等久一点）──
	# 西门在 (620,178)，宿管站 (560,178)。先把控制权切到宿管。
	Director.set_control(k)   # 11-05：直接点名，不然第一下轮到的是第二个学生
	k.global_position = Vector2(560, 178)
	await _wait(0.2)
	_记("⑥ 宿管感应区里有门", _感应区里有(k, "door"))
	await _tap("open_door")
	await _wait(1.8)
	_记("⑥ 宿管把西门推开了", 西门._amount >= 0.99)
	_记("⑥ 推西门的人是宿管", 西门._user == k)

	# ── ⑦ 空处按键不该出事（玩家最常做错的事）──
	# 【位置为什么从 300 改成 1700】11-05 加了钥匙板之后，(320,160) 摆了一块一号板，
	# 站 300 按 F 会把它扛起来 —— 那就不再是"对着空处按键"了，用例本身失效。
	# 1700 附近确认什么都没有（最近的是宿管 1500，宿管是身体不是感应区，不算）。
	s.global_position = Vector2(1700, 178)
	Director.set_control(s)   # 控制权还给学生
	await _wait(0.2)
	await _tap("open_door")
	await _tap("interaction")
	await _wait(0.2)
	_记("⑦ 对着空处按键不报错、不改状态", s._carry_state == s.CarryState.EMPTY)

	print("=== 三层交互链路自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	print("=== 通过 %d 项 / 失败 %d 项 ===" % [通过数, 失败数])
	get_tree().quit(0 if 失败数 == 0 else 1)


## 角色感应区里现在有没有"某个组"的东西（这是测试在偷看，正式代码里角色不看）
func _感应区里有(角色: Node, 组名: String) -> bool:
	for area in 角色.get_node("PickupZone").get_overlapping_areas():
		if area.is_in_group(组名):
			return true
	return false


## 记账并打印：一眼看出哪条没过
func _记(项: String, 通过: bool) -> void:
	r[项] = "✅" if 通过 else "❌"
	if 通过:
		通过数 += 1
	else:
		失败数 += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## 模拟按一下某个动作键：press → 两个物理帧 → release → 稳定 0.1 秒
func _tap(动作: String) -> void:
	Input.action_press(动作)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(动作)
	await _wait(0.1)
