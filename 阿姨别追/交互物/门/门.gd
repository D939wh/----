extends Node2D
## 门 —— 双方都能开、都能关，只是快慢不同
##
## 开门用时等数据来自 `数据/通用规则.gd`，每扇门可在清单里单独配。
## 谁按 E 谁就是 _user：门立刻按新使用者的速度反向走，进度不清零。
## 调手感：改 `数据/通用规则.gd` 顶部的「默认开门用时」，或给某扇门单独配。

## 这扇门的身份证（"1-走廊东" 这种）。由物件代理照清单盖章，或在检查器里手填。
## **全工程不许重号** —— 总管拿它当唯一键。
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 中文别名：全工程代码统一用「编号」读写，和 `thing_id` 是同一个值
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

## 交互优先级：同一位置挤着好几件东西时，数字大的先问（门是 0，箱子是 10）
@export var 互动优先级: int = 0

## 这扇门自己的开门用时。由物件代理照清单填进来
## 空字典 = 还没填（= 配置漏了），用的时候 `_time_needed()` 会 push_error
var _开门用时: Dictionary = {}

var _amount: float = 0.0        # 0 = 全关，1 = 全开
var _target: float = 0.0        # 正往哪去
var _user: Node = null          # 现在是谁在推这扇门
var _blocked: bool = true       # 当前碰撞体是不是挡着路

@onready var _panel: Polygon2D = $Panel
@onready var _blocker: CollisionShape2D = $Blocker/CollisionShape2D


## 由物件代理按清单调用：站哪、开门要几秒。（编号由代理在 add_child 前盖好）
func setup(pos: Vector2, 用时: Dictionary = {}) -> void:
	position = pos
	if not 用时.is_empty():
		_开门用时 = 用时.duplicate()


func _ready() -> void:
	_apply()
	# 报到：从这一刻起，总管拿编号就能找到这扇门
	Director.register_thing(编号, self)


## 有人按了 E（求生者）或要开关门（宿管）。谁按，谁接管。
func press(who: Node) -> void:
	_user = who
	_target = 0.0 if _target > 0.5 else 1.0
	Director.door_pressed.emit(编号, who)


## 按键进来：只认「开门」这一个键，其余不归我管（返回 false，让别人接着问）
func 被按键(键: String, 谁: Node) -> bool:
	if 键 != "open_door":
		return false
	press(谁)
	return true


## 收到一件事（总管按编号递过来的）。现在只认「解锁」这一件
func on_report(event: String, data: Dictionary) -> void:
	if event == "unlock":
		print("[门] %s 收到「%s」插满了" % [编号, data.get("锁口", "?")])
		被解锁()


## 被解锁：三个锁孔插满时，总管按编号把话递到这里（不走 press()，直接弹开）
func 被解锁() -> void:
	_user = null
	_amount = 1.0
	_target = 1.0
	_apply()                                   # 门板藏掉、碰撞体撤掉，人能过
	Director.door_finished.emit(编号, true)
	print("[门] %s 被解锁，弹开了" % 编号)


func _process(delta: float) -> void:
	if is_equal_approx(_amount, _target):
		return
	_amount = move_toward(_amount, _target, (1.0 / _time_needed(_user)) * delta)
	_apply()
	if is_equal_approx(_amount, _target):
		var is_open := _target > 0.5
		Director.door_finished.emit(编号, is_open)
		print("[门] %s %s（%s 推的）" % [
			编号,
			"已打开" if is_open else "已关上",
			"宿管" if _is_keeper(_user) else "求生者",
		])


## 这扇门这次要花几秒？只看推的人是谁。数字来自清单，不写在这里
## 缺数据报错而不兜底：兜底会让清单漏配的错误不可见
func _time_needed(who: Node) -> float:
	var 谁 := "宿管" if _is_keeper(who) else "求生者"
	if not _开门用时.has(谁):
		push_error("[门] %s 没拿到开门用时，检查清单里这件东西是不是经过物件代理建的" % 编号)
		return 1.0   # 明显不合理的值：看得见、好定位，不是"正常速度"
	return float(_开门用时[谁])


func _is_keeper(who: Node) -> bool:
	return who != null and who.is_in_group("keeper")


## 把「开到哪儿」变成看得见的样子。两态：关着 = 实体，开着 = 隐藏
func _apply() -> void:
	_panel.visible = _amount <= 0.95   # 关着才看得见门板，开够就整块藏掉
	var want_blocked := _amount <= 0.95
	if want_blocked != _blocked:
		_blocked = want_blocked
		_blocker.set_deferred("disabled", not want_blocked)
