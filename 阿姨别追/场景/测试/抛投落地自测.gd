extends Node
## 抛投落地自测 —— 【2026-11-13】主人报的两个声纹 bug 的数据层验证。
##
## 用法：Godot --headless 场景/测试/抛投落地自测.tscn
##
## 【测什么】
##   1. 箱子被扔到远处 → 落地那一声发在**落点**（档_很大，600px），不是扔的人脚下。
##      —— 修前：落地根本不发声，线只在正中动（那是学生松手那一下）。
##   2. 箱子从高处自由摔下 → 落地有声（档_较大，400px）。
##   3. 顺台阶蹭下去的小掉落 → 不该响（冲击 < 300px/s）。
##   4. 被队友扔出去的人 → 落地同样响在落点（扔人当诱饵这条战术线上看得见）。
##   5. 宿管在外面走动 → 脚步升档后（走=2 档 400px）学生隔着老远也能听见；
##      顺带验证她**不会被自己的脚步钓进「搜索」**（4px 自排除还在工作）。
##
## 【不数像素】只问「这一声发在哪、多大半径」，不碰声纹的画法。

const 声音表 := preload("res://数据/声音表.gd")
const 状态名 := preload("res://角色/宿管/状态/状态名.gd")

var _过: int = 0
var _败: int = 0
var _地面们: Array = []
var _声: Array = []      # 收到的每一声：{位置, 半径, 来源}


func _ready() -> void:
	Events.noise_made.connect(_收声)
	_加地面(-300.0, 2400.0, 208.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# 受控学生站远处：Director 得有人控着，宿管才肯当 AI（当前控制为 null 时
	# 她算「手控」，站在原地不动，脚步永远不响 —— 测的就是巡逻脚步，得让她走）。
	var 学生场景: PackedScene = load("res://角色/学生/student.tscn")
	var 学生: CharacterBody2D = 学生场景.instantiate()
	add_child(学生)
	await get_tree().physics_frame
	学生.global_position = Vector2(1600.0, 208.0)   # 离宿管 1200px：视野外、无干扰
	Director.set_control(学生)
	await _等(0.1)

	# ── 1. 箱子扔出去，落地声在落点 ──
	var 箱子场景: PackedScene = load("res://交互物/可搬运箱子/可搬运箱子.tscn")
	var 箱: Area2D = 箱子场景.instantiate()
	add_child(箱)
	await get_tree().physics_frame
	箱.global_position = Vector2(500.0, 199.0)        # 底边贴地（底半高 9）
	箱.抛(Vector2(1.0, 0.0), 300.0, 208.0)           # 往右扔 300px
	await _等(1.5)                                    # 飞行 ≈0.8s，留足余量
	var 落地声: Array = _声.filter(func(e): return e["来源"] == 声音表.来源_丢物 and e["半径"] == 声音表.半径(声音表.档_很大))
	断言("1 箱子落地声发在落点（≈800，不是出手点 500）",
		落地声.size() >= 1 and absf(float(落地声[0]["位置"].x) - 箱.global_position.x) < 40.0 and absf(float(落地声[0]["位置"].x) - 500.0) > 100.0,
		"落点 x=%.0f，第一声丢物 x=%.0f（共 %d 声）" % [箱.global_position.x,
			float(落地声[0]["位置"].x) if 落地声.size() > 0 else -1.0, 落地声.size()])

	# ── 2. 大落差自由摔下：有声，档_较大 ──
	_声.clear()
	箱.global_position = Vector2(600.0, 128.0)       # 底边离地 71px → 冲击 ≈357px/s
	await _等(1.2)
	var 摔声: Array = _声.filter(func(e): return e["来源"] == 声音表.来源_丢物 and e["半径"] == 声音表.半径(声音表.档_较大))
	断言("2 从高处摔下会响（2 档 400px）",
		摔声.size() >= 1 and absf(float(摔声[0]["位置"].x) - 600.0) < 30.0,
		"该有 %d 声 2 档，实收 %d 声" % [声音表.半径(声音表.档_较大), 摔声.size()])

	# ── 3. 小掉落（顺台阶蹭一下）：不该响 ──
	_声.clear()
	箱.global_position = Vector2(600.0, 188.0)       # 底边离地 11px → 冲击 ≈140px/s
	await _等(1.0)
	var 误响: Array = _声.filter(func(e): return e["来源"] == 声音表.来源_丢物)
	断言("3 小掉落不响（冲击 < 300px/s）", 误响.is_empty(),
		"不该响却响了 %d 声（半径 %s）" % [误响.size(),
			str(误响.map(func(e): return e["半径"])) if not 误响.is_empty() else "—"])
	箱.queue_free()

	# ── 4. 被扔出去的队友，落地声在落点 ──
	_声.clear()
	学生.global_position = Vector2(800.0, 208.0)
	await get_tree().physics_frame
	学生.抛出去(1.0, 200.0, 208.0)                    # 往右扔 200px → 落点 ≈1000
	await _等(1.5)
	var 人声: Array = _声.filter(func(e): return e["来源"] == 声音表.来源_丢物 and e["半径"] == 声音表.半径(声音表.档_很大))
	断言("4 队友落地声发在落点（≈1000）",
		人声.size() >= 1 and absf(float(人声[0]["位置"].x) - 学生.global_position.x) < 40.0,
		"落点 x=%.0f，落地声 x=%.0f（共 %d 声）" % [学生.global_position.x,
			float(人声[0]["位置"].x) if 人声.size() > 0 else -1.0, 人声.size()])
	学生.global_position = Vector2(1600.0, 208.0)     # 挪回远处，别在宿管的戏里

	# ── 5. 宿管在外面走动，脚步声传得过来（升档后半径 400）+ 不被自己钓进搜索 ──
	_声.clear()
	var 宿管场景: PackedScene = load("res://角色/宿管/宿管.tscn")
	var 宿管: CharacterBody2D = 宿管场景.instantiate()
	add_child(宿管)
	await get_tree().physics_frame
	宿管.global_position = Vector2(400.0, 208.0)     # 距学生 1200px：她看不见学生
	await _等(4.0)                                    # 待机 2s → 巡逻 → 慢走脚步 0.5s/步
	var 脚步: Array = _声.filter(func(e): return e["来源"] == 声音表.来源_脚步)
	var 老脚步: Array = 脚步.filter(func(e): return e["半径"] == 声音表.半径(声音表.档_很轻))
	断言("5 宿管走动脚步传得过来（2 档 400px）",
		脚步.size() >= 2 and 老脚步.is_empty(),
		"收 %d 声脚步，其中还是旧 1 档(200px) 的 %d 声" % [脚步.size(), 老脚步.size()])
	断言("6 她没被自己的脚步钓进搜索", 宿管._机器.当前() == 状态名.巡逻 or 宿管._机器.当前() == 状态名.待机,
		"当前状态「%s」（应还在巡逻/待机）" % 宿管._机器.当前())

	print("")
	print("=== 抛投落地自测：%d 过 / %d 败 ===" % [_过, _败])
	get_tree().quit(0 if _败 == 0 else 1)


func _收声(at_position: Vector2, radius: float, source_id: int) -> void:
	_声.append({"位置": at_position, "半径": radius, "来源": source_id})


func _等(秒: float) -> void:
	await get_tree().create_timer(秒).timeout


func _加地面(左: float, 右: float, 顶: float) -> void:
	var 体 := StaticBody2D.new()
	体.collision_layer = 1        # 层_地板
	体.collision_mask = 0
	var 形 := CollisionShape2D.new()
	var 矩 := RectangleShape2D.new()
	矩.size = Vector2(右 - 左, 40.0)
	形.shape = 矩
	形.position = Vector2((左 + 右) * 0.5, 顶 + 20.0)
	体.add_child(形)
	add_child(体)
	_地面们.append(体)


func 断言(名: String, 条: bool, 细节: String = "") -> void:
	if 条:
		过()
	else:
		败()
	print("%s %s｜%s" % ["PASS" if 条 else "FAIL", 名, 细节])


func 过() -> void:
	_过 += 1


func 败() -> void:
	_败 += 1
