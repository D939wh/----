extends Node2D
## 门 —— 双方都能开、都能关，只是快慢不同
##
## 开门用时等数据来自 `数据/通用规则.gd`，每扇门可在清单里单独配。
## 谁按 E 谁就是 _user：门立刻按新使用者的速度反向走，进度不清零。
## 调手感：改 `数据/通用规则.gd` 顶部的「默认开门用时」，或给某扇门单独配。

## 声音表：门是 4 档（「极大」）—— 全图最响的几件事之一。
const 声音表 := preload("res://数据/声音表.gd")
## 默认开门用时：手摆在场景里的门（没走过物件代理）靠它开口
const 规则 := preload("res://数据/通用规则.gd")

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

# ============================================================
# 外形：尺寸 + 贴图（2026-11-12 21:55 加）
# ------------------------------------------------------------
# 以前门的长相焊死在 `门.tscn` 里 —— 想换一扇就得改模板，一改全楼的门一起变。
# 现在每扇门自己带这三个值（清单里配，或场景里选中门直接在检查器改）。
#
# **优先级**：有 `texture` 就**完全按图的像素尺寸**，`width`/`height` 不起作用；
#   没图才用 `width`/`height`。理由：美术给的图自带正确尺寸，硬要再填一遍数值
#   只会出现「图 64 宽、碰撞 50 宽」这种对不上的情况。
#
# **锚点约定**：门的图**底边中点 = 节点原点**（原点就是地面线），和原来色块一致。
#   所以给美术的一句话是：门图画到「下边缘贴着地面」就行，别留空白边。
# ============================================================

## 门有多宽（像素）。有 `texture` 时这个值不起作用。导出一律英文名：中文名在 .tscn 里赋值会静默失效
@export var width: float = 64.0:
	set(值):
		width = maxf(值, 4.0)
		if is_node_ready():
			_改外形()

## 门有多高（像素）。同上
@export var height: float = 96.0:
	set(值):
		height = maxf(值, 4.0)
		if is_node_ready():
			_改外形()

## 门板贴图。**留空 = 用色块占位**（现在是纯色，等美术出图）
@export var texture: Texture2D = null:
	set(值):
		texture = 值
		if is_node_ready():
			_改外形()

## 中文别名：代码里统一用「宽 / 高 / 贴图」读写
var 宽: float:
	get:
		return width
	set(值):
		width = 值

var 高: float:
	get:
		return height
	set(值):
		height = 值

var 贴图: Texture2D:
	get:
		return texture
	set(值):
		texture = 值

## 感应区比门板每边多出来的像素。留这一圈，人站在门前（还没贴到门上）就能按 E
const 感应外扩: float = 12.0

## 这扇门自己的开门用时。由物件代理照清单填进来
## 空字典 = 没配，用 `通用规则.gd` 的默认值（手摆在场景里的门就是这种）
var _开门用时: Dictionary = {}

var _amount: float = 0.0        # 0 = 全关，1 = 全开
var _target: float = 0.0        # 正往哪去
var _user: Node = null          # 现在是谁在推这扇门
var _blocked: bool = true       # 当前碰撞体是不是挡着路
var _已解锁: bool = false       # 被钥匙板弹开过 = 从此锁死，谁也关不上
var 空气墙: bool = false        # 看不见门板 + E 推不动（大门用：画面由美术拼在图上，本体只是一堵会消失的墙）

## 要钥匙才开：**看得见门板，但按 E 推不动**，只能等锁口插满把它弹开。
## 和「空气墙」的区别只在看不看得见 —— 空气墙是连门板都没有的隐形墙，
## 这个是一扇正正经经的门，只是锁着。（2026-11-12 22:10 拆出来的）
## 英文名导出：中文名在 `.tscn` 里赋值会静默失效。
@export var needs_key: bool = false

## 开局就是开着的（2026-11-12 加）。
## 用来做「追逃路线上的门」：默认关着的门对玩家和宿管都是一堵墙，
## 只有**先开着**，玩家才有「跑过去把它关上，挡她 1.5 秒」这个选项。
## 英文名导出：中文名在 `.tscn` 里赋值会静默失效。
@export var start_open: bool = false

## 中文别名：代码里统一用「要钥匙」
var 要钥匙: bool:
	get:
		return needs_key
	set(值):
		needs_key = 值

@onready var _panel: Polygon2D = $Panel          # 没贴图时的占位色块
@onready var _art: Sprite2D = $Art               # 有贴图时显示的正主
@onready var _blocker: CollisionShape2D = $Blocker/CollisionShape2D
@onready var _zone: CollisionShape2D = $Zone/CollisionShape2D


## 由物件代理按清单调用：站哪、开门要几秒、是不是空气墙、多大、什么图、要不要钥匙。
## 后几个不写 = 用这扇门自己的导出值（手摆在场景里的门就是这种）。
func setup(pos: Vector2, 用时: Dictionary = {}, 是空气墙: bool = false,
		新宽: float = 0.0, 新高: float = 0.0, 新贴图: Texture2D = null,
		是要钥匙: bool = false) -> void:
	position = pos
	if not 用时.is_empty():
		_开门用时 = 用时.duplicate()
	空气墙 = 是空气墙
	要钥匙 = 是要钥匙
	if 新宽 > 0.0:
		width = 新宽      # setter 里会调 _改外形
	if 新高 > 0.0:
		height = 新高
	if 新贴图 != null:
		texture = 新贴图
	_改外形()             # 三个都没变时 setter 不会触发，这里兜一次
	_apply()              # _ready 在 add_child 时先跑过一次，这里按新配置再刷一遍（空气墙藏门板）


func _ready() -> void:
	# 开局就开着的门：先把开度拨到 1，再让 `_apply()` 按它刷（否则会先挡一下再弹开）
	if start_open:
		_amount = 1.0
		_target = 1.0
	_改外形()
	_apply()
	# 报到：从这一刻起，总管拿编号就能找到这扇门
	Director.register_thing(编号, self)


## 按当前「宽 / 高 / 贴图」重算三样东西：门板、挡路体、感应区。
##
## **形状必须每次新建 RectangleShape2D**：`.tscn` 里那份是所有门实例共用的 sub_resource，
## 直接改 size 会让全楼的门一起变（梯子、判定区都踩过同一个坑）。
## 新建 = 每扇门一份，互不影响 —— 这是「一扇门一个尺寸」能成立的前提。
func _改外形() -> void:
	var 宽 := width
	var 高 := height
	if texture != null:
		# 有图就听图的：像素尺寸是美术画的时候定好的，别拿数值去拧它
		宽 = float(texture.get_width())
		高 = float(texture.get_height())

	# 门板：有图显示图，没图显示色块
	if _art != null:
		_art.texture = texture
		_art.position = Vector2(0.0, -高 * 0.5)     # 图底边贴在原点（地面线）
	if _panel != null:
		_panel.polygon = PackedVector2Array([
			Vector2(-宽 * 0.5, -高),
			Vector2(宽 * 0.5, -高),
			Vector2(宽 * 0.5, 0.0),
			Vector2(-宽 * 0.5, 0.0),
		])

	# 挡路体 = 门的实体，和门板一样大
	if _blocker != null:
		var 形 := RectangleShape2D.new()
		形.size = Vector2(宽, 高)
		_blocker.shape = 形
		_blocker.position = Vector2(0.0, -高 * 0.5)

	# 感应区 = 门的实体往外扩一圈（人能站在门前按 E，不用贴脸）
	if _zone != null:
		var 感形 := RectangleShape2D.new()
		感形.size = Vector2(宽 + 感应外扩 * 2.0, 高 + 感应外扩 * 2.0)
		_zone.shape = 感形
		_zone.position = Vector2(0.0, -高 * 0.5)

	_刷新显隐()


## 这扇门现在**推得开吗**（不是隐形墙、没锁、没被钥匙弹死）。
## AI 靠它判断「挡在前面这扇门我该不该去推」—— 推不开的她会站住，不会傻推。
func 能推开() -> bool:
	return not (空气墙 or 要钥匙 or _已解锁)


## AI 用：**只往开的方向走，不会把门关回去**（2026-11-12 加）。
##
## 为什么不让她调 `press()`：`press()` 是开关切换，AI 每帧问一次门还在不在挡路，
## 连问两帧就会「开→关→开→关」，门在她面前原地抽搐，而且永远过不去。
## 这个函数是幂等的：已经在开了就什么都不做。
func 求开(who: Node) -> void:
	if not 能推开():
		return
	if _target > 0.5:
		return          # 已经在开了 / 已经开着：不重复发令
	_user = who
	_target = 1.0
	Director.door_pressed.emit(编号, who)


## 有人按了 E（求生者）或要开关门（宿管）。谁按，谁接管。
## 已经解锁的门不再接受开关：策划案 §2.3 写的是「弹开并撑住」。
func press(who: Node) -> void:
	# 三种推不开：隐形的死墙 / 看得见但锁着 / 已经被钥匙弹开过
	if 空气墙 or 要钥匙 or _已解锁:
		return
	_user = who
	_target = 0.0 if _target > 0.5 else 1.0
	Director.door_pressed.emit(编号, who)


## 按键进来：只认「开门」这一个键，其余不归我管（返回 false，让别人接着问）
## **开不了的门要返回 false**：锁着 / 隐形墙 / 已解锁都算「这键我办不了」，
## 让总管接着问下一件（比如门口堆着的箱子），不能自己吃掉这个键。
func 被按键(键: String, 谁: Node) -> bool:
	if 键 != "open_door":
		return false
	if 空气墙 or 要钥匙 or _已解锁:
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
	_已解锁 = true
	_apply()                                   # 门板藏掉、碰撞体撤掉，人能过
	Director.door_finished.emit(编号, true)
	Match.register_unlock(编号)                # 账本只认这一条：真正的解锁
	Events.发声(global_position, 声音表.档_极大, 声音表.来源_门)   # 弹开比推开更响，同样 4 档
	print("[门] %s 被解锁，弹开了" % 编号)


func _process(delta: float) -> void:
	if is_equal_approx(_amount, _target):
		return
	_amount = move_toward(_amount, _target, (1.0 / _time_needed(_user)) * delta)
	_apply()
	if is_equal_approx(_amount, _target):
		var is_open := _target > 0.5
		Director.door_finished.emit(编号, is_open)
		# 4 档：开关门是「非常大」的声音（主人定）—— 门一动，半层楼都知道。
		# 发在「走完」这一刻：推的过程没有反馈，门板到位的声响最容易被听懂。
		Events.发声(global_position, 声音表.档_极大, 声音表.来源_门)
		print("[门] %s %s（%s 推的）" % [
			编号,
			"已打开" if is_open else "已关上",
			"宿管" if _is_keeper(_user) else "求生者",
		])


## 这扇门这次要花几秒？只看推的人是谁。数字来自清单，不写在这里
## **手动摆在场景里的门**（新场景做测试那种）没走过物件代理，`_开门用时` 整份是空的 ——
## 这是合法用法，用 `通用规则.gd` 的默认值就行，不当成配置错误。
## 但如果字典**有内容却缺这一项**，那就是清单漏配，要报出来（别让错误看不见）。
func _time_needed(who: Node) -> float:
	var 谁 := "宿管" if _is_keeper(who) else "求生者"
	if not _开门用时.has(谁):
		if _开门用时.is_empty():
			return float(规则.默认开门用时.get(谁, 1.0))
		push_error("[门] %s 没拿到开门用时，检查清单里这件东西是不是经过物件代理建的" % 编号)
		return 1.0   # 明显不合理的值：看得见、好定位，不是"正常速度"
	return float(_开门用时[谁])


func _is_keeper(who: Node) -> bool:
	return who != null and who.is_in_group("keeper")


## 把「开到哪儿」变成看得见的样子。两态：关着 = 实体，开着 = 隐藏
func _apply() -> void:
	_刷新显隐()
	var want_blocked := _amount <= 0.95
	if want_blocked != _blocked:
		_blocked = want_blocked
		_blocker.set_deferred("disabled", not want_blocked)


## 什么时候露脸：不空气墙、且门没开够。**有图露图，没图露色块**，两个不会同时出现。
func _刷新显隐() -> void:
	var 露 := (not 空气墙) and _amount <= 0.95
	if _panel != null:
		_panel.visible = 露 and texture == null
	if _art != null:
		_art.visible = 露 and texture != null
