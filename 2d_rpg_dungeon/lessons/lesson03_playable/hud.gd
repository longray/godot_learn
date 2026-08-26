extends CanvasLayer

# =========================
# 第 8 课：HUD 状态面板（独立场景）
# 职责单一：只管显示，不持有游戏状态——
# Main 通过 update_* 方法推送数据，玩家生命经 health_changed 信号 → Main 转发进来
# =========================

@onready var health_ui: HBoxContainer = $VBoxContainer/HealthUI
@onready var gold_label: Label = $VBoxContainer/GoldRow/GoldLabel
@onready var key_label: Label = $VBoxContainer/KeyRow/KeyLabel
@onready var floor_label: Label = $VBoxContainer/FloorLabel
@onready var treasure_label: Label = $VBoxContainer/TreasureLabel
@onready var explore_label: Label = $VBoxContainer/ExploreLabel

# 作业 2/3（第 8 课）：钥匙/金币图标（TextureRect 显示像素素材，替代纯文字前缀）
@onready var key_icon: TextureRect = $VBoxContainer/KeyRow/KeyIcon

# 作业 4/5（第 8 课）：受伤红屏覆盖层 + 死亡大字
@onready var hurt_overlay: ColorRect = $HurtOverlay
@onready var death_label: Label = $DeathLabel

# 红屏参数：瞬间拉到 0.25 透明度，每秒衰减 0.5（约 0.5s 消退）
const HURT_FLASH_ALPHA := 0.25
const HURT_FADE_SPEED := 0.5

# 死亡提示显示时长（秒）
const DEATH_SHOW_TIME := 1.2

var _death_showing := false

# 第 5 课资产迁移：心形纹理（满/空心）
const HEART_FULL_TEXTURE: Texture2D = preload("res://assets/sprites/heart_full.png")
const HEART_EMPTY_TEXTURE: Texture2D = preload("res://assets/sprites/heart_empty.png")


func update_health(current_health: int, max_health: int) -> void:
	# 心形数量随 max_health 动态同步（场景里预置 3 颗，运行时按需增减）
	_sync_heart_count(max_health)

	# 作业 1（第 5 课）：i < current 满心，否则空心
	for i in health_ui.get_child_count():
		var heart := health_ui.get_child(i) as TextureRect
		if heart == null:
			continue

		heart.texture = HEART_FULL_TEXTURE if i < current_health else HEART_EMPTY_TEXTURE


func update_gold(gold: int) -> void:
	# 作业 3（第 8 课）：金币图标已在行首，文字只留数量
	gold_label.text = "× %d" % gold
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))


func update_key(has_key: bool) -> void:
	# 作业 2（第 8 课）：钥匙图标随状态点亮/灰暗——图标即语义，文字只留状态
	key_icon.modulate = Color(1.0, 1.0, 1.0) if has_key else Color(0.35, 0.35, 0.4)

	if has_key:
		key_label.text = "已获得 ✓ 出口已解锁"
		key_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	else:
		key_label.text = "未获得"
		key_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))


func show_key_locked_hint() -> void:
	# 第 4 课资产迁移：踩到锁定出口时的红字提示（覆盖 update_key 的常规文案）
	key_label.text = "出口被锁住了！去寻找金钥匙…"
	key_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))


func update_floor(floor_number: int) -> void:
	# 第 8 课新增：层数显示（出口进入下一层时 +1）
	floor_label.text = "层数：第 %d 层" % floor_number
	floor_label.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))


func update_treasure(opened: int, total: int) -> void:
	# 第 5 课格式迁移：已开 / 总数（宝箱拾取后不回收格子，总数稳定）
	treasure_label.text = "宝箱：%d/%d" % [opened, total]
	treasure_label.add_theme_color_override("font_color", Color(1.0, 0.67, 0.43))


func update_explore(explored: int, total: int) -> void:
	# 作业 5（第 9 课）：探索进度（走进过的房间数 / 总房间数）
	explore_label.text = "探索：%d / %d" % [explored, total]
	explore_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))


func _sync_heart_count(count: int) -> void:
	# 动态增减心形节点（max_health 改变时 HUD 自动跟上）
	while health_ui.get_child_count() < count:
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(16, 16)
		heart.texture = HEART_EMPTY_TEXTURE
		health_ui.add_child(heart)

	# queue_free 到帧末才真正移除，child_count 不会立即下降——缩容循环天然只跑一次
	while health_ui.get_child_count() > count:
		health_ui.get_child(health_ui.get_child_count() - 1).queue_free()


func _process(delta: float) -> void:
	# 作业 4（第 8 课）：红屏渐隐（每帧把红色 alpha 往 0 衰减）
	if hurt_overlay.color.a > 0.0:
		hurt_overlay.color.a = maxf(0.0, hurt_overlay.color.a - HURT_FADE_SPEED * delta)


func flash_hurt() -> void:
	# 作业 4（第 8 课）：受伤瞬间红屏（透明度瞬间拉满，_process 里负责消退）
	hurt_overlay.color.a = HURT_FLASH_ALPHA


func show_death() -> void:
	# 作业 5（第 8 课）：死亡大字，居中弹出 DEATH_SHOW_TIME 秒后隐藏
	# _death_showing 守卫：连续死亡时避免两个并发 await 互相提前关灯
	if _death_showing:
		return

	_death_showing = true
	death_label.visible = true
	await get_tree().create_timer(DEATH_SHOW_TIME).timeout
	death_label.visible = false
	_death_showing = false
