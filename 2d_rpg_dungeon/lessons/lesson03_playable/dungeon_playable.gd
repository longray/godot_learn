extends Node2D

# =========================
# 第 3 课：连通性验证、玩家出生点、简单移动、出口触发
# 第 4 课：钥匙、宝箱、怪物出生点、出口锁（POI 体系重构）
# 在第 2 课基础上新增：A* 可达性验证与自动修复、玩家、网格移动阻挡、出口 Area2D 触发
# 第 4 课新增：used_cells 占用管理、dynamic_entities 动态实体、宝箱计数、怪物危险区
# 第 5 课新增：敌人巡逻路径分配（确定性零 RNG）、respawn_player、每层重置玩家状态
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

# ---------- 第 10 课：死亡惩罚参数 ----------

# 死亡后是否重置当前局（回第 1 层重新生成）；false = 保留第 5 课"本层复原"行为
@export var death_resets_run: bool = true
# 死亡后保留的金币比例（0.7 = 损失 30%）
@export_range(0.0, 1.0) var death_gold_keep_ratio: float = 0.7
# 死亡重开时是否随机地图种子（换一张新图）
@export var randomize_seed_on_death: bool = true

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

# 作业 5：把 enemy.tscn 拖到这里（未设置时怪物回退为旧版危险区）
@export var enemy_scene: PackedScene

@export var exit_radius_multiplier: float = 0.45
@export var debug_print_path: bool = false

# ---------- POI 参数（第 4 课：钥匙、宝箱、怪物出生点） ----------

@export_group("POI")

@export_range(0, 10) var min_treasures: int = 2
@export_range(0, 10) var max_treasures: int = 5

@export_range(0, 12) var min_monsters: int = 2
@export_range(0, 12) var max_monsters: int = 6

# 第 6 课：掉落参数（死亡掉率 0.7；掉落物中 0.25 是药水、0.75 是金币）
@export_range(0.0, 1.0) var enemy_drop_chance: float = 0.7
@export_range(0.0, 1.0) var enemy_potion_chance: float = 0.25

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

# 第 9 课方案 C：走廊数据（元素 = {cells: Array[Vector2i], room_a: int, room_b: int}）
# 两端任一房间探索过 → 小地图整条走廊点亮
var corridors: Array = []

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
const GOLD_TEXTURE: Texture2D = preload("res://assets/sprites/gold.png")
const POTION_TEXTURE: Texture2D = preload("res://assets/sprites/potion.png")

# 第 6 课：金币计数（跨层保留——玩家长期资源）
var gold_count: int = 0

# 第 8 课：层数（出口进入下一层 +1；金币跨层保留，钥匙/宝箱/生命每层重置）
var floor_number: int = 1

# 第 10 课：长期数据（跨局保存在 user:// 存档）
# 第 11 课：降级为局内镜像——真源与存档职责已迁至 GameData（Autoload）
var best_floor: int = 1
var total_deaths: int = 0

# 第 11 课：死亡结算后返回商店（游戏主循环：商店 → 地牢 → 死亡 → 商店）
const SHOP_SCENE := "res://lessons/lesson03_playable/shop.tscn"

# 作业 2（第 11 课）：死亡等待按键状态（true 时拦截 R/Backspace，任意键回商店）
var _death_awaiting_input := false

var has_key := false
var treasure_count := 0

var key_cell := INVALID_CELL
var treasure_cells: Array[Vector2i] = []
var monster_cells: Array[Vector2i] = []

# 已被占用的格子，避免钥匙/宝箱/怪物重叠
var used_cells: Dictionary = {}

# 当前地牢里生成的钥匙、宝箱、怪物节点（玩家和出口不在此列，仍复用）
var dynamic_entities: Array[Node] = []

# 第 8 课：独立 HUD 场景实例（hud.tscn）——显示逻辑全部下沉到它，Main 只推送数据
@onready var hud: Node = get_node_or_null("HUD")

# 第 9 课：房间检测与小地图
# 当前房间索引 / 已探索房间（key=索引，字典查询 O(1)）/ 检测节流计时
var current_room_index: int = -1
var explored_rooms: Dictionary = {}
var room_check_timer: float = 0.0

@onready var minimap: Control = get_node_or_null("HUD/MiniMap")


func _ready() -> void:
	# 第 10 课：启动先读档
	# 第 11 课：存档职责迁至 GameData——启动时已 load_game，这里拉取镜像
	# （get_node_or_null 而非全局名 GameData：--check-only 单脚本编译不加载 autoload 标识符）
	var game_data := get_node_or_null("/root/GameData")

	if game_data:
		gold_count = game_data.gold
		best_floor = game_data.best_floor
		total_deaths = game_data.total_deaths

	if tile_layer == null:
		push_error("找不到 TileMapLayer，请确认场景里有名为 TileMapLayer 的子节点。")
		return

	generate()


func _process(delta: float) -> void:
	# 第 9 课：房间检测节流——0.1s 一次足够（不必每帧，房间切换不是帧敏感事件）
	room_check_timer += delta

	if room_check_timer >= 0.1:
		room_check_timer = 0.0
		_update_player_room()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return

	# 作业 2（第 11 课）：死亡等待——任意按键返回商店（优先拦截 R/Backspace，防等待期误操作）
	if _death_awaiting_input:
		if key.pressed and not key.echo:
			_death_awaiting_input = false
			get_tree().change_scene_to_file(SHOP_SCENE)
		return

	if key.pressed and not key.echo and key.keycode == KEY_R:
		generate()

	# 作业 3（第 10 课）：Backspace 删档重开（调试用——清空金币/纪录/升级等级）
	if key.pressed and not key.echo and key.keycode == KEY_BACKSPACE:
		var game_data := get_node_or_null("/root/GameData")
		if game_data:
			game_data.call("reset_progress")
		gold_count = 0
		best_floor = 1
		total_deaths = 0
		floor_number = 1
		print("存档已删除，一切归零。")
		_update_gold_hud()
		_update_hud()
		call_deferred("generate")


func generate() -> void:
	# 防止地图太小
	map_width = maxi(20, map_width)
	map_height = maxi(16, map_height)

	# 第 4 课：每层重置玩家状态
	has_key = false
	treasure_count = 0

	# 第 9 课：每层重置房间探索状态（死亡重置层时同样走到这里，迷雾自然复原）
	current_room_index = -1
	explored_rooms.clear()
	corridors.clear()

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

	# 第 9 课：初始化小地图并立即检测一次（开局入口房间即为已探索）
	_setup_minimap()
	_update_player_room()

	_update_hud()
	_update_gold_hud()

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

		# 第 9 课方案 C：收集本条走廊格子与两端房间（小地图"整条点亮"判定用）
		var cells: Array[Vector2i] = []

		if rng.randf() < 0.5:
			_carve_h_corridor(from.x, b.x, from.y, cells)
			_carve_v_corridor(from.y, b.y, b.x, cells)
		else:
			_carve_v_corridor(from.y, b.y, from.x, cells)
			_carve_h_corridor(from.x, b.x, b.y, cells)

		corridors.append({
			"cells": cells,
			"room_a": best_j,
			"room_b": i,
		})


func _room_center(room: Rect2i) -> Vector2i:
	return Vector2i(
		room.position.x + room.size.x / 2,
		room.position.y + room.size.y / 2
	)


func _carve_h_corridor(x1: int, x2: int, y: int, sink: Array = []) -> void:
	var from := mini(x1, x2)
	var to := maxi(x1, x2)

	for x in range(from, to + 1):
		_set_cell(x, y, CELL_FLOOR)
		# 第 9 课方案 C：可选收集走廊格子（小地图用；不影响挖掘顺序与 RNG）
		if sink != null:
			sink.append(Vector2i(x, y))


func _carve_v_corridor(y1: int, y2: int, x: int, sink: Array = []) -> void:
	var from := mini(y1, y2)
	var to := maxi(y1, y2)

	for y in range(from, to + 1):
		_set_cell(x, y, CELL_FLOOR)
		# 第 9 课方案 C：可选收集走廊格子（小地图用；不影响挖掘顺序与 RNG）
		if sink != null:
			sink.append(Vector2i(x, y))


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
	# 第 9 课方案 C：保底走廊也收集（端点房间按格子反查；查不到记 -1，点亮条件退化为另一端）
	var fix_cells: Array[Vector2i] = []

	if rng.randf() < 0.5:
		_carve_h_corridor(entrance_cell.x, exit_cell.x, entrance_cell.y, fix_cells)
		_carve_v_corridor(entrance_cell.y, exit_cell.y, exit_cell.x, fix_cells)
	else:
		_carve_v_corridor(entrance_cell.y, exit_cell.y, entrance_cell.x, fix_cells)
		_carve_h_corridor(entrance_cell.x, exit_cell.x, exit_cell.y, fix_cells)

	corridors.append({
		"cells": fix_cells,
		"room_a": _find_room_index_containing_cell(entrance_cell),
		"room_b": _find_room_index_containing_cell(exit_cell),
	})

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

		# 作业 4：出口锁状态覆盖层（红=锁定 / 绿=解锁，_update_exit_lock_visual 刷新颜色）
		var lock_overlay := Polygon2D.new()
		lock_overlay.name = "LockOverlay"
		var half := cell_size * 0.5
		lock_overlay.polygon = PackedVector2Array([
			Vector2(-half, -half),
			Vector2(half, -half),
			Vector2(half, half),
			Vector2(-half, half)
		])
		exit_area.add_child(lock_overlay)

		tile_layer.add_child(exit_area)
	else:
		var collision := exit_area.get_child(0) as CollisionShape2D
		if collision:
			var circle := collision.shape as CircleShape2D
			if circle:
				circle.radius = cell_size * exit_radius_multiplier

	exit_area.position = get_exit_local_position()
	_update_exit_lock_visual()


func _update_exit_lock_visual() -> void:
	# 作业 4：出口覆盖层随钥匙状态变色（锁定=红半透明，解锁=绿半透明）
	if exit_area == null or not is_instance_valid(exit_area):
		return

	var overlay := exit_area.get_node_or_null("LockOverlay") as Polygon2D
	if overlay == null:
		return

	if has_key:
		overlay.color = Color(0.3, 1.0, 0.4, 0.45)
	else:
		overlay.color = Color(1.0, 0.25, 0.25, 0.45)


func _on_exit_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	# 第 4 课：出口锁——必须先拿到钥匙
	if has_key:
		print("使用钥匙，进入下一层。")
		# 第 8 课：层数 +1（金币跨层保留；钥匙/宝箱/生命由 generate 内部重置）
		floor_number += 1
		# 第 10 课：更新最佳层数并保存（下楼即存档，随时关机不亏）
		best_floor = maxi(best_floor, floor_number)
		_sync_game_data()
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
		_spawn_monster_at_cell(cell)


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


func _spawn_monster_at_cell(cell: Vector2i) -> void:
	# 第 5 课：实例化巡逻敌人（setup 注入地图引用 + 巡逻路径）
	if enemy_scene != null:
		var enemy := enemy_scene.instantiate() as CharacterBody2D

		if enemy:
			add_child(enemy)

			enemy.global_position = get_cell_world_position(cell)

			# 作业 3（第 6 课）：加权随机分配类型（60% 普通 / 25% 敏捷 / 15% 坦克）
			if "enemy_type" in enemy:
				var roll := rng.randf()
				if roll < 0.60:
					enemy.enemy_type = "normal"
				elif roll < 0.85:
					enemy.enemy_type = "fast"
				else:
					enemy.enemy_type = "tank"

			if enemy.has_method("setup"):
				enemy.setup(self, _make_patrol_points(cell))

			dynamic_entities.append(enemy)
			return

	# 回退：未配置敌人场景时用旧版危险区（保底不断更）
	push_warning("enemy_scene 未设置，怪物回退为危险区。")
	_create_hazard_area(cell)


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
	_update_exit_lock_visual()
	# 第 9 课：拿到钥匙后小地图黄点消失（show_key 开启时）
	_update_minimap()
	_remove_entity(area)


func _on_treasure_body_entered(body: Node2D, area: Area2D) -> void:
	if not body.is_in_group("player"):
		return

	treasure_count += 1

	print("打开宝箱，当前宝箱数：", treasure_count)

	_update_hud()
	_remove_entity(area)


func _on_monster_body_entered(body: Node2D, area: Area2D) -> void:
	# 第 5 课（5.8）：回退危险区也走 take_damage（掉血+击退+无敌）
	if not body.is_in_group("player"):
		return

	if body.has_method("take_damage"):
		body.take_damage(1, area.global_position)
	else:
		print("碰到怪物！回到入口。")

		if is_instance_valid(player_instance):
			player_instance.global_position = get_entrance_world_position()


func respawn_player() -> void:
	# 第 5 课：玩家死亡后重生到入口（轻惩罚版）
	# 第 10 课：仅当 reset_current_layer 不存在时的回退分支（本仓库不可达，防御性保留）
	if is_instance_valid(player_instance):
		player_instance.global_position = get_entrance_world_position()
		# 第 9 课：回入口后小地图立刻切回入口房间
		_update_player_room()


func reset_current_layer() -> void:
	# 第 5 课：死亡重置本层 → 第 10 课：死亡三连惩罚 → 第 11 课：死亡返回商店
	# 惩罚三连：死亡次数 +1 / 金币 ×death_gold_keep_ratio / 层数归 1（参数可调，@export）
	total_deaths += 1
	gold_count = int(gold_count * death_gold_keep_ratio)

	print("本层已重置！死亡 ", total_deaths, " 次，金币剩余：", gold_count)

	if death_resets_run:
		# 整局结束：层数归 1 +（可选）随机种子——下一局从商店进入时生效
		floor_number = 1

		if randomize_seed_on_death:
			use_random_seed = true

	_sync_game_data()
	_update_gold_hud()
	# 金币惩罚后 HUD 必须单独刷金币行（_update_hud 不覆盖 gold_label）
	_update_hud()

	if death_resets_run:
		# 第 11 课 + 作业 2：死亡大字 + 损失副标题持续显示，等玩家按键再回商店
		# （不再定时自动切——给玩家看清惩罚的仪式感）
		var lost_pct := int(round((1.0 - death_gold_keep_ratio) * 100.0))

		if hud and hud.has_method("show_death"):
			hud.show_death("损失 %d%% 金币 · 按任意键返回商店" % lost_pct, false)

		_death_awaiting_input = true
	else:
		# 轻模式（death_resets_run=false）：保留第 10 课行为——固定种子下本层复原
		generate()


func _remove_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return

	dynamic_entities.erase(entity)

	# 踩坑：monitoring 属物理状态，物理回调中必须 set_deferred（第 3 课验证过）
	if entity is Area2D:
		entity.set_deferred("monitoring", false)

	entity.queue_free()


# =========================
# 第 6 课：敌人死亡掉落（金币/药水）
# =========================

func remove_dynamic_entity(entity: Node) -> void:
	# 敌人自杀（queue_free）前，从动态实体清单移除自己
	dynamic_entities.erase(entity)


func on_enemy_died(enemy: Node, death_position: Vector2) -> void:
	# 敌人死亡：移出清单 + 运行期掉落判定（rng 消耗在 generate 重置种子后，不影响复现）
	remove_dynamic_entity(enemy)

	# 作业 4（第 6 课）：差异化掉落——按敌人类型决定掉率与掉落表
	var drop_chance := enemy_drop_chance
	var potion_chance := enemy_potion_chance

	var etype: String = enemy.get("enemy_type") if "enemy_type" in enemy else "normal"
	match etype:
		"fast":
			# 敏捷怪：掉率低但必掉金币（跑得快击杀难，奖励集中）
			drop_chance = 0.5
			potion_chance = 0.0
		"tank":
			# 坦克怪：必掉且高概率药水（硬仗厚奖）
			drop_chance = 1.0
			potion_chance = 0.6

	if rng.randf() < drop_chance:
		_spawn_drop_at_position(death_position, potion_chance)


func _spawn_drop_at_position(world_position: Vector2, potion_chance: float = -1.0) -> void:
	# potion_chance < 0 时用全局默认（保持文档版调用兼容）
	if potion_chance < 0.0:
		potion_chance = enemy_potion_chance

	var drop_type := "gold"

	if rng.randf() < potion_chance:
		drop_type = "potion"

	_create_drop_area(drop_type, world_position)


func _create_drop_area(drop_type: String, world_position: Vector2) -> Area2D:
	var area := Area2D.new()

	area.monitoring = true
	area.collision_layer = 0
	area.collision_mask = 1

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = cell_size * 0.25
	collision.shape = circle
	area.add_child(collision)

	# 像素素材可视化（金币/药水）+ 上下浮动（吸引注意："地上有东西"）
	var visual := Sprite2D.new()
	visual.texture = GOLD_TEXTURE if drop_type == "gold" else POTION_TEXTURE
	area.add_child(visual)

	var tween := area.create_tween().set_loops()
	tween.tween_property(visual, "position:y", -1.5, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_SINE)

	area.add_to_group("drop")
	area.body_entered.connect(_on_drop_body_entered.bind(area, drop_type))

	add_child(area)
	area.global_position = world_position

	dynamic_entities.append(area)

	return area


func _on_drop_body_entered(body: Node2D, area: Area2D, drop_type: String) -> void:
	if not body.is_in_group("player"):
		return

	if drop_type == "gold":
		gold_count += 1
		print("捡到金币，当前金币：", gold_count)
		_update_gold_hud()
		# 第 10 课：捡到金币立刻存档（长期数据即时落盘）
		_sync_game_data()
	elif drop_type == "potion":
		if body.has_method("heal"):
			body.heal(1)
		print("捡到药水并恢复生命。")

	_remove_entity(area)


func _update_hud(locked_hint: bool = false) -> void:
	# 第 8 课：转发到独立 HUD（hud.tscn 实例）——Main 不再直接持有 Label
	if hud == null:
		return

	if locked_hint:
		hud.show_key_locked_hint()
	else:
		hud.update_key(has_key)

	# 宝箱行无条件刷新（旧版嵌在 else 分支里，已获得钥匙时宝箱数不更新——顺手修正）
	hud.update_treasure(treasure_count, treasure_cells.size())
	hud.update_floor(floor_number, best_floor)

	# 作业 1（第 10 课）：死亡次数行（长期纪录）
	if hud.has_method("update_deaths"):
		hud.update_deaths(total_deaths)


func _update_gold_hud() -> void:
	# 作业 5（第 6 课）：金币计数（跨层保留，只在拾取时刷新）
	if hud:
		hud.update_gold(gold_count)


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	# 第 8 课：接收玩家 health_changed 信号 → 转发 HUD 刷新心形
	# （替代第 5 课的 player 直调 dungeon.update_health_ui——信号解耦，双向不认识对方）
	if hud and hud.has_method("update_health"):
		hud.update_health(current_health, max_health)


func _on_player_damaged(_amount: int) -> void:
	# 作业 4（第 8 课）：受伤 → HUD 红屏闪烁
	if hud and hud.has_method("flash_hurt"):
		hud.flash_hurt()


func _on_player_died() -> void:
	# 作业 5（第 8 课）：死亡 → HUD 大字提示
	if hud and hud.has_method("show_death"):
		hud.show_death()


# =========================
# 第 10 课：存档 → 第 11 课迁至 GameData；Main 只做镜像同步
# =========================

func _sync_game_data() -> void:
	# 镜像 → 真源：长期数据变化时同步 GameData 并落盘
	var game_data := get_node_or_null("/root/GameData")

	if game_data == null:
		return

	game_data.gold = gold_count
	game_data.best_floor = best_floor
	game_data.total_deaths = total_deaths

	game_data.save_game()


# =========================
# 第 9 课：房间检测与小地图
# =========================

func _setup_minimap() -> void:
	# generate() 末尾：注入世界尺寸、房间矩形、走廊数据与类型表
	if minimap and minimap.has_method("setup"):
		minimap.setup(map_width, map_height, rooms, corridors, _build_room_types())

	_update_minimap()


func _build_room_types() -> Array[int]:
	# 作业 4（第 9 课）：房间类型表（纯读取已有 POI 格子，不碰 RNG）
	# 优先级：入口 > 出口 > 宝箱 > 怪物 > 普通（导航价值高的覆盖低的）
	var types: Array[int] = []
	types.resize(rooms.size())
	types.fill(MiniMap.ROOM_NORMAL)

	for cell in treasure_cells:
		var idx := _find_room_index_containing_cell(cell)
		if idx >= 0:
			types[idx] = MiniMap.ROOM_TREASURE

	for cell in monster_cells:
		var idx := _find_room_index_containing_cell(cell)
		if idx >= 0 and types[idx] == MiniMap.ROOM_NORMAL:
			types[idx] = MiniMap.ROOM_MONSTER

	var entrance_idx := _find_room_index_containing_cell(entrance_cell)
	if entrance_idx >= 0:
		types[entrance_idx] = MiniMap.ROOM_ENTRANCE

	var exit_idx := _find_room_index_containing_cell(exit_cell)
	if exit_idx >= 0:
		types[exit_idx] = MiniMap.ROOM_EXIT

	return types


func _update_minimap() -> void:
	# 状态变化时推送（探索记录/当前房间/入口/出口/钥匙）
	if minimap and minimap.has_method("update_state"):
		minimap.update_state(
			explored_rooms,
			current_room_index,
			entrance_cell,
			exit_cell,
			has_key,
			key_cell,
			# 作业 1（第 9 课）：出口所在房间索引（探索过才画红点）
			_find_room_index_containing_cell(exit_cell),
			# 作业 2（第 9 课）：钥匙所在房间索引（探索过才画黄点）
			_find_room_index_containing_cell(key_cell)
		)

	# 作业 5（第 9 课）：探索进度行（探索变化时同步刷新）
	if hud and hud.has_method("update_explore"):
		hud.update_explore(explored_rooms.size(), rooms.size())


func _update_player_room() -> void:
	# 世界坐标 → 格子 → 房间索引；变化才重绘（节流 + 按需）
	if player_instance == null or not is_instance_valid(player_instance):
		return

	if tile_layer == null:
		return

	var local_position := tile_layer.to_local(player_instance.global_position)

	var cell := Vector2i(
		floori(local_position.x / float(cell_size)),
		floori(local_position.y / float(cell_size))
	)

	var room_index := _find_room_index_containing_cell(cell)

	# 走廊里不在任何房间——保持上一个当前房间不动
	if room_index == -1:
		return

	var changed := false

	if room_index != current_room_index:
		current_room_index = room_index
		changed = true

	if not explored_rooms.has(room_index):
		explored_rooms[room_index] = true
		changed = true

	if changed:
		_update_minimap()


func _find_room_index_containing_cell(cell: Vector2i) -> int:
	# 索引版（explored_rooms 的 key 需要索引；Rect2i 版供第 5 课巡逻复用）
	for i in rooms.size():
		if _room_has_cell(rooms[i], cell):
			return i

	return -1


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

	# 第 8 课：连接玩家生命信号（实例重建时是全新对象，天然不会重复连接；
	# is_connected 守卫兜底同一实例重复进入本函数的路径）
	if player_instance.has_signal("health_changed"):
		if not player_instance.is_connected("health_changed", _on_player_health_changed):
			player_instance.connect("health_changed", _on_player_health_changed)

	# 作业 4/5（第 8 课）：受伤红屏 / 死亡大字（事件信号，见 player.gd 注释）
	if player_instance.has_signal("damaged"):
		if not player_instance.is_connected("damaged", _on_player_damaged):
			player_instance.connect("damaged", _on_player_damaged)

	if player_instance.has_signal("died"):
		if not player_instance.is_connected("died", _on_player_died):
			player_instance.connect("died", _on_player_died)

	# 第 5 课（5.7）：每层重置玩家生命/无敌/击退状态
	if player_instance.has_method("reset_for_new_layer"):
		player_instance.reset_for_new_layer()


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

func get_cell_world_position(cell: Vector2i) -> Vector2:
	# 第 5 课：格子坐标 → 世界坐标（敌人巡逻点用）
	if tile_layer == null:
		return _cell_to_center_local(cell)

	return tile_layer.to_global(_cell_to_center_local(cell))


func _make_patrol_points(cell: Vector2i) -> Array:
	# 第 5 课改进：房间内多点环游巡逻（A→B→C→…→A），替代两点往返
	# 生成期消耗 main.rng（同种子可复现）；位于 POI 选点之后，不影响地图/POI 统计
	var points: Array = []

	var room := _find_room_containing_cell(cell)

	if room.size != Vector2i.ZERO:
		# 候选 = 房间内可走且未被 POI 占用的格子
		var candidates: Array[Vector2i] = []
		for y in range(room.position.y, room.position.y + room.size.y):
			for x in range(room.position.x, room.position.x + room.size.x):
				var c := Vector2i(x, y)
				if c != cell and _is_cell_available(c):
					candidates.append(c)

		# 中心点优先入环（巡视必经），可用则插入
		var center_cell := _room_center(room)
		var ring: Array[Vector2i] = []
		if center_cell != cell and _is_cell_available(center_cell):
			ring.append(center_cell)

		# 从候选随机补 2~3 个点（小房间自动少补）
		var extra: int = clampi(candidates.size() / 4, 2, 3)
		for i in extra:
			if candidates.is_empty():
				break
			var idx := rng.randi_range(0, candidates.size() - 1)
			var pick := candidates[idx]
			candidates.remove_at(idx)
			if not ring.has(pick):
				ring.append(pick)

		if not ring.is_empty():
			# 环游顺序打乱 → 路径自然交叉，像乱逛而非巡逻兵
			# 踩坑：Array.shuffle() 走全局 RNG（不受种子控制）——改用 main.rng
			# 手写 Fisher-Yates，保证同种子顺序可复现（C# 可对齐）
			for i in range(ring.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp := ring[i]
				ring[i] = ring[j]
				ring[j] = tmp

			points.append(get_cell_world_position(cell))
			for rc in ring:
				points.append(get_cell_world_position(rc))
			return points

	# 不在房间/候选为空：沿上下左右找可走方向做短距离巡逻（保留原逻辑）
	var directions := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for dir in directions:
		var forward := _scan_walkable_cells(cell, dir, 5)

		if not forward.is_empty():
			points.append(get_cell_world_position(cell))
			points.append(get_cell_world_position(forward[-1]))
			return points

		var backward := _scan_walkable_cells(cell, -dir, 5)

		if not backward.is_empty():
			points.append(get_cell_world_position(cell))
			points.append(get_cell_world_position(backward[-1]))
			return points

	# 实在找不到巡逻路径，就原地站立
	points.append(get_cell_world_position(cell))
	return points


func _find_room_containing_cell(cell: Vector2i) -> Rect2i:
	for room in rooms:
		if _room_has_cell(room, cell):
			return room

	return Rect2i()


func _room_has_cell(room: Rect2i, cell: Vector2i) -> bool:
	return (
		cell.x >= room.position.x
		and cell.x < room.position.x + room.size.x
		and cell.y >= room.position.y
		and cell.y < room.position.y + room.size.y
	)


func _scan_walkable_cells(from_cell: Vector2i, dir: Vector2i, max_steps: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var cell := from_cell + dir

	for i in max_steps:
		if is_cell_walkable(cell):
			result.append(cell)
			cell += dir
		else:
			break

	return result


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
