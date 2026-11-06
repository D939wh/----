extends Node2D
## 检修口 —— 楼板上一个缺口，上面盖着一块单向平台
##
## 只负责按清单把自己摆到位置上。踩得住、按 S 穿下去由引擎负责：
##   盖板在第 2 层「可以穿过的地板」+ One Way；按 S 摘层见 `student.gd`。
## 不在此绘制外观；美术放场景里的渲染节点。
## 盖板单独占第 2 层（层号在 `数据/通用规则.gd`）：摘层时只放开它，墙和楼板不动。

## 全局规则。层号从那里取，这里不许写死 5 或 16
const 规则 := preload("res://数据/通用规则.gd")

## 盖板的碰撞形状厚度（像素）。**只是几何尺寸，不决定能不能穿。**
## 上表面压在节点原点（清单里的 y 填的就是「地面那条线」）。
const 盖板厚度: float = 6.0

## 半宽（像素）。由 setup 按清单给的宽度算
var 半宽: float = 16.0

## 这个检修口的身份证（"4-检修口" 这种）。由物件代理照清单盖章，或在检查器里手填。
## 不参与按键（按 S 是学生自己摘物理层）；编号只用于总管按号查找。
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 中文别名：全工程代码统一用「编号」读写，和 `thing_id` 是同一个值
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值


func _ready() -> void:
	Director.register_thing(编号, self)


## 由物件代理照清单调用：中心 x、地面 y（= 盖板**上表面**的 y）、宽度
func setup(中心x: float, 地面y: float, 宽: float) -> void:
	position = Vector2(中心x, 地面y)
	name = "检修口_%d_%d" % [int(中心x), int(地面y)]
	半宽 = 宽 * 0.5
	_改宽度(宽)


## 换宽度：形状重新造一个（RectangleShape2D 是共享资源，直接改 size 会波及别的口）
##
## 顺便把「属于哪一层、是不是单向」在这里落死一次：就算有人手滑改坏了 .tscn，
## 代理一摆出来也会被纠正回第 2 层 + 单向。层号来自规则，全工程只有一个数。
func _改宽度(宽: float) -> void:
	var 形 := RectangleShape2D.new()
	形.size = Vector2(宽, 盖板厚度)

	var 节点 := get_node_or_null("平台/CollisionShape2D") as CollisionShape2D
	if 节点 != null:
		# 形状中心压在 (0, +盖板厚度/2)，让**上表面**正好落在节点原点上 ——
		# 这样清单里的 y 填的就是「地面那条线」，和门、锁口的填法一致。
		节点.position = Vector2(0.0, 盖板厚度 * 0.5)
		# 单向：从下往上能穿过去（爬梯子不会撞头），从上往下踩得住
		节点.one_way_collision = true

	var 平台 := get_node_or_null("平台") as StaticBody2D
	if 平台 != null:
		平台.collision_layer = 规则.层_可穿过地板
		平台.collision_mask = 0
