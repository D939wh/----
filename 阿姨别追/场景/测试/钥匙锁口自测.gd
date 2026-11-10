extends Node
## 钥匙板 + 锁口自测
##
## 验的是这一整条链路通不通：
##
##   学生扛起钥匙板 → 走到锁口前按 R → 代理认出来 → 锁口自己读 2 秒
##   → 插上、孔亮、人空手 → 三块插满 → 锁口往上报 → 代理开门
##
## 每一环都要看得见证据，不是"跑一下没报错"：
##   [锁口] 1-门厅 开始插「一号」（2.0 秒）   ← 编号把 R 递到了锁口
##   [锁口] 1-门厅 开始插「一号」（2.0 秒）
##   [门] 1-走廊东 收到「1-门厅」插满了      ← 按编号递到了门
##   [门] 1-走廊东 被解锁，弹开了
##
## 用法：
##   Godot_v4.7.2 的 console 版 --headless --path <工程> res://场景/测试/钥匙锁口自测.tscn

var r := {}
var 通过数 := 0
var 失败数 := 0

## 规则（颜色/编号）是全工程共用的，不在地图清单里
const 规则 = preload("res://数据/通用规则.gd")
## 学生的状态名常量：这里要核对「赢家进了已逃出」
const 状态名 = preload("res://角色/学生/状态/状态名.gd")


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var s: CharacterBody2D = scene.get_node("student")
	var s2: CharacterBody2D = scene.get_node("student2")
	s2.global_position = Vector2(1800, 178)  # 挪远，别混进感应区
	# 这张图里住着一位宿管（keeper）。她的 AI 会自己巡逻、把没人管的学生打瘫扛走，
	# 扛着路过判定区会把「谁在不在区里」搅成一锅粥 —— 本测的只是钥匙→门→判定区
	# 这条链，把她请出场（宿管的行为有她自己的自测管）。
	var 宿管: Node = scene.get_node_or_null("keeper")
	if 宿管 != null:
		宿管.queue_free()
	# 全部拿编号向总管要，不翻代理的内部字典
	var 锁口: Node = Director.thing("1-门厅")
	var 东门: Node = Director.thing("1-走廊东")
	var 一号: Node = Director.thing("一号")
	var 二号: Node = Director.thing("二号")
	var 三号: Node = Director.thing("三号")

	# ── ① 代理照清单把东西都摆出来了 ──
	_记("① 三块钥匙板都建出来了",
		一号 != null and 二号 != null and 三号 != null)
	_记("① 锁口建出来了一个", 锁口 != null)
	if 一号 == null or 锁口 == null:
		_收尾()
		return
	_记("① 三块各有编号", 一号.编号 == "一号" and 三号.编号 == "三号")
	# 颜色必须是通用规则那一份，不是各写各的（不然会出现「钥匙黄、孔红」）
	_记("① 板子颜色来自通用规则", 一号.牌色 == 规则.钥匙板配色["一号"])

	Director.set_control(s)

	# ── ⑨a 反向验证：大门是空气墙 —— 不插钥匙只按 E，什么都该纹丝不动 ──
	# 空气墙看不见门板、E 推不动，只能被三块钥匙板真正解锁弹开。
	s.global_position = Vector2(810, 178)   # 门外侧，正好在出口判定区里
	await _wait(0.45)
	await _tap("open_door")
	await _wait(0.6)
	_记("⑨a 空气墙按 E 推不开（门板没动）", 东门._amount <= 0.01)
	_记("⑨a 按了 E 也不算「解锁」", not Match.is_door_unlocked("1-走廊东"))
	_记("⑨a 人站在判定区里也不算赢（门没真解锁，出口没激活）", Match.escaped.is_empty())

	# ── ② 扛起一号板：从 320 那边拿 ──
	s.global_position = Vector2(320, 178)
	await _wait(0.45)
	_记("② 感应区里有钥匙板", _感应区里有(s, "carryable"))
	await _tap("interaction")
	await _wait(0.2)
	_记("② 一号扛起来了", s._carry_state == s.CarryState.CARRYING)
	_记("② 扛的是 15kg（1 档）", s._负重公斤 == 15.0)
	_记("② 1 档只罚一点速度", s._移速倍率 >= 0.85 and s._移速倍率 <= 0.95)
	_记("② 1 档还能跳还能爬", s._跳跃高度倍率 >= 1.0 and s._可否攀爬)

	# ── ③ 走到锁口前按 R：开始读条，人不能动 ──
	# 锁口在 (760,178)，和东门同一个位置（锁孔本来就在门板上）。
	# 站 810 = 门右边（三层自测用的同一个安全位），感应区一定够得着锁口。
	s.global_position = Vector2(810, 178)
	await _wait(0.45)
	_记("③ 感应区里有锁口", _感应区里有(s, "keyhole"))
	await _tap("insert_key")
	await _wait(0.1)
	_记("③ 锁口开始读了", 锁口._进行中)
	_记("③ 人被钉住了", s.被钉住)

	# 读条中按右方向键：不该挪一步
	var 插前x: float = s.global_position.x
	Input.action_press("right")
	await _wait(0.35)
	Input.action_release("right")
	_记("③ 读条中按右也不走（位移 %.0f）" % (s.global_position.x - 插前x),
		absf(s.global_position.x - 插前x) < 1.0)

	# ── ④ 2 秒到：孔亮、手空、板子从世界里消失 ──
	await _wait(1.8)
	_记("④ 一号孔亮了", bool(锁口._孔["一号"]["亮"]))
	_记("④ 手上空了", s._carry_state == s.CarryState.EMPTY)
	_记("④ 板子没掉在地上", not is_instance_valid(一号))
	_记("④ 人松开了", not s.被钉住)
	_记("④ 计到 1 块", 锁口.已插数() == 1)

	# ── ⑤ 空手按 R：什么都不该发生（玩家最常做错的事）──
	await _tap("insert_key")
	await _wait(0.1)
	_记("⑤ 空手按 R 不开始读条", not 锁口._进行中)

	# ── ⑥ 拿错的那块插不进去，而且不消耗 ──
	# 三号孔先手动标成「已插」，模拟"这块的孔已经满了"。
	# （偷看内部状态，但这里验的正是「重复的牌子不消耗」这条规则）
	s.global_position = Vector2(1400, 178)
	await _wait(0.45)
	await _tap("interaction")
	await _wait(0.2)
	_记("⑥ 三号扛起来了", s._carry_state == s.CarryState.CARRYING)

	锁口._孔["三号"]["亮"] = true
	s.global_position = Vector2(810, 178)
	await _wait(0.45)
	await _tap("insert_key")
	await _wait(0.15)
	_记("⑥ 孔已满时插不进去", not 锁口._进行中)
	_记("⑥ 板子还在手上（没白扣）", s._carry_state == s.CarryState.CARRYING)
	_记("⑥ 人没被钉住", not s.被钉住)
	锁口._孔["三号"]["亮"] = false   # 恢复现场

	# ── ⑦ 把二号、三号依次插上 ──
	await _tap("insert_key")
	await _wait(2.3)
	_记("⑦ 三号插上了", bool(锁口._孔["三号"]["亮"]))
	_记("⑦ 计到 2 块", 锁口.已插数() == 2)

	s.global_position = Vector2(540, 178)
	await _wait(0.45)
	await _tap("interaction")
	await _wait(0.2)
	_记("⑦ 二号扛起来了", s._carry_state == s.CarryState.CARRYING)

	s.global_position = Vector2(810, 178)
	await _wait(0.45)
	await _tap("insert_key")
	await _wait(2.3)

	# ── ⑧ 三块插满 → 锁口上报 → 代理开门 ──
	_记("⑧ 三块都插上了", 锁口.已插数() == 3)
	_记("⑧ 门被解锁（整扇全开）", 东门._amount >= 0.99)
	_记("⑧ 门现在不挡路", 东门._blocker.disabled)

	# ── ⑨ 门被真正解锁后，求生者一碰到判定区就算赢 ──
	# 判定区整块摆在门外侧（门线 760 往右 120px = 760~880）。
	# 插第三块钥匙时 s 正站在 810 交互位上 —— 人在判定区里，
	# 门一真正解锁、判定区一激活，他当场就赢，这正是「碰到即赢」。
	var 出口: Node = Director.thing("1-门厅出口")
	_记("⑨ 出口建出来了", 出口 != null)
	if 出口 != null:
		var 提示: Label = 出口.get_node("HUD/提示")
		_记("⑨ 解锁记进了账本", Match.is_door_unlocked("1-走廊东"))
		_记("⑨ 出口认到了自己等的门（已启用）", 出口._启用中)
		_记("⑨ 人在判定区里，解锁当场就赢", Match.escaped.size() == 1 and s._机器.当前() == 状态名.已逃出)
		_记("⑨ 赢家横幅弹出来了", 提示.visible)

		# s2 接力做边界验证：他还没碰到判定区，一次都不该赢
		s2.global_position = Vector2(950, 178)   # 判定区外（区在 760~880）
		await _wait(0.4)
		_记("⑨ 没碰到判定区不算", Match.escaped.size() == 1)

		s2.global_position = Vector2(740, 178)   # 门内侧：贴线站也不算
		await _wait(0.4)
		_记("⑨ 站在门内侧不算（判定区整块在门外）", Match.escaped.size() == 1)

		# ── ⑩ 把队友扔进判定区也算他赢 ──
		# s2 血量清零 = 瘫着（和被宿管打空两格血是同一个状态，不按 H 不会自己起来）：
		# 瘫着躺在判定区里同样算「求生者碰到」—— 等于被队友拖出门扔进去
		s2.血量 = 0
		await _wait(0.2)                        # 等状态机抢占进「瘫痪」
		s2.global_position = Vector2(790, 178)  # 碰到门外判定区：一碰到就算赢
		await _wait(0.5)
		_记("⑩ 瘫着的队友躺在判定区里也赢（被扔/拖进去）", Match.escaped.size() == 2)
		_记("⑩ 瘫着赢也进「已逃出」", s2._机器.当前() == 状态名.已逃出)
		_记("⑨ 同一个人不会被记第二次", Match.escaped.count(s) == 1 and Match.escaped.count(s2) == 1)
		_记("⑨ 出口没停摆，还在等下一个人", 出口._启用中)

		# ── ⑨b 一张图可以不止一个出口：西边还挂着一个等「1-走廊西」的 ──
		var 西出口: Node = Director.thing("1-西走廊出口")
		_记("⑨b 第二个出口建出来了（多出口不写死）", 西出口 != null)
		_记("⑨b 它等的门没真解锁，全程没激活", 西出口 != null and not 西出口._启用中)

	_收尾()


## 角色感应区里现在有没有"某个组"的东西（测试在偷看，正式代码里角色不看）
func _感应区里有(角色: Node, 组名: String) -> bool:
	for area in 角色.get_node("PickupZone").get_overlapping_areas():
		if area.is_in_group(组名):
			return true
	return false


func _记(项: String, 通过: bool) -> void:
	r[项] = "✅" if 通过 else "❌"
	if 通过:
		通过数 += 1
	else:
		失败数 += 1


func _收尾() -> void:
	print("=== 钥匙板 · 锁口自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	print("=== 通过 %d 项 / 失败 %d 项 ===" % [通过数, 失败数])
	get_tree().quit(0 if 失败数 == 0 else 1)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _tap(动作: String) -> void:
	Input.action_press(动作)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(动作)
	await _wait(0.1)
