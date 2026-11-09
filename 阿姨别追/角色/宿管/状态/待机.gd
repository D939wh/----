extends "res://组件/状态机/状态.gd"
## 待机 —— AI 的常态：站在原地不动，看见人、或者站够时间，就交给决策挑下一步。
##
## 和学生的 `待机` 一个意思：这里不做事，判断在上面 `宿管.gd` 的 `decide()`。
## 「看得见谁」由 `_看得见的目标()` 给出，状态里不写察觉逻辑 ——
## 照参考项目那样：感知归感知，走位归走位。
##
## 为什么要有 `待机最长`：只靠「看见人才动」的话，主场景3 里她就是一根柱子。
## 站够 2 秒自己起身巡逻，楼道里才有东西在动。

const 状态名 := preload("res://角色/宿管/状态/状态名.gd")

## 这次已经站了多久（秒）。进状态时清零。
var _站了: float = 0.0


func 进入(_上个: String = "") -> void:
	_站了 = 0.0


func 每帧(delta: float) -> void:
	var h = host

	# 站定：速度收回 0，但重力照常（站在半空会被放下来）
	h.velocity.x = move_toward(h.velocity.x, 0.0, h.FRICTION * delta)
	if not h.is_on_floor():
		h.velocity.y += h.GRAVITY * delta
	h.move_and_slide()

	# 看见人 → 立刻交给决策（`decide()` 会给出追击）
	if h._看得见的目标() != null:
		机器().切(h.decide())
		return

	# 看不见人，但站够时间了 → 起身巡逻
	_站了 += delta
	if _站了 >= h.待机最长:
		机器().切(状态名.巡逻)
