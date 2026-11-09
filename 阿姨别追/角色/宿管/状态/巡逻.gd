extends "res://组件/状态机/状态.gd"
## 巡逻 —— 没看见人时的走位：在出生点左右各 `巡逻半径` 之间来回走。
##
## 走到巡逻点就掉头；撞墙 / 到崖边也掉头，别原地踏步（跟参考项目一个写法）。
## 看见人了同样交给 `decide()`，不在这里自己判断「要不要追」。

const 状态名 := preload("res://角色/宿管/状态/状态名.gd")

## 走到离目标点这么近就算到了，可以掉头（像素）。太小会在端点上来回抖。
const 到位判定: float = 12.0


func 进入(_上个: String = "") -> void:
	# 出生点就是巡逻中心。每次重新进这个状态时记一遍，被人推走了也能拉回来。
	host._巡逻起点 = host.global_position


func 每帧(delta: float) -> void:
	var h = host

	# 看见人 → 交回决策（`decide()` 会给出追击）
	if h._看得见的目标() != null:
		机器().切(h.decide())
		return

	var 目标横坐标: float = h._巡逻起点.x + h.巡逻半径 * h._巡逻方向
	if absf(h.global_position.x - 目标横坐标) < 到位判定:
		h._巡逻方向 = -h._巡逻方向
		return

	# 走一步。撞墙 / 到崖边 → 掉头（返回值就是这么用的）
	if not h._朝目标走(目标横坐标, h.巡逻速度, delta):
		h._巡逻方向 = -h._巡逻方向
