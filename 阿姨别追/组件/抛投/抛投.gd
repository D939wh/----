extends RefCounted
## 抛投 —— 抛物线飞行：给定「想飞多远」，反解 45° 出手初速，再逐小步推进位置。
##
## 【它管什么】只算位移：撞墙就贴墙往下掉，探到地面就停。
##   落地之后怎么收尾（恢复碰撞、切状态、进入贴地待机）是宿主自己的事 ——
##   这个文件里没有一句在判断游戏规则；地面在哪一层由宿主设 `地面层`。
##
## 【谁在用】可搬运箱子（`可搬运箱子.gd` 的 `抛()`）、学生（被队友扔出去）。
##   两边用同一个重力、同一个出手角，所以「箱子怎么飞」和「人怎么飞」是同一套数。

const 出手角 := 0.70710678   # 45° 的正弦 / 余弦
const 每步上限 := 6.0        # 一帧的位移拆成 ≤6px 的小步，免得穿过墙和地板

var 重力: float = 900.0
var 最大速度: float = 700.0      # 再快也不会穿地：一帧最多 700/60 ≈ 12px
var 底半高: float = 0.0          # 原点离底边多远：学生原点在脚底 → 0；箱子在中心 → 半高
var 半宽: float = 8.0
var 地面层: int = 1              # 探地面 / 探墙认哪层（宿主照规则表设，这里不写死）

var _速度: Vector2 = Vector2.ZERO
var 在飞: bool = false


## 起飞。`平抛距离` 从出手点算起；≤2px 当作原地放下，返回 false。
## `横` = 往哪边（±1）。`地面y` 由调用方给：贴着地的东西从自己身上打射线，
## 会从地面下方穿出去、量到地板底面，高度就错了。
func 起飞(宿主: Node2D, 横: float, 平抛距离: float, 地面y: float) -> bool:
	在飞 = false
	if 平抛距离 <= 2.0:
		return false
	if 横 == 0.0:
		横 = 1.0
	# 出手点离地多高？越高飞得越远，所以要把这段补进公式。
	var 离地 := 地面y - (宿主.global_position.y + 底半高)
	if 离地 < 0.0:
		宿主.global_position.y = 地面y - 底半高   # 拖行档本来就压在地里，出手前先抬到地面
		离地 = 0.0
	var v := _初速(平抛距离, 离地)
	_速度 = Vector2(signf(横) * v * 出手角, -v * 出手角)
	在飞 = true
	return true


## 45° 出手时 d = v²/g；起点有高度 h 就更远，迭代几次把 v 收回来。
## 「向上」的初速是正数（Godot 里 y 向下为正，落到 `_速度` 时才写负号）。
func _初速(平抛距离: float, 离地: float) -> float:
	var v := sqrt(平抛距离 * 重力)
	for _i in 6:
		var 上 := v * 出手角
		var 落地用时 := (上 + sqrt(上 * 上 + 2.0 * 重力 * 离地)) / 重力
		var 落点 := 上 * 落地用时
		if 落点 <= 0.01:
			break
		v *= sqrt(平抛距离 / 落点)
	return v


## 推进一帧。返回 true = 这一帧落地了（`在飞` 已置 false，宿主自己收尾）。
func 推进(宿主: Node2D, delta: float) -> bool:
	if not 在飞:
		return false
	_速度.y = minf(_速度.y + 重力 * delta, 最大速度)
	var 位移 := _速度 * delta
	var 步数 := maxi(1, ceili(位移.length() / 每步上限))
	var 步 := 位移 / float(步数)
	for _i in 步数:
		if absf(步.x) > 0.001 and _撞墙(宿主, 步.x):
			_速度.x = 0.0            # 撞墙就贴在墙上往下掉，不穿过去
		else:
			宿主.global_position.x += 步.x
		# 只有往下走才看地面：刚出手时向上抛，脚下 2px 就报落地，会立刻停住
		if 步.y > 0.0:
			var 命中 := 探脚下(宿主, 步.y + 2.0)
			if not 命中.is_empty():
				宿主.global_position.y = float(命中["position"].y) - 底半高
				_速度 = Vector2.ZERO
				在飞 = false
				return true
		宿主.global_position.y += 步.y
	return false


## 从身体底边往下探一条射线（空字典 = 脚下是空的）。
## 自由落体也用得上，所以是公开的。
## 排除宿主自己：学生自己就站在「地板层」，不排除的话射线一出手就撞在自己身上。
func 探脚下(宿主: Node2D, 探距: float) -> Dictionary:
	var 起点 := 宿主.global_position + Vector2(0.0, 底半高 - 2.0)
	var 查询 := PhysicsRayQueryParameters2D.create(
		起点, 起点 + Vector2(0.0, maxf(探距, 0.0) + 2.0), 地面层)
	查询.collide_with_areas = false    # 只认实心地面，不认梯子/道具这些感应区
	查询.collide_with_bodies = true
	var 排出: Array[RID] = [宿主.get_rid()]
	查询.exclude = 排出
	return 宿主.get_world_2d().direct_space_state.intersect_ray(查询)


## 这一步会不会撞到墙。只认实心块，不认感应区。
func _撞墙(宿主: Node2D, 步长: float) -> bool:
	var 起点 := 宿主.global_position + Vector2(signf(步长) * 半宽, 0.0)
	var 查询 := PhysicsRayQueryParameters2D.create(
		起点, 起点 + Vector2(步长, 0.0), 地面层)
	查询.collide_with_areas = false
	查询.collide_with_bodies = true
	var 排出: Array[RID] = [宿主.get_rid()]
	查询.exclude = 排出
	return not 宿主.get_world_2d().direct_space_state.intersect_ray(查询).is_empty()
