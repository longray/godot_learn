extends CharacterBody2D

# =========================
# 第 4 课作业 5：真正的敌人场景
# 根节点 CharacterBody2D（为下一课移动 AI / 战斗预留架构）
# 本课行为与"怪物危险区"一致：玩家触碰 → 信号通知 Main → 传送回入口
# =========================

# 玩家触碰信号（解耦：敌人只报告事件，惩罚逻辑归 Main）
signal player_touched

# 呼吸动画计时
var _t := 0.0


func _ready() -> void:
	var hazard := $HazardArea as Area2D
	if hazard:
		hazard.body_entered.connect(_on_hazard_body_entered)


func _process(delta: float) -> void:
	# 史莱姆呼吸：轻微正弦缩放
	# 只缩 Sprite2D 不缩根节点——根 scale 会连带缩放子节点碰撞体，破坏触发半径
	_t += delta
	var s := 1.0 + 0.08 * sin(_t * 3.0)
	$Sprite2D.scale = Vector2(s, s)


func _on_hazard_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_touched.emit()
