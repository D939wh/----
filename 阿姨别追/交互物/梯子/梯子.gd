extends Area2D
## 梯子判定框 —— 只回答「人站在这块范围里能不能爬」，**不负责外观**
##
## 图块管看，这个节点管爬；老地图不调 `setup()` 就一个字不变。
## 认出方式：`collision_layer` = 第 4 层「梯子」，学生 `ClimbZone` 掩码从 `数据/通用规则.gd` 取。
## 不给编号：不是按键交互物，学生用感应区自己撞上来。

## 手摆在场景里时用的尺寸（2026-11-12 加，和门的 width/height 一个套路）。
## 走物件代理的（清单建的）会被 `setup()` 覆盖，两者不冲突。
## 名字必须英文：中文名导出属性在 `.tscn` 里赋值会静默失效。
## 位置仍然是**中心**（不是底边），所以「从地面 352 爬到平台 208」= 高 144、中心 y 280。
@export var ladder_height: float = 300.0
@export var ladder_width: float = 32.0
@export var show_texture: bool = false


func _ready() -> void:
	# 手摆的梯子：按自己的导出值把判定框重算一遍，别用 .tscn 里那份默认 300 高的。
	setup(position, ladder_height, ladder_width, show_texture)

## 按「中心点 + 高 + 宽」摆一块判定框。
##
## 【位置是中心，不是底边】物件清单里的坐标一律是这件东西的**中心**，
##   和梯子图块的贴合方式最简单：图块占了几格，中心就是那几格的正中。
##
## shape 要 duplicate：`梯子.tscn` 里的 `RectangleShape2D` 是所有实例共用的，
## 直接改 `size` 会全场一起变；duplicate 一份再换上，各改各的。
func setup(中心: Vector2, 高: float, 宽: float = 32.0, 显示贴图: bool = false) -> void:
	position = 中心
	var 原形状: RectangleShape2D = $CollisionShape2D.shape as RectangleShape2D
	var 形状: RectangleShape2D = 原形状.duplicate()
	形状.size = Vector2(宽, 高)
	$CollisionShape2D.shape = 形状
	$CollisionShape2D.position = Vector2.ZERO

	var 图: Sprite2D = $Sprite2D
	图.visible = 显示贴图
	if 显示贴图:
		var 原尺寸: Vector2 = 图.texture.get_size()
		图.scale = Vector2(宽 / 原尺寸.x, 高 / 原尺寸.y)
		图.position = Vector2.ZERO
