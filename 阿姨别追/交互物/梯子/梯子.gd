extends Area2D
## 梯子判定框 —— 只回答「人站在这块范围里能不能爬」，**不负责外观**
##
## 【为什么外观和判定要分开】（2026-11-06 主人用图块画了整张地图的梯子）
##   图块已经把梯子画出来了。如果再叠一张 `梯子.png`，两层图会错位、
##   互相盖住，改图时还得两边一起改。所以：**图块管看，这个节点管爬**。
##   老地图（主场景2）是把整套梯子当节点摆的，贴图仍然照旧显示 ——
##   不调用 `setup()` 就一个字不变。
##
## 【它凭什么被认出来】本节点 `collision_layer` = 第 4 层「梯子」（位值 8）。
##   学生的 `ClimbZone` 掩码里含着这一层，它在 `_ready` 里从
##   `数据/通用规则.gd` 取，不写死。层号一改，两边同时跟上。
##
## 【为什么不给编号】梯子不是「按 E 交互」的东西，总管不需要认识它；
##   学生是自己用感应区撞上去的。硬塞一个编号进账本，只会让人以为
##   它有交互逻辑，然后去找一个不存在的 `被按键`。

## 按「中心点 + 高 + 宽」摆一块判定框。
##
## 【位置是中心，不是底边】物件清单里的坐标一律是这件东西的**中心**，
##   和梯子图块的贴合方式最简单：图块占了几格，中心就是那几格的正中。
##
## 【为什么 shape 要 duplicate】`梯子.tscn` 里的 `RectangleShape2D` 是
##   sub_resource，**所有实例共用同一份**。直接改它的 `size`，场上每一把
##   梯子会一起变高 —— 而且报错都报不出来，只是爬着爬着发现高度不对。
##   duplicate 一份再换上，各改各的。
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
