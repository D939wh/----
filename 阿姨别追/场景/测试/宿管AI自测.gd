extends Node
## 宿管 AI 自测：验证「没人按键时会自己动、会追人」，以及「按了键还是原来那套」。
## 用法：Godot --headless 场景/测试/宿管AI自测.tscn
##
## 用「实例化真场景 + 正常游戏循环」而不是 --script：autoload（Director）要活着，
## 因为 `_受控()` 判的是 `Director.当前控制`。

var r := {}
var k: CharacterBody2D
var s: CharacterBody2D
var s2: CharacterBody2D

## F 组收到的宿管脚步事件：{t: 毫秒, 半径, 来源}
var _脚步: Array = []


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景3.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	s = scene.get_node("student")
	s2 = scene.get_node("student2")
	# 主场景3 从 11-12 17:20 起**不再预摆宿管**（阿姨改成剧情触发时才召唤）。
	# 本测专测她的 AI，那就自己造一只，位置沿用原来那只 (900, 320)。
	var 宿管场景: PackedScene = load("res://角色/宿管/宿管.tscn")
	k = 宿管场景.instantiate()
	scene.add_child(k)

	# 主场景3 里 11-12 新加了一块「剧情判定区」（踩中就召唤一只阿姨）。
	# 本测只管宿管 AI，多出来一只阿姨会把「场上就她一个」的读数搅乱 —— 直接标成已触发，等于关掉。
	var 判定区 := Director.thing("剧情-一楼走廊")
	if 判定区 != null:
		判定区.已触发 = true

	# ── A. 有人按键时：她必须交给手控，姿态与原来一致 ──
	Director.set_control(k)
	k.global_position = Vector2(900, 320)
	await _wait(0.3)
	r["A1 控制权给宿管后状态"] = k._机器.当前() + "（应 手控）"

	# 按住右方向键 0.4 秒，她应该往右走（原 if 链的走速 370）
	Input.action_press("right")
	await _wait(0.4)
	Input.action_release("right")
	r["A2 按右键后走了"] = "%.0f px（应 > 60）" % (k.global_position.x - 900.0)
	await _wait(0.2)

	# ── B. 学生离开察觉圈 → AI 接管，进待机或巡逻，自己会动 ──
	Director.set_control(s)          # 控制权交给学生，宿管没人按了
	s.global_position = Vector2(200, 320)
	s2.global_position = Vector2(220, 320)
	k.global_position = Vector2(900, 320)
	await _wait(0.5)
	var 起始横: float = k.global_position.x
	await _wait(2.6)                 # 待机最长 2 秒，之后必须起身巡逻
	r["B1 没人按时状态"] = k._机器.当前() + "（应 巡逻 或 待机）"
	r["B2 她有没有自己动"] = "%.0f px（应 > 0）" % absf(k.global_position.x - 起始横)
	r["B3 有没有拿到目标"] = str(k._看得见的目标())
	r["B4 她还在楼板上"] = str(k.is_on_floor())

	# ── C. 学生走进察觉圈 → 必须切追击并朝学生靠拢 ──
	k.global_position = Vector2(900, 320)
	s.global_position = Vector2(620, 320)    # 距离 280 < 察觉半径 360
	s2.global_position = Vector2(200, 320)   # 另一个学生远在圈外
	await _wait(0.4)
	r["C1 学生进圈后状态"] = k._机器.当前() + "（应 追击）"
	var 追前: float = absf(k.global_position.x - s.global_position.x)
	await _wait(0.6)
	var 追后: float = absf(k.global_position.x - s.global_position.x)
	r["C2 距离有没有缩短"] = "%.0f → %.0f（应变小）" % [追前, 追后]
	r["C3 追击用的是追击速度"] = "%.0f" % k.追击速度

	# ── D. 学生跑出圈 → 必须脱战（回待机 / 巡逻）──
	# 注意：场上还有 student2，必须两个人一起挪远，否则她追的还是 student2
	s.global_position = Vector2(100, 320)
	s2.global_position = Vector2(-900, 320)
	await _wait(0.6)
	r["D1 目标跑掉后状态"] = k._机器.当前() + "（应 待机 或 巡逻）"
	r["D2 目标已丢失"] = str(k._看得见的目标())

	# ── E. 贴身：够得着就挥（11-09 打人重做 + 击退之后的基线）──
	# 旧文案是「这轮不撞人、不打人」，那已经过期了：现在贴到 `挥击距离`（60）
	# 就会进 攻击 状态抬手，打中还会把人推开 —— 这三条跟着改。
	k.global_position = Vector2(700, 320)
	s.global_position = Vector2(720, 320)    # 差 20 < 挥击距离 60
	await _wait(0.5)
	r["E1 贴身时状态"] = k._机器.当前() + "（应 攻击）"
	var 贴前: float = absf(k.global_position.x - s.global_position.x)
	await _wait(0.5)
	var 贴后: float = absf(k.global_position.x - s.global_position.x)
	r["E2 打中把人推开了"] = "%.0f → %.0f（应变大：击退 ≈68）" % [贴前, 贴后]
	r["E3 学生掉了一格"] = "%d（应 1：两格血挨了一棍）" % s.血量

	# ── F. 走路出声 + 自听排除（2026-11-10 加）──
	# 她自己迈步也会响：快走（370）= 2 档每 0.3s 一脚，巡逻（222）= 1 档每 0.5s 一脚；
	# 且自己的脚步不许进自己的耳朵，不然每一步都把自己钩进「搜索」。
	# 直接连 Events.noise_made 数事件，不靠日志 —— 和声音自测一个套路。
	s.global_position = Vector2(-1500, 320)    # 两个学生挪出戏：别被她看见，也别发别的声
	s2.global_position = Vector2(-1800, 320)
	Events.noise_made.connect(_记脚步)
	k.global_position = Vector2(1100, 320)
	Director.set_control(k)
	await _wait(0.3)
	k._脚步计时 = 0.0

	# F1 手控快走 370 → 稳定期每 0.3s 一脚 2 档（先清耳朵：走完看有没有被自己弄脏）
	# 起步头几帧速度还没爬过判定线，第一脚会按慢走档发 —— 属「档位随速度线切换」
	# 的正常现象（规格里写明），所以档位断言看末脚（稳定期），不看首脚。
	k._听觉目标 = Vector2.ZERO
	k._听觉音量 = 0.0
	k._听觉剩余 = 0.0
	_脚步.clear()
	Input.action_press("left")
	await _wait(1.4)
	Input.action_release("left")
	await _wait(0.2)
	r["F1 快走步频档位"] = "1.4s 内 %d 脚（应 4~6）/ 末脚半径 %.0f（应 400）/ 来源 %d（应 1=跑动）/ 中位间隔 %.0f ms（应 ≈300）/ 间隔 %s" % [
		_脚步.size(), _末半径(), _末来源(), _中位间隔(), str(_相邻间隔())]
	r["F1b 自己脚步没进耳朵"] = "听觉剩余 %.1f / 音量 %.2f（都应 0：手控照听，但脚下那声被切掉）" % [
		k._听觉剩余, k._听觉音量]

	# F2 站定不发声
	_脚步.clear()
	await _wait(0.8)
	r["F2 站定不发声"] = "静立 0.8s %d 脚（应 0）" % _脚步.size()

	# F3 空中不发声：抛到半空自由落体，这段里脚不沾地
	_脚步.clear()
	k.global_position.y -= 120.0
	await _wait(0.35)
	r["F3 空中不发声"] = "空中 0.35s %d 脚（应 0）/ 在空中 %s（应 True）" % [
		_脚步.size(), not k.is_on_floor()]
	await _wait(0.4)     # 等她落地站稳，别把落地帧漏给下一组

	# F4 AI 巡逻 222 → 每 0.5s 一脚 1 档；走几秒也不被自己钩进搜索
	Director.set_control(s)
	await _wait(2.6)     # 待机最长 2s，此刻必已起身巡逻
	_脚步.clear()
	k._听觉目标 = Vector2.ZERO
	k._听觉音量 = 0.0
	k._听觉剩余 = 0.0
	await _wait(2.2)
	r["F4 巡逻步频档位"] = "2.2s 内 %d 脚（应 3~6）/ 末脚半径 %.0f（应 200）/ 来源 %d（应 0=脚步）/ 中位间隔 %.0f ms（应 ≈500）/ 间隔 %s" % [
		_脚步.size(), _末半径(), _末来源(), _中位间隔(), str(_相邻间隔())]
	r["F4b 不被自己钩进搜索"] = "状态 %s（应 巡逻）/ 听觉剩余 %.1f / 音量 %.2f（都应 0）" % [
		k._机器.当前(), k._听觉剩余, k._听觉音量]

	print("=== 宿管 AI 自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


## F 组用：收到一声就记一笔（毫秒时间戳 + 半径 + 来源）。
## 只认宿管脚下 100px 内的事 —— 学生都挪到 1500px 外了，按位置区分人。
func _记脚步(位置: Vector2, 半径: float, 来源: int) -> void:
	if absf(位置.x - k.global_position.x) < 100.0 and absf(位置.y - k.global_position.y) < 100.0:
		_脚步.append({"t": Time.get_ticks_msec(), "半径": 半径, "来源": 来源})


func _末半径() -> float:
	return _脚步.back()["半径"] if not _脚步.is_empty() else -1.0


func _末来源() -> int:
	return _脚步.back()["来源"] if not _脚步.is_empty() else -1


## 相邻两脚的间隔（毫秒），升序排好。
## 掉头瞬间 vx 过 0 会触发「脚停重计」，紧跟一脚稀疏的密脚 ——
## 所以步频断言用中位数（扛得住个别密脚），不用 min/max。
func _相邻间隔() -> Array:
	var out: Array = []
	for i in range(1, _脚步.size()):
		out.append(int(_脚步[i]["t"]) - int(_脚步[i - 1]["t"]))
	out.sort()
	return out


func _中位间隔() -> float:
	var v := _相邻间隔()
	if v.is_empty():
		return -1.0
	return float(v[v.size() / 2])


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
