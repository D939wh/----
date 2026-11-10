extends Area2D
## 出口 —— 门被三块钥匙板真正解锁之后，求生者一碰到判定区就算他赢。
##
## 【判定区摆哪、多大，地图说了算】代码不挪它、不改它：
##   清单里用「判定区大小 / 判定区偏移」两个字段按张调；
##   也可以直接把出口拖进场景，在编辑器里改 CollisionShape2D，想怎么摆就怎么摆。
## 【它和门是分开的】出口只听对局账本 `Match.door_unlocked` 的广播，不认识门本体；
##   门负责物理上堵路（空气墙），出口只负责「等到真解锁 + 碰到即赢」。
## 按 E 推开的门也会发 `door_finished`，但胜负只认真解锁，不认那条广播。
## 判完一个就复位继续等下一个人：后跑出去的队友也能各拿各的胜利。

## 全工程规则（物理层位掩码）。`_ready` 里配碰撞掩码要用。
const 规则 := preload("res://数据/通用规则.gd")
## 声音表：合闸是 4 档（「极大」）—— 逃出是全队大事，全图都听得见
const 声音表 := preload("res://数据/声音表.gd")

## 赢家横幅挂多久后自动收起（秒）。不做全屏结算，只当一条提示
const 提示时长: float = 2.0

## 这个出口的身份证。由物件代理照清单盖章，或在检查器里手填。
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 我在等哪扇门（填那扇门的**编号**），它被真正解锁我才有用。
## 手摆进场景的出口在检查器里填；清单建的由 setup() 写进来。
## 必须用英文名 gate_id 导出 —— 同上。
@export var gate_id: String = ""

## 中文别名：全工程代码统一用「编号 / 等的门」读写
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

var 等的门: String:
	get:
		return gate_id
	set(值):
		gate_id = 值

var _启用中: bool = false
var _提示代号: int = 0          # 提示的「这一根」编号，旧的到期不许收掉新的


func _ready() -> void:
	collision_layer = 0
	# 只负责「看见人」：站着的（地板层）和瘫在地上的（瘫痪层）。
	# 层号问规则要，不写死数字
	collision_mask = 规则.层_地板 | 规则.层_瘫痪
	Match.door_unlocked.connect(_on_door_unlocked)
	Director.register_thing(编号, self)
	$HUD/提示.visible = false


## 由物件代理照清单调用（编号由代理在 add_child 前盖好）。
## 只管「站哪、等哪扇门」；判定区大小/偏移另走「改判定区大小 / 改判定区偏移」，
## 清单没给就保持出口场景里摆好的那一块
func setup(pos: Vector2, 门号: String) -> void:
	position = pos
	等的门 = 门号


## 判定区多大：Vector2(宽, 高)。先复制一份形状再改 —— 一张图几个出口各改各的，不串门
func 改判定区大小(大小: Vector2) -> void:
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	$CollisionShape2D.shape.size = 大小


## 判定区中心相对出口锚点挪多少：Vector2(x, y)，y 负 = 往上。不写就不挪
func 改判定区偏移(偏移: Vector2) -> void:
	$CollisionShape2D.position = 偏移


## 只有「三块钥匙板插满」才算解锁。推开的门不算 —— 胜负只认账本这一条
func _on_door_unlocked(哪扇门: String) -> void:
	if 哪扇门 != 等的门:
		return
	_启用中 = true
	print("[出口] %s 的门被解锁，碰到判定区就算逃出去" % 哪扇门)


func _physics_process(_delta: float) -> void:
	if not _启用中:
		return

	# 求生者一碰到就算赢：不读条、不挑姿势 —— 被队友扔进来、扛进来放下、
	# 瘫着被拖进来都算。判完一个继续等下一个，游戏不结束
	for body in get_overlapping_bodies():
		if not body.is_in_group("student"):
			continue
		if Match.escaped.has(body):
			continue
		赢了(body)
		return


## 一个人碰到了：上报账本继续等下一个人。游戏不结束、不冻结全场
func 赢了(人: Node) -> void:
	# 逃出是「全队大事」：响一声最大档的合闸，宿管全图都听得见
	Events.发声(global_position, 声音表.档_极大, 声音表.来源_合闸)
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
