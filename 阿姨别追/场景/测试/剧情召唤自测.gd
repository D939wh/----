extends Node2D
## 「剧情判定区 + 召唤」自测（2026-11-12 主人要求：判定区与召唤必须是两个模块）
##
## 五项，缺一项就是 bug：
##   ① 判定区照清单建出来了，运行时**看不见**那个框，而且不挡路（collision_layer = 0）
##   ② 玩家踩进去 → 剧情开演**一次**，阿姨生在**视野矩形之外**
##   ③ 只触发一次：出来再进去不再演，也不会多生一个
##   ④ 判定区不认识阿姨：脚本里没有 `宿管` / `阿姨` / `res://角色`，也没有 `Summon`
##   ⑤ 召唤不认识判定区与剧情表：脚本里没有 `判定区` / `剧情表` / `Story`
##
## 跑法：godot --headless --path <工程> res://场景/测试/剧情召唤自测.tscn

var 图: Node
var 学生                      # 不加类型：要直接摸 student.gd 自己的接口（拉起 / 血量…）
var 判定区                    # 同上：判定区自己的 编号 / 路由 / 已触发 不属于 Area2D
var 结果: Dictionary = {}
var 演了几次: int = 0
## 演出**那一刻**的落点与视野。为什么不在后面再量：生出来的阿姨有 AI，
## 0.1 秒就会自己走两步，镜头也在平滑跟人 —— 晚一帧量出来的都是「两回事」。
var 演出时位置: Vector2 = Vector2.INF
var 演出时视野: Rect2 = Rect2()


func _ready() -> void:
	图 = load("res://场景/主场景3.tscn").instantiate()
	add_child(图)
	await _等(0.4)

	学生 = 图.get_node("student")
	# 主场景3 从 11-12 17:20 起**不再预摆宿管**（阿姨改成剧情触发时才召唤），
	# 这里留个兜底：万一以后又摆回去一只，把她挪到地图外，免得她追着学生打搅乱读数。
	var 预摆阿姨 := 图.get_node_or_null("宿管") as Node2D
	if 预摆阿姨 != null:
		预摆阿姨.global_position = Vector2(4000, 178)
	判定区 = Director.thing("剧情-一楼走廊")
	Story.剧情开始.connect(_记下演出瞬间)

	await _测1_判定区本身()
	await _测2_踩进去就演()
	await _测3_只演一次()
	_测4_模块分开()

	_打印()
	get_tree().quit()


## ① 建出来了？运行时看不见？不挡路？
func _测1_判定区本身() -> void:
	var 框 := 判定区.get_node_or_null("框") as Node2D if 判定区 != null else null
	结果["① 判定区"] = "找到=%s｜编号「%s」｜路由「%s」｜尺寸 %s" % [
		判定区 != null,
		判定区.编号 if 判定区 != null else "-",
		判定区.路由 if 判定区 != null else "-",
		(判定区.get_node("CollisionShape2D").shape.size if 判定区 != null else Vector2.ZERO)]
	结果["① 游戏里看不见"] = "框 visible=%s（应 false）" % [
		框.visible if 框 != null else "没有框节点"]
	结果["① 不挡路"] = "collision_layer=%d（应 0）｜mask=%d（应 5 = 地板层1 + 瘫痪层4）｜monitorable=%s（应 false）" % [
		判定区.collision_layer, 判定区.collision_mask, 判定区.monitorable]


## ② 走进去：剧情演一次，阿姨生在视野外
func _测2_踩进去就演() -> void:
	学生.global_position = 判定区.global_position      # 相当于「玩家走进判定区」
	await _等(0.15)

	var 阿姨 := 图.get_node_or_null("阿姨_剧情召唤") as Node2D
	var 半宽 := 演出时视野.size.x * 0.5
	var 离中心: float = absf(演出时位置.x - 演出时视野.get_center().x) if 演出时位置 != Vector2.INF else 0.0
	var 差: float = absf(离中心 - (半宽 + 64.0))

	结果["② 踩中"] = "判定区已触发=%s｜剧情开演 %d 次（应 1）" % [判定区.已触发, 演了几次]
	结果["② 阿姨"] = "生出来了=%s｜名字「%s」｜演出瞬间位置 (%.0f, %.0f)｜现在 (%.0f, %.0f)" % [
		阿姨 != null,
		阿姨.name if 阿姨 != null else "-",
		演出时位置.x, 演出时位置.y,
		阿姨.global_position.x if 阿姨 != null else NAN,
		阿姨.global_position.y if 阿姨 != null else NAN]
	结果["② 在视野外"] = "离视野中心 %.0f px（半宽 %.0f + 留白 64 = %.0f，误差 %.1f 应 <20）｜落在框里=%s（应 false）" % [
		离中心, 半宽, 半宽 + 64.0, 差,
		演出时视野.has_point(演出时位置)]
	# 误差容差为什么放到 20：镜头有 position_smoothing，玩家一走过去镜头会**滞后**几帧，
	# 演出那一瞬的「视野中心」并不等于学生脚下 —— 差十几像素是镜头在追，不是召唤算错。
	# 271 和 277 在玩法上没有区别（都在屏幕外），别为了凑整数去改召唤公式。
	结果["② 贴地"] = "阿姨脚下 y=%.0f｜学生脚下 y=%.0f（差应 ≤6：生成后又落了半帧重力）" % [
		演出时位置.y, 学生.global_position.y]
	# 视野矩形本身也要像个样子：640×360 的视口、镜头 zoom 1.5 → 约 427×240
	结果["② 视野矩形"] = "%.0f×%.0f（应 ≈427×240 = 640÷1.5 × 360÷1.5）" % [
		演出时视野.size.x, 演出时视野.size.y]
	# 2026-11-13 加：视野改成视锥之后，生在背后又面朝反方向的她根本看不见人，
	# 所以剧情表里开了 `"惊动": true` —— 她至少知道「刚才有人在哪儿」。
	结果["② 被惊动"] = "听觉剩余 %.1f 秒（应 >0：知道人在哪儿，会过来看）｜记的坐标 x=%.0f（学生 %.0f）" % [
		阿姨._听觉剩余, 阿姨._听觉目标.x, 学生.global_position.x]

	# 把她挪走：第二只 AI 会追着学生打，③ 就测不干净了
	if 阿姨 != null:
		阿姨.global_position = Vector2(4200, 178)


## 记下**演出那一刻**的落点和视野（见文件顶部那两行变量的说明）
func _记下演出瞬间(_名字: String, 谁: Node) -> void:
	演了几次 += 1
	var 生 := 图.get_node_or_null("阿姨_剧情召唤")
	if 生 is Node2D:
		演出时位置 = 生.global_position
	var 参照: Node2D = 谁 if 谁 is Node2D else 学生
	演出时视野 = Summon.视野矩形(参照)


## ③ 只触发一次：出去再进来，不再演、不再生
func _测3_只演一次() -> void:
	var 生之前 := _数阿姨()
	学生.拉起()
	学生.global_position = 判定区.global_position + Vector2(-120, 0)   # 先出去
	await _等(0.2)
	学生.global_position = 判定区.global_position                      # 再进来
	await _等(0.2)
	结果["③ 再进一次"] = "已触发=%s（应 true）｜剧情开演 %d 次（应还是 1）｜场上阿姨 %d → %d 个（应不变）" % [
		判定区.已触发, 演了几次, 生之前, _数阿姨()]


## ④⑤ 两个模块必须互不认识 —— 用「脚本里有没有对方的字样」来验
func _测4_模块分开() -> void:
	var 判 := FileAccess.get_file_as_string("res://交互物/判定区/判定区.gd")
	var 召 := FileAccess.get_file_as_string("res://单例/召唤.gd")
	结果["④ 判定区只认路由"] = "提到 宿管=%s｜阿姨=%s｜res://角色=%s｜Summon=%s（都应 false）" % [
		判.contains("宿管"), 判.contains("阿姨"), 判.contains("res://角色"), 判.contains("Summon")]
	结果["⑤ 召唤只认摆位"] = "提到 判定区=%s｜剧情表=%s｜Story=%s｜宿管=%s（都应 false）" % [
		召.contains("判定区"), 召.contains("剧情表"), 召.contains("Story"), 召.contains("宿管")]


func _数阿姨() -> int:
	var 数 := 0
	for 子 in 图.get_children():
		if str(子.name).begins_with("阿姨_剧情召唤"):
			数 += 1
	return 数


func _等(秒: float) -> void:
	await get_tree().create_timer(秒).timeout


func _打印() -> void:
	print("──────── 剧情判定区 / 召唤 自测 ────────")
	for 项 in 结果:
		print("%s：%s" % [项, 结果[项]])
	print("──────── 完 ────────")
