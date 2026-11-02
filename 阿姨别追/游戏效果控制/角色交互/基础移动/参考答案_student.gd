# ============================================================
# W1D1→W1D3 参考答案 · 学生移动（走+跳+爬）· v5「跟正式版逐行对齐 + 攀爬」
# ------------------------------------------------------------
# 用途：这份是正式版 student.gd 的「带注释镜像」——
#       【代码部分与 student.gd 完全一致，一个字不差】（主人 2026-10-29 22:48 定的规矩）；
#       差异只在注释：这份写足比喻、调法、门诊表。
#       以后调手感只改正式版，改完小鲸把这份同步过来。
#
# v5（2026-10-30 12:52）同步 W1D3 攀爬上车：
#   攀爬 = 学生摸到梯子（ClimbZone 感应区碰 layer 3）后，W 上爬 / S 下爬 / 空格蹬开。
#   无头模拟按键六动作全验证过：爬升 1.5s 升 100px（70px/s）✓ 松手挂住 ✓
#   下爬 ✓ 回地面 ✓ 蹬开 ✓。工程输入映射补了 down 动作（绑 S）。
#
# 前提（工程里已建好，不用改）：
#   - 输入动作名：left / right / jump / sprint / up / down
#   - student.tscn 里有 ClimbZone（Area2D，mask 只认 layer 3=梯子）
#   - 挂在 CharacterBody2D（角色车身）上
# ============================================================

extends CharacterBody2D

# ---------- 一、手感旋钮（调手感只动正式版这一段；规矩：一次只动一个数） ----------
# —— 走路：骑自行车 ——
const SPEED: float = 315.0      # 快走全速（像素/秒）。主人手拧：150→315
								# 嫌走得慢 → 调大；嫌太赶 → 调小
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
const JUMP_VELOCITY: float = -260.0  # 起跳蹬地那一下，负=向上。主人手拧 -230→-260
									 # 跳的高度只看它（≈260²÷736≈92px），想跳更高/矮 → 动它
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
								   # 定格期间顺余速最多再多飘约 40×0.03≈1px

# —— 攀爬（W1D3 新增：电梯式——按住 W 上爬 / S 下爬 / 空格蹬开）——
# 电梯类比：梯子是竖直的走廊，W/S 是"上行/下行"按钮；不按按钮就停在原地（挂住）。
const CLIMB_SPEED: float = 70.0     # 爬梯速度（像素/秒）。策划案 2.2 m/s 是换算失真前旧值，
									# 手感不对直接拧这。嫌爬得慢 → 调大
const CLIMB_OFF_JUMP: float = -180.0  # 从梯子上蹬开跳的初速（比地面跳矮——梯子跳主要是
									  # 横移到旁边平台，不是用来跳高的）。想蹬得更远 → 调大

# ---------- 二、八份"记性"（var 是活的，const 是定死的） ----------
var _on_ladder: bool = false  # 开关：手正摸着梯子吗（ClimbZone 碰到梯子层）
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
# ----------------------------------------------------------------

func _ready() -> void:
	# 抓梯感应区：ClimbZone（Area2D）碰到梯子层（layer 3）就算「摸到梯子」。
	# 信号=电话铃：ClimbZone 一碰/一离开梯子，就打给下面两个接电话的函数
	$ClimbZone.area_entered.connect(_on_climb_enter)
	$ClimbZone.area_exited.connect(_on_climb_exit)

func _on_climb_enter(_area: Area2D) -> void:
	_on_ladder = true   # 碰到梯子：记下"手在梯子上"

func _on_climb_exit(_area: Area2D) -> void:
	_on_ladder = false  # 离开梯子：记下"手松开了"

func _physics_process(delta: float) -> void:
	var dir := Input.get_axis("left", "right")  # 方向盘：右=1 左=-1 不按=0
	var sprint_held := Input.is_action_pressed("sprint")  # 按住 Shift？（按住=慢走）
	var updown := Input.get_axis("up", "down")  # 竖梯的方向盘：W=+1 上 S=-1 下
	# 注意：get_axis(up, down) 的值是"按 up 得 -1、按 down 得 +1"——W 上爬时
	# updown=-1，正好让 velocity.y = -70（负=向上），方向天然就是对的

	# ---- 0. 攀爬分支：整个梯子世界，跳过下面全部 ----
	# 【历史记录——正式版里这段注释已删，只留常量说明；过程都保留在这里】
	# 版本一（W1D3 初版）：条件写「按了上下 或 人不在地上」——站在梯子底下时人不归梯子管。
	# 版本二（2026-11-02 上午）：主人报"只有按 W 才像在爬"。实测确认 S 一直在爬，
	#   只是脚下是地板无处可下、位置不动，玩家以为自己没挂上。改成"贴梯+按上下=直接抓梯"。
	# 版本三（2026-11-02 下午，现行）：主人再提"只有按上键已经爬过梯子了所以挂着，
	#   没有就不要挂着"——碰到梯子本身不算挂，**必须真的按过上下键（开始爬过）才挂住**。
	#   所以拆成两个记性：`_on_ladder`（碰不碰得到梯子）和 `_climbing`（这一趟爬没爬过）。
	#   人贴着梯子但不按键、也没爬过 → 正常下落，不会被梯子吸住。
	#   爬过之后松手 → 仍挂住（电梯"暂停"档）。
	if _on_ladder and updown != 0.0:
		_climbing = true                     # 按了上下 = 这一趟开爬，记下"挂上了"
	if _on_ladder and _climbing:
		velocity.y = updown * CLIMB_SPEED    # 电梯：W 升 S 降；不按键=0=挂住
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 爬梯时左右刹住
		# 跳蹬开：从梯子上跳走。不给土狼宽限——不然贴着梯子每帧都"能跳"，会乱
		if Input.is_action_just_pressed("jump"):
			velocity.y = CLIMB_OFF_JUMP      # 蹬一下（比地面跳矮）
			velocity.x = dir * SPEED * 0.6    # 顺按住的方向横移（0.6=别荡太远）
			_climbing = false                 # 跳走这一瞬松手
		move_and_slide()
		return  # 这一帧到梯子为止，不走下面的重力/跳跃/左右——梯子上没重力

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
			# 注：从平台边走下去（初速≈0）也会先定格一拍再掉——
			# 悬停的副作用，代号宝石同款；正好和土狼宽限一起兜住"刚出边"的慌
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
	# 蹬完两表清零，防止落地瞬间又凑齐"想跳+能跳"变无限连跳
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
		# （物理惯性：真空没阻力，离地那一刻多快空中就多快）
		var same_dir := signf(velocity.x) == signf(dir)
		if not (not is_on_floor() and same_dir and absf(velocity.x) > target):
			velocity.x = move_toward(velocity.x, dir * target, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)  # 松脚：滑行

	# ---- 7. 挂挡 ----
	move_and_slide()
