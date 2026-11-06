extends Node
## 场景总管 —— 你那份《游戏流程》里写的「总体的全部管线（负责处理各个系统的信号）」
##
## 它自己不做任何事，只干三件：
##   1. 登记：一件东西出生就来报个到，记下它的编号（register_thing）
##   2. 上报：谁碰上什么事，跟总管说一句（交互 / report）
##   3. 转发：按编号把话递给那件东西自己办（被按键 / on_report）
##
## 这样做的好处：学生不用知道门在哪、灯在哪、图上有几层。
## 学生只管喊「我碰到了编号 X」，由总管把话递过去。

## 门被按了。编号=哪扇门，by=谁按的
## 这个信号本文件自己不 emit，是留给门（以后的灯、柜子）向全工程喊话的。
## 所以加下面那行，告诉编辑器「它没人用是正常的，别报红黄」。
@warning_ignore("unused_signal")
signal door_pressed(编号: String, by: Node)

## 门开完了或关完了。is_open=true 表示现在敞开着
@warning_ignore("unused_signal")
signal door_finished(编号: String, is_open: bool)

# ============================================================
# 编号账本（2026-11-06 按编号重构）
# ------------------------------------------------------------
# 全工程只有这一本账：**编号 → 节点**。
# 谁想找哪件东西，拿编号来问；谁想让哪件东西办事，拿编号来递话。
#
# 【为什么不再按楼层】原来这里记的是「四楼 → 代理」，人按键前先要问
#   「我在第几层」，而层是块会变的：地图一改高度，四层的层带全要重算，
#   算错就静默把人判到隔壁层。按编号以后这个问题根本不用问 ——
#   人只报「我碰到了编号 X」。
# ============================================================

## 编号 -> 节点
var _things: Dictionary = {}


## 一件东西出生时报到。**编号不许空、不许重**：
##   空编号 → 它这辈子谁都找不到它，等于白摆；
##   重编号 → 后来的顶掉前面的，被顶掉的那件静默失联，最难查。
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


## 角色按键时走这里。传进来的是**感应区**（一堆 Area2D），不是编号 ——
## 编号由这里解析，所以学生和宿管两边的写法完全一样，谁都不用认识类型。
##
## 流程：感应区 → 往上找带编号的那件东西 → 去重 → 按「谁优先」排序
##      → 一件一件问「这键归你吗」，第一件认了的就到此为止。
## 一次按键只办一件事：不然站在箱子旁边按 F 会连道具一起收走。
##
## 【为什么解析放在这里】以前这份逻辑在学生脚本里，宿管要照抄一遍，
##   两个角色的行为早晚会漂（一边认箱子、一边不认）。总管本来就要拿编号查账，
##   顺手在这儿做完最合适：加一个角色，按键只写一行。
func 交互(谁: Node, 键: String, 区们: Array) -> bool:
	for 号 in _编号们(区们):
		var 物: Node = thing(号)
		if 物 == null:
			continue
		if 物.has_method("被按键") and 物.被按键(键, 谁):
			return true
	return false


## 感应区 → 编号列表（去重，按互动优先级从高到低）
##
## 【为什么要往上找】门的感应区是挂在门身上的一块子 Area2D，编号盖在门本体上；
##   箱子/道具本身就是 Area2D，一眼就是它自己。统一成「从这块区往上走，
##   第一件报了编号的就是它」——两种都能认。
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
##
## 【为什么要有返回值】true = 找到了、话递到了；false = 没这件东西。
##   角色不需要靠它做判断，但「递没递到」必须问得出来 —— 不然出 bug 只能靠猜。
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
