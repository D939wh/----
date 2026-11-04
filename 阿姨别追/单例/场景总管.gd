extends Node
## 场景总管 —— 你那份《游戏流程》里写的「总体的全部管线（负责处理各个系统的信号）」
##
## 它自己不做任何事，只干三件：
##   1. 登记：楼层出生时来报个到（register_floor）
##   2. 上报：谁碰上什么事，跟总管说一句（report）
##   3. 转发：总管把话递给对应楼层的代理（on_report）
##
## 这样做的好处：学生不用知道门在哪、灯在哪、这楼有几层。
## 学生只管喊「我碰了东西」，由总管去找该负责的那一层。

## 门被按了。floor_id=哪层，door_id=哪扇，by=谁按的
## 这个信号本文件自己不 emit，是留给门（以后的灯、柜子）向全工程喊话的。
## 所以加下面那行，告诉编辑器「它没人用是正常的，别报红黄」。
@warning_ignore("unused_signal")
signal door_pressed(floor_id: String, door_id: String, by: Node)

## 门开完了或关完了。is_open=true 表示现在敞开着
@warning_ignore("unused_signal")
signal door_finished(floor_id: String, door_id: String, is_open: bool)

## 楼层号 -> 代理节点
var _floors: Dictionary = {}


## 楼层出生时来报到。同名楼层重复报到会报警（说明有两层撞了名字）
func register_floor(floor_id: String, agent: Node) -> void:
	if _floors.has(floor_id):
		push_warning("[总管] 楼层重名，后来的会顶掉前面的：" + floor_id)
	_floors[floor_id] = agent
	print("[总管] 楼层登记：%s（现在共 %d 层）" % [floor_id, _floors.size()])


## 拿某一层的代理。没有就返回 null
func get_floor(floor_id: String) -> Node:
	return _floors.get(floor_id, null)


## 上报一件事。event 是事情的名字，data 是附带的数据
## 例：Director.report("一楼", "interact", {"谁": self, "键": "open_door", "碰到": [...]})
##
## 【为什么要有返回值】（2026-11-04 加）
##   这个函数现在会回答一句「递到了没有」：true = 这一层登记过、话已经交给代理；
##   false = 压根没这一层，话递不出去。
##   角色不需要靠这个返回值做判断（它报完就不管了，现在也确实是忽略返回值的），
##   但「递没递到」必须能问得出来——不然出了 bug 只能靠猜。
##   以后要加提示音、要在联机里做「这层没人」的兜底，都从这里接。
func report(floor_id: String, event: String, data: Dictionary = {}) -> bool:
	var agent: Node = _floors.get(floor_id, null)
	if agent == null:
		push_warning("[总管] 没登记过这一层，话递不到：" + floor_id)
		return false
	agent.on_report(event, data)
	return true


## 给学生之类的角色用：我在哪个楼层？
## 先按 y 坐标粗判——W2 只有一层，先返回唯一那层
func floor_of(_node: Node) -> String:
	if _floors.size() == 1:
		return _floors.keys()[0]
	return ""


## 调试用：把当前登记了哪几层打出来
func dump() -> void:
	print("[总管] 当前楼层表：", _floors.keys())


# ============================================================
# 控制权（开发者模式用，2026-11-03 加）
# ------------------------------------------------------------
# 现在玩家手里操作的是谁。按 F1 在学生和宿管之间来回换。
#
# 这里只管一件事：「谁吃键盘」。镜头也跟着换。
# 以后宿管交给 AI 的时候，改的是「谁在替她按键」，这个接口不用动。
# ============================================================

## 当前被玩家控制的角色（null = 还没人报到）
var 当前控制: Node = null

## 换人了。调试面板听到这个信号就刷新显示
signal control_changed(who: Node)

## 所有能控制的角色，按出场顺序存着（学生先报到，所以是第 0 个）
var _controllables: Array[Node] = []


## 角色出生时自己来报到（在 _ready 里喊一句就行）
func register_controllable(who: Node) -> void:
	if who in _controllables:
		return
	_controllables.append(who)
	if 当前控制 == null:
		当前控制 = who
	# 每来一个都重设一遍镜头：保证「只有当前控制的那个人」的相机是开的。
	# 不然新出生的人会带着自己的相机一起开着，两个人抢镜头。
	_相机交给(当前控制)
	control_changed.emit(当前控制)
	print("[总管] 可控制角色报到：%s（现在共 %d 个）" % [who.name, _controllables.size()])


## 按 F1 调这个：换到下一个角色，转一圈回到第一个
func switch_control() -> void:
	if _controllables.size() < 2:
		print("[总管] 现在只有一个可控制角色，没得换")
		return
	var 旧的: Node = 当前控制
	var i := _controllables.find(当前控制)
	当前控制 = _controllables[(i + 1) % _controllables.size()]
	# 把旧角色身上的速度清干净：不然切走之后她还会顺着惯性滑一段，
	# 调试时容易看成「她怎么自己动了」。
	if 旧的 != null and 旧的 is CharacterBody2D:
		旧的.velocity = Vector2.ZERO
	_相机交给(当前控制)
	control_changed.emit(当前控制)
	print("[总管] 换人 —— 现在控制：%s" % 当前控制.name)


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
