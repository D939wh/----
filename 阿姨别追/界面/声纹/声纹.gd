extends Control
## ============================================================
# 声纹 —— 屏幕正中央底下的一条「声音波形线」，全项目声音的脸。
# ------------------------------------------------------------
# 平时是一条几乎不动的细线。谁弄出动静，线就在「那个方向」隆起一段
# 起伏的波：越响顶得越高、波包越宽、颜色越白；越远越贴线两端、越黯淡。
# 声音在流动 —— 波包里的波浪会一直往一边滚，像真的在放音频。
#
# 【横轴怎么读】
#   线的正中央 = 听者脚下。往右是听者右边，往左是听者左边。
#   横轴不是线性的：中间（近处）撑得开，两端（远处）挤在一起，
#   用的是 sqrt 压缩。因为玩家最需要分清的是「近处左边还是右边」，
#   而不是 700 和 900 像素的区别。映射范围见 listen_span。
#   上下楼层的声音（dx≈0）会落在正中 —— 那正是「就在我附近」的读法。
#
# 【只管显示，不参与判断】
#   「多大声算听得见」跟宿管 AI 用同一把尺子：声音表.音量() +
#   声音表.最低反应音量。本文件不写第二份衰减公式或阈值。
#
# 【美术上的几条硬规矩】（借 ../../Git/gonju/TX/pixelfx 的做法）
#   1. 硬边、无抗锯齿：所有坐标 floor 成整数，1 列 = 1 像素。
#   2. 有限调色板：只有 dim / main / hot 三个色阶，按振幅换色，
#      不做连续渐变 —— 渐变在像素图里会糊成一片。
#   3. 线，不是填充：只画上下两条 1px 的包络线，中间不填。
#      填充之后响一声就变成一块实心矩形，像血条不像声纹。
#   4. 静线也要活：没人说话时有一层 ±1px 的呼吸，别画成一条死直线。
#
# 【怎么用】把 声纹.tscn 挂进场景（CanvasLayer，自己钉在视口上）。
# 听者 = Director.当前控制：F1 换人后，下一声按新耳朵算；
# 已经画出来的波不追着重算 —— 出声那一刻的方向和音量就定死了。
## ============================================================

const 声音表 := preload("res://数据/声音表.gd")

# —— 摆放（编辑器里直接调，不用改代码）——
@export_group("摆放")
## 线有多长（像素）。填 0 = 跟视口一样宽。
@export var line_length: float = 360.0
## 基线离屏幕底边多少像素。
@export var bottom_margin: float = 34.0

# —— 观感 ——
@export_group("观感")
## 最响的一声能顶多高（像素）。整条线的纵向预算就是它。
@export var max_amplitude: float = 26.0
## 向下画多少（1 = 完全对称）。线在屏幕底部，向下容易出屏，默认压扁一点。
@export var down_ratio: float = 0.38
## 线的左右两端代表「离听者多远的水平距离」。默认 = 最响那档的传播半径。
@export var listen_span: float = 900.0
## 次亮色：小峰的暖黄。
@export var mid_color: Color = Color(1.0, 0.80, 0.42, 0.9)
## 主色：主峰的亮黄。
@export var main_color: Color = Color(1.0, 0.92, 0.65, 0.97)
## 高光色：波峰的白。
@export var hot_color: Color = Color(1.0, 0.98, 0.90, 1.0)
## 静息色：贴着中线的暗金。
@export var dim_color: Color = Color(0.74, 0.68, 0.52, 0.72)
## 关掉就没有静息呼吸线了（只剩声音本身）。
@export var show_at_rest: bool = true

# —— 内部常量：改这些等于改手感，先想清楚 ——
const 波寿命: float = 1.15          # 一声从出现到消失多久
const 起音时间: float = 0.06       # 多快顶到最高（短 = 脆）
const 衰减指数: float = 1.5        # 越大尾巴收得越快
const 最薄窗宽: float = 0.08       # 波包半宽（归一化），轻响用这个
const 最宽窗宽: float = 0.20       # 波包半宽，贴脸巨响用这个
const 加厚阈值: float = 10.0       # 振幅超过这个才加 1px 光晕
const 静息幅度: float = 0.35        # 静线呼吸的峰值（像素；大了整条线会毛成虚线）
## 最多同时画几道波。超了丢最旧的 —— 十个人一起吵，线也只需要说「很吵」。
const 最多波数: int = 6

## 每种来源的波「糙不糙」：数字越大，一个波包里挤的峰越多。
## 脚步声是碎的、门声是闷的 —— 光看波纹疏密就能分出是什么响。
## 注意这个数字是「d=1 处转过几个半周期」，2.6 差不多是一个波包 3 个峰；
## 早先写成 8，一个波包挤了十几个峰，放大看全是一撮锯齿。
const 来源频率 := {
	声音表.来源_脚步: 4.6,
	声音表.来源_跑动: 4.0,
	声音表.来源_丢物: 3.0,
	声音表.来源_门: 1.8,
	声音表.来源_合闸: 1.2,
}

# —— 可读状态（自测直接读，不数像素）——
var _波们: Array = []     # {位置(-1..1), 音量(0..1), 剩余(秒), 频率, 种子}
var _时钟: float = 0.0
var _序号: int = 0


func _ready() -> void:
	Events.noise_made.connect(_听见声音)
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_时钟 += delta
	for i in range(_波们.size() - 1, -1, -1):
		_波们[i]["剩余"] = float(_波们[i]["剩余"]) - delta
		if float(_波们[i]["剩余"]) <= 0.0:
			_波们.remove_at(i)
	queue_redraw()


# ============================================================
# 听：够响就记下来，落在线的哪个位置
# ============================================================

func _听见声音(at_position: Vector2, radius: float, source_id: int) -> void:
	var 听者: Node = Director.当前控制
	if 听者 == null or not is_instance_valid(听者) or not (听者 is Node2D):
		return
	var 耳: Vector2 = (听者 as Node2D).global_position
	var 音量: float = 声音表.音量(耳.distance_to(at_position), radius)
	if 音量 < 声音表.最低反应音量:
		return   # 和宿管同一双耳朵：太轻就当没听见

	_序号 += 1
	var 位置: float = 归一(at_position.x - 耳.x)
	var 频率: float = float(来源频率.get(source_id, 6.0))

	# 同一个方向又来一声 → 刷新那个波包，不叠一个新的。
	# 不加这一步，连跑两步就在同一处叠出两团波，糊成一片看不出几下；
	# 而且「一直有人在那边跑」本来就该表现为那边一直在动，不是越堆越高。
	for 波 in _波们:
		if absf(float(波["位置"]) - 位置) < 0.06:
			波["音量"] = 音量
			波["剩余"] = 波寿命
			波["频率"] = 频率
			return

	_波们.append({
		"位置": 位置,
		"音量": 音量,
		"剩余": 波寿命,
		"频率": 频率,
		# 黄金角错开每一道波的相位，免得两声叠在一起长得一模一样
		"种子": fmod(float(_序号) * 2.39996, TAU),
	})
	if _波们.size() > 最多波数:
		_波们.remove_at(0)   # 丢最旧的那一道


## 水平距离（像素）→ 线的位置（-1 最左，+1 最右，0 正中 = 脚下）。
## sqrt 压缩：近处撑得开，远处挤在两端。
func 归一(水平距离: float) -> float:
	var 跨度: float = maxf(listen_span, 1.0)
	var t: float = clampf(水平距离 / 跨度, -1.0, 1.0)
	return signf(t) * sqrt(absf(t))


# ============================================================
# 算：某个位置此刻高多少（像素，正 = 向下）
# 纯函数，不依赖 _draw —— 无头测试也能直接问。
# ============================================================

func 取高(u: float) -> float:
	var 总: float = 0.0

	if show_at_rest:
		# 静息呼吸：两条不同步的慢正弦，范围约 ±0.35px，floor 之后只偶尔抖 1px
		总 += 静息幅度 * (0.6 * sin(u * 4.0 + _时钟 * 1.2) + 0.4 * sin(u * 9.3 - _时钟 * 1.9))

	for 波 in _波们:
		var 寿命: float = 波寿命
		var 已过: float = 寿命 - float(波["剩余"])
		var t: float = clampf(已过 / 寿命, 0.0, 1.0)
		var 起: float = clampf(已过 / 起音时间, 0.0, 1.0)          # 起音：一下顶上去
		var 包: float = 起 * pow(1.0 - t, 衰减指数)                 # 包络：慢慢收
		if 包 <= 0.001:
			continue

		var 音量: float = float(波["音量"])
		var 窗: float = 最薄窗宽 + (最宽窗宽 - 最薄窗宽) * pow(音量, 0.7)
		var d: float = (u - float(波["位置"])) / 窗
		if absf(d) > 2.4:
			continue   # 波包外面：不参与，省算力

		var 高斯: float = exp(-d * d * 1.5)
		# 波包里的浪：cos 保证 d=0（声源正上方）一定是个峰 —— 用 sin 的话
		# 声源恰好落在零点上，一声巨响会变成两小撮，读起来像两个声源。
		# 相位随时间往前滚 → 「声纹在流」；疏密看来源。
		var 相: float = d * PI * float(波["频率"]) - _时钟 * TAU * (1.6 + 1.2 * 音量) + float(波["种子"])
		var 浪: float = cos(相)
		# 音量开 0.6 次方：轻响也顶得起来，不然刚过阈值的那声几乎看不见
		总 += max_amplitude * pow(音量, 0.6) * 包 * 高斯 * 浪

	# 软限幅：好几声叠在一起时圆过去，不削出硬平顶（像素图里平顶像马赛克）
	return max_amplitude * tanh(总 / max_amplitude)


# ============================================================
# 画：一列一个像素点，上下两条包络线
# ============================================================

func _draw() -> void:
	var 长: float = line_length if line_length > 0.0 else size.x
	var 左: float = floorf((size.x - 长) * 0.5)
	var 中: float = floorf(size.y - bottom_margin)
	var 列数: int = int(round(长))
	if 列数 <= 0:
		return

	var 上次上: float = 中
	var 上次下: float = 中
	for i in range(列数):
		# 取列心，-1 最左 / +1 最右
		var u: float = ((float(i) + 0.5) / float(列数)) * 2.0 - 1.0
		var h: float = 取高(u)
		var 幅: float = absf(h)
		var x: float = 左 + float(i)
		var 色: Color = 色阶(幅)
		色.a *= 边缘淡出(u)

		var 上y: float = 中 - floorf(h)
		var 下y: float = 中 + floorf(h * down_ratio)

		# 补点：相邻两列高差 1~3px 时把中间填上。
		# 不补的话陡坡处会断成一串虚线，放大看像脏点，不像一条线。
		if i > 0:
			补竖(上次上, 上y, x, 色)
			补竖(上次下, 下y, x, 色)

		draw_rect(Rect2(x, 上y, 1, 1), 色)
		draw_rect(Rect2(x, 下y, 1, 1), 色)

		# 波峰外沿补一格极淡的光晕：像素图里的「rim light」
		if 幅 > 加厚阈值:
			var 晕: Color = Color(hot_color.r, hot_color.g, hot_color.b, 0.16)
			draw_rect(Rect2(x, 上y - 1, 1, 1), 晕)
			draw_rect(Rect2(x, 下y + 1, 1, 1), 晕)

		上次上 = 上y
		上次下 = 下y

## 同一列上把 a→b 之间空着的点补齐（只补近的，远的是真跳变，补了会变实心柱）。
func 补竖(a: float, b: float, x: float, 色: Color) -> void:
	var 差: float = absf(b - a)
	if 差 <= 1.0 or 差 > 4.0:
		return
	var 低: float = minf(a, b)
	for k in range(1, int(差)):
		draw_rect(Rect2(x, 低 + float(k), 1, 1), 色)


## 线两端淡淡收进去，不要硬切一刀 —— 硬边的线头像一根尺子贴在画面上。
func 边缘淡出(u: float) -> float:
	return clampf((1.0 - absf(u)) / 0.07, 0.0, 1.0)


## 振幅 → 四档颜色。档位少是故意的：连续渐变在像素画里会糊。
func 色阶(幅: float) -> Color:
	if 幅 <= 1.2:
		return dim_color
	if 幅 <= 5.0:
		return mid_color
	if 幅 <= 12.0:
		return main_color
	return hot_color


# ============================================================
# 给自测 / 别的系统读的状态
# ============================================================

func 波数() -> int:
	return _波们.size()


## 波们此刻的样子（复制一份，别让外面改到内部）
func 波快照() -> Array:
	var 出: Array = []
	for 波 in _波们:
		出.append({
			"位置": float(波["位置"]),
			"音量": float(波["音量"]),
			"剩余": float(波["剩余"]),
		})
	return 出


## 基线此刻画在哪（本节点坐标；全屏铺开时就是屏幕坐标）
func 基线() -> Vector2:
	return Vector2(floorf(size.x * 0.5), floorf(size.y - bottom_margin))


## 此刻线最高处的位置（-1..1）和它有多高（像素）。没声音时高度趋近 0。
func 峰值() -> Dictionary:
	var 最好: float = -1.0
	var 最好高: float = 0.0
	for i in range(161):
		var u: float = (float(i) / 160.0) * 2.0 - 1.0
		var h: float = absf(取高(u))
		if h > 最好高:
			最好高 = h
			最好 = u
	return { "位置": 最好, "高": 最好高 }
