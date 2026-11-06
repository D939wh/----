extends Node2D
## 锁口 —— 门板上那排锁孔。三个孔各认一块钥匙板，插满三块门就开
## 插钥匙的进度由这里数（`_进度` 是真源，读条只负责画）。
## 插满后按编号上报总管开门，不直接引用门节点。

const 读条脚本 := preload("res://界面/读条/读条.gd")
## 编号和配色是**全工程共用**的，不属于哪张地图 —— 所以读 `通用规则.gd`，不读地图清单
const 规则 = preload("res://数据/通用规则.gd")

## 孔是灭的时候的颜色
const 暗色 := Color(0.10, 0.10, 0.12, 1.0)

## 必须拿对牌子的那个孔吗？
##   true  = 一号只认一号孔（策划案 v0.5 的规则）
##   false = 随便哪个空孔都能插，凑满三个就行（策划案说的「这条可关」）
## 改这一个开关就退化，代码不用动。
@export var 要求配对: bool = true

## 这个锁口的身份证（"1-门厅" 这种）。由物件代理照清单盖章，或在检查器里手填
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
@export var thing_id: String = ""

## 中文别名：全工程代码统一用「编号」读写，和 `thing_id` 是同一个值
var 编号: String:
	get:
		return thing_id
	set(值):
		thing_id = 值

## 交互优先级（同位置多件东西时数字大的先问；锁口和门都是 0）
@export var 互动优先级: int = 0

var _插孔用时: float = 2.0      # 由代理照这张图的清单填。0.1 基本等于按一下就进
var _连哪扇门: String = ""      # 插满时开哪扇门（名字，不是节点）

## 编号 -> { "亮": bool, "色": Color, "节点": Polygon2D }
var _孔: Dictionary = {}

## 这一次插的进度。0 = 没在插
var _进行中: bool = false
var _谁: Node = null            # 谁在插
var _在读: Area2D = null        # 手上那块板子
var _本次孔: String = ""        # 这一次插的是哪个孔
var _进度: float = 0.0
var _读条: CanvasLayer = null


func _ready() -> void:
	# 报到：总管拿编号就能找到这个锁口（三孔插满时要按编号找门，也是靠这本账）
	Director.register_thing(编号, self)
	# 场景里固定摆着三个孔节点（孔1/孔2/孔3），这里把它们和编号对起来。
	# 颜色从 `通用规则.gd` 取 —— 和钥匙板铁牌是同一份，不会出现「钥匙黄、孔红」。
	var i := 0
	for 号 in 规则.钥匙板编号:
		var 节点 := get_node_or_null("孔%d" % (i + 1)) as Polygon2D
		if 节点 != null:
			节点.color = 暗色
			_孔[号] = {
				"亮": false,
				"色": 规则.钥匙板配色.get(号, Color.WHITE),
				"节点": 节点,
			}
		i += 1


## 由物件代理按清单调用：站哪、插一块要几秒、插满开哪扇门
## （编号由代理在 add_child 之前盖好，见 物件代理.gd）
func setup(pos: Vector2, 用时: float, 门: String) -> void:
	position = pos
	_插孔用时 = maxf(用时, 0.01)
	_连哪扇门 = 门


## 按键进来：只认「插钥匙」，其余不归我管
func 被按键(键: String, 谁: Node) -> bool:
	if 键 != "insert_key":
		return false
	return 插(谁)


## 有人按 R 想插钥匙。返回 true = 接下了（开始读条）。先查牌子/孔位再读条
func 插(谁: Node) -> bool:
	if _进行中:
		return false   # 已经在插了，再按一次 R 不该重来
	if 谁 == null or not is_instance_valid(谁):
		return false

	var 货: Node = null
	if 谁.has_method("手上扛着"):
		货 = 谁.手上扛着()
	if 货 == null:
		print("[锁口] %s：空着手插不了" % 编号)
		return false

	var 号 := str(货.get("编号"))
	if 号 == "":
		print("[锁口] %s：扛的不是钥匙板" % 编号)
		return false

	var 孔号 := _选孔(号)
	if 孔号 == "":
		if _孔.has(号) and bool(_孔[号]["亮"]):
			print("[锁口] %s：%s 的孔已经插过了，这门上没别的位置给它" % [编号, 号])
		else:
			print("[锁口] %s：这块是「%s」，这门上没这个孔" % [编号, 号])
		return false

	_进行中 = true
	_谁 = 谁
	_在读 = 货
	_本次孔 = 孔号
	_进度 = 0.0
	if 谁.has_method("钉住"):
		谁.钉住(true)          # 插的过程中人不能动
	# 优先借「谁」自己的读条（插钥匙/救人共用一根），没有才现造一根
	if 谁.has_method("借读条"):
		_读条 = 谁.借读条()
	else:
		_读条 = 读条脚本.新建(self)
	_读条.开始(谁, "插钥匙", _插孔用时)
	print("[锁口] %s 开始插「%s」（%.1f 秒）" % [编号, 号, _插孔用时])
	return true


func _process(delta: float) -> void:
	if not _进行中:
		return

	# 插到一半，人没了 / 被打瘫了 / 玩家换人了 → 这次作废
	if not is_instance_valid(_谁) or _谁.瘫痪 or not _还受控():
		_中断("插钥匙的人没了 / 被打断了 / 被切走了")
		return

	_进度 += delta
	if _读条 != null:
		_读条.推进(_进度)
	if _进度 >= _插孔用时:
		_完成()


## 现在是不是玩家还在操作「插钥匙的那个人」
func _还受控() -> bool:
	var 控: Node = Director.当前控制
	return 控 == null or 控 == _谁


## 这块板子该插哪个孔。返回 "" = 插不进去
func _选孔(号: String) -> String:
	if 要求配对:
		if not _孔.has(号):
			return ""
		if bool(_孔[号]["亮"]):
			return ""
		return 号
	# 不要求配对：从左往右找第一个空孔
	for k in _孔:
		if not bool(_孔[k]["亮"]):
			return k
	return ""


func _完成() -> void:
	var 谁 := _谁
	var 孔号 := _本次孔

	_收场()          # 先把进度、读条、钉住清干净，再做「插上了」这件事

	if _孔.has(孔号):
		_孔[孔号]["亮"] = true
		(_孔[孔号]["节点"] as Polygon2D).color = _孔[孔号]["色"]

	# 板子从手上消失：人回到空手状态，铁牌钉在孔上（孔亮起就是它）
	var 货: Node = null
	if is_instance_valid(谁) and 谁.has_method("交出搬运物"):
		货 = 谁.交出搬运物()
	if 货 == null and is_instance_valid(_在读):
		货 = _在读
	if 货 != null and is_instance_valid(货):
		货.queue_free()

	print("[锁口] %s 插上「%s」，%d/%d" % [编号, 孔号, _亮孔数(), _孔.size()])

	if _亮孔数() >= _孔.size() and _孔.size() > 0:
		_全插满()


func _全插满() -> void:
	print("[锁口] %s 三个孔都插满了，开「%s」" % [编号, _连哪扇门])
	# 按编号递给总管，由总管找到那扇门去开；门不在时 report 会报红，不静默失败
	Director.report(_连哪扇门, "unlock", { "锁口": 编号 })


func _中断(原因: String) -> void:
	print("[锁口] %s 插到一半断了：%s" % [编号, 原因])
	_收场()


## 把「正在插」这件事清干净。完成和中断都走这里
func _收场() -> void:
	if is_instance_valid(_谁) and _谁.has_method("钉住"):
		_谁.钉住(false)
	if _读条 != null and is_instance_valid(_读条):
		_读条.收()
	_读条 = null
	_进行中 = false
	_进度 = 0.0
	_谁 = null
	_在读 = null
	_本次孔 = ""


func _亮孔数() -> int:
	var n := 0
	for k in _孔:
		if bool(_孔[k]["亮"]):
			n += 1
	return n


## 给外部查：这个锁口插了几块了
func 已插数() -> int:
	return _亮孔数()
