extends Node
## 声纹预览 —— 唯一目的是「把声纹渲染出来看一眼」，不参与游戏。
##
## 用法（**不能加 --headless**，加了就没有画面可截）：
##   Godot_v4.7.2-stable_win64_console.exe --path . res://场景/测试/声纹预览.tscn
##
## 它会：载入主场景4 → 挂上声纹 → 从四个不同方向/远近各发一声 →
## 截图存到 素材/特效/声纹/ 然后自己退出。删掉重跑就有一张新的。

const 主场景 := "res://场景/主场景4.tscn"
const 声纹场景 := "res://界面/声纹/声纹.tscn"
const 存图 := "res://素材/特效/声纹/"


func _ready() -> void:
	var 局: Node = load(主场景).instantiate()
	add_child(局)
	await get_tree().process_frame
	await get_tree().physics_frame

	var 纹: CanvasLayer = load(声纹场景).instantiate()
	局.add_child(纹)
	await get_tree().process_frame

	var 学生: Node2D = 局.get_node("student")
	var 耳: Vector2 = 学生.global_position

	# 第一张：只发一声，看一个波包到底长什么样
	Events.发声(Vector2(耳.x - 150.0, 耳.y), 3, 2)
	await get_tree().create_timer(0.10).timeout
	await _存("预览-单声.png")
	await get_tree().create_timer(1.1).timeout

	# 第二张：四声叠加 —— 左近（响）、右中（跑动）、左很远（门，极响）、右贴脸（脚步，轻）
	var 单: Array = [
		[Vector2(耳.x - 120.0, 耳.y), 3, 2],
		[Vector2(耳.x + 260.0, 耳.y - 40.0), 2, 1],
		[Vector2(耳.x - 700.0, 耳.y), 4, 3],
		[Vector2(耳.x + 60.0, 耳.y), 1, 0],
	]
	for i in range(单.size()):
		Events.发声(单[i][0], 单[i][1], 单[i][2])
		await get_tree().create_timer(0.16).timeout

	await get_tree().create_timer(0.10).timeout
	await _存("预览-游戏内.png")
	get_tree().quit()


## 截一次图，同时把底部 60px 放大 3 倍存一份 —— 1px 的东西不放大根本看不出来。
func _存(文件名: String) -> void:
	await RenderingServer.frame_post_draw
	var 图: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(存图))
	图.save_png(存图 + 文件名)

	var 底: Image = 图.get_region(Rect2i(0, 图.get_height() - 60, 图.get_width(), 60))
	底.resize(图.get_width() * 3, 180, Image.INTERPOLATE_NEAREST)
	底.save_png(存图 + 文件名.replace(".png", "-放大.png"))
	print("[预览] 已存 %s（%s）" % [文件名, str(图.get_size())])
