extends Node2D
## 门 —— 双方都能开、都能关，只是快慢不同（按主人 2026-11-02 定的规则）
##
## 【谁说了算】（2026-11-04 主人定：开门属于场景）
##   角色不决定开多快，它只会说一句「我要推这扇门」，然后等门回话。
##   「开多快、现在开到哪儿」全在门自己身上；
##   门摆在哪来自这张地图的清单，开多快来自 `数据/通用规则.gd`（全地图共用），
##   所以每扇门可以不一样（防火门 3 秒、常开门 0 秒）。
##   结论：学生和宿管的脚本里，一个「几秒」都不会出现。
##
## 「抢使用权」怎么实现的：
##   门自己不记「谁开的」，只记「现在推到哪儿了」（_amount：0=全关，1=全开）
##   和「现在是谁在推」（_user）。
##   谁按 E，谁就变成 _user，门立刻按新主人的速度朝反方向走，进度不清零。
##   所以：宿管慢慢开到一半，学生冲过来按 E，门马上掉头、而且掉头很快。
##
## 调手感：改 `数据/通用规则.gd` 顶部的「默认开门用时」，或给某扇门单独配。
##
## 【2026-11-04 删掉了"兜底用时"】
##   以前这里藏着一份写死的兜底时长（学生快、宿管慢），说是"门被单独摆出来时用"。
##   但同一份数字在 `数据/通用规则.gd` 里已经有一份了 —— 同一个数存两处，
##   改一处另一处不会跟着变：哪天清单把默认改快，代理建出来的门跟着变、
##   单独摆出来的门还是老速度，同一局两种开门速度，还查不出来源。
##   现在：这扇门的用时只有清单一个来源。代理没把用时传进来就是配置错了，
##   报错、不偷偷兜底 —— 悄悄用默认值，等于让错误永远看不见。

## 这扇门的身份证（"1-走廊东" 这种）。由物件代理照清单盖章，或在检查器里手填。
## **全工程不许重号** —— 总管拿它当唯一键。
## 身份证（编号）。**必须用英文名导出** —— 中文名的导出属性在 `.tscn` 里赋值会
## **静默失效**（2026-11-06 实测：`.tscn` 里明明写着 `编号 = "1-箱子"`，运行时读出来是空串，
## 属性表里那一项也在，就是不生效）。所以编辑器里填 `thing_id`，代码里读 `编号`。
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
##
## 【为什么不用回话给角色】
##   角色只需要说「我要推你」，说完就没它的事了 —— 它不需要知道几秒、开到几成。
##   门开够了（_amount > 0.95）自己把 Blocker 撤掉，人一撞就走过去了。
##   「碰撞体消失」就是回话，而且是玩家用眼睛看得见的那种回话。
##   所以这里没有返回值：单向，一句话，够用。
func press(who: Node) -> void:
	_user = who
	_target = 0.0 if _target > 0.5 else 1.0
	Director.door_pressed.emit(编号, who)


## 按键进来：只认「开门」这一个键，其余不归我管（返回 false，让别人接着问）
##
## 【为什么这个函数长在门身上】学生不认识门，它只说「我按了 E，我碰到了编号 X」。
##   是不是归这扇门办、按了要干什么，门自己最清楚。以后加灯、加柜子，
##   各自实现这一个函数就行，总管和代理一个字不用改。
func 被按键(键: String, 谁: Node) -> bool:
	if 键 != "open_door":
		return false
	press(谁)
	return true


## 收到一件事（总管按编号递过来的）。现在只认「解锁」这一件
##
## 【为什么这句话让门自己办】锁口只说「插满了」，谁该开、怎么开，门自己最清楚。
##   以后加「电闸箱供电才能开」这种规矩，也只改这里，锁口一个字不用动。
func on_report(event: String, data: Dictionary) -> void:
	if event == "unlock":
		print("[门] %s 收到「%s」插满了" % [编号, data.get("锁口", "?")])
		被解锁()


## 被解锁：三个锁孔插满时，总管按编号把话递到这里（2026-11-05，11-06 改成按编号）
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
## 【为什么缺数据要报错而不是兜底】
##   兜底会让"清单漏配"这个错误永远看不见：门照样能开，只是速度不对，
##   而"速度不对"很难被当成 bug 报上来。宁可在控制台红一行，
##   也不要同一局里悄悄出现两种开门速度。
func _time_needed(who: Node) -> float:
	var 谁 := "宿管" if _is_keeper(who) else "求生者"
	if not _开门用时.has(谁):
		push_error("[门] %s 没拿到开门用时，检查清单里这件东西是不是经过物件代理建的" % 编号)
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
