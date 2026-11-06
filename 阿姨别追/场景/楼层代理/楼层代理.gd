extends Node2D
## 楼层代理 —— 你自己写的那句「各个地方有各个的代理」
##
## 它只负责「这一层」：
##   开局读清单，把这一层的门按位置建出来
##   以后灯、快递柜、电闸箱也归它管，用的是同一套写法（读清单 → 建出来 → 出事了照单处理）
##
## 所以你只要学会这一个文件，多少层楼、多少张地图用的都是同一份脚本，
## 区别只是挂上去时把「一楼」改成「二楼」、再指一张这张图的清单。

##
## 【清单分两份，这一层用哪份必须自己声明】（2026-11-06）
##   正式地图的坐标表在 `数据/正式/`（`run/main_scene` 那一局用的就是它）；
##   测试/自测当布景的旧图在 `数据/测试/`。
##   本脚本**不再自带默认清单**：以前默认指向旧一楼那张表，正式地图只要漏填，
##   就会悄悄读测试数据 —— 看着一切正常，其实测试和正式混在一起了。

## 全局规则：**对所有地图生效**的那份数（开门用时、钥匙板配色/编号）。
## 和清单分开：清单只属于某一张图，规则属于整个工程。
const 规则 = preload("res://数据/通用规则.gd")
const 门场景 = preload("res://交互物/门/门.tscn")
const 钥匙板场景 = preload("res://交互物/钥匙板/钥匙板.tscn")
const 锁口场景 = preload("res://交互物/锁口/锁口.tscn")
const 出口场景 = preload("res://交互物/出口/出口.tscn")
const 检修口场景 = preload("res://交互物/检修口/检修口.tscn")

## 这一层叫什么名字，要和清单里的名字对得上
@export var floor_id: String = "一楼"

## 用哪张清单。**必填**，每张地图自己声明，两个去处：
##   正式地图 → `res://数据/正式/楼层清单.gd`
##   测试布景 → `res://数据/测试/楼层清单_旧一楼.gd`
## 【为什么可以换】清单是「这张地图的坐标表」，换地形就得换表；
##   而规则（开门用时、钥匙板配色）不在任何一张清单里，在 `数据/通用规则.gd`，
##   对所有地图生效 —— 换图只换坐标，规则一个字不用碰。
##
## 【为什么填路径而不填资源】（2026-11-06 实测）
##   `@export var 清单: Script` 在 4.7 里能从检查器赋值，但存进 .tscn 以后读回来是 null
##   （属性存在、就是没被赋上值，静默失败 —— 代理照旧用默认那张表，看起来一切正常）。
##   换成字符串路径 + load()，一样能换表，而且出错会当场报出来。
@export_file("*.gd") var floor_list_path: String = ""

## 实际用的那张表。_ready 里决定，所有 _seed_* 都用它
var _表: Script = null

## 编号 -> 门节点。以后灯、柜子也各自有一本这样的账
var _doors: Dictionary = {}

## 编号 -> 钥匙板节点（"一号"/"二号"/"三号"）
var _keys: Dictionary = {}

## 编号 -> 锁口节点
var _locks: Dictionary = {}

## 编号 -> 出口判定区
var _exits: Dictionary = {}

## 这一层所有的检修口（数组，顺序就是清单里的顺序）
var _hatches: Array = []


func _ready() -> void:
	# 漏填 = 当场报错，不再退回某张「默认表」。宁可这一层空着并报红，
	# 也不要它悄悄去读另一张（测试）表、把坐标算到别的图上。
	if floor_list_path == "":
		push_error("[代理·%s] 没填 floor_list_path —— 每张地图都必须自己声明用哪份清单" % floor_id)
		return
	var 装 := load(floor_list_path)
	if not (装 is Script):
		push_error("[代理·%s] 清单路径读不出脚本：%s" % [floor_id, floor_list_path])
		return
	_表 = 装
	# 层带从清单里读，不在节点上再填一遍 —— 同一个数存两处，早晚对不上。
	# 清单没写 = 这一层占满全图（老的单层地图不用改）。
	var 带: Vector2 = _表.楼层.get(floor_id, {}).get("层带", Vector2(-1.0e12, 1.0e12))
	# 指错了表最典型的症状：这一层在那张表里根本没名字 → 一样东西都不建，
	# 却只有几行「建了 0 个」，看着不报错。
	if not _表.楼层.has(floor_id):
		push_warning("[代理·%s] 清单里没有这一层（floor_list_path=\"%s\"）—— 这层会空着，检查是不是指错表了"
			% [floor_id, floor_list_path])
	Director.register_floor(floor_id, self, 带)
	_seed_doors()
	_seed_keys()
	_seed_locks()
	_seed_exits()
	_seed_hatches()


## 照清单把门建出来。位置来自这张图的清单，开门用时来自 `通用规则.gd`（全图共用）
func _seed_doors() -> void:
	var data: Dictionary = _表.楼层.get(floor_id, {})
	var door_list: Array = data.get("门", [])
	for one in door_list:
		var d: Node2D = 门场景.instantiate()
		add_child(d)
		d.setup(floor_id, one["编号"], one["位置"], 规则.开门用时(one))
		_doors[one["编号"]] = d
	print("[代理·%s] 照清单建了 %d 扇门" % [floor_id, _doors.size()])


## 照清单把钥匙板摆出来。
## 【颜色从哪来】`通用规则.gd` 的 `钥匙板配色`，和门上的锁孔是同一份 ——
## 两边各写一份颜色，早晚会变成「钥匙是黄的、孔是红的」，玩家插不进去还查不出原因。
func _seed_keys() -> void:
	var data: Dictionary = _表.楼层.get(floor_id, {})
	for one in data.get("钥匙板", []):
		var k: Node2D = 钥匙板场景.instantiate()
		add_child(k)
		var 号: String = one["编号"]
		k.setup(号, one["位置"], 规则.钥匙板配色.get(号, Color.WHITE))
		_keys[号] = k
	print("[代理·%s] 照清单摆了 %d 块钥匙板" % [floor_id, _keys.size()])


## 照清单把锁口建出来。插一块几秒、插满开哪扇门，全在清单里
func _seed_locks() -> void:
	var data: Dictionary = _表.楼层.get(floor_id, {})
	for one in data.get("锁口", []):
		var p: Node2D = 锁口场景.instantiate()
		add_child(p)
		p.setup(
			floor_id,
			one["编号"],
			one["位置"],
			float(one.get("插孔用时", 2.0)),
			str(one.get("连哪扇门", ""))
		)
		_locks[one["编号"]] = p
	print("[代理·%s] 照清单建了 %d 个锁口" % [floor_id, _locks.size()])


## 照清单把门口判定区摆出来。它听门开门关的广播，不靠谁去通知
func _seed_exits() -> void:
	var data: Dictionary = _表.楼层.get(floor_id, {})
	for one in data.get("出口", []):
		var e: Node2D = 出口场景.instantiate()
		add_child(e)
		e.setup(
			floor_id,
			one["编号"],
			one["位置"],
			str(one.get("等的门", "")),
			float(one.get("站多久", 1.0))
		)
		_exits[one["编号"]] = e
	print("[代理·%s] 照清单建了 %d 个出口" % [floor_id, _exits.size()])


## 照清单把检修口摆出来（2026-11-06）
##
## 【检修口是什么】地板上的一个缺口，上面盖着一块单向平台：站着掉不下去，
##   按 S 就把平台临时放开 0.4 秒，人从缺口漏到下一层。
##   所以「下楼免费、上楼只能爬梯」这条规则，物理上就成立，不靠任何开关变量。
##
## 【为什么归代理建】和门、锁口一样：它属于「这一层有什么」。
##   学生只知道「我按了 S」，不知道脚下有没有口、在哪个 x —— 它不该知道。
func _seed_hatches() -> void:
	var data: Dictionary = _表.楼层.get(floor_id, {})
	for one in data.get("检修口", []):
		var h: Node2D = 检修口场景.instantiate()
		add_child(h)
		h.setup(one["位置"].x, one["位置"].y, float(one.get("宽", 32.0)))
		_hatches.append(h)
	print("[代理·%s] 照清单建了 %d 个检修口" % [floor_id, _hatches.size()])


## 总管把话递到这里。以后「灯要亮」「柜子要弹开」也走这一个口
func on_report(event: String, data: Dictionary) -> void:
	match event:
		"interact":
			_处理交互(data)
		"unlock":
			_处理解锁(data)
		"drop_down":
			_处理下穿(data)
		"door_pressed":
			print("[代理·%s] 收到：%s 被按了" % [floor_id, data.get("door_id", "?")])
		_:
			print("[代理·%s] 收到不认识的事：%s" % [floor_id, event])


## 有人按了 S，想从检修口往下漏（2026-11-06）
##
## 【判定为什么在这里】「脚下这块地有没有口」是场景知道的事，不是角色知道的事。
##   角色只说一句「我在这个位置按了 S」，找口、开哪块板、开多久，全在这一层。
##   以后加「消防通道口」「通风井」，清单里加一行就行，学生脚本不动。
##
## 【找不到口怎么办】什么也不做，只打印一句。这是正常操作（玩家在走廊中间按 S），
##   不是故障 —— 但一定要有声音，不然「按了没反应」会被当成 bug 查半天。
func _处理下穿(data: Dictionary) -> void:
	var 谁: Node = data.get("谁", null)
	if 谁 == null or _hatches.is_empty():
		print("[代理·%s] 这一层没有检修口，按 S 下不去" % floor_id)
		return
	var 点: Vector2 = 谁.global_position
	for h in _hatches:
		if h.has_method("能接住") and h.能接住(点):
			h.开()
			print("[代理·%s] 检修口打开：%s 可以下去了" % [floor_id, 谁.name])
			return
	print("[代理·%s] 脚下不是检修口（这一层有 %d 个口），按 S 没反应" % [floor_id, _hatches.size()])


## 锁口插满三个孔之后往上报的一句话。
## 【为什么开哪扇门由这里决定，不由锁口决定】
##   锁口不该知道门叫什么名字，就像门不该知道推它的人叫什么。
##   这一层才有那本「谁是谁」的账（_doors），所以这一句只能在这里落地。
func _处理解锁(data: Dictionary) -> void:
	var 门号: String = str(data.get("门", ""))
	print("[代理·%s] 收到：%s 插满了 → 开「%s」" % [
		floor_id, data.get("锁口", "?"), 门号])
	var d: Node = _doors.get(门号, null)
	if d == null:
		push_error("[代理·%s] 锁口说开「%s」，但这一层没有这扇门" % [floor_id, 门号])
		return
	if d.has_method("被解锁"):
		d.被解锁()


## 角色只说了「我在这一层碰了东西，按的是这个键」，剩下全靠这里认。
## 这就是三层架构真正落地的那一段：判定权在代理手里，不在角色手里。
##
## 【为什么判定要放在这一层】
##   1. 学生不认识门、不认识箱子 —— 加十种新家具，学生脚本一个字不改；
##   2. 只有这一层知道「这一层都有什么」（_doors 就是它建的）；
##   3. 以后要加「开着门的时候不许搬箱子」这种场景规矩，也只有这里改得动。
func _处理交互(data: Dictionary) -> void:
	var 谁: Node = data.get("谁", null)
	var 键: String = data.get("键", "")
	var 碰到: Array = data.get("碰到", [])
	print("[代理·%s] 收到：interact" % floor_id)

	if 谁 == null:
		return   # 没说是谁碰的，没人能动手。不报错：宁可什么都不做，也别乱开门

	if 键 == "open_door":
		# 门的分身（Area2D「Zone」）在 door 组里，门本体是它的父节点
		for area in 碰到:
			if area.is_in_group("door"):
				var door: Node = area.get_parent()
				if door != null and door.has_method("press"):
					print("[代理·%s] 判定：是门 → 交给门自己开" % floor_id)
					door.press(谁)
				return
		return

	if 键 == "interaction":
		# 顺序不能改：先箱子，再道具。这是拆分 E/F 之前就定下的行为
		# （箱子是大事、道具是小事；站在两件东西中间时先搬箱子）
		for area in 碰到:
			if area.is_in_group("carryable"):
				print("[代理·%s] 判定：是可搬运物 → 让%s扛起" % [floor_id, 谁.name])
				谁.扛起(area)
				return
		for area in 碰到:
			if area.is_in_group("usable_item"):
				if 谁.收起道具(area):
					print("[代理·%s] 判定：是道具 → %s 收进了道具格" % [floor_id, 谁.name])
				return
		return

	if 键 == "insert_key":
		# 锁口的分身（Area2D「Zone」）在 keyhole 组里，锁口本体是它的父节点。
		# 这里只负责「认出来并递过去」，插多久、对不对孔、门开不开都不在这里（见 锁口.gd）
		for area in 碰到:
			if area.is_in_group("keyhole"):
				var lock: Node = area.get_parent()
				if lock != null and lock.has_method("插"):
					print("[代理·%s] 判定：是锁口 → 交给锁口自己读" % floor_id)
					lock.插(谁)
				return
		return

	# 一样都没找到：正常。玩家对着空气按键就是会发生的事，不是故障



## 给外部查询：这一层的某扇门
func get_door(door_id: String) -> Node:
	return _doors.get(door_id, null)
