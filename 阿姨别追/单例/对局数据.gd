extends Node
## 对局账本 —— 只记两件事：哪扇门被真正解锁、谁已经跑出去了。
##
## 【它是什么】一块公开的事实板：不做判定、不管界面、不结束对局。
##   门解锁时往这里记一笔；出口判定成功时往这里上报一个人。
##   别人想听就接这里的两条信号，不用去找门或出口直接耦合。
##
## 【为什么挂载名必须英文】autoload 用中文名会被引擎按 Latin-1 解成乱码，找不到。

## 某扇门被三块钥匙板真正解锁（不是被 E 推开）。
signal door_unlocked(门号: String)

## 有人逃出去了。`谁` = 那个人本身。同一个人只会发一次。
signal door_escaped(谁: Node)

## 已经解锁的门编号。被推开的门不进这里。
var door_open: Array[String] = []

## 已经逃出去的人。按人去重，顺序就是逃出的先后。
var escaped: Array[Node] = []


## 这扇门是不是被解锁过
func is_door_unlocked(门号: String) -> bool:
	return 门号 in door_open


## 记一扇门被解锁。记过的门不再重复记、也不重复发信号
func register_unlock(门号: String) -> void:
	if 门号 in door_open:
		return
	door_open.append(门号)
	door_unlocked.emit(门号)
	print("[对局] %s 被真正解锁" % 门号)


## 记一个人逃出去。返回 true = 这是第一次记他（出口据此决定要不要弹提示）
func register_escape(谁: Node) -> bool:
	if 谁 == null or 谁 in escaped:
		return false
	escaped.append(谁)
	door_escaped.emit(谁)
	print("[对局] %s 逃出去了（第 %d 个）" % [谁.name, escaped.size()])
	return true


## 重开一局：把账本清空（留给以后的「重新开始」用）
func reset_match() -> void:
	door_open.clear()
	escaped.clear()
