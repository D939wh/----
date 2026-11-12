extends Node
## 声纹性能自测 —— 量「算一帧 360 列波形」要多久。超过 2ms 就得减少列数。
## 用法：Godot --headless 场景/测试/声纹性能自测.tscn
##
## 【为什么不做成 -s 探针】`-s` 跑的脚本里 autoload 名字编译期不可见
## （Events / Director 都报 Identifier not found），声纹.gd 直接编译失败。
## 走正常场景树就没事，代价是多一个 .tscn。

var _过: int = 0
var _败: int = 0


func _ready() -> void:
	var 面: Control = Control.new()
	面.set_script(load("res://界面/声纹/声纹.gd"))
	面.size = Vector2(640.0, 360.0)

	var 空: float = _量(面)
	断言("1 静息一帧 < 1ms", 空 < 1.0, "360 列 ≈ %.2f ms" % 空)

	for i in range(6):
		面._波们.append({
			"位置": -0.8 + float(i) * 0.3,
			"音量": 0.6,
			"剩余": 0.8,
			"频率": 3.4,
			"种子": float(i),
		})
	var 满: float = _量(面)
	断言("2 六道波一帧 < 2ms", 满 < 2.0, "360 列 ≈ %.2f ms（最挤的情况）" % 满)

	print("")
	print("=== 声纹性能自测：%d 过 / %d 败 ===" % [_过, _败])
	面.free()
	get_tree().quit(0 if _败 == 0 else 1)


## 返回「算完整 360 列」平均要多少毫秒
func _量(面: Control) -> float:
	var 列: int = 360
	var 轮: int = 200
	var t0: int = Time.get_ticks_usec()
	for r in range(轮):
		for i in range(列):
			面.取高((float(i) / float(列)) * 2.0 - 1.0)
	var t1: int = Time.get_ticks_usec()
	return float(t1 - t0) / 1000.0 / float(轮)


func 断言(名: String, 通过: bool, 细节: String) -> void:
	print("  %s: %s —— %s" % [名, "PASS" if 通过 else "FAIL", 细节])
	if 通过:
		_过 += 1
	else:
		_败 += 1
