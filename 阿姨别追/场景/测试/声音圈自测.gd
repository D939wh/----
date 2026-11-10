extends Node
## 声音圈自测 —— 数据层：够响的声生成波、太轻不生成、换人跟随、脚下不显示、多波并存。
## 用法：Godot --headless 场景/测试/声音圈自测.tscn
## 逐项断言打印 PASS/FAIL，和 声音自测/宿管AI自测 一个套路。

const 声音表 := preload("res://数据/声音表.gd")

var _过: int = 0
var _败: int = 0
var 圈: CanvasLayer
var s: CharacterBody2D
var k: CharacterBody2D


func _ready() -> void:
	var packed: PackedScene = load("res://场景/主场景.tscn")
	var scene := packed.instantiate()
	get_parent().add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	s = scene.get_node("student")
	k = scene.get_node("keeper")
	scene.get_node("student2").global_position = Vector2(200, 208)   # 挪出戏
	Director.set_control(s)
	await _wait(0.1)

	var 圈场景: PackedScene = load("res://界面/声音圈/声音圈.tscn")
	圈 = 圈场景.instantiate()
	scene.add_child(圈)
	await get_tree().process_frame
	var 画面: Control = 圈.get_node("画面")

	# ── 1. 底环钉死视口正中，不随镜头 ──
	var 中心: Vector2 = 画面.环中心()
	断言("1 底环在视口正中",
		中心 == Vector2(320.0, 180.0),
		"底环中心 (%.0f, %.0f)（应 320,180，视口正中）" % [中心.x, 中心.y])

	# ── 2. 够响的声 → 生成一道朝声源方向的波 ──
	s.global_position = Vector2(1000, 208)
	await _wait(0.1)
	Events.发声(Vector2(900, 208), 声音表.档_很大, 声音表.来源_丢物)   # 左边 100px，音量 0.83
	await get_tree().process_frame
	var 快照: Array = 画面.波快照()
	断言("2 朝左的声在左边", 快照.size() == 1 and absf(快照[0]["方向"] - PI) < 0.01,
		"波数 %d（应 1）/ 方向 %.2f（应 %.2f = 朝左）" % [快照.size(), 快照[0]["方向"] if 快照.size() > 0 else -99.0, PI])

	# ── 3. 低于阈值不生成 ──
	await _wait(1.2)   # 等上一道波淡完
	Events.发声(Vector2(1500, 208), 声音表.档_很轻, 声音表.来源_脚步)   # 右边 500px > 半径 200
	await get_tree().process_frame
	断言("3 太轻不显示", 画面.波数() == 0, "波数 %d（应 0）" % 画面.波数())

	# ── 4. 音量单调影响显示强度 ──
	var 弱弧宽: float = 画面.弧角宽(0.2)
	var 强弧宽: float = 画面.弧角宽(0.9)
	断言("4 越响弧越宽", 弱弧宽 < 强弧宽,
		"音量 0.2 → 弧宽 %.2f / 音量 0.9 → 弧宽 %.2f（应前者小）" % [弱弧宽, 强弧宽])
	var 弱亮度: float = 画面.峰值亮度(0.2)
	var 强亮度: float = 画面.峰值亮度(0.9)
	断言("4b 越响越亮", 弱亮度 < 强亮度,
		"音量 0.2 → 亮度 %.2f / 音量 0.9 → 亮度 %.2f（应前者小）" % [弱亮度, 强亮度])

	# ── 5. 换人跟随：换听者后新波按新听者算 ──
	Director.set_control(k)
	k.global_position = Vector2(1000, 208)
	await _wait(0.1)
	Events.发声(Vector2(1100, 208), 声音表.档_很大, 声音表.来源_丢物)   # 宿管右边 100px
	await get_tree().process_frame
	快照 = 画面.波快照()
	断言("5 换人后朝向对", 快照.size() == 1 and absf(快照[0]["方向"] - 0.0) < 0.01,
		"波数 %d（应 1）/ 方向 %.2f（应 0.00 = 朝右）" % [快照.size(), 快照[0]["方向"] if 快照.size() > 0 else -99.0])

	# ── 6. 听者自己脚下的声不显示 ──
	await _wait(1.2)
	Events.发声(k.global_position + Vector2(2, 0), 声音表.档_极大, 声音表.来源_门)   # 脚下 2px
	await get_tree().process_frame
	断言("6 脚下不显示", 画面.波数() == 0, "波数 %d（应 0）" % 画面.波数())

	# ── 7. 多道波并存 ──
	# 宿管听到前面的声会进「搜索」自己走动，听者一漂，连发声就可能落她脚下
	# 或掉到阈值下。先把听者钉回原位再连发三声。
	k.global_position = Vector2(1000, 208)
	k.velocity = Vector2.ZERO
	await get_tree().physics_frame
	for i in range(3):
		Events.发声(Vector2(900 + i * 200.0, 208), 声音表.档_较大, 声音表.来源_跑动)
	await get_tree().process_frame
	断言("7 三波并存", 画面.波数() >= 3, "波数 %d（应 >= 3）" % 画面.波数())

	# ── 8. 寿命递减 ──
	var 波初: float = 画面.波快照()[0]["剩余"]
	await _wait(0.5)
	var 波后: float = 画面.波快照()[0]["剩余"] if 画面.波快照().size() > 0 else -1.0
	断言("8 剩余寿命在走", 波后 >= 0.0 and 波后 < 波初,
		"0.5 秒后剩余 %.2f（应 < %.2f 且 >= 0）" % [波后, 波初])

	print("")
	print("=== 声音圈自测：%d 过 / %d 败 ===" % [_过, _败])
	get_tree().quit(0 if _败 == 0 else 1)


func 断言(名: String, 通过: bool, 细节: String) -> void:
	var 行 := "  %s: %s —— %s" % [名, "PASS" if 通过 else "FAIL", 细节]
	print(行)
	if 通过:
		_过 += 1
	else:
		_败 += 1


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
