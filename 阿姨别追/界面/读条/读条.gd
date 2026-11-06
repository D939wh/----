extends CanvasLayer
## ============================================================
# 通用读条 · 「还要按住多久」
# ------------------------------------------------------------
# 凡是要长按的东西，头上给一根条，条上写还剩几秒。
#
# 【它只负责显示，不负责计时】
# 进度真源在使用者那边，每帧把「已经按了多久」报进来，条只照这个数画。
#
# 【怎么用】
#   const 读条脚本 := preload("res://界面/读条/读条.gd")
#   var _读条: CanvasLayer = null
#
#   _读条 = 读条脚本.新建(self)          # 第一次要用时才建，挂到当前场景下
#   _读条.开始(self, "拉起队友", 4.0)     # 挂在自己头顶（也可以换成别人）
#   _读条.推进(_救人进度)                # 每帧把「已经按了多久」报上去
#   _读条.收()                           # 松手 / 中断 / 完成，一定记得收
#
# 自带一层 CanvasLayer：不受父节点位置和相机影响，坐标就是屏幕坐标。
## ============================================================

const 场景路径 := "res://界面/读条/读条.tscn"

const 条宽: float = 64.0        # 条的外框宽（屏幕像素，640×360 的坐标系）
const 条高: float = 6.0         # 条的外框高
const 描边: float = 1.0         # 填充比外框小一圈，才有「框住」的样子

var _跟谁: Node2D = null        # 这根条挂在谁头顶（null = 没在跟人）
var _要是跟人的: bool = false    # 这一次「说好了要跟一个人」吗？
## 「打算跟人」和「引用还活着」分开记：跟的人被 queue_free 后 _跟谁 会变成 null，
## 要和「这次本来就不跟人」区分开。
var _启用: bool = false          # 现在到底要不要显示
var _总时长: float = 1.0        # 这一次要按满几秒
var _已用: float = 0.0          # 已经按了几秒（由使用者每次报进来）
var _说明: String = ""          # 条上的字（"拉起队友" / "抓捕" / "" = 只显示秒数）
var _头顶偏移: float = -62.0    # 离脚底往上的距离（世界像素；学生高 44、宿管 48）

@onready var _框: Control = $框
@onready var _填充: ColorRect = $框/填充
@onready var _文字: Label = $框/文字


## 【建一根条】给谁用，就挂谁家（当前场景）下，跟着那个人一起消失。
## 不在 _ready 里建（current_scene 可能还是 null），第一次要用时才建。
static func 新建(使用者: Node) -> CanvasLayer:
	var 条: CanvasLayer = (load(场景路径) as PackedScene).instantiate()
	var 树 := 使用者.get_tree()
	var 挂点: Node = 树.current_scene if 树.current_scene != null else 树.root
	挂点.add_child(条)
	# 用的人没了，条跟着没 —— 不然删角色之后屏幕上会留一根不动的条
	if 使用者.is_inside_tree():
		使用者.tree_exiting.connect(func() -> void:
			if is_instance_valid(条):
				条.queue_free()
		)
	return 条


## 开始读条：跟谁、写什么字、总共几秒
## 跟谁 传 null = 不跟人，摆在屏幕下方正中（以后通关那种「全屏读条」用这个）
func 开始(跟谁: Node2D, 说明: String, 总时长: float, 头顶偏移: float = -62.0) -> void:
	_跟谁 = 跟谁
	_要是跟人的 = 跟谁 != null
	_说明 = 说明
	_总时长 = maxf(总时长, 0.001)   # 防零：除以 0 出来是 nan，条会瞬间乱跳
	_已用 = 0.0
	_头顶偏移 = 头顶偏移
	_启用 = true
	_框.visible = true
	_刷新()
	_跟位置()                      # 立刻摆好，别让它在 (0,0) 闪一帧


## 每帧报进度（已经按了几秒）。条不自己数秒，只照这个数画
func 推进(已用: float) -> void:
	if not _启用:
		return
	_已用 = 已用
	_刷新()


## 收起来：松手、中断、做完了都调它。可以放心重复调（已经在收着也不报错）
func 收() -> void:
	_启用 = false
	_要是跟人的 = false
	_跟谁 = null
	_已用 = 0.0
	if is_node_ready():
		_框.visible = false


## 现在看得见吗（给自测看的）
func 在显示中() -> bool:
	return is_node_ready() and _框.visible


func _process(_delta: float) -> void:
	if not is_node_ready() or not _启用:
		return
	# 说好了跟人，结果这个人被删了 / 被移出场景了 → 条自己收掉，
	# 不能挂在一个不存在的坐标上，也不能跑回屏幕中间当全屏读条
	if _要是跟人的 and (_跟谁 == null or not is_instance_valid(_跟谁)):
		收()
		return
	_跟位置()


## 把「已经按了几秒」画成条和字
func _刷新() -> void:
	var 比例 := clampf(_已用 / _总时长, 0.0, 1.0)
	_填充.size = Vector2(maxf(条宽 - 描边 * 2.0, 0.0) * 比例, 条高 - 描边 * 2.0)
	var 剩余 := maxf(_总时长 - _已用, 0.0)
	if _说明 == "":
		_文字.text = "%.1fs" % 剩余
	else:
		_文字.text = "%s %.1fs" % [_说明, 剩余]


## 摆到「那个人头顶」。世界坐标 → 屏幕坐标这一步由相机变换代劳，
## 所以相机怎么缩放、怎么跟随，条都自动对上，不用在这里乘 1.5。
func _跟位置() -> void:
	if _跟谁 == null or not is_instance_valid(_跟谁):
		# 不跟人 = 固定在屏幕下方正中（640×360 的一半再往下一截）
		_框.position = (Vector2(320.0, 268.0) - Vector2(条宽 * 0.5, 条高 * 0.5)).round()
		return
	var 屏幕点: Vector2 = get_viewport().get_canvas_transform() * (
		_跟谁.global_position + Vector2(0.0, _头顶偏移))
	_框.position = (屏幕点 - Vector2(条宽 * 0.5, 0.0)).round()
