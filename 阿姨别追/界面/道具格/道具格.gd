extends CanvasLayer
# ============================================================
# HUD · 屏幕上的界面层（道具格住在这里）
# ------------------------------------------------------------
# 搬家说明（2026-11-02）：以前这个画布层挂在学生身上——搭错了。
# UI 属于「界面」，不属于「角色」。框架铁律：发的人不知道谁在听。
#   学生只朝「hud」组喊一嗓子「我拿到/用掉了什么」（call_group），
#   这边的道具格听到就亮/灭。学生不认识 HUD，HUD 也不认识学生。
# 以后宿管的危险度环、倒计时想上 HUD，同样进组听广播就行，互不牵连。
# ============================================================

func _ready() -> void:
	add_to_group("hud")   # 报名进组：「hud 频道我在听」
	# 换人时先把格子清空（2026-11-05 加）。
	# 为什么要清：场上不止一个学生之后，格子只有一个，谁最后喊就显示谁的。
	# 切到宿管时没人会来喊，格子就会一直挂着上一个学生的道具，看着像是她揣着东西。
	# 清空之后，新控制的人如果是学生，他会延后一帧再喊一嗓子把道具补上；宿管则保持空。
	Director.control_changed.connect(_on_control_changed)

func _on_control_changed(_who: Node) -> void:
	set_item(null)

# 收到广播才动格：有图 = 亮格显示；没图 = 灭格
func set_item(tex: Texture2D) -> void:
	var slot := $HUDRoot/ItemSlot
	slot.visible = tex != null
	slot.get_node("ItemIcon").texture = tex
