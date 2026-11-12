@tool
extends Area2D
## 判定区 —— 一块**隐形**的矩形，只干一件事：谁踩进来了，把我身上的「路由名」报出去。
##
## 【它认识什么】只有一个路由名（`route`，中文别名 `路由`）和一个触发者组。
##   它不知道路由的那头要演什么，也不知道会生出谁来 —— 那些都在剧情表里。
##   所以同一块判定区，想改成「进门关灯」「走到这里掉个箱子」，只改剧情表，这里一个字不动。
##
## 【为什么是 @tool】子节点「框」只在**编辑器 2D 视图**里看得见，靠 `Engine.is_editor_hint()`
##   判断。不加 @tool 的话 `_ready` 在编辑器里根本不跑，框的显隐就没人管。
##   @tool 下必须守住一条：**编辑器里只负责「看得见」，不登记、不接信号、不跑逻辑**（见 `_ready`）。
##
## 【碰撞】它自己不挡路：`collision_layer = 0`（谁都感应不到它），只开 `monitoring` 去认人。
##   认谁由 `触发者组` 决定，默认 "student"（学生 `_ready` 里自带这个组）。

const 规则 := preload("res://数据/通用规则.gd")

## 默认尺寸（像素）。清单里不写「宽 / 高」时用它。
const 默认宽: float = 48.0
const 默认高: float = 56.0

## 这个判定区的身份证（"剧情-走廊" 这种）。由物件代理照清单盖章，或在检查器里手填。
## 必须用英文名导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""
## 路由名：剧情表里那一条的键。空着 = 踩了也不知道找谁，`_ready` 会报错。
@export var route_name: String = ""
## 只有这个组里的角色踩进来才触发。默认只认学生（追捕者、箱子、被扔的队友都不算）。
@export var 触发者组: String = "student"
## 只演一次？true = 演过就不再演（默认）；false = 每次进来都演（循环戏用）。
@export var 只触发一次: bool = true

## 中文别名：全工程代码统一用「编号」读写
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

## 中文别名：路有名
var 路由: String:
	get:
		return route_name
	set(值):
		route_name = 值

## 已经演过了吗（只触发一次时用）
var 已触发: bool = false

## 子节点「框」：只有编辑器里露脸的那个色块
@onready var _框: Node2D = $框

## 编辑器里上一次画过的尺寸。用来判断「形状被拖过了吗」，没变就不重画
## —— 每帧都改 polygon 会让场景一直显示成「已修改」。
var _上次框尺寸: Vector2 = Vector2.ZERO


func _ready() -> void:
	# 编辑器里：框亮出来好摆位置，其余一概不做
	if _框 != null:
		_框.visible = Engine.is_editor_hint()
	if Engine.is_editor_hint():
		_跟一次尺寸()      # 让框和场景里存着的 shape 尺寸对上
		return
	set_process(false)     # 运行时不需要 `_process`，那是编辑器专用的

	# 运行时：自己绝不挡路，也不被别人感应到
	collision_layer = 0
	# 认两层：站着的人（地板层）+ 瘫着爬进来的人（瘫痪层）。
	# 只认地板层的话，两格血被打空、蹭着爬进判定区的玩家不会触发 —— 那也算「进来了」。
	collision_mask = 规则.层_地板 | 规则.层_瘫痪
	monitorable = false
	body_entered.connect(_有人进来)
	# 进组：调位置时想「把所有判定区一起显示出来」就一行
	#   get_tree().call_group("判定区", "显示调试框", true)
	add_to_group("判定区")

	# 编号是**可选的**：这块判定区不需要被人按名字找（Director.thing("xxx")）时，
	# 留空就行 —— 复制十几块出来各走各的戏，是这块积木最正常的用法。
	# 只有「别处要按编号找到它」时才填，那时才登记。
	if 编号.strip_edges() != "":
		Director.register_thing(编号, self)
	# 「路由」不能在这里查：物件代理是 add_child → 再 setup()，这一刻还是空的。
	# 延到本帧末尾再验，那时 setup 已经跑完。
	_校验路由.call_deferred()


## 由物件代理照清单调用。**「位置」= 这块区域的正中心**（不是底边，和梯子一样）。
## 门 / 锁口 / 出口填的是「贴地那条线」，别混。
##
## **不改节点名**：这块积木是可复用的，名字不该带某出戏的名字（曾经拼成
## `判定区_走廊召唤阿姨`，结果同一个路由摆两块就重名）。要认哪块，靠 `编号`
## 或它在场景树里的位置，不靠名字。
func setup(位置: Vector2, 宽: float, 高: float, 新路由: String, 一次性: bool = true) -> void:
	position = 位置
	route_name = 新路由
	只触发一次 = 一次性
	_改大小(宽, 高)


## 改尺寸：形状和那个色块一起改。
## **必须新建 RectangleShape2D**：`.tscn` 里的是 sub_resource，所有实例共用一份，
## 直接改 size 会让场上每块判定区一起变（梯子那里踩过同样的坑）。
func _改大小(宽: float, 高: float) -> void:
	var 形 := RectangleShape2D.new()
	形.size = Vector2(宽, 高)
	var 形状节点 := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if 形状节点 != null:
		形状节点.shape = 形
	_画框(宽, 高)


## 把编辑器里看的那个框画成 宽 × 高 的矩形（半透明填充 + 一圈实线）
func _画框(宽: float, 高: float) -> void:
	var 半边 := Vector2(宽, 高) * 0.5
	var 四角 := PackedVector2Array([
		Vector2(-半边.x, -半边.y),
		Vector2(半边.x, -半边.y),
		Vector2(半边.x, 半边.y),
		Vector2(-半边.x, 半边.y),
	])
	var 面 := get_node_or_null("框/面") as Polygon2D
	if 面 != null:
		面.polygon = 四角
	var 线 := get_node_or_null("框/线") as Line2D
	if 线 != null:
		var 闭合 := 四角.duplicate()
		闭合.append(四角[0])       # 首尾相连才有「一整圈」的样子
		线.points = 闭合


## 编辑器专用：让粉色框跟上 `CollisionShape2D` 的尺寸。
## 为什么要每帧看 —— 在编辑器里拖形状的 size 没有任何信号能接，只能比一次。
## 尺寸没变就立刻 return，不会把场景一直标成「已修改」。
func _process(_帧: float) -> void:
	if not Engine.is_editor_hint():
		return
	_跟一次尺寸()


func _跟一次尺寸() -> void:
	var 形状节点 := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if 形状节点 == null or not (形状节点.shape is RectangleShape2D):
		return
	var 尺寸: Vector2 = 形状节点.shape.size
	if 尺寸 == _上次框尺寸:
		return
	_上次框尺寸 = 尺寸
	_画框(尺寸.x, 尺寸.y)


## 运行时临时把框显示出来（排查用）。正常情况下游戏里永远看不到它。
func 显示调试框(开: bool) -> void:
	if _框 != null:
		_框.visible = 开


## 有人踩进来了。只做三件事：筛人（是不是玩家）、筛次数、把路由报给剧情。
func _有人进来(body: Node) -> void:
	if 只触发一次 and 已触发:
		return
	if 触发者组 != "" and not body.is_in_group(触发者组):
		return                # 不是玩家组的东西踩进来都不算（追捕者、箱子、被扔出去的队友）
	已触发 = true
	print("[判定区] %s 踩中 → 路由「%s」" % [body.name, 路由])
	# **一定要延后一帧再演**：`body_entered` 是在物理查询刷新过程中回调的，
	# 这时候往场景里 add_child 一个带碰撞体的角色，引擎会当场报
	# `Can't change this state while flushing queries`（而且生出来的东西碰撞是坏的）。
	_演出.call_deferred(body)


## 真正的「报给剧情」。延后一帧执行，见 `_有人进来` 里的说明。
func _演出(body: Node) -> void:
	Story.触发(路由, body)


## 延后校验：路由必须有。没写 = 这块判定区踩了也没人管，属于配置错误，当场报出来。
## 报错带上坐标 —— 判定区可以复制很多块、名字都一样，光看名字根本找不着是哪一块。
func _校验路由() -> void:
	if 路由.strip_edges() == "":
		push_error("[判定区] 有一块没填「路由」（位置 %s）—— 踩进去也找不到该演哪条剧情" % position)


## 复位：让这块判定区可以再演一次（自测 / 重开一局用）
func 复位() -> void:
	已触发 = false
