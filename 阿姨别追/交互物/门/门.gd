extends Node2D
## 门 —— 双方都能开、都能关，只是快慢不同（按主人 2026-11-02 定的规则）
##
## 【谁说了算】（2026-11-04 主人定：开门属于场景）
##   角色不决定开多快，它只会说一句「我要推这扇门」，然后等门回话。
##   「开多快、现在开到哪儿」全在门自己身上；
##   门的数据来自 `数据/楼层清单.gd`，所以每扇门可以不一样（防火门 3 秒、常开门 0 秒）。
##   结论：学生和宿管的脚本里，一个「几秒」都不会出现。
##
## 「抢使用权」怎么实现的：
##   门自己不记「谁开的」，只记「现在推到哪儿了」（_amount：0=全关，1=全开）
##   和「现在是谁在推」（_user）。
##   谁按 E，谁就变成 _user，门立刻按新主人的速度朝反方向走，进度不清零。
##   所以：宿管慢慢开到一半，学生冲过来按 E，门马上掉头、而且掉头很快。
##
## 调手感：改 `数据/楼层清单.gd` 顶部的「默认开门用时」，或给某扇门单独配。
##
## 【2026-11-04 删掉了"兜底用时"】
##   以前这里藏着一份写死的兜底时长（学生快、宿管慢），说是"门被单独摆出来时用"。
##   但同一份数字在 `数据/楼层清单.gd` 里已经有一份了 —— 同一个数存两处，
##   改一处另一处不会跟着变：哪天清单把默认改快，代理建出来的门跟着变、
##   单独摆出来的门还是老速度，同一局两种开门速度，还查不出来源。
##   现在：这扇门的用时只有清单一个来源。代理没把用时传进来就是配置错了，
##   报错、不偷偷兜底 —— 悄悄用默认值，等于让错误永远看不见。

var floor_id: String = ""
var door_id: String = ""

## 这扇门自己的开门用时。由楼层代理照清单填进来
## 空字典 = 还没填（= 配置漏了），用的时候 `_time_needed()` 会 push_error
var _开门用时: Dictionary = {}

var _amount: float = 0.0        # 0 = 全关，1 = 全开
var _target: float = 0.0        # 正往哪去
var _user: Node = null          # 现在是谁在推这扇门
var _blocked: bool = true       # 当前碰撞体是不是挡着路

@onready var _panel: Polygon2D = $Panel
@onready var _blocker: CollisionShape2D = $Blocker/CollisionShape2D


## 由楼层代理按清单调用：告诉它自己是哪层、哪扇、站哪、开门要几秒
func setup(f: String, id: String, pos: Vector2, 用时: Dictionary = {}) -> void:
	floor_id = f
	door_id = id
	position = pos
	if not 用时.is_empty():
		_开门用时 = 用时.duplicate()


func _ready() -> void:
	_apply()


## 有人按了 E（求生者）或要开关门（宿管）。谁按，谁接管。
##
## 【为什么不用回话给角色】
##   角色只需要说「我要推你」，说完就没它的事了 —— 它不需要知道几秒、开到几成。
##   门开够了（_amount > 0.95）自己把 Blocker 撤掉，人一撞就走过去了。
##   「碰撞体消失」就是回话，而且是玩家用眼睛看得见的那种回话。
##   所以这里没有返回值：单向，一句话，够用。
func press(who: Node) -> void:
	_user = who
	_target = 0.0 if _target > 0.5 else 1.0
	Director.report(floor_id, "door_pressed", { "door_id": door_id, "by": who })
	Director.door_pressed.emit(floor_id, door_id, who)


## 被解锁：三个锁孔插满时，由楼层代理替门喊这一句（2026-11-05）
##
## 【为什么不用 press()】
##   press 是「谁在推门」，要记是谁推的、按那个人的速度慢慢开。
##   解锁不是推出来的，是锁开了 —— 没有推的人，也不需要几秒，就是弹开。
##   硬套 press 会得出「宿管推的所以按 1.5 秒慢慢开」这种荒唐结果。
func 被解锁() -> void:
	_user = null
	_amount = 1.0
	_target = 1.0
	_apply()                                   # 门板藏掉、碰撞体撤掉，人能过
	Director.door_finished.emit(floor_id, door_id, true)
	print("[门] %s 被解锁，弹开了" % door_id)


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


## 这扇门这次要花几秒？只看推的人是谁。数字来自清单，不写在这里
## 【为什么缺数据要报错而不是兜底】
##   兜底会让"清单漏配"这个错误永远看不见：门照样能开，只是速度不对，
##   而"速度不对"很难被当成 bug 报上来。宁可在控制台红一行，
##   也不要同一局里悄悄出现两种开门速度。
func _time_needed(who: Node) -> float:
	var 谁 := "宿管" if _is_keeper(who) else "求生者"
	if not _开门用时.has(谁):
		push_error("[门] %s 没拿到开门用时，检查它是不是经过楼层代理建的" % door_id)
		return 1.0   # 明显不合理的值：看得见、好定位，不是"正常速度"
	return float(_开门用时[谁])


func _is_keeper(who: Node) -> bool:
	return who != null and who.is_in_group("keeper")


## 把「开到哪儿」变成看得见的样子（2026-11-04 主人改规则）
## 不再要「往上缩进墙里」的动画：门就是干脆的两态——
##   关着 = 实体（看得见、挡路）；开着 = 隐藏（看不见、过得去）
func _apply() -> void:
	_panel.visible = _amount <= 0.95   # 关着才看得见门板，开够就整块藏掉
	var want_blocked := _amount <= 0.95
	if want_blocked != _blocked:
		_blocked = want_blocked
		_blocker.set_deferred("disabled", not want_blocked)
