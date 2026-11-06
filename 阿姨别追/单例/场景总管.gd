extends Node
## 场景总管 —— 全工程的中枢：登记物件编号、转发交互与上报。
## 只干三件：登记（register_thing）、上报（report）、按编号转发（交互）。

## 门被按了。编号=哪扇门，by=谁按的。由物件 emit，本文件不用，故忽略未使用警告
@warning_ignore("unused_signal")
signal door_pressed(编号: String, by: Node)

## 门开完了或关完了。is_open=true 表示现在敞开着
@warning_ignore("unused_signal")
signal door_finished(编号: String, is_open: bool)

# ============================================================
# 编号账本
# ------------------------------------------------------------
# 全工程只有这一本账：**编号 → 节点**。
# 谁想找哪件东西，拿编号来问；谁想让哪件东西办事，拿编号来递话。
# ============================================================

## 编号 -> 节点
var _things: Dictionary = {}


## 一件东西出生时报到。编号不许空、不许重（空=谁都找不到它，重=先登记的失联）
func register_thing(编号: String, 节点: Node) -> void:
	if 编号.strip_edges() == "":
		push_warning("[总管] 有东西没填编号，登记不上：%s（%s）" % [
			节点.name, 节点.get_script().resource_path if 节点.get_script() else "?"])
		return
	if _things.has(编号) and _things[编号] != 节点:
		push_warning("[总管] 编号重了：%s —— 后来的 %s 顶掉前面的 %s" % [
			编号, 节点.name, _things[编号].name])
	_things[编号] = 节点


## 按编号拿节点。没有就返回 null
func thing(编号: String) -> Node:
	return _things.get(编号.strip_edges(), null)


## 现在登记了多少件东西（调试/自测用）
func thing_count() -> int:
	return _things.size()


## 角色按键时走这里。传进来的是**感应区**（一堆 Area2D），编号由这里解析，
## 所以学生和宿管两边的写法完全一样。
## 流程：感应区 → 找编号 → 去重 → 按优先级排序 → 逐件问「这键归你吗」。
## 一次按键只办一件事：不然站在箱子旁边按 F 会连道具一起收走。
func 交互(谁: Node, 键: String, 区们: Array) -> bool:
	for 号 in _编号们(区们):
		var 物: Node = thing(号)
		if 物 == null:
			continue
		if 物.has_method("被按键") and 物.被按键(键, 谁):
			return true
	return false


## 感应区 → 编号列表（去重，按互动优先级从高到低）。
## 从感应区往上找第一件带编号的节点，门和箱子两种挂法都能认
func _编号们(区们: Array) -> Array:
	var 候选: Array = []
	for 区 in 区们:
		var 物: Node = _带编号的(区)
		if 物 == null:
			continue
		var 号 := str(物.get("编号"))
		if 号 == "" or 候选.any(func(项): return 项[1] == 号):
			continue    # 空编号 = 没盖章；同一件东西两块感应区只算一次
		候选.append([_优先级(物), 号])
	候选.sort_custom(func(a, b): return a[0] > b[0])
	var 结果: Array = []
	for 项 in 候选:
		结果.append(项[1])
	return 结果


func _带编号的(区: Node) -> Node:
	var 现在: Node = 区
	while 现在 != null:
		var 号 = 现在.get("编号")
		if 号 != null and str(号) != "":
			return 现在
		现在 = 现在.get_parent()
	return null


## 优先级：没写这一栏的当 0（门 / 锁口 / 道具都是 0，箱子是 10）
func _优先级(物: Node) -> int:
	var 值 = 物.get("互动优先级")
	return int(值) if 值 != null else 0


## 上报一件事给某一件东西（编号点名）。event 是事情的名字，data 是附带数据。
## 例：Director.report("1-门厅", "unlock", {"门": "1-走廊东"})
## 返回 true = 话递到了；false = 没这件东西。
func report(编号: String, event: String, data: Dictionary = {}) -> bool:
	var 物: Node = thing(编号)
	if 物 == null:
		push_warning("[总管] 没有这件东西，话递不到：" + str(编号))
		return false
	if 物.has_method("on_report"):
		物.on_report(event, data)
	return true


## 调试用：把当前登记了哪些编号打出来
func dump() -> void:
	print("[总管] 当前登记的物件：", _things.keys())


# ============================================================
# 控制权（开发者模式用）
# ------------------------------------------------------------
# 现在玩家手里操作的是谁。按 F1 在学生和宿管之间来回换。
# 这里只管「谁吃键盘」，镜头也跟着换。
# ============================================================

## 当前被玩家控制的角色（null = 还没人报到）
var 当前控制: Node = null

## 换人了。调试面板听到这个信号就刷新显示
signal control_changed(who: Node)

## 所有能控制的角色，按出场顺序存着
var _controllables: Array[Node] = []


## 角色出生时自己来报到（在 _ready 里喊一句就行）
func register_controllable(who: Node) -> void:
	if who in _controllables:
		return
	_controllables.append(who)
	if 当前控制 == null:
		当前控制 = who
	# 每来一个都重设一遍镜头：保证只有当前控制角色的相机开着，避免两人抢镜头。
	_相机交给(当前控制)
	control_changed.emit(当前控制)
	print("[总管] 可控制角色报到：%s（现在共 %d 个）" % [who.name, _controllables.size()])


## 按 F1 调这个：换到下一个角色，转一圈回到第一个（内部调 set_control）
func switch_control() -> void:
	_剔除失效()
	if _controllables.size() < 2:
		print("[总管] 现在只有一个可控制角色，没得换")
		return
	var i := _controllables.find(当前控制)
	set_control(_controllables[(i + 1) % _controllables.size()])


## 直接指定「现在控谁」。成功返回 true，这个人不在可控制名单里返回 false。
func set_control(who: Node) -> bool:
	_剔除失效()
	if who == null or not (who in _controllables):
		return false
	if who == 当前控制:
		return true
	var 旧的: Node = 当前控制
	# 把旧角色身上的速度清干净，避免切走后顺着惯性滑一段
	if 旧的 != null and is_instance_valid(旧的) and 旧的 is CharacterBody2D:
		旧的.velocity = Vector2.ZERO
	当前控制 = who
	_相机交给(当前控制)
	control_changed.emit(当前控制)
	print("[总管] 换人 —— 现在控制：%s" % 当前控制.name)
	return true


## 把已经被删掉的角色从名单里剔掉，避免留死节点导致换人时出错。
func _剔除失效() -> void:
	var 有效: Array[Node] = []
	for one in _controllables:
		if is_instance_valid(one):
			有效.append(one)
	if 有效.size() == _controllables.size():
		return
	_controllables = 有效
	if 当前控制 != null and not is_instance_valid(当前控制):
		当前控制 = _controllables[0] if _controllables.size() > 0 else null
		_相机交给(当前控制)
		control_changed.emit(当前控制)


## 把镜头交给它。每个角色自带一个相机，同一时刻只开一个
func _相机交给(who: Node) -> void:
	for one in _controllables:
		var 镜头 := one.get_node_or_null("Camera2D")
		if 镜头 != null:
			镜头.enabled = (one == who)
	if who == null:
		return
	var cam := who.get_node_or_null("Camera2D")
	if cam != null:
		cam.make_current()
