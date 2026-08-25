extends Node2D

# =========================
# 第 3 课：连通性验证、玩家出生点、简单移动、出口触发
# 第 4 课：钥匙、宝箱、怪物出生点、出口锁（POI 体系重构）
# 在第 2 课基础上新增：A* 可达性验证与自动修复、玩家、网格移动阻挡、出口 Area2D 触发
# 第 4 课新增：used_cells 占用管理、dynamic_entities 动态实体、宝箱计数、怪物危险区
# 可视化：像素素材（assets/sprites/，generate_sprites.ps1 生成）替代色块
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

# ---------- POI 参数（第 4 课：钥匙、宝箱、怪物出生点） ----------

@export_group("POI")

@export_range(0, 10) var min_treasures: int = 2
@export_range(0, 10) var max_treasures: int = 5

@export_range(0, 12) var min_monsters: int = 2
@export_range(0, 12) var max_monsters: int = 6

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

# =========================
# 第 4 课：POI（钥匙、宝箱、怪物出生点）
# =========================

const INVALID_CELL := Vector2i(-1, -1)

# 作业 2：怪物出生点距入口的最小距离（平方距离，36 = 欧氏 6 格）
const MONSTER_MIN_DISTANCE_SQ := 36

# 作业 3：POI 不可达时的重选上限（每类 POI 独立计数，防极端情况死循环）
const POI_REACHABLE_RETRIES := 16

# 像素素材（assets/sprites/generate_sprites.ps1 生成，16x16 透明背景）
const KEY_TEXTURE: Texture2D = preload("res://assets/sprites/key.png")
const CHEST_TEXTURE: Texture2D = preload("res://assets/sprites/chest.png")
const MONSTER_TEXTURE: Texture2D = preload("res://assets/sprites/monster.png")

var has_key := false
var treasure_count := 0

var key_cell := INVALID_CELL
var treasure_cells: Array[Vector2i] = []
var monster_cells: Array[Vector2i] = []

# 已被占用的格子，避免钥匙/宝箱/怪物重叠
var used_cells: Dictionary = {}

# 当前地牢里生成的钥匙、宝箱、怪物节点（玩家和出口不在此列，仍复用）
var dynamic_entities: Array[Node] = []

# HUD 引用（场景里的 CanvasLayer > Label）
@onready var key_label: Label = $HUD/KeyLabel
@onready var treasure_label: Label = $HUD/TreasureLabel


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

	# 第 4 课：每层重置玩家状态
	has_key = false
	treasure_count = 0

	_setup_rng()

	# 第 4 课：清理上一层的钥匙、宝箱、怪物（玩家和出口仍复用）
	_clear_dynamic_entities()

	_clear_map()
	_place_rooms()
	_connect_rooms()
	_build_astar()
	_pick_entrance_and_exit()
	_ensure_exit_reachable()

	# 第 4 课：生成钥匙、宝箱、怪物位置
	_pick_poi_cells()

	_setup_tilemap()
	_build_tilemap()

	_update_or_spawn_exit()
	_spawn_poi_nodes()
	_update_or_spawn_player()
	_spawn_markers()
	_center_camera()

	# 作业 3：把最终的入口→出口路径交给覆盖层绘制（修复后的最新路径）
	if path_overlay:
		path_overlay.set_path(astar_grid.get_id_path(entrance_cell, exit_cell), cell_size)

	_update_hud()

	if debug_print_path:
		print("入口：", entrance_cell, "  出口：", exit_cell)
		print("钥匙：", key_cell, "  宝箱数：", treasure_cells.size(), "  怪物数：", monster_cells.size())


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

	# 踩坑：如需添加物理碰撞层，碰撞多边形坐标必须相对于 tile 中心（而非左上角）
	# Pitfall: TileSet collision polygon coordinates are relative to tile center, not top-left
	# 例如 16×16 tile 的碰撞多边形应为：PackedVector2Array(-8,-8, 8,-8, 8,8, -8,8)
	# 详见：doc/notes/tileset_collision_coordinates.md

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
	if not body.is_in_group("player"):
		return

	# 第 4 课：出口锁——必须先拿到钥匙
	if has_key:
		print("使用钥匙，进入下一层。")
		# 物理回调中不能直接改场景树，延迟到帧末安全执行
		call_deferred("generate")
	else:
		print("出口被锁住了，需要钥匙。")
		_update_hud(true)


# =========================
# 第 4 课：POI 选点（钥匙、宝箱、怪物）
# =========================

func _pick_poi_cells() -> void:
	used_cells.clear()

	key_cell = INVALID_CELL
	treasure_cells.clear()
	monster_cells.clear()

	# 入口和出口不能被内容点占用
	_mark_cell_used(entrance_cell)
	_mark_cell_used(exit_cell)

	# 先选钥匙（最远房策略 + 作业 3 可达性验证）
	key_cell = _pick_reachable_cell(_pick_key_cell(), false)
	if key_cell != INVALID_CELL:
		_mark_cell_used(key_cell)

	# 再选宝箱（作业 3：带可达性验证的重选循环）
	var min_t := mini(min_treasures, max_treasures)
	var max_t := maxi(min_treasures, max_treasures)
	var treasure_amount := rng.randi_range(min_t, max_t)

	for i in treasure_amount:
		var cell := _pick_reachable_cell(
			_pick_random_available_cell_in_rooms(), false
		)
		if cell == INVALID_CELL:
			break

		treasure_cells.append(cell)
		_mark_cell_used(cell)

	# 最后选怪物（作业 2 距离过滤 + 作业 3 可达验证）
	var min_m := mini(min_monsters, max_monsters)
	var max_m := maxi(min_monsters, max_monsters)
	var monster_amount := rng.randi_range(min_m, max_m)

	for i in monster_amount:
		var cell := _pick_reachable_cell(_pick_monster_cell(), true)
		if cell == INVALID_CELL:
			break

		monster_cells.append(cell)
		_mark_cell_used(cell)


func _pick_reachable_cell(first_try: Vector2i, is_monster: bool) -> Vector2i:
	# 作业 3：验证 first_try 从入口可达；不可达则重选（重试有上限）
	# 每次重选同样消耗一次 RNG —— 同种子序列稳定（重试次数由地图决定，可复现）
	if _is_cell_reachable(first_try):
		return first_try

	for retry in POI_REACHABLE_RETRIES:
		var candidate: Vector2i
		if is_monster:
			candidate = _pick_monster_cell()
		else:
			candidate = _pick_random_available_cell_in_rooms()

		if candidate == INVALID_CELL:
			break

		if _is_cell_reachable(candidate):
			return candidate

	# 重试用尽：接受原格（地图整体已连通，此分支理论上不触发，仅保底）
	return first_try


func _is_cell_reachable(cell: Vector2i) -> bool:
	# 作业 3：astar_grid 在 generate() 流程中先行构建，此处直接查询
	if cell == INVALID_CELL:
		return false

	return not astar_grid.get_id_path(entrance_cell, cell).is_empty()


func _mark_cell_used(cell: Vector2i) -> void:
	if cell == INVALID_CELL:
		return

	used_cells[cell] = true


func _is_cell_available(cell: Vector2i) -> bool:
	if cell == INVALID_CELL:
		return false

	if cell.x < 0 or cell.x >= map_width:
		return false
	if cell.y < 0 or cell.y >= map_height:
		return false

	if grid[cell.y][cell.x] != CELL_FLOOR:
		return false

	if used_cells.has(cell):
		return false

	return true


func _pick_key_cell() -> Vector2i:
	# 第 4 课策略：排除入口房和出口房，选离入口最远的房间
	# → 强制玩家探索（第 3 课为随机房，本课升级）
	if rooms.is_empty():
		return INVALID_CELL

	var candidate_rooms: Array = []

	# 优先排除入口房和出口房
	for room in rooms:
		var center := _room_center(room)

		if center == entrance_cell:
			continue
		if center == exit_cell:
			continue

		candidate_rooms.append(room)

	if candidate_rooms.is_empty():
		candidate_rooms = rooms

	# 在候选房间里选择离入口最远的房间
	var best_room: Rect2i = candidate_rooms[0]
	var best_distance := -1

	for room in candidate_rooms:
		var center := _room_center(room)
		var distance := entrance_cell.distance_squared_to(center)

		if distance > best_distance:
			best_distance = distance
			best_room = room

	var cell := _pick_random_available_cell_in_room(best_room)

	if cell != INVALID_CELL:
		return cell

	# 如果这个房间没有合适位置，就全局找一个
	return _pick_random_available_cell_in_grid()


func _pick_random_available_cell_in_room(room: Rect2i) -> Vector2i:
	var candidates: Array[Vector2i] = []

	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var cell := Vector2i(x, y)

			if _is_cell_available(cell):
				candidates.append(cell)

	if candidates.is_empty():
		return INVALID_CELL

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _pick_random_available_cell_in_rooms() -> Vector2i:
	var candidates: Array[Vector2i] = []

	for room in rooms:
		for y in range(room.position.y, room.position.y + room.size.y):
			for x in range(room.position.x, room.position.x + room.size.x):
				var cell := Vector2i(x, y)

				if _is_cell_available(cell):
					candidates.append(cell)

	if candidates.is_empty():
		return _pick_random_available_cell_in_grid()

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _pick_monster_cell() -> Vector2i:
	# 作业 2：怪物出生点远离入口（避免玩家一出生就撞怪被传送）
	# 候选 = 房间内可用 + 距入口平方距离 > MONSTER_MIN_DISTANCE_SQ
	var candidates: Array[Vector2i] = []

	for room in rooms:
		for y in range(room.position.y, room.position.y + room.size.y):
			for x in range(room.position.x, room.position.x + room.size.x):
				var cell := Vector2i(x, y)

				if not _is_cell_available(cell):
					continue

				if entrance_cell.distance_squared_to(cell) <= MONSTER_MIN_DISTANCE_SQ:
					continue

				candidates.append(cell)

	# 小地图/极端情况：达标格子耗尽时回退原逻辑，保证怪物仍能生成
	if candidates.is_empty():
		return _pick_random_available_cell_in_rooms()

	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _pick_random_available_cell_in_grid() -> Vector2i:
	var candidates: Array[Vector2i] = []

	for y in map_height:
		for x in map_width:
			var cell := Vector2i(x, y)

			if _is_cell_available(cell):
				candidates.append(cell)

	if candidates.is_empty():
		return INVALID_CELL

	return candidates[rng.randi_range(0, candidates.size() - 1)]


# =========================
# 第 4 课：POI 节点生成（Area2D + 色块可视化）
# =========================

func _clear_dynamic_entities() -> void:
	for entity in dynamic_entities:
		if is_instance_valid(entity):
			entity.queue_free()

	dynamic_entities.clear()


func _spawn_poi_nodes() -> void:
	if tile_layer == null:
		return

	if key_cell != INVALID_CELL:
		_create_pickup_area(
			key_cell,
			"key",
			KEY_TEXTURE,
			0.35
		)

	for cell in treasure_cells:
		_create_pickup_area(
			cell,
			"treasure",
			CHEST_TEXTURE,
			0.30
		)

	for cell in monster_cells:
		_create_hazard_area(cell)


func _create_pickup_area(
	cell: Vector2i,
	pickup_type: String,
	texture: Texture2D,
	radius_multiplier: float
) -> Area2D:
	var area := _create_poi_area(cell, texture, radius_multiplier)

	area.add_to_group(pickup_type)

	if pickup_type == "key":
		area.body_entered.connect(_on_key_body_entered.bind(area))
	elif pickup_type == "treasure":
		area.body_entered.connect(_on_treasure_body_entered.bind(area))

	return area


func _create_hazard_area(cell: Vector2i) -> Area2D:
	var area := _create_poi_area(
		cell,
		MONSTER_TEXTURE,
		0.40
	)

	area.add_to_group("monster")
	area.body_entered.connect(_on_monster_body_entered.bind(area))

	return area


func _create_poi_area(
	cell: Vector2i,
	texture: Texture2D,
	radius_multiplier: float
) -> Area2D:
	var area := Area2D.new()
	area.position = _cell_to_center_local(cell)
	area.monitoring = true

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = cell_size * radius_multiplier
	collision.shape = circle
	area.add_child(collision)

	# 像素素材可视化（Sprite2D 默认居中，16x16 原尺寸 = 满格）
	var visual := Sprite2D.new()
	visual.texture = texture
	area.add_child(visual)

	tile_layer.add_child(area)
	dynamic_entities.append(area)

	return area


# =========================
# 第 4 课：POI 触发逻辑
# =========================

func _on_key_body_entered(body: Node2D, area: Area2D) -> void:
	if not body.is_in_group("player"):
		return

	has_key = true

	print("拿到了钥匙！出口已解锁。")

	_update_hud()
	_remove_entity(area)


func _on_treasure_body_entered(body: Node2D, area: Area2D) -> void:
	if not body.is_in_group("player"):
		return

	treasure_count += 1

	print("打开宝箱，当前宝箱数：", treasure_count)

	_update_hud()
	_remove_entity(area)


func _on_monster_body_entered(body: Node2D, area: Area2D) -> void:
	if not body.is_in_group("player"):
		return

	print("碰到怪物！回到入口。")

	# 本课规则：碰到怪物 → 传送回入口（后续课程升级为扣血/战斗）
	if is_instance_valid(player_instance):
		player_instance.global_position = get_entrance_world_position()


func _remove_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return

	dynamic_entities.erase(entity)

	# 踩坑：monitoring 属物理状态，物理回调中必须 set_deferred（第 3 课验证过）
	if entity is Area2D:
		entity.set_deferred("monitoring", false)

	entity.queue_free()


func _update_hud(locked_hint: bool = false) -> void:
	# 作业 1：钥匙状态行
	if key_label == null:
		return

	if has_key:
		key_label.text = "钥匙：已获得 ✓ 出口已解锁"
		key_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	elif locked_hint:
		key_label.text = "出口被锁住了！去寻找金钥匙…"
		key_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	else:
		key_label.text = "钥匙：未获得（找金钥匙）"
		key_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))

	# 作业 1：宝箱计数行（已开 / 总数；宝箱拾取后不回收格子，总数稳定）
	if treasure_label != null:
		treasure_label.text = "宝箱：%d/%d" % [treasure_count, treasure_cells.size()]
		treasure_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))


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
