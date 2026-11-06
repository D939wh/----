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

## 楼层号 -> 层带 Vector2(上界 y, 下界 y)。判层用，代理登记时一起交上来
##   上界 = 这一层最高的地方（y 更小），下界 = 这一层最低的地方（y 更大）
##   为什么带在数据里、不在这里算：地图是手画的，层高不齐（160/192 都有），
##   脚本里写死任何一个数，改地图就得改代码 —— 这是铁律五的反面教材。
var _bands: Dictionary = {}


## 楼层出生时来报到。同名楼层重复报到会报警（说明有两层撞了名字）
##
## 【层带】（2026-11-06 加）不填 = 这一层占满全图（老的单层地图不用改）。
##   多层地图必须填：总管靠它回答「这个人在第几层」（floor_of）。
func register_floor(floor_id: String, agent: Node, 层带: Vector2 = Vector2(-1.0e12, 1.0e12)) -> void:
	if _floors.has(floor_id):
		push_warning("[总管] 楼层重名，后来的会顶掉前面的：" + floor_id)
	_floors[floor_id] = agent
	_bands[floor_id] = 层带
	print("[总管] 楼层登记：%s（层带 y %.0f..%.0f，现在共 %d 层）" % [
		floor_id, 层带.x, 层带.y, _floors.size()])


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
##
## 【2026-11-06 改】以前这里写的是「只有一层就先返回那一层」——多层时永远返回空串，
##   交互全都递不出去。现在按「层带」查：人在哪条带里，就是哪一层。
##
## 【为什么不是「按 y 找脚下最近的那条地面线」】
##   那张手绘地图每层由 3~4 段错开 16 像素的台阶拼成，层距 160~192 像素，
##   台阶和层距差一个数量级 —— 用「最近地面线」判，站在台阶上就会判到隔壁层去。
##   层带是**每层自己声明的范围**（数据），不是算出来的（猜测）。
##   地图以后怎么改，改的是清单里那两个数，这个函数一个字不用动。
##
## 【掉在两层之间的空中怎么办】
##   挑最近的那一层。宁可给一个「八成对」的答案，也不要返回空串让交互静默失败 ——
##   静默失败最难查。
func floor_of(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if _floors.size() == 1:
		return _floors.keys()[0]
	if not (node is Node2D):
		return ""

	var y: float = (node as Node2D).global_position.y

	# 1) 先找带：直接命中
	for id in _floors:
		var 带: Vector2 = _bands.get(id, Vector2(-1.0e12, 1.0e12))
		if y >= 带.x and y < 带.y:
			return id

	# 2) 不在任何带里（空中、或者地图外的坐标）：挑最近的那层
	var 最近 := ""
	var 最近距离 := INF
	for id in _floors:
		var 带: Vector2 = _bands.get(id, Vector2(-1.0e12, 1.0e12))
		var 距离 := 0.0
		if y < 带.x:
			距离 = 带.x - y
		elif y >= 带.y:
			距离 = y - 带.y
		if 距离 < 最近距离:
			最近距离 = 距离
			最近 = id
	return 最近


## 调试用：这一层登记的层带是多少
func band_of(floor_id: String) -> Vector2:
	return _bands.get(floor_id, Vector2(-1.0e12, 1.0e12))


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
## （2026-11-05 起它只是 set_control 的一个调用者，自己不再直接改 当前控制）
func switch_control() -> void:
	_剔除失效()
	if _controllables.size() < 2:
		print("[总管] 现在只有一个可控制角色，没得换")
		return
	var i := _controllables.find(当前控制)
	set_control(_controllables[(i + 1) % _controllables.size()])


## 直接指定「现在控谁」。成功返回 true，这个人不在可控制名单里返回 false。
##
## 【为什么要它】（2026-11-05 加）
##   F1 只能一个一个往下轮：场上两个人还行，人一多就要按好几次才轮到想看的那个。
##   开发者模式改成「鼠标点谁就控谁」之后，从这里一步到位。
##   点名这件事必须由总管做——它才是记着「谁可控制」的那本账，
##   面板只负责把「点了哪个坐标」翻译成人，不自己维护名单。
func set_control(who: Node) -> bool:
	_剔除失效()
	if who == null or not (who in _controllables):
		return false
	if who == 当前控制:
		return true
	var 旧的: Node = 当前控制
	# 把旧角色身上的速度清干净：不然切走之后她还会顺着惯性滑一段，
	# 调试时容易看成「她怎么自己动了」。
	if 旧的 != null and is_instance_valid(旧的) and 旧的 is CharacterBody2D:
		旧的.velocity = Vector2.ZERO
	当前控制 = who
	_相机交给(当前控制)
	control_changed.emit(当前控制)
	print("[总管] 换人 —— 现在控制：%s" % 当前控制.name)
	return true


## 把已经被删掉的角色从名单里剔掉。
## 不剔会怎样：测试里复制出来的临时学生 queue_free 之后，名单里还留着一个死节点，
## 下次换人时对着一具空壳调 get_node，当场崩（11-05 真的这么崩过一次）。
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
