extends Area2D
## 可使用物品 —— 捡了直接进右下角格子（蓝图；今天捡了没有任何效果）
##
## 【为什么 2026-11-06 才给它补一个脚本】
##   以前它靠"属于 usable_item 组"被代理认出来，自己一行代码都没有。
##   按编号重构之后，每件东西都要**报编号**、都要**自己认键**（谁按 F 才归谁管），
##   没有脚本就没有这两样东西 —— 于是它成了"摆在那儿但谁都捡不起来"的哑巴。
##   现在：`_ready` 报到，`被按键` 说「F 归我」。
##
## 【它仍然不知道学生是谁】`谁.收起道具(self)` 只是一句请求，
##   收不收得下（身上格子满了）由学生自己回答。

## 这件东西的身份证。由物件代理照清单盖章，或在检查器里手填
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

## 交互优先级：道具 0 < 箱子 10 —— 两件挤在一起时先搬箱子
@export var 互动优先级: int = 0


func _ready() -> void:
	Director.register_thing(编号, self)


## 按键进来：F 键归我（捡起来）。其余键不归我管，返回 false 让别人接着问
func 被按键(键: String, 谁: Node) -> bool:
	if 键 != "interaction":
		return false
	if 谁 == null or not is_instance_valid(谁) or not 谁.has_method("收起道具"):
		return false
	return 谁.收起道具(self)
