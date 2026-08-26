class_name MiniMap
extends Control

# =========================
# 第 9 课：简单地牢小地图
# 纯 _draw() 绘制（方块/圆点/边框），零图片资源；
# 数据全部由 Main 推送（setup + update_state），自身不查游戏状态
# =========================

# 作业 4（第 9 课）：房间类型（Main 构建类型表用同一组常量；优先级 入口>出口>宝箱>怪物>普通）
const ROOM_NORMAL := 0
const ROOM_TREASURE := 1
const ROOM_MONSTER := 2
const ROOM_ENTRANCE := 3
const ROOM_EXIT := 4

# 作业 3（第 9 课）：房间编号字号（180x130 小地图上房间块约 20px，9px 恰好）
const NUMBER_FONT_SIZE := 9

@export var map_display_size: Vector2 = Vector2(180, 130)
@export var margin: float = 12.0

# 打开后小地图显示钥匙位置（默认关闭，避免直接暴露钥匙——探索型地牢保持迷雾）
@export var show_key: bool = false

var map_width: int = 1
var map_height: int = 1

var rooms: Array = []
var explored_rooms: Dictionary = {}

# 方案 C：走廊数据（元素 = {cells, room_a, room_b}，两端任一探索过整条点亮）
var corridors: Array = []

var current_room_index: int = -1

var entrance_cell := Vector2i(-1, -1)
var exit_cell := Vector2i(-1, -1)

var has_key: bool = false
var key_cell := Vector2i(-1, -1)

# 作业 1（第 9 课）：出口所在房间索引（-1 = 不在任何房间；探索过才显示红点）
var exit_room_index: int = -1

# 作业 2（第 9 课）：钥匙所在房间索引（-1 = 无钥匙；探索过才显示黄点）
var key_room_index: int = -1

# 作业 4（第 9 课）：房间类型表（索引对齐 rooms；空表 = 全普通）
var room_types: Array = []


func _ready() -> void:
	# UI 不应该挡住鼠标输入（攻击点击会落在小地图区域上）
	mouse_filter = MOUSE_FILTER_IGNORE

	_layout()


func _layout() -> void:
	# 固定在屏幕右上角（CanvasLayer 下不随相机移动）
	var viewport_size := get_viewport_rect().size

	size = map_display_size

	position = Vector2(
		viewport_size.x - size.x - margin,
		margin
	)


func setup(world_width: int, world_height: int, room_data: Array, corridor_data: Array = [], type_data: Array = []) -> void:
	# generate() 末尾调用：注入世界尺寸、房间矩形、走廊数据与类型表（格子坐标）
	map_width = maxi(1, world_width)
	map_height = maxi(1, world_height)

	rooms = room_data
	corridors = corridor_data
	room_types = type_data

	queue_redraw()


func update_state(
	explored: Dictionary,
	current_index: int,
	entrance: Vector2i,
	exit: Vector2i,
	key_owned: bool,
	key_pos: Vector2i,
	exit_room_idx: int = -1,
	key_room_idx: int = -1
) -> void:
	# Main 每次房间变化/钥匙拾取时推送最新状态
	explored_rooms = explored
	current_room_index = current_index
	entrance_cell = entrance
	exit_cell = exit
	has_key = key_owned
	key_cell = key_pos
	exit_room_index = exit_room_idx
	key_room_index = key_room_idx

	queue_redraw()


func _draw() -> void:
	# 背景（半透明深色，压在游戏画面上仍可辨认）
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(0.04, 0.04, 0.07, 0.65)
	)

	# 边框
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(1.0, 1.0, 1.0, 0.18),
		false,
		1.0
	)

	if rooms.is_empty():
		return

	if map_width <= 0 or map_height <= 0:
		return

	# 世界格子 → 小地图像素的缩放
	var scale := size / Vector2(map_width, map_height)

	# 方案 C：画走廊（先画，房间块覆盖在其上形成层次）
	# 两端任一房间探索过 → 整条点亮；颜色比房间灰块暗一档
	for corridor in corridors:
		var room_a: int = corridor.get("room_a", -1)
		var room_b: int = corridor.get("room_b", -1)

		if not (explored_rooms.has(room_a) or explored_rooms.has(room_b)):
			continue

		for cell_v in corridor.get("cells", []):
			var cell: Vector2i = cell_v
			draw_rect(
				Rect2(Vector2(cell.x, cell.y) * scale, Vector2(1, 1) * scale),
				Color(0.35, 0.35, 0.42, 0.85)
			)

	# 画已探索房间（未探索的不画——迷雾）
	for i in rooms.size():
		if not explored_rooms.has(i):
			continue

		var room: Rect2i = rooms[i]

		var room_position := Vector2(room.position.x, room.position.y)
		var room_size := Vector2(room.size.x, room.size.y)

		var rect := Rect2(room_position * scale, room_size * scale)

		# 作业 4：按房间类型配色；当前房间提亮（类型仍可辨）
		var is_current := i == current_room_index
		draw_rect(rect, _room_color(_room_type_at(i), is_current))

		# 作业 3：房间编号（白字黑描边，任意底色可读；居中）
		var center := rect.position + rect.size * 0.5
		var text := str(i + 1)
		var text_pos := Vector2(rect.position.x, center.y + NUMBER_FONT_SIZE * 0.36)
		var font := ThemeDB.fallback_font
		draw_string_outline(
			font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x, NUMBER_FONT_SIZE, 2, Color(0, 0, 0, 0.85)
		)
		draw_string(
			font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x, NUMBER_FONT_SIZE, Color(1, 1, 1, 0.92)
		)

		# 当前房间黄框强调
		if is_current:
			draw_rect(
				rect,
				Color(1.0, 0.9, 0.3, 0.9),
				false,
				1.5
			)

	# 入口（绿点）
	if entrance_cell != Vector2i(-1, -1):
		draw_circle(
			_cell_to_minimap_position(entrance_cell, scale),
			3.0,
			Color(0.2, 0.9, 0.4)
		)

	# 出口（红点；作业 1：探索过出口房间才显示——迷雾一致性）
	if exit_cell != Vector2i(-1, -1) and explored_rooms.has(exit_room_index):
		draw_circle(
			_cell_to_minimap_position(exit_cell, scale),
			3.0,
			Color(0.9, 0.25, 0.25)
		)

	# 钥匙（黄点，可选；作业 2：探索过钥匙房间才显示，拿到后消失）
	if show_key and key_cell != Vector2i(-1, -1) and not has_key and explored_rooms.has(key_room_index):
		draw_circle(
			_cell_to_minimap_position(key_cell, scale),
			3.0,
			Color(1.0, 0.9, 0.2)
		)


func _room_type_at(index: int) -> int:
	# 作业 4：类型表越界/未注入时按普通房处理
	if index < 0 or index >= room_types.size():
		return ROOM_NORMAL

	return int(room_types[index])


func _room_color(room_type: int, is_current: bool) -> Color:
	# 作业 4：类型配色（文档色板）；当前房间向白色 lerp 0.35 提亮
	var base := Color(0.45, 0.45, 0.52, 0.9)

	match room_type:
		ROOM_TREASURE:
			base = Color(0.82, 0.58, 0.28, 0.92)
		ROOM_MONSTER:
			base = Color(0.58, 0.40, 0.75, 0.92)
		ROOM_ENTRANCE:
			base = Color(0.25, 0.65, 0.40, 0.92)
		ROOM_EXIT:
			base = Color(0.72, 0.30, 0.30, 0.92)

	if is_current:
		base = base.lerp(Color(1, 1, 1, 1), 0.35)

	return base


func _cell_to_minimap_position(cell: Vector2i, scale: Vector2) -> Vector2:
	# 格子中心（+0.5）映射到小地图像素
	return (
		Vector2(cell.x, cell.y) + Vector2(0.5, 0.5)
	) * scale
