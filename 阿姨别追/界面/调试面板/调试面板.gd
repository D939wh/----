extends CanvasLayer
## 开发者面板（2026-11-03 加）—— 左上角那小块，只为调试用
##
## 干三件事：
##   1. 告诉你现在手上控制的是谁
##   2. 显示她/他站在哪个坐标（改 楼层清单.gd 里的数字时，靠它对位置）
##   3. 提示按 F1 换人
##
## 正式导出的游戏里会自动消失（OS.is_debug_build() 只在编辑器里跑时是真）。
## 想强制让它出现/消失，改下面的 强制显示。

## true = 不管什么版本都显示；false = 只在编辑器里跑时显示
const 强制显示: bool = false

## 多久刷一次文字（秒）。不每帧刷，是因为坐标一秒变几十次，人眼也看不出
const 刷新间隔: float = 0.08

@onready var _文字: Label = $面板/文字

var _已过: float = 0.0


func _ready() -> void:
	visible = 强制显示 or OS.is_debug_build()
	set_process(visible)
	Director.control_changed.connect(_刷新)
	_刷新()


func _process(delta: float) -> void:
	_已过 += delta
	if _已过 < 刷新间隔:
		return
	_已过 = 0.0
	_刷新()


## F1 = 换人。放在这里而不是角色身上，是因为这整块只在调试时存在
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_role"):
		Director.switch_control()


## 既能被 control_changed 信号调用，也能自己直接调
func _刷新(_谁: Node = null) -> void:
	var who: Node = Director.当前控制
	var 名字 := "（还没人报到）"
	var 附加 := ""
	if who != null and is_instance_valid(who):
		名字 = who.name
		附加 = "\n位置：(%.0f, %.0f)" % [who.global_position.x, who.global_position.y]
		# 角色如果有「负重说明」就顺手显示出来（学生有，宿管没有）
		if who.has_method("负重说明"):
			附加 += "\n负重：" + str(who.负重说明())
	_文字.text = "开发者模式\n当前控制：%s\nF1 换人%s" % [名字, 附加]
