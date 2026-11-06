extends CanvasLayer
# ============================================================
# HUD · 屏幕上的界面层（道具格住在这里）
# ------------------------------------------------------------
# UI 属于「界面」，不属于「角色」。框架铁律：发的人不知道谁在听。
#   学生只朝「hud」组喊一嗓子「我拿到/用掉了什么」（call_group），
#   这边的道具格听到就亮/灭。学生不认识 HUD，HUD 也不认识学生。
# ============================================================

func _ready() -> void:
	add_to_group("hud")   # 报名进组：「hud 频道我在听」
	# 换人时先把格子清空：格子只有一个，切到宿管时没人来喊，
	# 会一直挂着上一个学生的道具；新控制的学生会延后一帧再喊一嗓子补上。
	Director.control_changed.connect(_on_control_changed)

func _on_control_changed(_who: Node) -> void:
	set_item(null)

# 收到广播才动格：有图 = 亮格显示；没图 = 灭格
func set_item(tex: Texture2D) -> void:
	var slot := $HUDRoot/ItemSlot
	slot.visible = tex != null
	slot.get_node("ItemIcon").texture = tex
