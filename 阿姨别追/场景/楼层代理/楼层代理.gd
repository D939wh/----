extends Node2D
## 楼层代理 —— 你自己写的那句「各个地方有各个的代理」
##
## 它只负责「这一层」：
##   开局读清单，把这一层的门按位置建出来
##   以后灯、快递柜、电闸箱也归它管，用的是同一套写法（读清单 → 建出来 → 出事了照单处理）
##
## 所以你只要学会这一个文件，五层楼用的是同一份脚本，
## 区别只是挂上去时把「一楼」改成「二楼」——这就是「学一次，用五次」。

const 清单 = preload("res://数据/楼层清单.gd")
const 门场景 = preload("res://交互物/门/门.tscn")

## 这一层叫什么名字，要和清单里的名字对得上
@export var floor_id: String = "一楼"

## 编号 -> 门节点。以后灯、柜子也各自有一本这样的账
var _doors: Dictionary = {}


func _ready() -> void:
	Director.register_floor(floor_id, self)
	_seed_doors()


## 照清单把门建出来。位置全部来自数据文件，脚本里没有写死任何一个坐标
func _seed_doors() -> void:
	var data: Dictionary = 清单.楼层.get(floor_id, {})
	var door_list: Array = data.get("门", [])
	for one in door_list:
		var d: Node2D = 门场景.instantiate()
		add_child(d)
		d.setup(floor_id, one["编号"], one["位置"])
		_doors[one["编号"]] = d
	print("[代理·%s] 照清单建了 %d 扇门" % [floor_id, _doors.size()])


## 总管把话递到这里。以后「灯要亮」「柜子要弹开」也走这一个口
func on_report(event: String, data: Dictionary) -> void:
	match event:
		"door_pressed":
			print("[代理·%s] 收到：%s 被按了" % [floor_id, data.get("door_id", "?")])
		_:
			print("[代理·%s] 收到不认识的事：%s" % [floor_id, event])


## 给外部查询：这一层的某扇门
func get_door(door_id: String) -> Node:
	return _doors.get(door_id, null)
