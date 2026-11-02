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
signal door_pressed(floor_id: String, door_id: String, by: Node)

## 门开完了或关完了。is_open=true 表示现在敞开着
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
## 例：Director.report("一楼", "door_pressed", {"door_id": "1-走廊东", "by": self})
func report(floor_id: String, event: String, data: Dictionary = {}) -> void:
	var agent: Node = _floors.get(floor_id, null)
	if agent == null:
		push_warning("[总管] 没登记过这一层，话递不到：" + floor_id)
		return
	agent.on_report(event, data)


## 给学生之类的角色用：我在哪个楼层？
## 先按 y 坐标粗判——W2 只有一层，先返回唯一那层
func floor_of(_node: Node) -> String:
	if _floors.size() == 1:
		return _floors.keys()[0]
	return ""


## 调试用：把当前登记了哪几层打出来
func dump() -> void:
	print("[总管] 当前楼层表：", _floors.keys())
