extends Node2D
## 物件代理 —— 全场景只有一个。开局读物件清单，照单建出所有交互物，
## 每建一件就在总管登记编号；之后的交互由总管按编号转发（见 场景总管.gd）。
## 加新物件：`类型场景` 加一行 + `_配置` 的 match 里加 setup 分支。
## 清单每条必须写「编号 + 类型」两栏，缺任一个当场报错。

## 类型 → 场景。**加新物件只改这一张表**
const 类型场景 := {
	"门": preload("res://交互物/门/门.tscn"),
	"钥匙板": preload("res://交互物/钥匙板/钥匙板.tscn"),
	"锁口": preload("res://交互物/锁口/锁口.tscn"),
	"出口": preload("res://交互物/出口/出口.tscn"),
	"检修口": preload("res://交互物/检修口/检修口.tscn"),
	"箱子": preload("res://交互物/可搬运箱子/可搬运箱子.tscn"),
	"道具": preload("res://交互物/可使用物品/可使用物品.tscn"),
	# 梯子：图块只画了外观，能爬靠这个判定框
	"梯子": preload("res://交互物/梯子/梯子.tscn"),
}

## 用哪张清单（.gd 路径），每张地图自己声明（正式图用 `数据/正式/`，测试布景用 `数据/测试/`）。
## 必须填路径而非 Script 资源：后者存进 .tscn 会静默失效。
## 导出属性名一律用英文，中文名在 .tscn 里赋值会静默失效。
@export_file("*.gd") var list_path: String = ""

## 这张图一共建出来几件（自测和排查用）
var 已建数: int = 0


func _ready() -> void:
	# 漏填就当场报错，不退回任何「默认表」，避免悄悄读成别的图
	if list_path == "":
		push_error("[物件代理] 没填 list_path —— 每张地图都必须自己声明用哪份清单")
		return
	var 装 = load(list_path)
	if not (装 is Script):
		push_error("[物件代理] 清单路径读不出脚本：%s" % list_path)
		return
	var 表: Dictionary = 装.物件
	_照单建(表)
	print("[物件代理] 照清单建了 %d 件（清单里一共 %d 条）" % [已建数, 表.size()])


## 照单全部建出来。一件建失败只报错那一条，不影响其他条目。
func _照单建(表: Dictionary) -> void:
	for 编号 in 表:
		var 条目: Dictionary = 表[编号]
		_建一件(str(编号), 条目)


func _建一件(编号: String, 条目: Dictionary) -> void:
	var 类型: String = str(条目.get("类型", ""))
	if 类型 == "":
		push_error("[物件代理] 「%s」没写「类型」，不知道该建什么" % 编号)
		return
	var 场: PackedScene = 类型场景.get(类型, null)
	if 场 == null:
		push_error("[物件代理] 「%s」的类型是「%s」，但代理不认识这种（认识的：%s）" % [
			编号, 类型, 类型场景.keys()])
		return
	if not 条目.has("位置"):
		push_error("[物件代理] 「%s」没写「位置」" % 编号)
		return

	var 物: Node2D = 场.instantiate()
	# 编号要在 add_child **之前** 盖上：add_child 那一刻 _ready 就跑，晚了登记成空编号
	if "编号" in 物:
		物.set("编号", 编号)
	add_child(物)
	_配置(物, 类型, 编号, 条目)
	Director.register_thing(编号, 物)
	已建数 += 1


## 按类型喂参数：把清单里人类可读的键翻译成各物件 setup() 的参数（唯一去处）
func _配置(物: Node2D, 类型: String, 编号: String, 条目: Dictionary) -> void:
	var 位置: Vector2 = 条目["位置"]
	match 类型:
		"门":
			# 用时 = 默认（通用规则）+ 这一扇的覆盖。规则不属于任何一张图。
			# 空气墙：看不见门板、E 推不动的死墙（大门用，画面以后由美术在图上拼）
			物.setup(位置, 规则.开门用时(条目), bool(条目.get("空气墙", false)))
		"钥匙板":
			# 颜色从规则表取 —— 和门上的锁孔是同一份，不会「钥匙黄、孔红」
			物.setup(位置, 规则.钥匙板配色.get(编号, Color.WHITE))
		"锁口":
			物.setup(
				位置,
				float(条目.get("插孔用时", 2.0)),
				str(条目.get("连哪扇门", ""))
			)
		"出口":
			# 判定区大小/偏移按张可选：给了才覆盖，没给就沿用出口场景里摆好的那一块
			物.setup(位置, str(条目.get("等的门", "")))
			if 条目.has("判定区大小"):
				物.改判定区大小(条目["判定区大小"])
			if 条目.has("判定区偏移"):
				物.改判定区偏移(条目["判定区偏移"])
		"检修口":
			物.setup(位置.x, 位置.y, float(条目.get("宽", 32.0)))
		"梯子":
			# 图上已经画了梯子时 `显示贴图` 留 false：再叠一张 `梯子.png` 会错位
			物.setup(
				位置,
				float(条目.get("高", 300.0)),
				float(条目.get("宽", 32.0)),
				bool(条目.get("显示贴图", false))
			)
		"箱子", "道具":
			# 这两样只要摆对位置，其余参数在场景里（重量、贴图）
			物.position = 位置
		_:
			# 类型表里认识的，这里没写配置 = 新加类型时漏了一步
			push_error("[物件代理] 类型「%s」没有配置分支，%s 摆不上（在 _配置 里补一段）" % [
				类型, 编号])


## 全局规则：**对所有地图生效**的那份数（开门用时、钥匙板配色/编号）。
## 和清单分开：清单只属于某一张图，规则属于整个工程。
const 规则 = preload("res://数据/通用规则.gd")
