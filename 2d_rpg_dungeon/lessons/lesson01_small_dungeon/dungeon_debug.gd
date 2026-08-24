extends Node2D

# =========================
# 第 1 课：小规模 2D 地牢
# 数据先行：先生成格子数据，再用 _draw() 可视化
# =========================

# 地图参数
@export var seed_value: int = 20260824
@export var use_random_seed: bool = false

@export var map_width: int = 48
@export var map_height: int = 32

# 房间参数
@export var room_attempts: int = 60
@export var max_rooms: int = 10

@export var min_room_size: Vector2i = Vector2i(4, 3)
@export var max_room_size: Vector2i = Vector2i(10, 7)

# 显示参数
@export var cell_size: int = 16

# 地图数据
# 0 = 墙
# 1 = 地板
var grid: Array = []

# 保存房间，方便后续放怪物、宝箱、入口、出口
var rooms: Array = []

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	generate()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return

	if key.pressed and not key.echo and key.keycode == KEY_R:
		generate()


func generate() -> void:
	# 防止地图太小
	map_width = maxi(20, map_width)
	map_height = maxi(16, map_height)

	_setup_rng()
	_clear_map()
	_place_rooms()
	_connect_rooms()
	_center_camera()

	queue_redraw()


func _setup_rng() -> void:
	if use_random_seed:
		rng.randomize()
	else:
		rng.seed = seed_value


func _clear_map() -> void:
	grid.clear()
	rooms.clear()

	grid.resize(map_height)

	for y in map_height:
		var row: Array = []
		row.resize(map_width)
		row.fill(0)
		grid[y] = row


func _place_rooms() -> void:
	for i in room_attempts:
		if rooms.size() >= max_rooms:
			break

		var room := _make_random_room()

		if room.size.x <= 0 or room.size.y <= 0:
			continue

		if not _overlaps_existing_room(room):
			rooms.append(room)
			_carve_room(room)


func _make_random_room() -> Rect2i:
	var max_w := mini(max_room_size.x, map_width - 3)
	var max_h := mini(max_room_size.y, map_height - 3)

	if max_w < 2 or max_h < 2:
		return Rect2i()

	var min_w := clampi(min_room_size.x, 2, max_w)
	var min_h := clampi(min_room_size.y, 2, max_h)

	var w := rng.randi_range(min_w, max_w)
	var h := rng.randi_range(min_h, max_h)

	var x := rng.randi_range(1, map_width - w - 2)
	var y := rng.randi_range(1, map_height - h - 2)

	return Rect2i(x, y, w, h)


func _overlaps_existing_room(room: Rect2i) -> bool:
	# 向外扩一格，让房间之间保留一点间距
	var expanded := Rect2i(
		room.position.x - 1,
		room.position.y - 1,
		room.size.x + 2,
		room.size.y + 2
	)

	for existing in rooms:
		if _rect2i_intersects(expanded, existing):
			return true

	return false


func _rect2i_intersects(a: Rect2i, b: Rect2i) -> bool:
	return (
		a.position.x < b.position.x + b.size.x
		and a.position.x + a.size.x > b.position.x
		and a.position.y < b.position.y + b.size.y
		and a.position.y + a.size.y > b.position.y
	)


func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			_set_cell(x, y, 1)


func _connect_rooms() -> void:
	if rooms.size() < 2:
		return

	# 作业 5：增量式最近邻连接
	# 每个新房间只连到「已入住房间」中离它最近的一个
	# 总连接数仍是 n-1（保证连通），但每次连接局部最优，走廊大幅缩短
	# 注意：distance_squared_to 不开根号——比大小结果相同，省 sqrt
	for i in range(1, rooms.size()):
		var from := _room_center(rooms[i])
		var best_j := 0
		var best_dist := from.distance_squared_to(_room_center(rooms[0]))

		for j in range(1, i):
			var d := from.distance_squared_to(_room_center(rooms[j]))
			if d < best_dist:
				best_dist = d
				best_j = j

		var b := _room_center(rooms[best_j])

		if rng.randf() < 0.5:
			_carve_h_corridor(from.x, b.x, from.y)
			_carve_v_corridor(from.y, b.y, b.x)
		else:
			_carve_v_corridor(from.y, b.y, from.x)
			_carve_h_corridor(from.x, b.x, b.y)


func _room_center(room: Rect2i) -> Vector2i:
	return Vector2i(
		room.position.x + room.size.x / 2,
		room.position.y + room.size.y / 2
	)


func _carve_h_corridor(x1: int, x2: int, y: int) -> void:
	var from := mini(x1, x2)
	var to := maxi(x1, x2)

	for x in range(from, to + 1):
		_set_cell(x, y, 1)


func _carve_v_corridor(y1: int, y2: int, x: int) -> void:
	var from := mini(y1, y2)
	var to := maxi(y1, y2)

	for y in range(from, to + 1):
		_set_cell(x, y, 1)


func _set_cell(x: int, y: int, value: int) -> void:
	if x < 0 or x >= map_width:
		return
	if y < 0 or y >= map_height:
		return

	grid[y][x] = value


func _center_camera() -> void:
	var cam := get_node_or_null(^"Camera2D") as Camera2D
	if cam:
		cam.make_current()
		cam.position = Vector2(
			map_width * cell_size * 0.5,
			map_height * cell_size * 0.5
		)


func _draw() -> void:
	if grid.is_empty():
		return

	# 画格子
	for y in map_height:
		for x in map_width:
			var rect := Rect2(
				x * cell_size,
				y * cell_size,
				cell_size,
				cell_size
			)

			var color := Color(0.08, 0.08, 0.10)

			if grid[y][x] == 1:
				color = Color(0.82, 0.75, 0.60)

			draw_rect(rect, color)

	# 画房间边框，方便观察房间分布
	for room in rooms:
		var rect := Rect2(
			room.position.x * cell_size,
			room.position.y * cell_size,
			room.size.x * cell_size,
			room.size.y * cell_size
		)

		draw_rect(rect, Color(0.2, 1.0, 0.5, 0.25), false, 2.0)

	# 作业 3：给每个房间中心画红色小圆点
	# 这些点未来会变成：怪物刷新点 / 玩家出生点 / 宝箱点 / 楼梯点
	for room in rooms:
		var center := _room_center(room)
		var pos := Vector2(
			center.x * cell_size + cell_size * 0.5,
			center.y * cell_size + cell_size * 0.5
		)
		draw_circle(pos, 3.0, Color(1.0, 0.3, 0.3))

	# 作业 4：显示房间编号（按生成顺序，观察 1→2→3 的链式连接路径）
	# draw_string 的 pos 是文本【基线】左端点：数字底贴基线、字形在基线上方约 7px
	# 所以基线 y 要放到圆心下方 +4（≈半个字形高）才是垂直居中；x +4 = 圆半径 3 + 1px 间隙
	var font := ThemeDB.fallback_font
	for i in rooms.size():
		var center := _room_center(rooms[i])
		var pos := Vector2(
			center.x * cell_size + cell_size * 0.5 + 4.0,
			center.y * cell_size + cell_size * 0.5 + 4.0
		)
		draw_string(font, pos, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.0, 0.0, 0.0))
