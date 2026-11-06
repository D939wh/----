extends Area2D
## 可使用物品 —— 捡了直接进右下角格子（蓝图，暂无使用效果）

## 这件东西的身份证。由物件代理照清单盖章，或在检查器里手填
## 必须用英文名 thing_id 导出 —— 中文名导出属性在 `.tscn` 里赋值会静默失效。
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
