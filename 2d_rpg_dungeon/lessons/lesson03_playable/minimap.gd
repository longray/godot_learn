extends Control

# =========================
# 第 9 课：简单地牢小地图
# 纯 _draw() 绘制（方块/圆点/边框），零图片资源；
# 数据全部由 Main 推送（setup + update_state），自身不查游戏状态
# =========================

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


func setup(world_width: int, world_height: int, room_data: Array, corridor_data: Array = []) -> void:
	# generate() 末尾调用：注入世界尺寸、房间矩形与走廊数据（格子坐标）
	map_width = maxi(1, world_width)
	map_height = maxi(1, world_height)

	rooms = room_data
	corridors = corridor_data

	queue_redraw()


func update_state(
	explored: Dictionary,
	current_index: int,
	entrance: Vector2i,
	exit: Vector2i,
	key_owned: bool,
	key_pos: Vector2i,
	exit_room_idx: int = -1
) -> void:
	# Main 每次房间变化/钥匙拾取时推送最新状态
	explored_rooms = explored
	current_room_index = current_index
	entrance_cell = entrance
	exit_cell = exit
	has_key = key_owned
	key_cell = key_pos
	exit_room_index = exit_room_idx

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

		# 当前房间更亮
		var color := Color(0.45, 0.45, 0.52, 0.9)

		if i == current_room_index:
			color = Color(0.85, 0.85, 0.92, 0.95)

		draw_rect(rect, color)

		# 当前房间黄框强调
		if i == current_room_index:
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

	# 钥匙（黄点，可选；拿到后消失）
	if show_key and key_cell != Vector2i(-1, -1) and not has_key:
		draw_circle(
			_cell_to_minimap_position(key_cell, scale),
			3.0,
			Color(1.0, 0.9, 0.2)
		)


func _cell_to_minimap_position(cell: Vector2i, scale: Vector2) -> Vector2:
	# 格子中心（+0.5）映射到小地图像素
	return (
		Vector2(cell.x, cell.y) + Vector2(0.5, 0.5)
	) * scale
