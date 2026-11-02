extends Node2D
## 门 —— 双方都能开、都能关，只是快慢不同（按主人 2026-11-02 定的规则）
##
## 「抢使用权」怎么实现的：
##   门自己不记「谁开的」，只记「现在推到哪儿了」（_amount：0=全关，1=全开）
##   和「现在是谁在推」（_user）。
##   谁按 E，谁就变成 _user，门立刻按新主人的速度朝反方向走，进度不清零。
##   所以：宿管慢慢开到一半，学生冲过来按 E，门马上掉头、而且掉头很快。
##
## 改手感只改下面这两行数字。

const OPEN_TIME_PLAYER := 0.3   # 求生者：一推就开，一推就关
const OPEN_TIME_KEEPER := 1.5   # 宿管：开也慢，关也慢

const DOOR_HEIGHT := 96.0       # 门板高度（像素），比这个高就往上挪

var floor_id: String = ""
var door_id: String = ""

var _amount: float = 0.0        # 0 = 全关，1 = 全开
var _target: float = 0.0        # 正往哪去
var _user: Node = null          # 现在是谁在推这扇门
var _blocked: bool = true       # 当前碰撞体是不是挡着路

@onready var _panel: Polygon2D = $Panel
@onready var _blocker: CollisionShape2D = $Blocker/CollisionShape2D


## 由楼层代理按清单调用：告诉它自己是哪层、哪扇、站哪
func setup(f: String, id: String, pos: Vector2) -> void:
	floor_id = f
	door_id = id
	position = pos


func _ready() -> void:
	_apply()


## 有人按了 E（求生者）或要开关门（宿管）。谁按，谁接管
func press(who: Node) -> void:
	_user = who
	_target = 0.0 if _target > 0.5 else 1.0
	Director.report(floor_id, "door_pressed", { "door_id": door_id, "by": who })
	Director.door_pressed.emit(floor_id, door_id, who)


func _process(delta: float) -> void:
	if is_equal_approx(_amount, _target):
		return
	_amount = move_toward(_amount, _target, (1.0 / _time_needed(_user)) * delta)
	_apply()
	if is_equal_approx(_amount, _target):
		var is_open := _target > 0.5
		Director.door_finished.emit(floor_id, door_id, is_open)
		print("[门] %s %s（%s 推的）" % [
			door_id,
			"已打开" if is_open else "已关上",
			"宿管" if _is_keeper(_user) else "求生者",
		])


## 这扇门这次要花几秒？只看推的人是谁
func _time_needed(who: Node) -> float:
	return OPEN_TIME_KEEPER if _is_keeper(who) else OPEN_TIME_PLAYER


func _is_keeper(who: Node) -> bool:
	return who != null and who.is_in_group("keeper")


## 把 _amount 这个数字变成看得见的样子
func _apply() -> void:
	_panel.position.y = -_amount * DOOR_HEIGHT      # 门板往上缩进墙里
	_panel.modulate.a = 1.0 - _amount * 0.55        # 开得越多越淡，一眼看出状态
	var want_blocked := _amount <= 0.95
	if want_blocked != _blocked:
		_blocked = want_blocked
		_blocker.set_deferred("disabled", not want_blocked)
