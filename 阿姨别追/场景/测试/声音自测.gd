extends Node
## 声音系统自测 —— 四档半径 → 距离衰减 → 学生真的发声 → 宿管听见后去搜索。
##
## 用法：Godot --headless 场景/测试/声音自测.tscn
## 全部结果靠打印（人读数字），不做自动断言 —— 和 `阿姨打人自测` 一个套路。
## 不依赖 `[声音]` 日志：直接连 `Events.noise_made`，收到什么就是什么。

const 声音表 := preload("res://数据/声音表.gd")
const 状态名 := preload("res://角色/宿管/状态/状态名.gd")

var r := {}
var s: CharacterBody2D
var k: CharacterBody2D
var _收到: Array = []      # 最近收到的发声事件：{位置, 半径, 来源}


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	s = scene.get_node("student")
	k = scene.get_node("keeper")
	scene.get_node("student2").global_position = Vector2(200, 208)   # 挪出戏：她会抢宿管的注意力
	Events.noise_made.connect(_记一笔)

	# ── 1. 表本身：四档半径 + 距离衰减 ──
	r["四档半径"] = "1档 %.0f / 2档 %.0f / 3档 %.0f / 4档 %.0f（应 200/400/600/900）" % [
		声音表.半径(声音表.档_很轻), 声音表.半径(声音表.档_较大),
		声音表.半径(声音表.档_很大), 声音表.半径(声音表.档_极大)]
	r["距离衰减"] = "3档@300px %.2f（应 0.50）/ 4档@900px %.2f（应 0.00）/ 4档@100px %.2f（应 0.89）" % [
		声音表.音量(300, 600), 声音表.音量(900, 900), 声音表.音量(100, 900)]

	# ── 2. 慢走 = 1 档，跑动 = 2 档 ──
	# 宿管先挪到走廊另一头：这一步只验「声音发没发出去」，别让她先听见。
	k.global_position = Vector2(1600, 208)
	s.global_position = Vector2(400, 208)
	Director.set_control(s)
	await _wait(0.3)

	_收到.clear()
	Input.action_press("sprint")     # Shift = 慢走
	Input.action_press("right")
	await _wait(1.0)
	Input.action_release("right")
	Input.action_release("sprint")
	await _wait(0.1)
	var 慢 := _最近()
	r["慢走"] = "1 秒发声 %d 次 / 半径 %.0f（应 200）/ 位置 y %.0f（贴地即可）" % [
		_收到.size(), 慢.get("半径", -1.0), 慢.get("位置", Vector2.ZERO).y]

	_收到.clear()
	Input.action_press("right")      # 不按 Shift = 常走 / 跑
	await _wait(1.0)
	Input.action_release("right")
	await _wait(0.1)
	var 跑 := _最近()
	r["跑动"] = "1 秒发声 %d 次 / 半径 %.0f（应 400）/ 比慢走密=%s" % [
		_收到.size(), 跑.get("半径", -1.0), _收到.size() >= 3]

	_收到.clear()
	await _wait(1.0)                 # 站着不动
	r["站着不发声"] = "静立 1 秒发声 %d 次（应 0）" % _收到.size()

	# ── 3. 丢下东西 = 3 档 ──
	# 主场景没有箱子，用「把队友撂下」走同一条 3 档线路（人砸地上一样响）。
	s.global_position = Vector2(700, 208)
	await _wait(0.2)
	var 队友: CharacterBody2D = s.duplicate()
	scene.add_child(队友)
	队友.global_position = Vector2(720, 208)
	Director.set_control(s)          # 复制品也会向总管报到，把控制权夺回来
	await _wait(0.2)
	s.扛起同学(队友)
	await _wait(0.2)
	_收到.clear()
	s.放下同学()
	await _wait(0.2)
	var 丢 := _最近()
	r["丢下东西"] = "发声 %d 次 / 半径 %.0f（应 600 = 3 档）" % [
		_收到.size(), 丢.get("半径", -1.0)]

	# ── 4. 开关门 = 4 档 ──
	var 门 = Director.thing("1-走廊东")
	_收到.clear()
	门.press(s)
	await _wait(1.4)                 # 推门要时间，声响在「门板走完」那一刻
	var 门次 := 0
	var 合闸次 := 0
	var 半径们 := {}
	for e in _收到:
		var 源: int = int(e["来源"])
		if 源 == 声音表.来源_门:
			门次 += 1
		elif 源 == 声音表.来源_合闸:
			合闸次 += 1
		半径们[e["半径"]] = true
	r["开关门 / 合闸"] = "门声 %d 次 / 合闸声 %d 次（这里只是推开，没解锁，出口不启用）/ 半径 %s（都应 900）" % [
		门次, 合闸次, str(半径们.keys())]

	# ── 5. 宿管听见 3 档 → 进「搜索」并朝声源走 ──
	# 距离 300 / 半径 600 → 音量 0.5，够响。
	# 距离要卡在「听得见（<510px）但看不见（>360px 察觉圈）」这段里：480。
	# 先把她按住：上一步开门那声巨响她还没忘，正在往门口走，
	# 不清理的话「设好 480」会被她自己的残余移动改掉。
	_静置()
	k.global_position = Vector2(1480, 208)
	s.global_position = Vector2(1000, 208)
	await _wait(0.3)
	Events.发声(s.global_position, 声音表.档_很大, 声音表.来源_丢物)
	await _wait(0.15)
	var 听见后 = k._机器.当前()
	var 起点x := k.global_position.x
	await _wait(0.6)
	r["听见去搜索"] = "音量记为 %.2f（应 0.20）/ 状态「%s」（应 搜索）/ 0.6 秒位移 %.0f（应朝左）" % [
		k._听觉音量, 听见后, k.global_position.x - 起点x]

	# ── 6. 太轻、又太远 → 听不见 ──
	_静置()
	k.global_position = Vector2(1400, 208)
	s.global_position = Vector2(1000, 208)    # 400px：看不见，也别让巡逻走乱距离
	await _wait(0.3)
	Events.发声(Vector2(1100, 208), 声音表.档_很轻, 声音表.来源_脚步)   # 300px > 200 半径
	await _wait(0.2)
	r["太轻听不见"] = "听觉剩余 %.1f（应 0.0）/ 状态「%s」" % [
		k._听觉剩余, k._机器.当前()]

	# ── 7. 看得见的时候，耳朵不抢方向盘 ──
	s.global_position = Vector2(1350, 208)     # 站在察觉圈（360）里
	await _wait(0.3)
	Events.发声(Vector2(800, 208), 声音表.档_极大, 声音表.来源_门)   # 远处门口一声巨响
	await _wait(0.3)
	r["眼睛压过耳朵"] = "状态「%s」（应 追击 / 攻击，不是 搜索）" % k._机器.当前()

	# ── 8. 搜完就忘：到地方张望完 → 回巡逻 ──
	s.global_position = Vector2(300, 208)      # 学生走出察觉圈
	_静置()
	k.global_position = Vector2(1400, 208)
	await _wait(0.3)
	var 脚边 := k.global_position + Vector2(100.0, 0.0)
	Events.发声(脚边, 声音表.档_很大, 声音表.来源_丢物)   # 100px 外：11-10 起宿管自听排除滤掉贴脚 <4px 的声
	await _wait(0.15)
	var 进搜索 = k._机器.当前()
	await _wait(2.4)                            # 张望 1.8 秒 + 余量
	r["搜索结束"] = "进「%s」→ 2.4 秒后「%s」（应 搜索 → 巡逻）" % [进搜索, k._机器.当前()]

	Director.set_control(s)
	print("=== 声音系统自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)


## 收到一次发声：记下来。日志里的 `[声音]` 也是从这条信号之后打的，两边对得上。
func _记一笔(位置: Vector2, 半径: float, 来源: int) -> void:
	# 宿管 11-10 起走路也出声了：她自己的脚步不该混进「学生发声」的账。
	# 她的脚步就发在自己 global_position 上，同帧回调时距离 ≈ 0 ——
	# 按宿管自听排除同一个 4px 口径，把她那份筛掉。
	if 位置.distance_to(k.global_position) < 4.0:
		return
	_收到.append({"位置": 位置, "半径": 半径, "来源": 来源})
	if _收到.size() > 60:
		_收到.pop_front()


## 把宿管按回「待机 + 什么都没听见」：测试里要精确控制距离，先让她别动。
func _静置() -> void:
	k._听觉剩余 = 0.0
	k._听觉音量 = 0.0
	k.velocity = Vector2.ZERO
	k._机器.切(状态名.待机)


func _最近() -> Dictionary:
	if _收到.is_empty():
		return {}
	return _收到.back()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
