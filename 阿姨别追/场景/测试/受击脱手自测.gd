extends Node2D
## 「挨一棍 → 手上的东西必须脱手、人回正常」自测
##
## 六项，缺一项就是 bug：
##   ① 扛着箱子挨打 → 箱子落地、双手空出来、状态回「正常」
##   ② 扛着队友挨打 → 队友落地、他也回正常、扛人者空手
##   ③ 蓄力中（正掂量扔多远）挨打 → 力条收起、东西脱手，不留半截蓄力
##   ④ 被钉住时挨打 → 钉住解除、人回正常（不能卡在插钥匙中）
##   ⑤ 插钥匙插到一半挨打 → 这次插孔作废、牌子还在地上（不能被悄悄吞掉）
##   ⑥ 挨打那一刻就在「被击退」里：硬直期间不吃键盘，硬直走完自动回正常
##
## 注意：这一份不测数字（击退多远、掉几格血），那些在 `阿姨打人自测` 里。
## 这里只盯「状态和手上东西」这两件事，免得两处断言重复、改一个数要改两处。
##
## 跑法：godot --headless --path <工程> res://场景/测试/受击脱手自测.tscn

var 主场景: Node
var 学生1: Node
var 学生2: Node
var 宿管: Node
var 箱子: Area2D
var 结果: Dictionary = {}


func _ready() -> void:
	主场景 = load("res://场景/主场景.tscn").instantiate()
	add_child(主场景)
	await _等(0.3)

	学生1 = 主场景.get_node("student")
	学生2 = 主场景.get_node("student2")
	宿管 = 主场景.get_node("keeper")
	箱子 = 主场景.get_node("CarryableBox")
	# 宿管挪到地图外：她有 AI，会自己走过来挥棍，把被测的那一棍搅乱。
	# 这里全都直接调 `被打中()`，不需要她站在旁边。
	宿管.global_position = Vector2(4000, 178)

	await _测1_扛箱子挨打()
	await _测2_扛队友挨打()
	await _测3_蓄力中挨打()
	await _测4_钉住时挨打()
	await _测5_插钥匙被打断()
	await _测6_硬直里不吃输入()

	_打印()
	get_tree().quit()


## ① 扛着箱子挨一棍：箱子回场景 + 开始下落，双手空出来，状态回「正常」
func _测1_扛箱子挨打() -> void:
	await _摆位()
	学生1.扛起(箱子)
	await _等(0.1)
	var 搬着前: bool = 学生1.正搬着()
	var 挂谁前: String = 箱子.get_parent().name
	var 负重前: String = 学生1.负重说明()

	学生1.被打中(1.0)
	await _等(0.05)
	var 搬着后: bool = 学生1.正搬着()
	var 挂谁后: String = 箱子.get_parent().name
	var 负重后: String = 学生1.负重说明()

	# 「自动掉下来」的实证：脱手之后它自己该受重力。搬到 60px 高处松手，
	# 0.4 秒内必须自己回地面 —— 扛着的时候它是关掉物理的，不会掉。
	var 地面y: float = 箱子.global_position.y
	箱子.global_position.y = 地面y - 60.0
	await _等(0.9)
	var 落回y: float = 箱子.global_position.y

	await _等(0.2)
	var 状态: String = 学生1._机器.当前()

	结果["① 扛着时"] = "搬着=%s｜箱子挂在 %s 身上｜他%s" % [搬着前, 挂谁前, 负重前]
	结果["① 挨打后"] = "搬着=%s（应 false）｜箱子回到 %s（应是场景）｜他%s" % [
		搬着后, 挂谁后, 负重后]
	结果["① 自己掉下来"] = "抬到 %.0f 高处松手 → %.0f（应落回地面 %.0f）｜他状态「%s」（应 正常）" % [
		地面y - 60.0, 落回y, 地面y, 状态]
	await _等(0.4)


## ② 扛着队友挨一棍：两人一起脱手，扛人者回正常、队友回场景
func _测2_扛队友挨打() -> void:
	await _摆位()
	学生1.扛起同学(学生2)
	await _等(0.1)
	var 被扛前: bool = 学生2.被扛着
	var 负重前: String = 学生1.负重说明()

	学生1.被打中(1.0)
	await _等(0.05)
	var 被扛后: bool = 学生2.被扛着
	var 父节点: String = 学生2.get_parent().name
	var 还扛着: bool = 学生1.正扛着人()
	var 负重后: String = 学生1.负重说明()

	await _等(0.6)
	var 状态: String = 学生1._机器.当前()

	结果["② 扛着时"] = "队友被扛=%s｜他%s" % [被扛前, 负重前]
	结果["② 挨打后"] = "队友被扛=%s（应 false）｜队友父节点=%s（应是场景）｜他还扛着人=%s（应 false）｜他%s" % [
		被扛后, 父节点, 还扛着, 负重后]
	结果["② 他状态"] = "「%s」（应 正常）" % 状态
	await _等(0.4)


## ③ 蓄力中挨打：力条收起、东西脱手
func _测3_蓄力中挨打() -> void:
	await _摆位()
	学生1.扛起(箱子)
	await _等(0.1)
	学生1._开始蓄力()
	await _等(0.2)
	var 蓄力前: bool = 学生1.蓄力中()
	var 条前: bool = _条可见(学生1)

	学生1.被打中(1.0)
	await _等(0.05)
	var 蓄力后: bool = 学生1.蓄力中()
	var 条后: bool = _条可见(学生1)
	var 搬着后: bool = 学生1.正搬着()

	结果["③ 蓄力中"] = "在蓄力=%s｜头顶有读条=%s" % [蓄力前, 条前]
	结果["③ 挨打后"] = "在蓄力=%s（应 false）｜读条可见=%s（应 false）｜还搬着=%s（应 false）" % [
		蓄力后, 条后, 搬着后]
	await _等(0.5)


## ④ 插钥匙（被钉住）时挨打：钉住必须解除，不然人永远钉在锁孔前
func _测4_钉住时挨打() -> void:
	await _摆位()
	学生1.钉住(true)
	await _等(0.1)
	var 钉住前: bool = 学生1.被钉住
	var 状态前: String = 学生1._机器.当前()

	学生1.被打中(1.0)
	await _等(0.05)
	var 钉住后: bool = 学生1.被钉住

	await _等(0.6)
	var 状态后: String = 学生1._机器.当前()

	结果["④ 钉住时"] = "被钉住=%s｜状态「%s」" % [钉住前, 状态前]
	结果["④ 挨打后"] = "被钉住=%s（应 false）｜状态「%s」（应 正常）" % [钉住后, 状态后]
	await _等(0.4)


## ⑤ 插钥匙插到一半挨打：这次作废、牌子还在（没被悄悄吞掉）、人回正常
func _测5_插钥匙被打断() -> void:
	await _摆位()
	var 锁口: Node = Director.thing("1-门厅")
	var 板: Node = Director.thing("一号")
	if 锁口 == null or 板 == null:
		结果["⑤ 锁口/一号板"] = "没找到（Director.thing 取不到），本项跳过"
		return
	板.global_position = Vector2(1005, 170)
	学生1.扛起(板)
	await _等(0.1)
	锁口.插(学生1)                  # 等价于站在锁孔前按 R
	await _等(0.15)
	var 进行中前: bool = 锁口._进行中
	var 钉住前: bool = 学生1.被钉住
	var 读条前: bool = _条可见(学生1)   # 插钥匙的读条（和力条借口同一根，2026-11-11 起才真能看见）
	学生1.被打中(1.0)                # 插到一半挨一棍
	await _等(0.1)
	var 钉住后: bool = 学生1.被钉住
	var 进行中后: bool = 锁口._进行中
	var 读条后: bool = _条可见(学生1)
	var 板还在: bool = is_instance_valid(板)
	var 板挂谁: String = 板.get_parent().name if 板还在 else "（已被吞掉）"
	var 孔亮: bool = bool(锁口._孔["一号"]["亮"])

	await _等(2.2)                   # 超过插孔用时（2 秒）：不能自己「插上了」
	var 板还在2: bool = is_instance_valid(板)
	var 孔亮2: bool = bool(锁口._孔["一号"]["亮"])
	var 状态: String = 学生1._机器.当前()

	结果["⑤ 插到一半"] = "锁口在读=%s｜被钉住=%s｜头顶读条=%s（应是 true）" % [
		进行中前, 钉住前, 读条前]
	结果["⑤ 挨打后"] = "被钉住=%s（应 false）｜锁口在读=%s（应 false）｜读条=%s（应 false）｜牌子还在=%s（应 true）｜挂在 %s" % [
		钉住后, 进行中后, 读条后, 板还在, 板挂谁]
	结果["⑤ 2.2 秒后"] = "牌子还在=%s（应 true，不能被吞掉）｜孔亮=%s（应 false）｜他状态「%s」（应 正常）｜挨打那一刻孔亮=%s" % [
		板还在2, 孔亮2, 状态, 孔亮]
	await _等(0.3)


## ⑥ 硬直期间按方向键不该动；硬直走完自己回到正常
func _测6_硬直里不吃输入() -> void:
	await _摆位()
	var 起点x: float = 学生1.global_position.x
	学生1.被打中(0.0)          # 方向 0 = 只掉血、原地推，方便量「有没有被我自己按走」
	await _等(0.05)
	var 硬直中: bool = 学生1._击退剩余 > 0.0
	Input.action_press("right")
	await _等(0.15)
	Input.action_release("right")
	var 位移: float = 学生1.global_position.x - 起点x
	await _等(0.3)
	var 状态: String = 学生1._机器.当前()

	结果["⑥ 硬直中"] = "硬直=%s（应 true）｜按右 0.15 秒的位移 %.0f（应 0）" % [
		硬直中, 位移]
	结果["⑥ 硬直后"] = "状态「%s」（应 正常）" % 状态


## 两项之间的复位：控制权、位置、血量、搬运保护全部还原
func _摆位() -> void:
	Director.set_control(学生1)
	学生1.拉起()
	学生2.拉起()
	学生1.被钉住 = false
	学生1.global_position = Vector2(1000, 178)
	学生2.global_position = Vector2(1080, 178)
	箱子.global_position = Vector2(1000, 170)
	学生1._搬运保护剩余 = 0.0
	学生2._搬运保护剩余 = 0.0
	箱子._搬运保护剩余 = 0.0
	await _等(0.25)


func _条可见(谁: Node) -> bool:
	var 条 = 谁.get("_读条条")
	return 条 != null and is_instance_valid(条) and 条.在显示中()


func _等(秒: float) -> void:
	await get_tree().create_timer(秒).timeout


func _打印() -> void:
	print("──────── 受击脱手自测 ────────")
	for 项 in 结果:
		print("%s：%s" % [项, 结果[项]])
	print("──────── 完 ────────")
