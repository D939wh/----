# ============================================================
# W1D1→W1D4 参考答案 · 学生移动（走+跳+爬+搬东西）· v6「跟正式版逐行对齐」
# ------------------------------------------------------------
# 用途：这份是正式版 student.gd 的「带注释镜像」——
#       【代码部分与 student.gd 完全一致，一个字不差】（主人 2026-10-29 22:48 定的规矩）；
#       差异只在注释：这份写足比喻、调法、门诊表。
#       以后调手感只改正式版，改完小鲸把这份同步过来。
#
# v6（2026-11-02 10:49）同步 W1D4 搬运与道具上车：
#   E = 拿起 / 放下 / 捡道具；右键 = 用道具。
#   角色状态从"没有状态"升级成 enum 两个状态：EMPTY 空手 / CARRYING 负重。
#   无头机器验证 12 条全过（搬一个✓ 不能搬两个✓ 放下✓ 钥匙进格✓ 使用消失✓）。
#
# 前提（工程里已建好，不用改）：
#   - 输入动作名：left / right / jump / sprint / up / down / interaction(E) / use_item(Q)
#   - student.tscn 里有 ClimbZone（Area2D，mask 只认 layer 3=梯子）
#   - student.tscn 里有 PickupZone（Area2D，mask 只认 layer 4=可交互物品）
#   - HUD.tscn（画布层→右下角 ItemSlot 道具格）独立摆在主场景里，不挂在学生身上
#   - 挂在 CharacterBody2D（角色车身）上
# ============================================================

extends CharacterBody2D

# ---------- 一、手感旋钮（调手感只动正式版这一段；规矩：一次只动一个数） ----------
# —— 走路：骑自行车 ——
const SPEED: float = 315.0      # 快走全速（像素/秒）。嫌走得慢 → 调大；嫌太赶 → 调小
const ACCEL: float = 1400.0     # 油门（像素/秒²）：起步约 0.2 秒到全速。
								# 起步太肉 → 调大；发飘没分量 → 调小
const FRICTION: float = 1800.0  # 松脚后的刹车（像素/秒²）。
								# 停不住 → 调大；想滑更远 → 调小（重量感旋钮之一）

# —— 按住 Shift：慢走档（2026-10-30 主人定稿）——
const SLOW_SPEED: float = 200.0  # 慢走目标：按住 Shift 减到这。嫌不够慢 → 调小
const SLOW_DECEL: float = 200.0  # 减速快慢：315→200 约 0.6 秒。嫌切换突兀 → 调小
const SPRINT_TIME: float = 0.16   # 冲刺时长（爆发式冲刺已废弃，暂留）
const SPRINT_CD: float = 1.5     # 冲刺冷却（爆发式冲刺已废弃，暂留）
const SPRINT_SPEED: float = 288.0  # 冲刺速度（爆发式冲刺已废弃，暂留）

# —— 跳跃 ——
# 铁律：屏幕 Y 轴朝下！竖直速度 负=向上，正=向下。
const GRAVITY: float = 368.0         # 重力（像素/秒²）。管上升减速。
									 # 注意：它只管上升段；下落由 FALL_GRAVITY_MULT 加倍
const JUMP_VELOCITY: float = -260.0  # 起跳蹬地那一下，负=向上。
									 # 跳的高度只看它，想跳更高/矮 → 动它
const JUMP_CUT: float = 0.45         # 蹦床泄劲：上升中松手，剩余上冲 ×0.45。
									 # 轻点跳太矮 → 调大（试试 0.6）；想逼玩家按满 → 调小
const COYOTE_TIME: float = 0.10      # 土狼宽限（秒）：出平台边缘后还能跳的时限。
									 # 边缘按跳没反应 → 调大（0.15）；太大会像"空气跳"
const JUMP_BUFFER: float = 0.12      # 跳跃记账（秒）：落地前按跳先记着，落地自动补。
									 # 落地前按跳没接住 → 调大；太大会"没按却跳了"

# —— 只加快下落（不动跳高）——
const FALL_GRAVITY_MULT: float = 2  # 下落重力 = GRAVITY × 它。主人手拧 1.6→2
									  # 嫌落得慢 → 调大；太快 → 调小
									  # 跳的高度不受它影响——高度是上升段决定的

# —— 顶点悬停（主人手拧：0.25→0.03，基本关掉）——
const HANG_TIME: float = 0.03      # 到顶定格几秒。嫌定格久/假 → 调小；填 0 = 整套关掉
const HANG_VY_BAND: float = 40.0   # 竖直速度小于它就算"到顶了"（一般不动）。

# —— 攀爬（W1D3：电梯式——按住 W 上爬 / S 下爬 / 空格蹬开）——
# 电梯类比：梯子是竖直的走廊，W/S 是"上行/下行"按钮；不按按钮就停在原地（挂住）。
const CLIMB_SPEED: float = 70.0     # 爬梯速度（像素/秒）。嫌爬得慢 → 调大
const CLIMB_OFF_JUMP: float = -180.0  # 从梯子上蹬开跳的初速（比地面跳矮——
									  # 梯子跳主要是横移到旁边平台，不是用来跳高的）

# ---------- 二、"记性"（var 是活的，const 是定死的） ----------
# 攀爬的记性
var _on_ladder: bool = false  # 开关：手正摸着梯子吗（ClimbZone 碰到梯子层）
var _climbing: bool = false   # 开关：这一趟真的按过上下键在爬吗（没按过=不挂住）

# ── W1D4 搬运与道具（2026-11-02 新增）──
# 生活比喻：手上有没有东西，是"你这个人现在处于什么姿态"。
# 站着空手和抱着箱子的你，是两个不同的人——别的代码问你一句
# 「你现在是空手还是负重」就能决定"这场能不能爬梯子、跑多快"。
# 这就是状态机的种子：一个 enum（状态清单）记住"我现在是哪种人"。
enum CarryState { EMPTY, CARRYING }
var _carry_state: CarryState = CarryState.EMPTY  # 现在：空手（EMPTY=0）/ 负重（CARRYING=1）
var _carried: Area2D = null             # 正扛着的那个箱子（空手时是 null）

const CARRY_OFFSET := Vector2(14, -30)  # 扛着时箱子挂在身前的相对位置
										# （x=身前 14 像素，y=往上抬 30 像素，抱在胸口）

# 道具格：null = 身上没东西；有图 = 有道具（右下角格子亮）
# 为什么用"图"当开关：格子亮不亮完全由数据说了算——
# 有图就亮、没图就灭，不是"提前藏一张固定的图再显示出来"（那是作弊写法）
var _item_icon: Texture2D = null

# 移动的老记性
var _coyote: float = 0.0       # 秒表① 土狼：离地后还能跳的宽限还剩多少
var _buffer: float = 0.0      # 秒表② 缓冲："想跳"这笔账还能记多久
var _sprint_left: float = 0.0 # 秒表③ 冲刺：这一下还剩多久（废弃冲刺遗留）
var _sprint_dir: float = 0.0  # 方向记性：这一下朝哪边（废弃冲刺遗留）
var _sprint_cd: float = 0.0   # 秒表④ 喘气：归 0 才能再冲（废弃冲刺遗留）
var _hang_left: float = 0.0   # 秒表⑤ 定格：顶点停滞还剩多久（0=没在定格）
var _fast_fall: bool = false  # 开关：定格结束后正处于快落中

# ---------- 手感门诊表：哪里不舒服 → 拧哪个旋钮 ----------
# （规矩：一次只动一个数，改完跑一遍记一句感受，再动下一个）
#   起步太肉 ............ ACCEL ↑
#   说停停不住 .......... FRICTION ↑
#   走太慢 .............. SPEED ↑
#   慢走不够慢 .......... SLOW_SPEED ↓
#   按 Shift 切换太突兀 .. SLOW_DECEL ↓
#   跳太矮 .............. JUMP_VELOCITY ↑（别动重力）
#   轻点跳太矮 .......... JUMP_CUT ↑
#   出边缘跳没反应 ...... COYOTE_TIME ↑
#   落地前按跳没接住 .... JUMP_BUFFER ↑
#   下落还是慢/拖 ....... FALL_GRAVITY_MULT ↑
#   落得太狠像砸 ........ FALL_GRAVITY_MULT ↓
#   顶点定格太久/嫌假 ... HANG_TIME ↓（0=整套关掉）
#   爬梯太慢 ............ CLIMB_SPEED ↑
#   梯子上蹬跳太矮 ...... CLIMB_OFF_JUMP ↑（负更多）
#   箱子挂在身前太远/太近 CARRY_OFFSET 的 x ↑↓
# ----------------------------------------------------------------

func _ready() -> void:
	# 抓梯感应区：ClimbZone（Area2D）碰到梯子层（layer 3）就算「摸到梯子」。
	# 信号=电话铃：ClimbZone 一碰/一离开梯子，就打给下面两个接电话的函数
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)

func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子（还不算挂着，要看有没有按上下键）

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false
	_climbing = false   # 离开梯子，爬的记性清零

func _physics_process(delta: float) -> void:
	var dir := Input.get_axis("left", "right")  # 方向盘：右=1 左=-1 不按=0
	var sprint_held := Input.is_action_pressed("sprint")  # 按住 Shift？（按住=慢走）
	var updown := Input.get_axis("up", "down")  # 竖梯的方向盘：W=+1 上 S=-1 下

	# ---- 0. 攀爬分支：整个梯子世界，跳过下面全部 ----
	# 贴在梯子上 + 按了上下 → 开始爬（按过才挂住；没按过不会吸在梯子上）
	if _on_ladder and updown != 0.0:
		_climbing = true
	if _on_ladder and _climbing:
		velocity.y = updown * CLIMB_SPEED   # 电梯：W 升 S 降；脚下有地板时 S 爬不动但已"在梯上"
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 爬梯时左右刹住，别荡秋千
		# 跳蹬开：从梯子上跳走。不给土狼宽限——不然贴着梯子每帧都"能跳"，会乱
		if Input.is_action_just_pressed("jump"):
			velocity.y = CLIMB_OFF_JUMP       # 蹬一下（比地面跳矮）
			velocity.x = dir * SPEED * 0.6     # 顺按住的方向横移（0.6=别荡太远）
			_climbing = false                  # 跳走这一瞬手松开梯子
		move_and_slide()
		return  # 这一帧到梯子为止，不走下面的重力/跳跃/左右——梯子上没重力

	# ---- W1D4：交互（E 拿起/放下、右键用道具）----
	# 为什么放在攀爬之后：梯子上不做交互（爬梯手占着），
	# 这也是和 D3 一样的"两个世界"分界——攀爬分支上面 return 了，走不到这
	_update_interaction()

	# ---- 1. 重力（三分支：定格中 / 刚到顶 / 正常）----
	# 抛橡皮的弧线升级版：冲上去 → 顶点定格一拍（重力归零）→ 倍数快落砸下来
	if not is_on_floor():
		if _hang_left > 0.0:
			# 定格中：重力归零，飘在顶点把秒表⑤走完
			_hang_left = maxf(_hang_left - delta, 0.0)
			if _hang_left <= 0.0:
				_fast_fall = true             # 定格结束：这一跳剩下的路全按快落走
		elif absf(velocity.y) < HANG_VY_BAND and not _fast_fall:
			_hang_left = HANG_TIME            # 刚到顶：定格开始
		else:
			# 正常上升/下落；快落中重力翻倍
			velocity.y += GRAVITY * (FALL_GRAVITY_MULT if _fast_fall else 1.0) * delta
	else:
		_fast_fall = false                    # 落地：开关复位，下一跳从头来

	# ---- 2. 三只老秒表：在地上/刚按下就回满，否则每帧减到 0 为止 ----
	_coyote = COYOTE_TIME if is_on_floor() else maxf(_coyote - delta, 0.0)
	_buffer = JUMP_BUFFER if Input.is_action_just_pressed("jump") else maxf(_buffer - delta, 0.0)
	_sprint_cd = maxf(_sprint_cd - delta, 0.0)

	# ---- 3. 起跳：账上有"想跳"（②>0）且宽限还在（①>0）→ 蹬地！----
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		_hang_left = 0.0    # 新跳清掉上一跳的定格/快落
		_fast_fall = false  # （不清的话：上一跳的快落会把这一跳拽矮）

	# ---- 4. 可变跳高：上升中松开空格 → 蹦床泄劲，矮跳 ----
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	# ---- 5. 冲刺起手（已废弃：点按爆发删掉了，三常量暂留备复活）----
	# if Input.is_action_just_pressed("sprint") and _sprint_cd <= 0.0 and dir != 0.0:
	# 	_sprint_left = SPRINT_TIME
	# 	_sprint_dir = dir
	# 	_sprint_cd = SPRINT_CD

	# ---- 6. 左右速度：冲刺段(废弃，空转) > 慢走 > 快走 > 刹停 ----
	if _sprint_left > 0.0:
		_sprint_left -= delta
		velocity.x = _sprint_dir * SPRINT_SPEED       # 冲刺：直接满速（现在永远走不到这）
	elif dir != 0.0:
		# 按住 Shift：减速档（慢走 200）；松手目标回快走 315
		var slow_ok := sprint_held and is_on_floor()
		var target := SLOW_SPEED if slow_ok else SPEED
		var accel := SLOW_DECEL if slow_ok else ACCEL
		# 空中保留助跑：起跳时多快就保持多快，不往回拽（只放行同向超速）
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > target):
			velocity.x = move_toward(velocity.x, dir * target, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 松脚：滑行

	# ---- 7. 挂挡 ----
	move_and_slide()

# ============================================================
# W1D4 · 搬运与道具（下面是今天新增的全部）
# ------------------------------------------------------------
# 交互键 E 一件事分三步走（先看手上有没有东西）：
#   1) 正扛着箱子 → 放下
#   2) 空手 + 附近有箱子 → 扛起来（状态变 CARRYING）
#   3) 空手 + 附近有道具 → 捡进右下角格子
# 右键单独管"用道具"：消耗掉、格子变空。今天用掉没有任何效果。
# ============================================================

func _update_interaction() -> void:
	# 扛着的箱子跟着人走（挂在身前）
	# 生活比喻：箱子已经"认人做爹"了（reparent 到学生节点下），
	# 这里每帧把它的相对位置摆回胸口——人走到哪，怀里的箱子跟到哪
	if _carry_state == CarryState.CARRYING and is_instance_valid(_carried):
		_carried.position = CARRY_OFFSET

	if Input.is_action_just_pressed("interaction"):
		_interact()

	# 右键用道具：只有身上真带着东西才响应（_item_icon != null）
	if Input.is_action_just_pressed("use_item") and _item_icon != null:
		_use_item()

# E 键：按上面三步走
func _interact() -> void:
	# 第一步：手上正扛着 → 放下（不管旁边有什么，先把手腾出来）
	if _carry_state == CarryState.CARRYING:
		_drop_box()
		return

	# 第二步/第三步：空手时看感应区里有什么
	# get_overlapping_areas() = "现在圈里有哪些东西"（名单现查，不用自己维护）
	# 先找可搬运的：箱子优先（箱子是大事，道具是小事）
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("carryable"):
			_pick_up_box(area)
			return
	# 再找可使用的：身上已经带着道具就不收了（一格只能放一个）
	for area in $PickupZone.get_overlapping_areas():
		if area.is_in_group("usable_item") and _item_icon == null:
			_pick_up_item(area)
			return

# 扛起箱子：变成箱子的父节点，位置摆在身前
func _pick_up_box(box: Area2D) -> void:
	_carried = box
	_carry_state = CarryState.CARRYING   # 状态切换：空手 → 负重（这就是"两个状态"）
	box.reparent(self, false)            # 认人做爹：从此跟着人走
	box.position = CARRY_OFFSET          # 摆到胸前

# 放下箱子：还回场景里，落在脚边
func _drop_box() -> void:
	var box := _carried
	_carried = null
	_carry_state = CarryState.EMPTY      # 状态切换：负重 → 空手
	box.reparent(get_parent(), false)    # 交还给场景（不再跟着人走）
	box.global_position = global_position + Vector2(18, -8)  # 放身前脚边

# 捡道具：图记进道具格，地上的物件消失
func _pick_up_item(item: Area2D) -> void:
	# 从物件身上找 Sprite2D 取图（不写死子节点名，换个叫法也不会崩）
	var spr := item.get_node_or_null("Sprite2D")
	if spr == null:
		for child in item.get_children():
			if child is Sprite2D:
				spr = child
				break
	if spr == null:
		return   # 没图就不收，免得收个空道具
	_item_icon = spr.texture
	item.queue_free()                  # 真消耗：地上的东西没了（不是藏起来）
	_refresh_item_slot()

# 用道具：今天没有任何效果，只负责消耗掉
func _use_item() -> void:
	_item_icon = null                  # 图没了 = 道具没了
	_refresh_item_slot()

# 道具格的亮/灭，只看 _item_icon 这一个数据
# 有图 → 显示；没图 → 隐藏。改道具系统时只动这一个数据，UI 自己会跟
#
# 【2026-11-02 搬家】道具格不再长在学生身上（那是搭错了：UI 属于界面，不属于角色）。
# 现在 HUD.tscn 独立摆在主场景里，学生只朝「hud」组喊一嗓子（广播站喊话）：
#   拿到/用掉了什么我不管你怎么显示——hud 组里的 HUD 听到，自己亮格/灭格。
# 铁律「发的人不知道谁在听」：学生不认识 HUD，HUD 也不认识学生。
# 换 HUD 布局、加宿管的危险度环，学生这行代码一个字不用动。
func _refresh_item_slot() -> void:
	get_tree().call_group("hud", "set_item", _item_icon)
