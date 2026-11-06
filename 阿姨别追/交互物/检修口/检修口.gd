extends Node2D
## 检修口 —— 地板缺口上盖着的一块单向平台
##
## 【它只干一件事】站着踩得住；这一层的代理喊一声「开」，它就放开 0.4 秒，
##   人从底下的缺口漏到下一层，然后自己关回去。
##
## 【为什么这 0.4 秒要留余量】放开以后人是「开始下落」而不是「瞬移」。
##   关得太早，身体还压在平台上，一恢复碰撞就会被顶回去（看起来像按了没用）；
##   按 GRAVITY 368、下落重力 ×2 算，0.4 秒能落 55 像素，身体高 44，刚够走干净。
##
## 【这个文件里没有一行画东西】
##   没有 Sprite2D、没有 Polygon2D、没有 ColorRect。检修口长什么样是美术的事，
##   要画就在场景里另外挂一个绘制节点（渲染层），不许长在这里 ——
##   框架 §6.6：光照与可见性不进组件。物理组件里长出美术，
##   以后换贴图得改物理脚本，调厚度会碰到画出来的东西，两件事永远分不开。
##
## 【物理层】平台在 16（第 5 层）。完整登记表在《阿姨别追了-整体技术框架》§4.2.2 ——
##   那份表是唯一真源，加层先去那里改；这里只记「我占第 5 位」。
##   单独占一层是为了「只放开它」：如果和墙（第 1 层）混在一起，
##   关掉碰撞的瞬间人会连墙一起穿过去。

## 放开多久（秒）。按上面那段推算，理论下限约 0.35，这里取 0.4 留余量
const 放开时长: float = 0.4

## 半宽（像素）。由 setup 按清单给的宽度算
var 半宽: float = 16.0

var _剩余: float = 0.0

@onready var _碰撞: CollisionShape2D = $平台/CollisionShape2D


## 由楼层代理照清单调用：中心 x、地面 y（= 平台**上表面**的 y）、宽度
func setup(中心x: float, 地面y: float, 宽: float) -> void:
	position = Vector2(中心x, 地面y)
	name = "检修口_%d_%d" % [int(中心x), int(地面y)]
	半宽 = 宽 * 0.5
	_改宽度(宽)


## 换宽度：形状重新造一个（RectangleShape2D 是共享资源，直接改 size 会波及别的口）
func _改宽度(宽: float) -> void:
	var 形 := RectangleShape2D.new()
	形.size = Vector2(宽, 6.0)
	var 节点 := get_node_or_null("平台/CollisionShape2D") as CollisionShape2D
	if 节点 != null:
		节点.shape = 形
		# 形状中心压在 (0, +3)，让**上表面**正好落在节点原点上 ——
		# 这样清单里的 y 填的就是「地面那条线」，和门、锁口的填法一致。
		节点.position = Vector2(0.0, 3.0)
		# 单向：从下往上能穿过去（爬梯子不会撞头），从上往下踩得住
		节点.one_way_collision = true


## 这个点算不算「站在这个口上」。由代理在收到 S 的时候问。
## 竖着给 12 像素余量：人站在平台上时脚底就在 y 附近，误差来自形状厚度和落地补偿。
func 能接住(点: Vector2) -> bool:
	return absf(点.x - global_position.x) <= 半宽 + 6.0 \
		and absf(点.y - global_position.y) <= 12.0


## 放开。代理调，人不用知道有这个东西
func 开() -> void:
	if _剩余 > 0.0:
		return   # 已经放开了，再按一次不该重新计时（不然按住 S 会无限延长）
	_剩余 = 放开时长
	if _碰撞 != null:
		_碰撞.set_deferred("disabled", true)
	set_process(true)


func _process(delta: float) -> void:
	if _剩余 <= 0.0:
		return
	_剩余 -= delta
	if _剩余 <= 0.0:
		_剩余 = 0.0
		if _碰撞 != null:
			_碰撞.set_deferred("disabled", false)
		set_process(false)
