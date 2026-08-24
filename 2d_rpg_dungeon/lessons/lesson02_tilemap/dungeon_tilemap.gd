extends Node2D

# =========================
# 第 2 课：接入 TileMapLayer 和入口/出口
# 表现层从 _draw() 换成 TileMap，数据层（grid/rooms）不变
# =========================

# ---------- 基础生成参数 ----------

@export var seed_value: int = 20260824
@export var use_random_seed: bool = false

@export var map_width: int = 48
@export var map_height: int = 32

@export var room_attempts: int = 60
@export var max_rooms: int = 10

@export var min_room_size: Vector2i = Vector2i(4, 3)
@export var max_room_size: Vector2i = Vector2i(10, 7)

@export var cell_size: int = 16

# ---------- TileMap 参数 ----------

@export_group("TileMap")

# 如果为 true，脚本会自动创建一个临时 TileSet
# 适合本课学习，不需要美术资源
@export var use_placeholder_tileset: bool = true

# 如果你使用自己的 TileSet，可以关闭 use_placeholder_tileset
# 然后手动设置 source id 和 atlas coords
@export var tile_source_id: int = 0

# 作业 5 方案 A：外部图集路径（非空且存在则优先加载，替代代码生成的纯色图集）
# 图集布局：横向 4 格 [地板][墙壁][入口][出口]，每格 cell_size 大小
@export var external_tiles_path: String = "res://assets/tiles/dungeon_tiles.png"

@export var floor_atlas_coords: Vector2i = Vector2i(0, 0)
@export var wall_atlas_coords: Vector2i = Vector2i(1, 0)
@export var entrance_atlas_coords: Vector2i = Vector2i(2, 0)
@export var exit_atlas_coords: Vector2i = Vector2i(3, 0)

# ---------- 节点 ----------

@onready var tile_layer: TileMapLayer = $TileMapLayer

# ---------- 数据 ----------

const CELL_WALL := 0
const CELL_FLOOR := 1

var rng := RandomNumberGenerator.new()

# grid[y][x]
# 0 = wall
# 1 = floor
var grid: Array = []

var rooms: Array = []

var entrance_cell := Vector2i.ZERO
var exit_cell := Vector2i.ZERO


func _ready() -> void:
	if tile_layer == null:
		push_error("找不到 TileMapLayer，请确认场景里有名为 TileMapLayer 的子节点。")
		return

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
	_pick_entrance_and_exit()

	_setup_tilemap()
	_build_tilemap()

	_center_camera()
	_spawn_markers()


# =========================
# 入口 / 出口标记（作业 1+2）
# =========================

func _spawn_markers() -> void:
	# 重新生成前先清理旧标记，否则每按一次 R 就多一对（queue_free 帧末生效，帧内短暂共存无害）
	_clear_markers()

	var entrance_marker := Marker2D.new()
	entrance_marker.name = "EntranceMarker"
	entrance_marker.position = get_entrance_local_position()
	add_child(entrance_marker)

	var exit_marker := Marker2D.new()
	exit_marker.name = "ExitMarker"
	exit_marker.position = get_exit_local_position()
	add_child(exit_marker)


func _clear_markers() -> void:
	for child in get_children():
		if child is Marker2D:
			# 先脱离树再延迟释放：remove_child 立即解除名字占用，
			# 否则同帧 spawn 的同名新节点会被 Godot 改成匿名节点（@Marker2D@2），引用会断
			remove_child(child)
			child.queue_free()


# =========================
# RNG
# =========================

func _setup_rng() -> void:
	if use_random_seed:
		rng.randomize()
	else:
		rng.seed = seed_value


# =========================
# 地图数据
# =========================

func _clear_map() -> void:
	grid.clear()
	rooms.clear()

	entrance_cell = Vector2i.ZERO
	exit_cell = Vector2i.ZERO

	grid.resize(map_height)

	for y in map_height:
		var row: Array = []
		row.resize(map_width)
		row.fill(CELL_WALL)
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
	# 向外扩一格，让房间之间保留间距
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
			_set_cell(x, y, CELL_FLOOR)


func _connect_rooms() -> void:
	if rooms.size() < 2:
		return

	# 第 1 课作业 5 成果：增量式最近邻连接（文档此处为旧版链式，已按仓库现状保留本版）
	# 每个新房间只连到「已入住房间」中离它最近的一个
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
		_set_cell(x, y, CELL_FLOOR)


func _carve_v_corridor(y1: int, y2: int, x: int) -> void:
	var from := mini(y1, y2)
	var to := maxi(y1, y2)

	for y in range(from, to + 1):
		_set_cell(x, y, CELL_FLOOR)


func _set_cell(x: int, y: int, value: int) -> void:
	if x < 0 or x >= map_width:
		return
	if y < 0 or y >= map_height:
		return

	grid[y][x] = value


# =========================
# 入口 / 出口
# =========================

func _pick_entrance_and_exit() -> void:
	if rooms.is_empty():
		# 如果参数太严格导致没有房间，做一个保底地板点
		entrance_cell = Vector2i(map_width / 2, map_height / 2)
		exit_cell = entrance_cell
		_set_cell(entrance_cell.x, entrance_cell.y, CELL_FLOOR)
		return

	# 作业 3：单房间时在房间内随机选两个不同格子，避免入口=出口
	if rooms.size() == 1:
		var room: Rect2i = rooms[0]
		entrance_cell = _random_cell_in_room(room)
		exit_cell = _random_cell_in_room(room)
		# 房间内格子有限，理论上可能重合——最多重试几次拉开
		var retries := 0
		while exit_cell == entrance_cell and retries < 8:
			exit_cell = _random_cell_in_room(room)
			retries += 1
		return

	# 入口：第一个房间中心
	entrance_cell = _room_center(rooms[0])

	# 作业 4：出口 = 从入口出发「实际路径」最长的房间中心
	# 直线最远 ≠ 走路最远：走廊绕行时欧氏距离会骗人，用 AStarGrid2D 算真实路径
	var astar := _build_astar_grid()

	exit_cell = entrance_cell
	var best_path_len := -1

	for room in rooms:
		var center := _room_center(room)
		var path := astar.get_id_path(entrance_cell, center)

		if path.size() > best_path_len:
			best_path_len = path.size()
			exit_cell = center


func _build_astar_grid() -> AStarGrid2D:
	# 用 grid 数据构建寻路网格：默认全墙，地板格才可通行
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, map_width, map_height)
	astar.cell_size = Vector2i(1, 1) # 直接用格子坐标作点 id
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER # 四方向，符合走廊地牢移动语义
	astar.update()

	astar.fill_solid_region(astar.region, true)

	for y in map_height:
		for x in map_width:
			if grid[y][x] == CELL_FLOOR:
				astar.set_point_solid(Vector2i(x, y), false)

	return astar


func _random_cell_in_room(room: Rect2i) -> Vector2i:
	# 在房间矩形内均匀随机取一格（含边界）
	return Vector2i(
		rng.randi_range(room.position.x, room.position.x + room.size.x - 1),
		rng.randi_range(room.position.y, room.position.y + room.size.y - 1)
	)


func get_entrance_local_position() -> Vector2:
	return _cell_to_center_local(entrance_cell)


func get_exit_local_position() -> Vector2:
	return _cell_to_center_local(exit_cell)


func _cell_to_center_local(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5


# =========================
# TileMap
# =========================

func _setup_tilemap() -> void:
	if use_placeholder_tileset:
		tile_source_id = _create_placeholder_tileset()

		# placeholder TileSet 固定使用这四个坐标
		floor_atlas_coords = Vector2i(0, 0)
		wall_atlas_coords = Vector2i(1, 0)
		entrance_atlas_coords = Vector2i(2, 0)
		exit_atlas_coords = Vector2i(3, 0)
	else:
		if tile_layer.tile_set == null:
			push_warning("你关闭了 use_placeholder_tileset，但 TileMapLayer 上没有设置 TileSet。")


func _create_placeholder_tileset() -> int:
	# 作业 5 方案 A：优先加载外部图集（像素风素材），文件缺失则回退代码生成
	var texture: Texture2D

	if external_tiles_path != "" and ResourceLoader.exists(external_tiles_path):
		texture = load(external_tiles_path) as Texture2D
	else:
		texture = _generate_placeholder_texture()

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(cell_size, cell_size)

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(cell_size, cell_size)

	var source_id := tile_set.add_source(source)

	if source_id < 0:
		push_error("创建 placeholder TileSet source 失败。")
		return -1

	source.create_tile(Vector2i(0, 0)) # floor
	source.create_tile(Vector2i(1, 0)) # wall
	source.create_tile(Vector2i(2, 0)) # entrance
	source.create_tile(Vector2i(3, 0)) # exit

	tile_layer.tile_set = tile_set

	return source_id


func _generate_placeholder_texture() -> Texture2D:
	# 代码生成纯色图集（外部素材缺失时的回退路径）：
	# [地板][墙壁][入口][出口]
	var image := Image.create(cell_size * 4, cell_size, false, Image.FORMAT_RGBA8)

	# 地板
	image.fill_rect(
		Rect2i(0, 0, cell_size, cell_size),
		Color(0.82, 0.75, 0.60)
	)

	# 墙壁
	image.fill_rect(
		Rect2i(cell_size, 0, cell_size, cell_size),
		Color(0.12, 0.12, 0.16)
	)

	# 入口
	image.fill_rect(
		Rect2i(cell_size * 2, 0, cell_size, cell_size),
		Color(0.20, 0.90, 0.40)
	)

	# 出口
	image.fill_rect(
		Rect2i(cell_size * 3, 0, cell_size, cell_size),
		Color(0.90, 0.25, 0.25)
	)

	return ImageTexture.create_from_image(image)


func _build_tilemap() -> void:
	if tile_layer == null:
		return

	if tile_source_id < 0:
		push_error("tile_source_id 无效，无法写入 TileMapLayer。")
		return

	tile_layer.clear()

	# 先写入整个地图
	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)

			var atlas_coords: Vector2i

			if grid[y][x] == CELL_FLOOR:
				atlas_coords = floor_atlas_coords
			else:
				atlas_coords = wall_atlas_coords

			tile_layer.set_cell(cell, tile_source_id, atlas_coords)

	# 最后覆盖入口和出口
	tile_layer.set_cell(entrance_cell, tile_source_id, entrance_atlas_coords)
	tile_layer.set_cell(exit_cell, tile_source_id, exit_atlas_coords)


# =========================
# Camera
# =========================

func _center_camera() -> void:
	var cam := get_node_or_null(^"Camera2D") as Camera2D
	if cam == null:
		return

	cam.make_current()
	cam.position = Vector2(
		map_width * cell_size * 0.5,
		map_height * cell_size * 0.5
	)
