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

# 第 12 课：测试跳层（输入层数直入地牢——测精英/层数成长用；正常游戏请走"进入地牢"）
@onready var floor_edit: LineEdit = get_node_or_null("MarginContainer/VBoxContainer/DebugHBox/FloorEdit")
@onready var jump_button: Button = get_node_or_null("MarginContainer/VBoxContainer/DebugHBox/JumpButton")
@onready var elite_hint_label: Label = get_node_or_null("MarginContainer/VBoxContainer/EliteHintLabel")


func _ready() -> void:
	if health_button:
		health_button.pressed.connect(_on_health_button_pressed)

	if attack_button:
		attack_button.pressed.connect(_on_attack_button_pressed)

	if speed_button:
		speed_button.pressed.connect(_on_speed_button_pressed)

	if start_button:
		start_button.pressed.connect(_on_start_button_pressed)

	# 测试跳层：按钮 + 输入实时刷新精英率提示
	if jump_button:
		jump_button.pressed.connect(_on_jump_button_pressed)

	if floor_edit:
		floor_edit.text_changed.connect(_on_floor_text_changed)
		floor_edit.text_submitted.connect(func(_t): _on_jump_button_pressed())

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


func _parse_floor_input() -> int:
	# 解析输入层数：非数字回退 1，范围钳制 1..99
	var f := int(floor_edit.text)

	if str(f) != floor_edit.text.strip_edges():
		f = 1

	return clampi(f, 1, 99)


func _on_floor_text_changed(new_text: String) -> void:
	# 实时提示该层精英率（公式与 dungeon_playable 三 @export 同步——仅提示用）
	var n := 1

	if new_text.strip_edges().is_valid_int():
		n = clampi(int(new_text), 1, 99)

	var chance := clampf(0.05 + 0.02 * n, 0.0, 0.25)
	elite_hint_label.text = "第 %d 层：精英率 %.0f%%（血 +1/2层 伤 +1/4层）" % [n, chance * 100.0]


func _on_jump_button_pressed() -> void:
	# 跳层测试：写 GameData 通道 → 地牢 generate 消费即清零（不影响正常流程/存档）
	var game_data := get_game_data()

	if game_data:
		game_data.debug_start_floor = _parse_floor_input()
		print("跳层测试：第 ", game_data.debug_start_floor, " 层")

	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_start_button_pressed() -> void:
	# 进入地牢（GameData 常驻，切换场景数据不丢）
	get_tree().change_scene_to_file(MAIN_SCENE)
