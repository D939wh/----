extends Area2D
## 可搬运箱子 —— 会被扛起来，也会被放下；放下之后**自己受重力落回地面**
##
## 为什么不用 RigidBody2D（明明那个才有真物理）：
##   ① 学生是靠「感应区里有什么」找到它的，`get_overlapping_areas()` 只认 Area2D；
##   ② 被扛起来时要 reparent 到学生身上，变成跟着人走的子节点。
##   所以重力自己算：每帧朝下打一条很短的射线，探到地面就贴住、探不到就往下掉。
##
## 改重量：改下面这个 `重量`（或在编辑器里点箱子改）。80kg 按策划案属 **4 档**——
## 扛起来只能横向拖行、不能跳、不能爬梯。具体惩罚在 `数据/重量档位.gd` 那张表里。
## 档位是每 20 公斤一刀：1 档 ≤20 / 2 档 ≤40 / 3 档 ≤60 / 4 档 >60

@export var 重量: float = 80.0

## 这件东西的身份证（"1-箱子" 这种）。由物件代理照清单盖章，或在检查器里手填。
## 空编号 = 谁都找不到它 —— 学生按 F 也扛不起来，只会打一句警告。
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

## 交互优先级：同一位置挤着好几件东西时，数字大的先问。
## 箱子 10 > 道具 0 —— 站在箱子和道具中间按 F，先搬箱子（11-05 定的行为）
@export var 互动优先级: int = 10

const 下落重力: float = 900.0      # 像素/秒²。死物掉得比人干脆，别在空中飘
const 最大下落速度: float = 700.0  # 再快也不会穿地：一帧最多 700/60 ≈ 12px < 一格 16px
const 地面层: int = 1              # 地图 TileMapLayer 在第 1 层

## 已经插进锁孔了？插上之后这东西就不该再被扛起来（钥匙板才用得上，箱子永远 false）
var 已插: bool = false

var 被扛着: bool = false            # 学生拿起时置 true、放下置 false
var _下落速度: float = 0.0
var _底半高: float = 9.0            # 从箱子中心到底边的距离，落地对齐用
var _站住了: bool = false           # 已经贴着地面了
var _复查倒计时: float = 0.0        # 站住之后多久再看一眼脚下（别每帧都算）


func _ready() -> void:
	_底半高 = _量底半高()
	set_physics_process(not 被扛着)
	Director.register_thing(编号, self)


## 按键进来：有人要搬我。接不接是这一件东西自己的事
##
## 【为什么由箱子自己判断】学生只知道「我按了 F，我碰到编号 X」，
##   它不认识箱子、也不该认识。是箱子说「这键归我」，人才被喊去扛。
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
	set_physics_process(not 扛)
	if not 扛:
		_落(0.0)   # 放下的那一瞬间先探一次脚下，别先往下掉一格才回过神来


## 多重？学生扛起来时问这一句，拿去查重量档位表
func 取重量() -> float:
	return 重量


func _physics_process(delta: float) -> void:
	if 被扛着:
		return
	# 已经贴着地了：不用每帧算，每 0.2 秒复查一次脚下（被搬到空中时会自己发现）
	if _站住了:
		_复查倒计时 -= delta
		if _复查倒计时 > 0.0:
			return
		_复查倒计时 = 0.2
	_落(delta)


func _落(delta: float) -> void:
	var 起点 := global_position + Vector2(0.0, _底半高 - 2.0)
	var 探距 := maxf(_下落速度 * delta, 0.0) + 4.0
	var 查询 := PhysicsRayQueryParameters2D.create(
		起点, 起点 + Vector2(0.0, 探距), 地面层)
	查询.collide_with_areas = false    # 只认实心地面，不认梯子/道具这些感应区
	查询.collide_with_bodies = true
	var 命中 := get_world_2d().direct_space_state.intersect_ray(查询)

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
