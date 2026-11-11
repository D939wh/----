extends Node2D
## 「被队友拖着走时按跳挣开」+「搬运保护」自测
##
## 六块，缺一块就是 bug：
##   ① 队友扛着 + 我站着 + 我控制着 → 按跳两边一起脱手（他负重清零，我跳出去）
##   ② 控制权在扛人那位身上 → 他按跳不能把肩上的人顺手放掉（防误伤）
##   ③ 我瘫着被队友扛 → 挣不开（瘫着站不起来）
##   ④ 被宿管扛着 → 挣不开（只认队友；宿管扛走只能等她放下）
##   ⑤ 搬运 CD：跳脱那一瞬间就套上，0.3 秒（空中也照常计时），期间抓不回去
##   ⑥ 箱子（钥匙板同一套）刚脱手也不能立刻捡
##   ⑦ 瘫痪不是钉死：能按 4 档速度蹭着爬，但跳不起来
##
## 注意：每一项开头都 `_摆位()`，里面会把搬运保护清零。不清的话，上一项放下时留下的
## 保护会把下一项的搬人动作挡掉，测出来的全是「扛不起来」这种假结果。
##
## 跑法：godot --headless --path <工程> res://场景/测试/挣脱自测.tscn

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
	# 把宿管挪到地图外：她有 AI，会走过来打人，一棍就把被测的学生打瘫 / 打脱手，
	# 那样测出来的全是假结果。第 ④ 项要用她时直接调她的接口，不需要她站在旁边。
	宿管.global_position = Vector2(4000, 178)

	await _测1_正常挣开()
	await _测2_扛人者按跳不误放()
	await _测3_瘫着挣不开()
	await _测4_宿管扛着挣不开()
	await _测5_跳脱保护挡住立刻再抓()
	await _测6_箱子也受保护()
	await _测7_瘫着能爬()

	_打印()
	get_tree().quit()


## ① 站着的人被队友拖着，切到自己身上按跳 → 两边一起脱手，人被弹起来
func _测1_正常挣开() -> void:
	await _摆位()
	学生1.扛起同学(学生2)
	await _等(0.15)
	var 扛着 = 学生2.被扛着
	var 挂谁 = 学生2.get_parent().name
	var 负重 = 学生1.负重说明()
	Director.set_control(学生2)
	await _等(0.1)

	var 地面前y: float = 学生2.global_position.y
	await _点跳()
	await _等(0.05)
	var 起跳速: float = 学生2.velocity.y
	await _等(0.12)
	var 腾空高度: float = 地面前y - 学生2.global_position.y

	结果["① 扛着时"] = "被扛着=%s｜挂在 %s 身上｜他%s" % [扛着, 挂谁, 负重]
	结果["① 按跳后"] = "被扛着=%s｜父节点=%s｜他扛着人=%s｜他%s" % [
		学生2.被扛着, 学生2.get_parent().name, 学生1.正扛着人(), 学生1.负重说明()]
	结果["① 跳出去了吗"] = "起跳速 %.0f（应为负）｜离地 %.0f 像素｜状态=%s" % [
		起跳速, 腾空高度, 学生2._机器.当前()]

	await _等(1.3)   # 等她落地


## ② 队友扛着人时，玩家还在操作扛人那位 —— 他按跳不该把肩上的人放掉
func _测2_扛人者按跳不误放() -> void:
	await _摆位()
	学生1.扛起同学(学生2)
	Director.set_control(学生1)
	await _等(0.15)
	await _点跳()
	await _等(0.15)
	结果["② 扛人者按跳"] = "还扛着=%s（应 true）｜他扛着人=%s（应 true）" % [
		学生2.被扛着, 学生1.正扛着人()]
	学生1.放下同学()
	await _等(0.2)


## ③ 瘫着的人被队友拖着 → 挣不开（瘫着站不起来）
func _测3_瘫着挣不开() -> void:
	await _摆位()
	学生2.血量 = 1
	学生2.被打中()
	await _等(0.6)          # 等击退滑停，不然扛起来的时候她还在被冲量推着
	学生1.扛起同学(学生2)
	Director.set_control(学生2)
	await _等(0.15)
	await _点跳()
	await _等(0.15)
	结果["③ 瘫着按跳"] = "瘫痪=%s｜还扛着=%s（应 true）｜他扛着人=%s（应 true）" % [
		学生2.瘫痪, 学生2.被扛着, 学生1.正扛着人()]
	学生1.放下同学()
	学生2.拉起()
	await _等(0.4)


## ④ 被宿管扛着（这里特意让她扛一个站着的人）→ 按跳挣不开
##    特意不用「瘫着的她扛」来测：那样是条件③挡住的，测不出「只认队友」这条
func _测4_宿管扛着挣不开() -> void:
	await _摆位()
	宿管._扛起(学生2)
	Director.set_control(学生2)
	await _等(0.15)
	await _点跳()
	await _等(0.15)
	结果["④ 宿管扛着按跳"] = "瘫痪=%s｜还扛着=%s（应 true）｜她肩上有人=%s（应 true）" % [
		学生2.瘫痪, 学生2.被扛着, str(宿管._carried_student != null)]
	if 宿管._carried_student != null:
		宿管._放下学生()
	await _等(0.3)


## ⑤ 刚跳脱那一刻就套上保护：空中抓不回、落地后还护一段、烧完才抓得动
func _测5_跳脱保护挡住立刻再抓() -> void:
	await _摆位()
	学生1.扛起同学(学生2)
	Director.set_control(学生2)
	await _等(0.12)
	await _点跳()                        # 挣开 → CD 在这一瞬间套上
	await _等(0.1)
	var 立刻保护: bool = not 学生2.可被搬运()
	var 立刻剩: float = 学生2._搬运保护剩余
	学生1.扛起同学(学生2)                # 想立刻抓回去
	var 立刻抓回: bool = 学生1.正扛着人()

	await _等(0.3)                        # CD 只有 0.3 秒，该走完了（人还在空中）
	var 空中解禁: bool = 学生2.可被搬运()
	var 人在空中: bool = not 学生2.is_on_floor()
	学生1.扛起同学(学生2)
	var 空中抓回: bool = 学生1.正扛着人()

	结果["⑤ 刚挣脱 0.1 秒"] = "保护中=%s（应 true）｜剩 %.2fs（0.3 的 CD）｜抓到=%s（应 false）" % [
		立刻保护, 立刻剩, 立刻抓回]
	结果["⑤ 再等 0.3 秒"] = "可被搬运=%s（应 true）｜此刻还在空中=%s（空中照常计时）｜抓到=%s（应 true）" % [
		空中解禁, str(人在空中), 空中抓回]
	学生1.放下同学()
	await _等(0.4)


## ⑥ 箱子/钥匙板同一条规则：刚脱手不能立刻捡
func _测6_箱子也受保护() -> void:
	_清保护()
	学生1.global_position = 箱子.global_position
	await _等(0.2)
	学生1.扛起(箱子)
	await _等(0.1)
	var 扛起来了: bool = 学生1.正搬着()
	学生1._drop_box()                     # 脱手
	await _等(0.1)
	var 保护中: bool = not 箱子.可被搬运()
	var 立刻捡: bool = 箱子.被按键("interaction", 学生1)    # 应 false
	var 捡到没: bool = 学生1.正搬着()
	await _等(0.5)                        # CD 只有 0.3 秒
	var 解禁: bool = 箱子.可被搬运()
	var 之后再捡: bool = 箱子.被按键("interaction", 学生1)  # 应 true

	结果["⑥ 箱子脱手"] = "扛起=%s｜保护中=%s（应 true）" % [扛起来了, 保护中]
	结果["⑥ 立刻捡"] = "按键接下=%s（应 false）｜他搬着=%s（应 false）" % [立刻捡, 捡到没]
	结果["⑥ 保护烧完"] = "可被搬运=%s（应 true）｜按键接下=%s（应 true）" % [解禁, 之后再捡]
	学生1._drop_box()
	await _等(0.2)


## 两项之间的复位：控制权交回学生1、两人摆回原处、**搬运保护清零**
func _摆位() -> void:
	Director.set_control(学生1)
	学生1.global_position = Vector2(1000, 178)
	学生2.global_position = Vector2(1060, 178)
	_清保护()
	await _等(0.15)


func _清保护() -> void:
	学生1._搬运保护剩余 = 0.0
	学生2._搬运保护剩余 = 0.0
	箱子._搬运保护剩余 = 0.0


## 按一下跳（下一物理帧再松开）
func _点跳() -> void:
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")


## 等若干秒（真时间，让物理跑起来）
func _等(秒: float) -> void:
	await get_tree().create_timer(秒).timeout


func _打印() -> void:
	print("──────── 挣脱自测 ────────")
	for 项 in 结果:
		print("%s：%s" % [项, 结果[项]])
	print("──────── 完 ────────")


## ⑦ 瘫痪 = 背着隐形 4 档重物：能慢慢挪（30% 速度），但跳不起来
func _测7_瘫着能爬() -> void:
	await _摆位()
	学生2.血量 = 1
	学生2.被打中()                    # 两格打空 → 瘫
	await _等(0.6)                     # 等击退滑停
	Director.set_control(学生2)
	var 起点x: float = 学生2.global_position.x
	var 起跳前y: float = 学生2.global_position.y
	Input.action_press("right")
	await _等(0.6)
	Input.action_release("right")
	var 位移: float = 学生2.global_position.x - 起点x
	await _等(0.1)
	await _点跳()                      # 4 档不能跳
	await _等(0.2)
	var 离地: float = 起跳前y - 学生2.global_position.y

	结果["⑦ 瘫着爬"] = "瘫痪=%s｜0.6 秒挪 %.0f 像素（4 档 30%% 速度应 ≈50）｜跳起 %.0f 像素（应 0）" % [
		学生2.瘫痪, 位移, 离地]
	学生2.拉起()
	await _等(0.3)
