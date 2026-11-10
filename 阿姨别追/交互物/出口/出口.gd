extends Area2D
## 出口 —— 门被三块钥匙板真正解锁之后，学生自己走到门外侧、站够 1 秒就算他赢。
##
## 门开没开：只听说对局账本 `Match.door_unlocked`，不和门直接耦合 ——
## 按 E 推开的门也会发 `door_finished`，但那条广播胜负不认。
## 判完一个就复位继续等下一个人：后跑出去的队友也能各拿各的胜利。

const 读条脚本 := preload("res://界面/读条/读条.gd")
## 全工程规则（物理层位掩码）。`_ready` 里配碰撞掩码要用。
const 规则 := preload("res://数据/通用规则.gd")
## 声音表：合闸是 4 档（「极大」）—— 主人定「读条就是最大的声音」。
const 声音表 := preload("res://数据/声音表.gd")

## 合闸读条多久响一声（秒）。不是响一次，是整段一直在响 ——
## 逃出是「全队大事」，宿管该被持续吸过来，而不是被响一声引过来后又走开。
const 合闸发声间隔: float = 0.6

## 赢家横幅挂多久后自动收起（秒）。不做全屏结算，只当一条提示
const 提示时长: float = 2.0

## 站够几秒算逃出去。策划案 §3.3 写的 1 秒
@export var 逃出用时: float = 1.0

## 这个出口的身份证。由物件代理照清单盖章，或在检查器里手填
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 中文别名：全工程代码统一用「编号」读写，和 `thing_id` 是同一个值
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

## 我在等哪扇门（写的是那扇门的**编号**）。它被解锁我才有用
var _等哪扇门: String = ""

## 门外在哪个方向：+1 = 右（+x）/ -1 = 左。由物件代理照清单填
var _出门方向: float = 1.0

var _启用中: bool = false
var _谁: Node = null            # 现在站在门口的这个人
var _进度: float = 0.0
var _扔进来的: bool = false     # 这次是被人扔进区域的：作废，得离开再自己走进来
var _读条: CanvasLayer = null
var _合闸计时: float = 0.0      # 离下一声「合闸」还有多久
var _提示代号: int = 0          # 提示的「这一根」编号，旧的到期不许收掉新的


func _ready() -> void:
	collision_layer = 0
	# 只负责「看见人」：站着的（地板层）和瘫在地上的（瘫痪层）。
	# 层号问规则要，不写死数字
	collision_mask = 规则.层_地板 | 规则.层_瘫痪
	Match.door_unlocked.connect(_on_door_unlocked)
	Director.register_thing(编号, self)
	$HUD/提示.visible = false


## 由物件代理照清单调用（编号由代理在 add_child 前盖好）
func setup(pos: Vector2, 门号: String, 用时: float = 1.0, 出门方向: float = 1.0) -> void:
	position = pos
	_等哪扇门 = 门号
	逃出用时 = 用时
	_出门方向 = signf(出门方向) if 出门方向 != 0.0 else 1.0


## 只有「三块钥匙板插满」才算解锁。推开的门不算 —— 胜负只认账本这一条
func _on_door_unlocked(哪扇门: String) -> void:
	if 哪扇门 != _等哪扇门:
		return
	_启用中 = true
	print("[出口] %s 的门被解锁，站 %.1f 秒就算逃出去" % [哪扇门, 逃出用时])


func _physics_process(delta: float) -> void:
	if not _启用中:
		return

	var 人 := _站在里面的人()
	# 必须在门外侧才计时：退到门内、或正站在门线上，读条清零
	if 人 == null or not _在门外侧(人):
		_取消()
		return

	if 人 != _谁:
		# 换了个人站进来（或者第一次站进来）：重新从 0 数
		_取消()
		_谁 = 人
		_扔进来的 = 人.has_method("在飞") and 人.在飞()
		if _扔进来的:
			return      # 被人扔进来的不算；要离开区域、自己再走进来才重新开始
		# 读条建一次反复用：「收」只是藏起来不销毁，下次有人站进来接着摆出来
		if _读条 == null or not is_instance_valid(_读条):
			_读条 = 读条脚本.新建(self)
		# 跟谁传 null = 摆在屏幕下方正中。逃出是「全队的大事」，不挂在某个人头上
		_读条.开始(null, "逃出", 逃出用时)

	# 这次是「飞进来的」：原地站着也不算，得先离开区域
	if _扔进来的:
		return

	_进度 += delta
	# 合闸整段都在响：隔 `合闸发声间隔` 一声，直到读条走完。
	# 4 档 = 全图最响，宿管在 900px 外都听得见 —— 这就是「最后一步最危险」。
	_合闸计时 -= delta
	if _合闸计时 <= 0.0:
		_合闸计时 = 合闸发声间隔
		Events.发声(global_position, 声音表.档_极大, 声音表.来源_合闸)
	if _读条 != null:
		_读条.推进(_进度)
	if _进度 >= 逃出用时:
		_赢了(人)


## 站在里面、还没瘫、也还没逃出去的那个学生。
## 只认 `student` 组：宿管同样站在地板层，不筛组会把她算成逃出者。
func _站在里面的人() -> Node:
	for body in get_overlapping_bodies():
		if not body.is_in_group("student"):
			continue
		if Match.escaped.has(body):
			continue
		if body.has_method("拉起") and not body.瘫痪:
			return body
	return null


## 人在门线的哪一边。只有门外侧才推进读条
func _在门外侧(人: Node) -> bool:
	return (人.global_position.x - global_position.x) * _出门方向 > 0.0


func _取消() -> void:
	# 只收（藏）不删、也不清引用：这根条建一次反复用，下次有人站进来直接再摆出来
	if _读条 != null and is_instance_valid(_读条):
		_读条.收()
	_进度 = 0.0
	_谁 = null
	_扔进来的 = false
	_合闸计时 = 0.0     # 下次站进来立刻响第一声


## 一个人站够了：上报账本 → 复位继续等下一个人。游戏不结束、不冻结全场
func _赢了(人: Node) -> void:
	_取消()
	if 人 != null and Match.register_escape(人):
		_喊赢家(人)


## 赢家横幅：复用出口场景里现成的 Label，显示 2 秒后自动收起
func _喊赢家(人: Node) -> void:
	var 标签: Label = $HUD/提示
	标签.text = "%s 逃出去了（赢）" % 人.name
	标签.visible = true
	_提示代号 += 1
	var 我的 := _提示代号
	await get_tree().create_timer(提示时长).timeout
	# 中间又有人逃出 / 节点已被释放：这一根作废，别把新的那条收掉
	if _提示代号 != 我的 or not is_instance_valid(标签):
		return
	标签.visible = false
