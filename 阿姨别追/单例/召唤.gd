extends Node
## 召唤 —— 只干一件事：**把一份场景生出来，摆在「该在的地方」**。
##
## 【边界】它不认识调用它的人，也不认识生出来的是谁：
##   输入 = 一份场景（PackedScene 或 `res://` 路径）+ 一个参照节点 + 一条摆位规则；
##   输出 = 新节点（已经摆好、已经挂进这张图）。
##   「该在的地方」只有一条本事：**算出参照的视野矩形，把东西生到框外面**。
##
## 【为什么单独一个文件】「在别人看不见的地方放一个东西」这件事以后会反复用
##   （吓人、刷怪、掉补给、把队友丢到远处、传送到下一个房间）。它跟「谁触发、为什么触发」
##   毫无关系 —— 所以摆位数学和触发逻辑必须分成两个文件：一个改演出内容，一个改数学，互不牵连。
##
## 【挂载名】autoload 名是 `Summon`（纯英文；中文挂载名会被引擎按 Latin-1 解成乱码）。

## 生出一个节点。失败返回 null（场景读不出来 / 既没给位置也没给参照）。
## 参数：
##   场景  PackedScene 或 `res://` 路径字符串
##   参照  以谁的视野为准（一般传玩家）。传 null 时必须给 `摆位["位置"]`
##   摆位  可选的键：
##     "位置"  Vector2    给了就跳过视野计算，直接摆这里
##     "方位"  String     "背后"（默认）/ "前面" / "左" / "右"
##     "留白"  float      视野边缘再往外让出多少像素，默认 64
##     "贴地"  bool       是否把 y 对齐到参照的脚底，默认 true
##     "名字"  String     生出来的节点叫什么（不写就用场景自己的名字）
##
## 【调用时机有个坑】它内部会 `add_child` 一个带碰撞体的东西。**不能在物理回调里直接调**
##   （`body_entered` / `area_entered` / `_integrate_forces` 之类）—— 引擎正在刷新物理查询，
##   这时候改碰撞状态会报 `Can't change this state while flushing queries`，生出来的东西碰撞也是坏的。
##   在物理回调里要调，请先 `call_deferred`（触发方自己延后一下，这里不做隐式延迟：
##   隐式延迟会让「生成完马上拿返回值用」变得不可靠）。
func 生成(场景, 参照: Node2D = null, 摆位: Dictionary = {}) -> Node2D:
	var 场 := _取场景(场景)
	if 场 == null:
		return null

	var 位置: Vector2
	if 摆位.has("位置"):
		位置 = 摆位["位置"]
	else:
		if 参照 == null or not is_instance_valid(参照):
			push_error("[召唤] 既没给「位置」，也没给参照 —— 不知道该生在哪")
			return null
		位置 = _视野外一点(
			参照,
			str(摆位.get("方位", "背后")),
			float(摆位.get("留白", 64.0))
		)
		if bool(摆位.get("贴地", true)):
			# 角色与交互物的原点都在脚底：同一个 y 就是同一层地面
			位置.y = 参照.global_position.y

	var 物 := 场.instantiate()
	# 名字要在 add_child **之前** 盖上：add_child 那一刻它的 _ready 就跑了，
	# 晚了会在总管的「报到」日志里留下一串 @CharacterBody2D@12 这种临时名
	if str(摆位.get("名字", "")) != "":
		物.name = str(摆位["名字"])
	_挂点(参照).add_child(物)
	if 物 is Node2D:
		物.global_position = 位置

	if 参照 != null and is_instance_valid(参照):
		var 框 := 视野矩形(参照)
		print("[召唤] 生出「%s」｜位置 (%.0f, %.0f)｜参照 (%.0f, %.0f)｜视野 %.0f×%.0f（中心 %.0f）" % [
			物.name, 位置.x, 位置.y,
			参照.global_position.x, 参照.global_position.y,
			框.size.x, 框.size.y, 框.get_center().x,
		])
	else:
		print("[召唤] 生出「%s」｜位置 (%.0f, %.0f)" % [物.name, 位置.x, 位置.y])
	return 物


## 参照此刻能看见的世界矩形。**算不对，「视野外」就是句空话** ——
## 所以这里是公开函数，自测可以拿它直接断言「生出来的东西没落在框里」。
##   有相机：相机的屏幕中心 + 视口尺寸 ÷ 缩放（本作 640×360 ÷ 1.5 ≈ 427×240）
##   没相机：退回视口尺寸，以参照为中心
func 视野矩形(参照: Node2D) -> Rect2:
	if 参照 == null or not is_instance_valid(参照):
		return Rect2()
	var 视口 := 参照.get_viewport()
	if 视口 == null:
		return Rect2(参照.global_position - Vector2(320, 180), Vector2(640, 360))
	var 屏 := 视口.get_visible_rect().size
	var 中心 := 参照.global_position
	var 缩放 := Vector2.ONE
	var 镜头 := 视口.get_camera_2d()
	if 镜头 != null:
		中心 = 镜头.get_screen_center_position()
		缩放 = 镜头.zoom
	var 世界尺寸 := Vector2(屏.x / maxf(缩放.x, 0.001), 屏.y / maxf(缩放.y, 0.001))
	return Rect2(中心 - 世界尺寸 * 0.5, 世界尺寸)


## 视野外的一个落点：从视野**中心**往挑好的那一侧挪「半宽 + 留白」。
## 为什么从中心量、不从参照量：镜头有拖拽边距（drag margin），人并不总在视野正中，
## 从人身上量会在某些位置算出「还在框内」。从中心量，挪过半宽就一定在框外。
func _视野外一点(参照: Node2D, 方位: String, 留白: float) -> Vector2:
	var 框 := 视野矩形(参照)
	var 中心 := 框.get_center()
	var 方向 := _挑边(参照, 方位)
	return Vector2(中心.x + 方向 * (框.size.x * 0.5 + 留白), 中心.y)


## 往哪一侧生：+1 = 世界的右边，-1 = 左边。
func _挑边(参照: Node2D, 方位: String) -> int:
	match 方位:
		"左":
			return -1
		"右":
			return 1
		"前面":
			return _朝向(参照)
		_:
			return -_朝向(参照)     # "背后"（默认）


## 参照正朝哪边：+1 右 / -1 左。只看这一刻的水平速度（正在往哪走 = 正朝哪）。
## 站着不动就当他朝左 —— 给一个固定的默认值，别每次演出都换边。
func _朝向(参照: Node2D) -> int:
	var 速度 = 参照.get("velocity")
	if 速度 is Vector2 and absf(速度.x) > 1.0:
		return 1 if 速度.x > 0.0 else -1
	return -1


## 生出来的东西挂哪：挂参照所在那张图（场景）的根上。
## **不直接挂参照的父节点**：参照可能正被扛着，父节点是个人；也不挂测试脚手架，
## 所以先往上爬到「当前场景的直接子节点」为止。
func _挂点(参照: Node2D) -> Node:
	var 根 := get_tree().current_scene
	if 参照 != null and is_instance_valid(参照):
		var 顶: Node = 参照
		while 顶.get_parent() != null and 顶.get_parent() != 根 and 顶.get_parent() != get_tree().root:
			顶 = 顶.get_parent()
		if 顶 != 参照:
			return 顶                      # 找到了「这张图的根」
		return 参照.get_parent() if 参照.get_parent() != null else get_tree().root
	return 根 if 根 != null else get_tree().root


func _取场景(场景) -> PackedScene:
	if 场景 == null:
		push_error("[召唤] 场景是空的")
		return null
	if 场景 is PackedScene:
		return 场景
	var 路径 := str(场景)
	if not ResourceLoader.exists(路径):
		push_error("[召唤] 找不到场景：%s" % 路径)
		return null
	return load(路径) as PackedScene
