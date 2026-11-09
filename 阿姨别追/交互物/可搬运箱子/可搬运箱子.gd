extends Area2D
## 可搬运箱子 —— 会被扛起来，也会被放下；放下之后**自己受重力落回地面**
##
## 用 Area2D 而非 RigidBody2D：感应区只认 Area2D；被扛时要 reparent 成学生的子节点。
## 重力自己算：每帧朝下打一条短射线，探到地面就贴住、探不到就往下掉。
##
## 改重量：改下面这个 `重量`（或在编辑器里点箱子改）。80kg 按策划案属 **4 档**——
## 扛起来只能横向拖行、不能跳、不能爬梯。具体惩罚在 `数据/重量档位.gd` 那张表里。
## 档位是每 20 公斤一刀：1 档 ≤20 / 2 档 ≤40 / 3 档 ≤60 / 4 档 >60

@export var 重量: float = 80.0

## 这件东西的身份证（"1-箱子" 这种）。由物件代理照清单盖章，或在检查器里手填。
## 空编号 = 谁都找不到它 —— 学生按 F 也扛不起来，只会打一句警告。
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 中文别名：全工程代码统一用「编号」读写，和 `thing_id` 是同一个值
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

## 交互优先级：同一位置挤着好几件东西时，数字大的先问。
## 箱子 10 > 道具 0 —— 站在箱子和道具中间按 F，先搬箱子
@export var 互动优先级: int = 10

## 全工程规则（物理层位掩码）。**放在 地面层 前面**：下面的常量要引用它，
## GDScript 读常量是从上往下求值的（和 student.gd 同一条规矩）。
const 规则 := preload("res://数据/通用规则.gd")
## 抛物线飞行（反解初速 + 逐小步探地探墙），学生被扔出去时用的是同一份。
const 抛投 := preload("res://组件/抛投/抛投.gd")

const 下落重力: float = 900.0      # 像素/秒²。死物掉得比人干脆，别在空中飘
const 最大下落速度: float = 700.0  # 再快也不会穿地：一帧最多 700/60 ≈ 12px < 一格 16px
## 探地面认哪几层：跟「人站的地面」同一套 —— 地板 + 可以穿过的地板。
## 检修口盖板就在第 2 层，只认第 1 层的话，箱子/钥匙板放到盖板上会穿板掉下楼。
## 层号一律问规则要，不写裸数字（层序要是再重排，这里不用跟着改）。
const 地面层: int = 规则.人站的地面

## 已经插进锁孔了？插上之后这东西就不该再被扛起来（钥匙板才用得上，箱子永远 false）
var 已插: bool = false

var 被扛着: bool = false            # 学生拿起时置 true、放下置 false
var _下落速度: float = 0.0
var _底半高: float = 9.0            # 从箱子中心到底边的距离，落地对齐用
var _站住了: bool = false           # 已经贴着地面了
var _复查倒计时: float = 0.0        # 站住之后多久再看一眼脚下（别每帧都算）

# ── 被抛出 ───────────────────────────────────────────────────
# 抛出去之后不再只是「直着往下掉」，而是带着水平速度走一段抛物线，
# 落地或撞墙就停。重力还是用上面那个 `下落重力`，和自由落体是同一份。
var _抛投 = 抛投.new()


func _ready() -> void:
	_底半高 = _量底半高()
	_抛投.底半高 = _底半高
	_抛投.半宽 = _量半宽()
	_抛投.重力 = 下落重力
	_抛投.最大速度 = 最大下落速度
	_抛投.地面层 = 地面层
	set_physics_process(not 被扛着)
	Director.register_thing(编号, self)


## 按键进来：有人要搬我。接不接是这一件东西自己的事
func 被按键(键: String, 谁: Node) -> bool:
	if 键 != "interaction":
		return false
	if 已插:
		return false   # 已经焊在锁孔上的板子不该再被扛走
	if 谁 == null or not is_instance_valid(谁) or not 谁.has_method("扛起"):
		return false
	谁.扛起(self)
	return true


## 学生拿起/放下时调用。扛着的时候不跑重力，不然它会在人手里往下掉
func 设被扛着(扛: bool) -> void:
	被扛着 = 扛
	_下落速度 = 0.0
	_站住了 = false
	_抛投.在飞 = false
	set_physics_process(not 扛)
	if not 扛:
		_落(0.0)   # 放下的那一瞬间先探一次脚下，别先往下掉一格才回过神来


## 被学生抛出去：沿 `方向` 走一段抛物线，水平落点力求正好是 `平抛距离`。
## 抛物线本身在 `组件/抛投/`，和「队友被扔出去」共用同一份。
## `地面y` 由学生给（他脚底就是脚下那块地）：拖行档的箱子本来就贴着地，
## 从箱子自己身上打射线会从地面下方穿出去，量到平台底面，高度就错了。
## 距离 ≤ 2px 当作原地放下，直接交给 `_落` 自己掉。
func 抛(方向: Vector2, 平抛距离: float, 地面y: float) -> void:
	if not _抛投.起飞(self, signf(方向.x), 平抛距离, 地面y):
		_站住了 = false
		_下落速度 = 0.0
		_落(0.0)
		return
	_站住了 = false
	_下落速度 = 0.0
	set_physics_process(true)
	print("[箱子] %s 被抛出：%.0fpx" % [编号, 平抛距离])


## 多重？学生扛起来时问这一句，拿去查重量档位表
func 取重量() -> float:
	return 重量


func _physics_process(delta: float) -> void:
	if 被扛着:
		return
	if _抛投.在飞:
		if _抛投.推进(self, delta):
			_下落速度 = 0.0
			_站住了 = true
			_复查倒计时 = 0.2
		return
	# 已经贴着地了：不用每帧算，每 0.2 秒复查一次脚下（被搬到空中时会自己发现）
	if _站住了:
		_复查倒计时 -= delta
		if _复查倒计时 > 0.0:
			return
		_复查倒计时 = 0.2
	_落(delta)


func _落(delta: float) -> void:
	var 命中 := _抛投.探脚下(self, maxf(_下落速度 * delta, 0.0) + 2.0)
	if 命中.is_empty():
		# 脚下空的：加速下落
		_站住了 = false
		_下落速度 = minf(_下落速度 + 下落重力 * delta, 最大下落速度)
		global_position.y += _下落速度 * delta
	else:
		# 踩到地了：把底边对齐到地面，然后进入「每 0.2 秒看一眼」的低耗状态
		global_position.y = float(命中["position"].y) - _底半高
		_下落速度 = 0.0
		_站住了 = true
		_复查倒计时 = 0.2


## 中心到底边有多远。碰撞体和贴图不一样大时取大的那个，免得视觉陷进地里
func _量底半高() -> float:
	var 半 := 8.0
	var col := get_node_or_null("CollisionShape2D")
	if col != null and col.shape is RectangleShape2D:
		半 = (col.shape as RectangleShape2D).size.y * 0.5
	var spr := get_node_or_null("Sprite2D")
	if spr != null and spr.texture != null:
		半 = maxf(半, spr.texture.get_height() * spr.scale.y * 0.5)
	return 半


## 中心到左右边有多远。飞行时探墙用：贴图再大也按碰撞体算
func _量半宽() -> float:
	var 半 := 8.0
	var col := get_node_or_null("CollisionShape2D")
	if col != null and col.shape is RectangleShape2D:
		半 = (col.shape as RectangleShape2D).size.x * 0.5
	return 半
