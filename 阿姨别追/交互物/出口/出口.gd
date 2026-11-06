extends Area2D
## 出口 —— 门被解锁之后，站在门口 1 秒就算逃出去
## 门开没开：监听总管的 door_finished 广播，不与门直接耦合

const 读条脚本 := preload("res://界面/读条/读条.gd")
## 全工程规则（物理层位掩码）。`_ready` 里配碰撞掩码要用。
const 规则 := preload("res://数据/通用规则.gd")

## 站够几秒算逃出去。策划案 §3.3 写的 1 秒
@export var 逃出用时: float = 1.0

## 这个出口的身份证。由物件代理照清单盖章，或在检查器里手填
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 中文别名：全工程代码统一用「编号」读写，和 `thing_id` 是同一个值
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

## 我在等哪扇门（写的是那扇门的**编号**）。它开了我才有用
var _等哪扇门: String = ""

var _启用中: bool = false
var _谁: Node = null            # 现在站在门口的这个人
var _进度: float = 0.0
var _读条: CanvasLayer = null


func _ready() -> void:
	collision_layer = 0
	# 只负责「看见人」：站着的（地板层）和瘫在地上的（瘫痪层）。
	# 层号问规则要，不写死数字
	collision_mask = 规则.层_地板 | 规则.层_瘫痪
	Director.door_finished.connect(_on_door_finished)
	Director.register_thing(编号, self)
	$HUD/提示.visible = false


## 由物件代理照清单调用（编号由代理在 add_child 前盖好）
func setup(pos: Vector2, 门号: String, 用时: float = 1.0) -> void:
	position = pos
	_等哪扇门 = 门号
	逃出用时 = 用时


## 门开了没有。开门这个动作可能是被推开的，也可能是三个锁孔插满弹开的，
## 对出口来说都一样：门能过人了，就该开始算数
func _on_door_finished(哪扇门: String, 开着: bool) -> void:
	if 哪扇门 != _等哪扇门:
		return
	if 开着:
		_启用中 = true
		print("[出口] %s 的门开了，站 %.1f 秒就算逃出去" % [哪扇门, 逃出用时])
	else:
		_取消()
		_启用中 = false


func _physics_process(delta: float) -> void:
	if not _启用中:
		return

	var 人 := _站在里面的人()
	if 人 == null:
		_取消()
		return

	if 人 != _谁:
		# 换了个人站进来（或者第一次站进来）：重新从 0 数
		_取消()
		_谁 = 人
		_进度 = 0.0
		# 读条建一次反复用：「收」只是藏起来不销毁，下次有人站进来接着摆出来
		if _读条 == null or not is_instance_valid(_读条):
			_读条 = 读条脚本.新建(self)
		# 跟谁传 null = 摆在屏幕下方正中。逃出是「全队的大事」，不挂在某个人头上
		_读条.开始(null, "逃出", 逃出用时)

	_进度 += delta
	if _读条 != null:
		_读条.推进(_进度)
	if _进度 >= 逃出用时:
		_赢了()


## 站在里面、还没瘫的那个人
func _站在里面的人() -> Node:
	for body in get_overlapping_bodies():
		if body.has_method("拉起") and not body.瘫痪:
			return body
	return null


func _取消() -> void:
	# 只收（藏）不删、也不清引用：这根条建一次反复用，下次有人站进来直接再摆出来
	if _读条 != null and is_instance_valid(_读条):
		_读条.收()
	_进度 = 0.0
	_谁 = null


func _赢了() -> void:
	var 人 := _谁
	_取消()
	_启用中 = false
	set_physics_process(false)
	$HUD/提示.visible = true
	print("[出口] %s 从 %s 跑出去了 —— 这一局结束" % [人.name if 人 != null else "有人", 编号])
