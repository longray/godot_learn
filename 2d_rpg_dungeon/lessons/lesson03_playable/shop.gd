extends Control

# =========================
# 第 11 课：商店与永久升级
# 数据全部走 GameData（Autoload）——本场景只做展示与购买入口
# =========================

const MAIN_SCENE := "res://lessons/lesson03_playable/lesson03.tscn"

@onready var gold_label: Label = get_node_or_null("MarginContainer/VBoxContainer/GoldLabel")

@onready var health_button: Button = get_node_or_null("MarginContainer/VBoxContainer/HealthButton")
@onready var attack_button: Button = get_node_or_null("MarginContainer/VBoxContainer/AttackButton")
@onready var speed_button: Button = get_node_or_null("MarginContainer/VBoxContainer/SpeedButton")
@onready var start_button: Button = get_node_or_null("MarginContainer/VBoxContainer/StartButton")


func _ready() -> void:
	if health_button:
		health_button.pressed.connect(_on_health_button_pressed)

	if attack_button:
		attack_button.pressed.connect(_on_attack_button_pressed)

	if speed_button:
		speed_button.pressed.connect(_on_speed_button_pressed)

	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)

	update_ui()


func get_game_data() -> Node:
	return get_node_or_null("/root/GameData")


func update_ui() -> void:
	var game_data := get_game_data()

	if game_data == null:
		push_warning("找不到 GameData，请确认已经注册 Autoload。")
		return

	if gold_label:
		gold_label.text = "金币：%d" % game_data.gold

	if health_button:
		health_button.text = "最大生命 +1（Lv.%d → %d）  花费：%d" % [
			game_data.max_health_level,
			game_data.max_health_level + 1,
			game_data.get_upgrade_cost("max_health")
		]
		health_button.disabled = not game_data.can_afford("max_health")

	if attack_button:
		attack_button.text = "攻击伤害 +1（Lv.%d → %d）  花费：%d" % [
			game_data.attack_level,
			game_data.attack_level + 1,
			game_data.get_upgrade_cost("attack")
		]
		attack_button.disabled = not game_data.can_afford("attack")

	if speed_button:
		speed_button.text = "移动速度 +10%%（Lv.%d → %d）  花费：%d" % [
			game_data.speed_level,
			game_data.speed_level + 1,
			game_data.get_upgrade_cost("speed")
		]
		speed_button.disabled = not game_data.can_afford("speed")


func _buy(type: String) -> void:
	var game_data := get_game_data()

	if game_data == null:
		return

	if game_data.try_buy(type):
		print("购买成功：", type)
		update_ui()
	else:
		print("金币不足。")


func _on_health_button_pressed() -> void:
	_buy("max_health")


func _on_attack_button_pressed() -> void:
	_buy("attack")


func _on_speed_button_pressed() -> void:
	_buy("speed")


func _on_start_button_pressed() -> void:
	# 进入地牢（GameData 常驻，切换场景数据不丢）
	get_tree().change_scene_to_file(MAIN_SCENE)
