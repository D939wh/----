extends "res://组件/状态机/状态.gd"
## 插钥匙中 —— 站在锁孔前那几秒，人钉在原地。
##
## 由锁口调用 `钉住(true)` 进入，`钉住(false)` 退出。
## 本状态不吃键盘、不跳跃、不攀爬，但重力照常。
## “插孔用时 2.0 秒”同时写在物件代理的兜底和锁口自己的初值里；
## “站多久 1.0 秒”也是代理和出口两处。现在两张清单里都显式填了数，
##所以两份默认值 没实际打架 ，但这属于同一句话写在两个地方，早晚容易改岔
## 后面看到这里记得修改
func 每帧(delta: float) -> void:
	var h = host
	# 不吃键盘、不能跳、不能爬；但重力照常 —— 脚下的地要是没了，该掉还是得掉
	h.velocity.x = 0.0
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	else:
		h.velocity.y = 0.0
	h.move_and_slide()
