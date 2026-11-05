extends Area2D
## 出口 —— 门被解锁之后，站在门口 1 秒就算逃出去
##
## 【为什么单独做一个东西，而不是塞进门里】
##   门管的是「开和关」，出口管的是「跑没跑出去」。两件事。
##   以后要加第二个出口（消防梯、天台晾衣绳），只是清单里多一行，
##   门那边一个字不用改 —— 这就是分开的理由。
##
## 【它怎么知道门开了】
##   不靠谁来喊。总管开门时会广播一句 `door_finished`（门自己发的），
##   这里听着，看是不是自己等的那一扇。门和出户口头不认识，只认名字。
##   好处：门因为别的原因开了（被推开的、被解锁的），出口照样生效。
##
## 【为什么站够 1 秒而不是一碰就走】
##   门口是唯一出口，站定那 1 秒就是「最后一搏」——宿管还有机会冲过来把人拉回去。
##   一碰就走的话，门一开游戏就结束了，最后那段追逐就没有了。

const 读条脚本 := preload("res://界面/读条/读条.gd")

## 站够几秒算逃出去。策划案 §3.3 写的 1 秒
@export var 逃出用时: float = 1.0

var floor_id: String = ""
var exit_id: String = ""
var _等哪扇门: String = ""      # 这扇门开了我才有用

var _启用中: bool = false
var _谁: Node = null            # 现在站在门口的这个人
var _进度: float = 0.0
var _读条: CanvasLayer = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2      # 只负责「看见人」：站着的（1）和瘫在地上的（2）
	Director.door_finished.connect(_on_door_finished)
	$HUD/提示.visible = false


## 由楼层代理照清单调用
func setup(f: String, id: String, pos: Vector2, 门号: String, 用时: float = 1.0) -> void:
	floor_id = f
	exit_id = id
	position = pos
	_等哪扇门 = 门号
	逃出用时 = 用时


## 门开了没有。开门这个动作可能是被推开的，也可能是三个锁孔插满弹开的，
## 对出口来说都一样：门能过人了，就该开始算数
func _on_door_finished(f: String, 门号: String, 开着: bool) -> void:
	if f != floor_id or 门号 != _等哪扇门:
		return
	if 开着:
		_启用中 = true
		print("[出口] %s 的门开了，站 1 秒就算逃出去" % 门号)
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
	if _读条 != null and is_instance_valid(_读条):
		_读条.收()
	_读条 = null
	_进度 = 0.0
	_谁 = null


func _赢了() -> void:
	var 人 := _谁
	_取消()
	_启用中 = false
	set_physics_process(false)
	$HUD/提示.visible = true
	print("[出口] %s 从 %s 跑出去了 —— 这一局结束" % [人.name if 人 != null else "有人", exit_id])
