extends CanvasLayer
## 开发者面板（2026-11-03 加，2026-11-05 改成点击换人）—— 左上角那小块，只为调试用
##
## 干四件事：
##   1. 告诉你现在手上控制的是谁
##   2. 显示她/他站在哪个坐标（改坐标表里的数字时，靠它对位置）
##   3. 鼠标左键点谁 = 立刻控谁（不用再一个个轮）
##   4. F1 循环换人（老办法，留着，键盘党顺手）
##
## 正式导出的游戏里会自动消失（OS.is_debug_build() 只在编辑器里跑时是真）。
## 想强制让它出现/消失，改下面的 强制显示。

## true = 不管什么版本都显示；false = 只在编辑器里跑时显示
const 强制显示: bool = false

## 多久刷一次文字（秒）。不每帧刷，是因为坐标一秒变几十次，人眼也看不出
const 刷新间隔: float = 0.08

## 点击命中判定要查哪几层：地板层 = 正常站着的角色，瘫痪层 = 瘫倒的学生。
## 瘫痪时脚本会把碰撞层从「地板」改到「瘫痪」，所以两层都得查，不然躺着的点不到。
## 【为什么问规则要】2026-11-06 主人重排过层级，原来这里写死的是 1 | 2。
const 规则 := preload("res://数据/通用规则.gd")
const 点击查询层: int = 规则.层_地板 | 规则.层_瘫痪

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


## 换人。放在这里而不是角色身上，是因为这整块只在调试时存在
##   左键点角色 → 点谁控谁（2026-11-05 加）
##   F1        → 还是老办法：轮着换
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("switch_role"):
		Director.switch_control()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var 鼠标 := event as InputEventMouseButton
		if 鼠标.pressed and 鼠标.button_index == MOUSE_BUTTON_LEFT:
			_点选角色(鼠标.position)


## 把「鼠标点在屏幕的哪一点」翻译成「点到了谁」
##
## 为什么不按角色坐标算距离：角色是有高有宽的，算半径的话点她头顶上面 20 像素也会中，
## 点两个人中间的空隙也可能误判成后一个。这里直接问物理引擎「这个点压到谁的碰撞体了」，
## 点哪儿中哪儿，跟肉眼看到的一致。
func _点选角色(屏幕点: Vector2) -> void:
	# 屏幕坐标 → 世界坐标。相机是会动的，所以必须过一遍画布变换的反变换，
	# 不能拿鼠标坐标直接当世界坐标用。
	var 世界点: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * 屏幕点
	var 查询 := PhysicsPointQueryParameters2D.new()
	查询.position = 世界点
	查询.collision_mask = 点击查询层
	查询.collide_with_bodies = true    # 角色是 CharacterBody2D，走 body 这一边
	查询.collide_with_areas = false    # 不查区域，免得点到感应区/箱子
	var 命中 := get_viewport().world_2d.direct_space_state.intersect_point(查询, 8)
	for one in 命中:
		var body: Node = one.get("collider")
		if body == null:
			continue
		# 正被宿管扛在肩上的学生：**照样能切**（「点谁控谁」就得一个不漏），
		# 但先说一句，免得你以为按键失灵了 —— 扛着的时候位置每帧由宿管摆，
		# 学生脚本在这期间直接返回，不吃键盘，所以切过去只能看着，动不了。
		if body.get("被扛着") == true:
			print("[调试] %s 正被宿管扛着，切过去只能看着（放下后才能操作）" % body.name)
		# 不是可控制角色（比如箱子落地的 StaticBody2D）就继续往上找
		if Director.set_control(body):
			get_viewport().set_input_as_handled()
			return


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
	_文字.text = "开发者模式\n当前控制：%s\n左键点角色换人 / F1 轮换%s" % [名字, 附加]
