extends Node2D

# =========================
# 第 3 课：连通性验证、玩家出生点、简单移动、出口触发
# 在第 2 课基础上新增：A* 可达性验证与自动修复、玩家、网格移动阻挡、出口 Area2D 触发
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

@export var use_placeholder_tileset: bool = true

# 作业 5 方案 B（第 2 课）：尊重手工配置的 TileSet
@export var use_external_tiles: bool = false

# 作业 5 方案 A（第 2 课）：外部图集路径
@export var external_tiles_path: String = "res://assets/tiles/dungeon_tiles.png"

@export var tile_source_id: int = 0

@export var floor_atlas_coords: Vector2i = Vector2i(0, 0)
@export var wall_atlas_coords: Vector2i = Vector2i(1, 0)
@export var entrance_atlas_coords: Vector2i = Vector2i(2, 0)
@export var exit_atlas_coords: Vector2i = Vector2i(3, 0)

# ---------- Gameplay 参数 ----------

@export_group("Gameplay")

# 把你的 player.tscn 拖到这里
@export var player_scene: PackedScene

@export var exit_radius_multiplier: float = 0.45
@export var debug_print_path: bool = false

# ---------- 节点 ----------

@onready var tile_layer: TileMapLayer = $TileMapLayer

# 作业 3：路径可视化覆盖层（画在 TileMapLayer 之上）
@onready var path_overlay: Node2D = $PathOverlay

# ---------- 常量与数据 ----------

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

var astar_grid := AStarGrid2D.new()

var player_instance: CharacterBody2D
var exit_area: Area2D

# 作业 4：钥匙门状态
var has_key := false
var key_area: Area2D

# HUD 引用（场景里的 CanvasLayer > Label）
@onready var key_label: Label = $HUD/KeyLabel


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
	_build_astar()
	_pick_entrance_and_exit()
	_ensure_exit_reachable()

	_setup_tilemap()
	_build_tilemap()

	_update_or_spawn_exit()
	_update_or_spawn_player()
	_spawn_markers()
	_center_camera()

	# 作业 3：把最终的入口→出口路径交给覆盖层绘制（修复后的最新路径）
	if path_overlay:
		path_overlay.set_path(astar_grid.get_id_path(entrance_cell, exit_cell), cell_size)

	# 作业 4：每层重新放钥匙 + 重置钥匙状态（放最后，避免影响既有 RNG 锚点）
	has_key = false
	_update_or_spawn_key()
	_update_hud()

	if debug_print_path:
		print("入口：", entrance_cell, "  出口：", exit_cell)


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

	# 第 1 课作业 5 成果：增量式最近邻连接（文档此处为旧版链式，按仓库现状保留本版）
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
		# 保底：如果参数太严格没有生成房间，就在地图中心挖一块地板
		entrance_cell = Vector2i(map_width / 2, map_height / 2)
		exit_cell = entrance_cell
		_set_cell(entrance_cell.x, entrance_cell.y, CELL_FLOOR)
		return

	# 入口：第一个房间中心
	entrance_cell = _room_center(rooms[0])

	if rooms.size() == 1:
		# 只有一个房间时，在同一个房间里选一个不同的地板点作为出口
		# （第 3 课文档改进：候选列表法，保证与入口不同）
		exit_cell = _pick_random_floor_cell_in_room(rooms[0], entrance_cell)
	else:
		# 第 2 课作业 4 成果：出口 = 从入口出发「实际路径」最长的房间中心
		# （文档此处为直线最远版，按仓库现状保留 A* 版；astar_grid 已在 generate 流程中先行构建）
		exit_cell = entrance_cell
		var best_path_len := -1

		for room in rooms:
			var center := _room_center(room)
			var path_len: int = astar_grid.get_id_path(entrance_cell, center).size()

			if path_len > best_path_len:
				best_path_len = path_len
				exit_cell = center

	# 极端情况下，确保出口不要和入口完全重合
	if exit_cell == entrance_cell:
		exit_cell = _pick_random_floor_cell_in_room(rooms[0], entrance_cell)


func _pick_random_floor_cell_in_room(room: Rect2i, avoid: Vector2i) -> Vector2i:
	# 枚举房间内所有地板格（排除 avoid），从中随机选一个——保证不重合
	var candidates: Array = []

	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)

			if cell == avoid:
				continue

			if grid[y][x] == CELL_FLOOR:
				candidates.append(cell)

	if candidates.is_empty():
		return avoid

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func get_entrance_local_position() -> Vector2:
	return _cell_to_center_local(entrance_cell)


func get_exit_local_position() -> Vector2:
	return _cell_to_center_local(exit_cell)


func get_entrance_world_position() -> Vector2:
	if tile_layer == null:
		return get_entrance_local_position()

	return tile_layer.to_global(get_entrance_local_position())


func _cell_to_center_local(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5


# =========================
# AStarGrid2D 连通性
# =========================

func _build_astar() -> void:
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, map_width, map_height)
	astar_grid.cell_size = Vector2i(1, 1) # 直接用格子坐标作点 id
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update()

	# 全图设墙（批量），地板格才解锁为可通行
	astar_grid.fill_solid_region(astar_grid.region, true)

	for y in map_height:
		for x in map_width:
			if grid[y][x] == CELL_FLOOR:
				astar_grid.set_point_solid(Vector2i(x, y), false)


func _ensure_exit_reachable() -> void:
	if _is_exit_reachable():
		return

	push_warning("入口到出口不可达，正在自动修复。")

	# 简单修复：直接从入口到出口挖一条 L 型通道
	if rng.randf() < 0.5:
		_carve_h_corridor(entrance_cell.x, exit_cell.x, entrance_cell.y)
		_carve_v_corridor(entrance_cell.y, exit_cell.y, exit_cell.x)
	else:
		_carve_v_corridor(entrance_cell.y, exit_cell.y, entrance_cell.x)
		_carve_h_corridor(entrance_cell.x, exit_cell.x, exit_cell.y)

	_build_astar()

	if not _is_exit_reachable():
		push_error("修复后入口到出口仍然不可达。")


func _is_exit_reachable() -> bool:
	if entrance_cell == exit_cell:
		return true

	var path := astar_grid.get_id_path(entrance_cell, exit_cell)

	if debug_print_path:
		print("AStar path length: ", path.size())

	return not path.is_empty()


# =========================
# TileMap
# =========================

func _setup_tilemap() -> void:
	if use_external_tiles:
		# 第 2 课方案 B：尊重手工配置的 TileSet，脚本不碰 tile_set
		if tile_layer.tile_set == null:
			push_warning("use_external_tiles 开着，但 TileMapLayer 上没有手工 TileSet。")
		return

	if use_placeholder_tileset:
		tile_source_id = _create_placeholder_tileset()

		floor_atlas_coords = Vector2i(0, 0)
		wall_atlas_coords = Vector2i(1, 0)
		entrance_atlas_coords = Vector2i(2, 0)
		exit_atlas_coords = Vector2i(3, 0)
	else:
		if tile_layer.tile_set == null:
			push_warning("你关闭了 use_placeholder_tileset，但 TileMapLayer 上没有设置 TileSet。")


func _create_placeholder_tileset() -> int:
	# 第 2 课方案 A：优先加载外部图集，文件缺失则回退代码生成
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
	# 代码生成纯色图集（外部素材缺失时的回退路径）
	var image := Image.create(cell_size * 4, cell_size, false, Image.FORMAT_RGBA8)

	image.fill_rect(Rect2i(0, 0, cell_size, cell_size), Color(0.82, 0.75, 0.60))
	image.fill_rect(Rect2i(cell_size, 0, cell_size, cell_size), Color(0.12, 0.12, 0.16))
	image.fill_rect(Rect2i(cell_size * 2, 0, cell_size, cell_size), Color(0.20, 0.90, 0.40))
	image.fill_rect(Rect2i(cell_size * 3, 0, cell_size, cell_size), Color(0.90, 0.25, 0.25))

	return ImageTexture.create_from_image(image)


func _build_tilemap() -> void:
	if tile_layer == null:
		return

	if tile_source_id < 0:
		push_error("tile_source_id 无效，无法写入 TileMapLayer。")
		return

	tile_layer.clear()

	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)

			var atlas_coords: Vector2i

			if grid[y][x] == CELL_FLOOR:
				atlas_coords = floor_atlas_coords
			else:
				atlas_coords = wall_atlas_coords

			tile_layer.set_cell(cell, tile_source_id, atlas_coords)

	tile_layer.set_cell(entrance_cell, tile_source_id, entrance_atlas_coords)
	tile_layer.set_cell(exit_cell, tile_source_id, exit_atlas_coords)


# =========================
# 出口触发区域
# =========================

func _update_or_spawn_exit() -> void:
	if tile_layer == null:
		return

	if exit_area == null or not is_instance_valid(exit_area):
		exit_area = Area2D.new()
		exit_area.name = "ExitArea"
		exit_area.monitoring = true

		var collision := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = cell_size * exit_radius_multiplier
		collision.shape = circle

		exit_area.add_child(collision)
		exit_area.body_entered.connect(_on_exit_body_entered)

		tile_layer.add_child(exit_area)
	else:
		var collision := exit_area.get_child(0) as CollisionShape2D
		if collision:
			var circle := collision.shape as CircleShape2D
			if circle:
				circle.radius = cell_size * exit_radius_multiplier

	exit_area.position = get_exit_local_position()


func _on_exit_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# 作业 4：门控——没钥匙进不了出口
		if not has_key:
			print("出口被锁住了，需要钥匙！")
			_update_hud(true)
			return

		print("玩家到达出口，重新生成地牢。")
		# 物理回调中不能直接改场景树，延迟到帧末安全执行
		call_deferred("generate")


# =========================
# 钥匙（作业 4）
# =========================

func _update_or_spawn_key() -> void:
	if tile_layer == null:
		return

	# 删旧钥匙（remove_child 先解除树，防同帧匿名坑）
	if key_area != null and is_instance_valid(key_area):
		tile_layer.remove_child(key_area)
		key_area.queue_free()

	var key_cell := _pick_key_cell()

	key_area = Area2D.new()
	key_area.name = "KeyArea"
	key_area.monitoring = true

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = cell_size * 0.45
	collision.shape = circle
	key_area.add_child(collision)

	# 金色菱形可视化（比玩家小一号）
	var visual := Polygon2D.new()
	var diamond: PackedVector2Array = [
		Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)
	]
	visual.polygon = diamond
	visual.color = Color(1.0, 0.8, 0.0)
	key_area.add_child(visual)

	key_area.body_entered.connect(_on_key_body_entered)

	tile_layer.add_child(key_area)
	key_area.position = _cell_to_center_local(key_cell)


func _pick_key_cell() -> Vector2i:
	# 钥匙优先放「既非入口也非出口」的房间 → 强制玩家绕支路探索
	if rooms.is_empty():
		return entrance_cell

	# 找出口所在房间
	var exit_room_idx := -1
	for i in rooms.size():
		if _room_center(rooms[i]) == exit_cell:
			exit_room_idx = i
			break

	# 候选：非入口(0)、非出口的房间
	var candidates: Array = []
	for i in range(1, rooms.size()):
		if i != exit_room_idx:
			candidates.append(i)

	if candidates.is_empty():
		# 只有入口+出口两个房间：钥匙放出口房间内（避开出口格）
		if exit_room_idx >= 0:
			return _pick_random_floor_cell_in_room(rooms[exit_room_idx], exit_cell)
		return _pick_random_floor_cell_in_room(rooms[0], entrance_cell)

	var room_idx: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	return _room_center(rooms[room_idx])


func _on_key_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not has_key:
		has_key = true
		print("获得钥匙！出口已解锁。")
		# 拾取后钥匙消失；monitoring 属物理状态，物理回调中必须 set_deferred
		key_area.set_deferred("monitoring", false)
		key_area.visible = false
		_update_hud()


func _update_hud(locked_hint: bool = false) -> void:
	if key_label == null:
		return

	if has_key:
		key_label.text = "钥匙：已获得 ✓ 出口已解锁"
		key_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	elif locked_hint:
		key_label.text = "出口被锁住了！去寻找金色钥匙…"
		key_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	else:
		key_label.text = "钥匙：未获得（找金色菱形）"
		key_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))


# =========================
# 玩家
# =========================

func _update_or_spawn_player() -> void:
	if player_scene == null:
		push_warning("没有在 Inspector 里设置 Player Scene，请拖入 player.tscn。")
		return

	if player_instance == null or not is_instance_valid(player_instance):
		player_instance = player_scene.instantiate() as CharacterBody2D

		if player_instance == null:
			push_error("player.tscn 的根节点必须是 CharacterBody2D。")
			return

		player_instance.add_to_group("player")
		add_child(player_instance)

	player_instance.global_position = get_entrance_world_position()

	if "dungeon" in player_instance:
		player_instance.dungeon = self


# =========================
# 入口 / 出口标记（第 2 课作业 1+2 成果，保留）
# =========================

func _spawn_markers() -> void:
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
			# 先脱离树再延迟释放：防止同帧 spawn 的同名新节点被匿名化
			remove_child(child)
			child.queue_free()


# =========================
# 移动阻挡查询
# =========================

func is_world_position_walkable(world_position: Vector2, radius: float = 0.0) -> bool:
	if grid.is_empty():
		return false

	if radius <= 0.0:
		return _is_world_point_walkable(world_position)

	# 简单采样：中心 + 四个方向
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(radius, 0.0),
		Vector2(-radius, 0.0),
		Vector2(0.0, radius),
		Vector2(0.0, -radius)
	]

	for offset in offsets:
		if not _is_world_point_walkable(world_position + offset):
			return false

	return true


func _is_world_point_walkable(world_position: Vector2) -> bool:
	if tile_layer == null:
		return false

	var local_position := tile_layer.to_local(world_position)

	var cell := Vector2i(
		floori(local_position.x / float(cell_size)),
		floori(local_position.y / float(cell_size))
	)

	return is_cell_walkable(cell)


func is_cell_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= map_width:
		return false
	if cell.y < 0 or cell.y >= map_height:
		return false

	return grid[cell.y][cell.x] == CELL_FLOOR


# =========================
# Camera
# =========================

func _center_camera() -> void:
	# 作业 2 后：相机职责已转移给 Player 自带的 Camera2D（跟随玩家）。
	# Main 场景已无 Camera2D 节点，此函数查找返回 null 自动跳过，保留以兼容旧场景。
	var cam := get_node_or_null(^"Camera2D") as Camera2D
	if cam == null:
		return

	cam.make_current()
	cam.position = Vector2(
		map_width * cell_size * 0.5,
		map_height * cell_size * 0.5
	)
