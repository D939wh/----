extends Node2D
## 「判定区能复用吗」自测（2026-11-12 17:40 主人要求：判定区要复用，不能定死一个名字）
##
## 四问，任何一条不过，这块积木就不能复制第二块：
##   ① 复制出来的两块各自独立：改甲的尺寸，乙必须不动（否则等于全场景一起变）
##   ② 编号可以留空：不填编号不报错、也不登记，照样能踩、照样能演
##   ③ 名字是通用的：`setup()` 不会把它改成某出戏的名字
##   ④ 路由可以各写各的：两块拖到不同位置、指向不同戏，互不干扰
##
## 跑法：godot --headless --path <工程> res://场景/测试/判定区复用自测.tscn

const 判定区场景 := "res://交互物/判定区/判定区.tscn"

var 结果: Dictionary = {}
var 甲                       # 不加类型：要直接摸 判定区.gd 自己的字段
var 乙


func _ready() -> void:
	var 包: PackedScene = load(判定区场景)
	甲 = 包.instantiate()
	乙 = 包.instantiate()
	add_child(甲)
	add_child(乙)
	# 先给个路由再等帧：路由留空会触发「没填路由」的配置报错（那是另一件事），
	# 这里只想测「能不能复用」，别让那条正当的报错混进来。
	甲.route_name = "甲戏"
	乙.route_name = "乙戏"
	await get_tree().process_frame

	_测1_尺寸独立()
	_测2_编号可空()
	_测3_名字通用()
	_测4_路由各写各的()

	_打印()
	get_tree().quit()


## ① 两块复制品必须各有各的碰撞形状
func _测1_尺寸独立() -> void:
	var 甲形: RectangleShape2D = 甲.get_node("CollisionShape2D").shape
	var 乙形: RectangleShape2D = 乙.get_node("CollisionShape2D").shape
	var 同一份: bool = 甲形 == 乙形
	var 乙原本: Vector2 = 乙形.size

	甲形.size = Vector2(200, 300)          # 只动甲
	var 乙现在: Vector2 = 乙.get_node("CollisionShape2D").shape.size

	结果["① 尺寸各自独立"] = "共用同一份 shape=%s（应 false）｜改甲成 200×300 后，乙 %s → %s（应一直是 %s）" % [
		同一份, str(乙原本), str(乙现在), str(乙原本)]


## ② 编号是可选字段：留空不报错、不登记，但照常工作
func _测2_编号可空() -> void:
	# 两块都没填编号，走到这里没崩、没刷一行错误，就已经说明「留空是合法的」
	var 查得到 := Director.thing("")
	结果["② 编号可留空"] = "甲编号「%s」乙编号「%s」（都应是空）｜Director.thing(\"\") = %s（应是 <null>）｜仍在「判定区」组=%s（应 true）" % [
		甲.编号, 乙.编号, str(查得到), 甲.is_in_group("判定区")]


## ③ `setup()` 不许把节点名改成戏名（曾经拼成「判定区_走廊召唤阿姨」，同一个路由摆两块就重名）
func _测3_名字通用() -> void:
	var 原名: String = str(甲.name)
	甲.setup(Vector2(120, 200), 40.0, 40.0, "某出戏")
	结果["③ 名字不被改死"] = "setup 前「%s」→ 后「%s」（应一样）｜路由已改成「%s」（应 某出戏）" % [
		原名, str(甲.name), 甲.路由]


## ④ 两块各指一条戏，互不干扰
func _测4_路由各写各的() -> void:
	乙.setup(Vector2(600, 200), 32.0, 64.0, "另一出戏")
	var 甲形: Vector2 = 甲.get_node("CollisionShape2D").shape.size
	var 乙形: Vector2 = 乙.get_node("CollisionShape2D").shape.size
	结果["④ 各走各的戏"] = "甲路由「%s」%s｜乙路由「%s」%s（尺寸应分别是 40×40 / 32×64）" % [
		甲.路由, str(甲形), 乙.路由, str(乙形)]


func _打印() -> void:
	print("──────── 判定区复用自测 ────────")
	for 项 in 结果:
		print("%s：%s" % [项, 结果[项]])
	print("──────── 完 ────────")
