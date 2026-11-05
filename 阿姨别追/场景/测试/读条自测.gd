extends Node
## 通用读条自测（2026-11-05）
## 干一件事：把 `界面/读条/读条.tscn` 单独拎出来，从头到尾走一遍，
## 看它「建 → 显示 → 走到一半 → 走满 → 收」是不是都对着。
##
## 为什么单独测它：这根条以后要塞给宿管抓人、学生救人、插钥匙、门口判赢四五个地方用。
## 它要是错，所有长按的地方一起错，而且错的方式很隐蔽（比如条走满了事却没成）。
## 所以先把它当零件测干净，再让角色去用它。
##
## 跑法：Godot --headless 场景/测试/读条自测.tscn

const 读条 := preload("res://界面/读条/读条.gd")

var r := {}          # 结果汇总
var 条: CanvasLayer  # 被测的那一根

func _ready() -> void:
	# 延后一帧再建：_ready 里父节点还在搭，直接 add_child 会被拒绝（老坑）
	await get_tree().process_frame
	条 = 读条.新建(self)

	# ── ① 刚建出来：应该藏着，不能一进游戏屏幕中间就冒一根空条 ──
	r["①建出来先藏着"] = "可见=%s（应 false）" % 条.在显示中()

	# ── ② 开始：露出条，字是「说明 + 总时长」──
	var 跟随 := Node2D.new()
	add_child(跟随)
	跟随.global_position = Vector2(400, 200)
	条.开始(跟随, "拉队友", 4.0)
	r["②开始后"] = "可见=%s / 文字「%s」" % [条.在显示中(), 条.get_node("框/文字").text]

	# ── ③ 走到一半：填充应该正好一半宽，字上写还剩 2.0 秒 ──
	条.推进(2.0)
	var 填充宽: float = 条.get_node("框/填充").size.x
	r["③半程"] = "填充宽 %.1f（应 31.0 = 62 的一半）/ 文字「%s」" % [
		填充宽, 条.get_node("框/文字").text]

	# ── ④ 按过头：填充封顶、字写 0.0s，不能出现负数和超宽 ──
	条.推进(9.0)
	r["④超时"] = "填充宽 %.1f（应 62.0 封顶）/ 文字「%s」" % [
		条.get_node("框/填充").size.x, 条.get_node("框/文字").text]

	# ── ⑤ 跟人：人往右挪 100，条也要跟着挪（不是钉死在屏幕上）──
	条.开始(跟随, "抓捕", 1.2)
	await get_tree().process_frame
	var 挪前: Vector2 = 条.get_node("框").position
	跟随.global_position += Vector2(100, 0)
	await get_tree().process_frame
	var 挪后: Vector2 = 条.get_node("框").position
	r["⑤跟人走"] = "人挪 100，条挪 %.0f（相机 zoom=1 时应 100）" % (挪后.x - 挪前.x)
	# 横向要正中在人身上（条宽 64，一半 32），纵向要在头顶之上
	var 屏幕点: Vector2 = get_viewport().get_canvas_transform() * 跟随.global_position
	r["⑤位置"] = "条中心 x %.0f vs 人 x %.0f（应差 0）/ 条在头顶：%s" % [
		挪后.x + 32.0, 屏幕点.x, 挪后.y < 屏幕点.y - 40.0]

	# ── ⑥ 不跟人（跟谁传 null）：应该固定在屏幕下方正中，做全屏读条用 ──
	条.开始(null, "开门", 3.0)
	await get_tree().process_frame
	r["⑥不跟人"] = "位置 %s（应 (288, 265) = 屏幕正中偏下）" % str(条.get_node("框").position)

	# ── ⑦ 收：藏起来，并且再收一次不能报错（松手会被每帧调）──
	条.收()
	var 收后: bool = 条.在显示中()
	条.收()
	条.收()
	r["⑦收"] = "收后可见=%s（应 false）/ 连收三次没报错=true" % 收后

	# ── ⑧ 说明留空：只显示秒数，不显示空括号（以后纯数字读条用得上）──
	条.开始(跟随, "", 2.0)
	条.推进(0.5)
	r["⑧不写字"] = "文字「%s」（应只有 1.5s）" % 条.get_node("框/文字").text

	# ── ⑨ 跟着的人被删了：条自己藏起来，不能挂在一个不存在的坐标上 ──
	var 临时 := Node2D.new()
	add_child(临时)
	条.开始(临时, "插钥匙", 2.0)
	await get_tree().process_frame
	var 删前: bool = 条.在显示中()
	临时.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	r["⑨人没了"] = "删之前可见=%s（应 true）/ 删之后可见=%s（应 false）" % [删前, 条.在显示中()]

	# ── ⑩ 用这根条的人被删了：条跟着一起没，不能留一根死条在屏幕上 ──
	var 假角色 := Node2D.new()
	add_child(假角色)
	var 他的条: CanvasLayer = 读条.新建(假角色)
	他的条.开始(假角色, "自救", 2.0)
	await get_tree().process_frame
	假角色.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	r["⑩角色没了"] = "他的条还在吗=%s（应 false）" % is_instance_valid(他的条)

	# ── ⑪ 中文字体：Godot 自带字体不含中文，会显示成方块。
	#     这根条上写的是「拉队友」「抓捕」这类中文，字体必须真的能认字。──
	var 字: Font = 条.get_node("框/文字").get_theme_font("font")
	r["⑪中文能显示"] = "字体「%s」认不认『拉』字=%s（应 true）" % [
		字.get_font_name(), 字.has_char("拉".unicode_at(0))]

	print("=== 通用读条自测 ===")
	for key in r:
		print("  %s: %s" % [key, r[key]])
	get_tree().quit(0)
