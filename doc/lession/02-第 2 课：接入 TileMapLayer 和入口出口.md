> 很好，我们进入 **第 2 课：接入 TileMapLayer 和入口/出口**。
>
> 上一课我们做的是：
>
> ```text
> 地图数据 grid
> + 随机房间
> + 走廊连接
> + _draw() 调试显示
> ```
>
> 这一课我们要把它变成真正更接近 Godot 2D RPG 的地图：
>
> ```text
> 地图数据 grid
> + TileMapLayer
> + TileSet
> + 地板/墙壁瓦片
> + 入口瓦片
> + 出口瓦片
> ```
>
> 本课完成后，你会得到：
>
> - 一个使用 `TileMapLayer` 显示的 2D 地牢。
> - 地板和墙壁用 tile 表示。
> - 自动生成入口。
> - 自动生成出口。
> - 按 `R` 重新生成。
> - 支持固定 seed 复现。
> - 后续可以很方便地接入玩家、碰撞、导航。
>
> ---
>
> # 1. 本课目标
>
> 我们要完成：
>
> 1. 在场景里加入 `TileMapLayer`。
> 2. 用代码创建一个临时 placeholder TileSet。
> 3. 把上一课的 `grid` 写入 `TileMapLayer`。
> 4. 选择入口和出口。
> 5. 用不同颜色的 tile 标记入口/出口。
> 6. 为后续玩家出生点做准备。
>
> 本课暂时不使用复杂美术资源。  
> 我会先带你用代码生成一个最简单的 placeholder TileSet，保证项目能直接跑起来。
>
> 等你跑通之后，再替换成真正的 RPG 美术瓦片。
>
> ---
>
> # 2. 为什么先使用代码生成的 placeholder TileSet？
>
> 因为学习程序化地图时，最常见的问题是：
>
> > 算法还没学会，结果被 TileSet、图集、瓦片坐标、物理层、地形层卡住了。
>
> 所以我们先用代码生成一个极简 TileSet：
>
> ```text
> (0, 0) = 地板
> (1, 0) = 墙壁
> (2, 0) = 入口
> (3, 0) = 出口
> ```
>
> 这样你可以把注意力集中在：
>
> ```text
> grid 数据
> TileMapLayer.set_cell()
> 入口/出口逻辑
> ```
>
> 后面我们再讲如何换成正式美术资源。
>
> ---
>
> # 3. 场景结构
>
> 继续使用上一课的场景，或者新建一个场景。
>
> 场景结构：
>
> ```text
> Main : Node2D
>   TileMapLayer
>   Camera2D
> ```
>
> 注意：
>
> - `TileMapLayer` 的名字就叫 `TileMapLayer`。
> - 因为脚本里会使用：
>
> ```gdscript
> @onready var tile_layer: TileMapLayer = $TileMapLayer
> ```
>
> 如果你想改名，脚本里的路径也要改。
>
> ---
>
> # 4. Godot 版本说明
>
> 本课使用：
>
> ```text
> Godot 4.3 / 4.4 / 4.5 / 4.7
> ```
>
> 因为 `TileMapLayer` 是 Godot 4.x 后期引入的节点。  
> 如果你使用的是非常老的 Godot 4.0 / 4.1 / 4.2，可能还是旧的 `TileMap` 多层结构，需要稍微改 API。
>
> ---
>
> # 5. 给 Main 添加脚本
>
> 给根节点 `Main` 添加脚本：
>
> ```text
> dungeon_tilemap.gd
> ```
>
> 完整代码如下。
>
> ---
>
> # 6. 第 2 课完整代码
>
> ```gdscript
> extends Node2D
> 
> # =========================
> # 第 2 课：接入 TileMapLayer 和入口/出口
> # =========================
> 
> # ---------- 基础生成参数 ----------
> 
> @export var seed_value: int = 20260824
> @export var use_random_seed: bool = false
> 
> @export var map_width: int = 48
> @export var map_height: int = 32
> 
> @export var room_attempts: int = 60
> @export var max_rooms: int = 10
> 
> @export var min_room_size: Vector2i = Vector2i(4, 3)
> @export var max_room_size: Vector2i = Vector2i(10, 7)
> 
> @export var cell_size: int = 16
> 
> # ---------- TileMap 参数 ----------
> 
> @export_group("TileMap")
> 
> # 如果为 true，脚本会自动创建一个临时 TileSet
> # 适合本课学习，不需要美术资源
> @export var use_placeholder_tileset: bool = true
> 
> # 如果你使用自己的 TileSet，可以关闭 use_placeholder_tileset
> # 然后手动设置 source id 和 atlas coords
> @export var tile_source_id: int = 0
> 
> @export var floor_atlas_coords: Vector2i = Vector2i(0, 0)
> @export var wall_atlas_coords: Vector2i = Vector2i(1, 0)
> @export var entrance_atlas_coords: Vector2i = Vector2i(2, 0)
> @export var exit_atlas_coords: Vector2i = Vector2i(3, 0)
> 
> # ---------- 节点 ----------
> 
> @onready var tile_layer: TileMapLayer = $TileMapLayer
> 
> # ---------- 数据 ----------
> 
> const CELL_WALL := 0
> const CELL_FLOOR := 1
> 
> var rng := RandomNumberGenerator.new()
> 
> # grid[y][x]
> # 0 = wall
> # 1 = floor
> var grid: Array = []
> 
> var rooms: Array = []
> 
> var entrance_cell := Vector2i.ZERO
> var exit_cell := Vector2i.ZERO
> 
> 
> func _ready() -> void:
> 	if tile_layer == null:
> 		push_error("找不到 TileMapLayer，请确认场景里有名为 TileMapLayer 的子节点。")
> 		return
> 
> 	generate()
> 
> 
> func _unhandled_input(event: InputEvent) -> void:
> 	var key := event as InputEventKey
> 	if key == null:
> 		return
> 
> 	if key.pressed and not key.echo and key.keycode == KEY_R:
> 		generate()
> 
> 
> func generate() -> void:
> 	# 防止地图太小
> 	map_width = maxi(20, map_width)
> 	map_height = maxi(16, map_height)
> 
> 	_setup_rng()
> 	_clear_map()
> 	_place_rooms()
> 	_connect_rooms()
> 	_pick_entrance_and_exit()
> 
> 	_setup_tilemap()
> 	_build_tilemap()
> 
> 	_center_camera()
> 
> 
> # =========================
> # RNG
> # =========================
> 
> func _setup_rng() -> void:
> 	if use_random_seed:
> 		rng.randomize()
> 	else:
> 		rng.seed = seed_value
> 
> 
> # =========================
> # 地图数据
> # =========================
> 
> func _clear_map() -> void:
> 	grid.clear()
> 	rooms.clear()
> 
> 	entrance_cell = Vector2i.ZERO
> 	exit_cell = Vector2i.ZERO
> 
> 	grid.resize(map_height)
> 
> 	for y in map_height:
> 		var row: Array = []
> 		row.resize(map_width)
> 		row.fill(CELL_WALL)
> 		grid[y] = row
> 
> 
> func _place_rooms() -> void:
> 	for i in room_attempts:
> 		if rooms.size() >= max_rooms:
> 			break
> 
> 		var room := _make_random_room()
> 
> 		if room.size.x <= 0 or room.size.y <= 0:
> 			continue
> 
> 		if not _overlaps_existing_room(room):
> 			rooms.append(room)
> 			_carve_room(room)
> 
> 
> func _make_random_room() -> Rect2i:
> 	var max_w := mini(max_room_size.x, map_width - 3)
> 	var max_h := mini(max_room_size.y, map_height - 3)
> 
> 	if max_w < 2 or max_h < 2:
> 		return Rect2i()
> 
> 	var min_w := clampi(min_room_size.x, 2, max_w)
> 	var min_h := clampi(min_room_size.y, 2, max_h)
> 
> 	var w := rng.randi_range(min_w, max_w)
> 	var h := rng.randi_range(min_h, max_h)
> 
> 	var x := rng.randi_range(1, map_width - w - 2)
> 	var y := rng.randi_range(1, map_height - h - 2)
> 
> 	return Rect2i(x, y, w, h)
> 
> 
> func _overlaps_existing_room(room: Rect2i) -> bool:
> 	# 向外扩一格，让房间之间保留间距
> 	var expanded := Rect2i(
> 		room.position.x - 1,
> 		room.position.y - 1,
> 		room.size.x + 2,
> 		room.size.y + 2
> 	)
> 
> 	for existing in rooms:
> 		if _rect2i_intersects(expanded, existing):
> 			return true
> 
> 	return false
> 
> 
> func _rect2i_intersects(a: Rect2i, b: Rect2i) -> bool:
> 	return (
> 		a.position.x < b.position.x + b.size.x
> 		and a.position.x + a.size.x > b.position.x
> 		and a.position.y < b.position.y + b.size.y
> 		and a.position.y + a.size.y > b.position.y
> 	)
> 
> 
> func _carve_room(room: Rect2i) -> void:
> 	for y in range(room.position.y, room.position.y + room.size.y):
> 		for x in range(room.position.x, room.position.x + room.size.x):
> 			_set_cell(x, y, CELL_FLOOR)
> 
> 
> func _connect_rooms() -> void:
> 	if rooms.size() < 2:
> 		return
> 
> 	for i in range(rooms.size() - 1):
> 		var a := _room_center(rooms[i])
> 		var b := _room_center(rooms[i + 1])
> 
> 		if rng.randf() < 0.5:
> 			_carve_h_corridor(a.x, b.x, a.y)
> 			_carve_v_corridor(a.y, b.y, b.x)
> 		else:
> 			_carve_v_corridor(a.y, b.y, a.x)
> 			_carve_h_corridor(a.x, b.x, b.y)
> 
> 
> func _room_center(room: Rect2i) -> Vector2i:
> 	return Vector2i(
> 		room.position.x + room.size.x / 2,
> 		room.position.y + room.size.y / 2
> 	)
> 
> 
> func _carve_h_corridor(x1: int, x2: int, y: int) -> void:
> 	var from := mini(x1, x2)
> 	var to := maxi(x1, x2)
> 
> 	for x in range(from, to + 1):
> 		_set_cell(x, y, CELL_FLOOR)
> 
> 
> func _carve_v_corridor(y1: int, y2: int, x: int) -> void:
> 	var from := mini(y1, y2)
> 	var to := maxi(y1, y2)
> 
> 	for y in range(from, to + 1):
> 		_set_cell(x, y, CELL_FLOOR)
> 
> 
> func _set_cell(x: int, y: int, value: int) -> void:
> 	if x < 0 or x >= map_width:
> 		return
> 	if y < 0 or y >= map_height:
> 		return
> 
> 	grid[y][x] = value
> 
> 
> # =========================
> # 入口 / 出口
> # =========================
> 
> func _pick_entrance_and_exit() -> void:
> 	if rooms.is_empty():
> 		# 如果参数太严格导致没有房间，做一个保底地板点
> 		entrance_cell = Vector2i(map_width / 2, map_height / 2)
> 		exit_cell = entrance_cell
> 		_set_cell(entrance_cell.x, entrance_cell.y, CELL_FLOOR)
> 		return
> 
> 	# 入口：第一个房间中心
> 	entrance_cell = _room_center(rooms[0])
> 
> 	# 出口：离入口最远的房间中心
> 	exit_cell = entrance_cell
> 	var best_distance := -1
> 
> 	for room in rooms:
> 		var center := _room_center(room)
> 		var distance := entrance_cell.distance_squared_to(center)
> 
> 		if distance > best_distance:
> 			best_distance = distance
> 			exit_cell = center
> 
> 
> func get_entrance_local_position() -> Vector2:
> 	return _cell_to_center_local(entrance_cell)
> 
> 
> func get_exit_local_position() -> Vector2:
> 	return _cell_to_center_local(exit_cell)
> 
> 
> func _cell_to_center_local(cell: Vector2i) -> Vector2:
> 	return Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5
> 
> 
> # =========================
> # TileMap
> # =========================
> 
> func _setup_tilemap() -> void:
> 	if use_placeholder_tileset:
> 		tile_source_id = _create_placeholder_tileset()
> 
> 		# placeholder TileSet 固定使用这四个坐标
> 		floor_atlas_coords = Vector2i(0, 0)
> 		wall_atlas_coords = Vector2i(1, 0)
> 		entrance_atlas_coords = Vector2i(2, 0)
> 		exit_atlas_coords = Vector2i(3, 0)
> 	else:
> 		if tile_layer.tile_set == null:
> 			push_warning("你关闭了 use_placeholder_tileset，但 TileMapLayer 上没有设置 TileSet。")
> 
> 
> func _create_placeholder_tileset() -> int:
> 	# 生成一张横向小图集：
> 	# [地板][墙壁][入口][出口]
> 	var image := Image.create(cell_size * 4, cell_size, false, Image.FORMAT_RGBA8)
> 
> 	# 地板
> 	image.fill_rect(
> 		Rect2i(0, 0, cell_size, cell_size),
> 		Color(0.82, 0.75, 0.60)
> 	)
> 
> 	# 墙壁
> 	image.fill_rect(
> 		Rect2i(cell_size, 0, cell_size, cell_size),
> 		Color(0.12, 0.12, 0.16)
> 	)
> 
> 	# 入口
> 	image.fill_rect(
> 		Rect2i(cell_size * 2, 0, cell_size, cell_size),
> 		Color(0.20, 0.90, 0.40)
> 	)
> 
> 	# 出口
> 	image.fill_rect(
> 		Rect2i(cell_size * 3, 0, cell_size, cell_size),
> 		Color(0.90, 0.25, 0.25)
> 	)
> 
> 	var texture := ImageTexture.create_from_image(image)
> 
> 	var tile_set := TileSet.new()
> 	tile_set.tile_size = Vector2i(cell_size, cell_size)
> 
> 	var source := TileSetAtlasSource.new()
> 	source.texture = texture
> 	source.texture_region_size = Vector2i(cell_size, cell_size)
> 
> 	var source_id := tile_set.add_source(source)
> 
> 	if source_id < 0:
> 		push_error("创建 placeholder TileSet source 失败。")
> 		return -1
> 
> 	source.create_tile(Vector2i(0, 0)) # floor
> 	source.create_tile(Vector2i(1, 0)) # wall
> 	source.create_tile(Vector2i(2, 0)) # entrance
> 	source.create_tile(Vector2i(3, 0)) # exit
> 
> 	tile_layer.tile_set = tile_set
> 
> 	return source_id
> 
> 
> func _build_tilemap() -> void:
> 	if tile_layer == null:
> 		return
> 
> 	if tile_source_id < 0:
> 		push_error("tile_source_id 无效，无法写入 TileMapLayer。")
> 		return
> 
> 	tile_layer.clear()
> 
> 	# 先写入整个地图
> 	for y in map_height:
> 		for x in map_width:
> 			var cell := Vector2i(x, y)
> 
> 			var atlas_coords: Vector2i
> 
> 			if grid[y][x] == CELL_FLOOR:
> 				atlas_coords = floor_atlas_coords
> 			else:
> 				atlas_coords = wall_atlas_coords
> 
> 			tile_layer.set_cell(cell, tile_source_id, atlas_coords)
> 
> 	# 最后覆盖入口和出口
> 	tile_layer.set_cell(entrance_cell, tile_source_id, entrance_atlas_coords)
> 	tile_layer.set_cell(exit_cell, tile_source_id, exit_atlas_coords)
> 
> 
> # =========================
> # Camera
> # =========================
> 
> func _center_camera() -> void:
> 	var cam := get_node_or_null(^"Camera2D") as Camera2D
> 	if cam == null:
> 		return
> 
> 	cam.make_current()
> 	cam.position = Vector2(
> 		map_width * cell_size * 0.5,
> 		map_height * cell_size * 0.5
> 	)
> ```
>
> ---
>
> # 7. 运行效果
>
> 运行场景后，你应该看到：
>
> - 深色方块：墙壁。
> - 浅色方块：地板。
> - 绿色方块：入口。
> - 红色方块：出口。
> - 按 `R` 重新生成地牢。
>
> 如果 `Use Random Seed` 关闭：
>
> - 同一个 `Seed Value` 会生成同一个地牢。
> - 入口和出口位置也会固定。
>
> 如果 `Use Random Seed` 打开：
>
> - 每次运行都会不同。
>
> ---
>
> # 8. 本课核心知识讲解
>
> ---
>
> ## 8.1 TileMapLayer 是什么？
>
> 在 Godot 4.x 中，`TileMapLayer` 是 2D 瓦片地图的一层。
>
> 它负责：
>
> - 显示瓦片。
> - 管理瓦片坐标。
> - 可以设置物理层。
> - 可以设置导航层。
> - 可以配合 `TileSet` 做地形自动拼接。
>
> 我们这一课只用它最基础的功能：
>
> ```gdscript
> tile_layer.set_cell(cell, source_id, atlas_coords)
> ```
>
> ---
>
> ## 8.2 set_cell 的三个核心参数
>
> ```gdscript
> tile_layer.set_cell(cell, source_id, atlas_coords)
> ```
>
> 含义：
>
> ```text
> cell         地图上的格子坐标，例如 Vector2i(3, 5)
> source_id     使用 TileSet 里的哪个图源
> atlas_coords  这个图源图集里的哪一张瓦片
> ```
>
> 例如：
>
> ```gdscript
> tile_layer.set_cell(Vector2i(5, 7), 0, Vector2i(0, 0))
> ```
>
> 意思是：
>
> ```text
> 在地图坐标 (5, 7) 的位置，
> 使用 TileSet 里 source id 为 0 的图源，
> 放置图集中坐标为 (0, 0) 的瓦片。
> ```
>
> ---
>
> ## 8.3 我们的 placeholder TileSet
>
> 代码中生成了一张横向图集：
>
> ```text
> (0, 0) 地板
> (1, 0) 墙壁
> (2, 0) 入口
> (3, 0) 出口
> ```
>
> 对应：
>
> ```gdscript
> floor_atlas_coords = Vector2i(0, 0)
> wall_atlas_coords = Vector2i(1, 0)
> entrance_atlas_coords = Vector2i(2, 0)
> exit_atlas_coords = Vector2i(3, 0)
> ```
>
> 这样我们不需要外部图片也能看到结果。
>
> ---
>
> ## 8.4 入口和出口是怎么选的？
>
> 当前逻辑：
>
> ```text
> 入口 = 第一个房间的中心
> 出口 = 离入口最远的房间中心
> ```
>
> 代码在：
>
> ```gdscript
> _pick_entrance_and_exit()
> ```
>
> 这个逻辑比较简单，但对小规模地牢很有效。
>
> 后续可以升级成：
>
> - 出口放在最后一个房间。
> - 出口放在离入口最远且路径最长的房间。
> - 出口放在 Boss 房。
> - 入口放在安全房。
> - 入口附近不放怪物。
> - 出口附近放置钥匙门。
>
> ---
>
> # 9. 如何替换成你自己的 TileSet？
>
> 当你跑通以后，可以开始替换成真正的美术资源。
>
> ---
>
> ## 方案 A：继续使用脚本，但替换图集
>
> 你可以把代码里的：
>
> ```gdscript
> var image := Image.create(...)
> ```
>
> 这一部分去掉，改成加载一张图片：
>
> ```gdscript
> var texture := load("res://assets/tiles/dungeon_tiles.png") as Texture2D
> ```
>
> 然后设置：
>
> ```gdscript
> source.texture = texture
> source.texture_region_size = Vector2i(16, 16)
> ```
>
> 前提是：
>
> ```text
> 你的图片横向排列：
> (0,0) 地板
> (1,0) 墙壁
> (2,0) 入口
> (3,0) 出口
> ```
>
> ---
>
> ## 方案 B：在 Godot 编辑器里手动创建 TileSet
>
> 这是正式项目更常用的方式。
>
> 步骤大概如下：
>
> 1. 选中 `TileMapLayer`。
> 2. 在 Inspector 中找到 `Tile Set`。
> 3. 点击 `<empty>`，选择 `New TileSet`。
> 4. 打开 TileSet 面板。
> 5. 添加一个 `Atlas Source`。
> 6. 指定你的瓦片图集纹理。
> 7. 设置 tile size，例如：
>
> ```text
> 16x16
> ```
>
> 或：
>
> ```text
> 32x32
> ```
>
> 8. 选择你需要的瓦片。
> 9. 记住：
>    - source id
>    - 地板瓦片坐标
>    - 墙壁瓦片坐标
>    - 入口瓦片坐标
>    - 出口瓦片坐标
>
> 然后在 `Main` 脚本的 Inspector 里关闭：
>
> ```text
> Use Placeholder Tileset
> ```
>
> 设置：
>
> ```text
> Tile Source Id = 你的 source id
> Floor Atlas Coords = 你的地板瓦片坐标
> Wall Atlas Coords = 你的墙壁瓦片坐标
> Entrance Atlas Coords = 你的入口瓦片坐标
> Exit Atlas Coords = 你的出口瓦片坐标
> ```
>
> ---
>
> # 10. 推荐你先用 Kenney 资源练习
>
> 如果你暂时没有自己的瓦片，可以使用 Kenney 的免费资源。
>
> 网站：
>
> ```text
> https://kenney.nl/assets
> ```
>
> 可以搜索：
>
> ```text
> Tiny Dungeon
> Roguelike RPG pack
> Tiny Town
> ```
>
> 很多资源是 CC0，适合练习。
>
> 使用真实资源时，你的脚本逻辑不变，只是瓦片坐标和图集不同。
>
> ---
>
> # 11. 常见问题排查
>
> ---
>
> ## 问题 1：运行后什么都没有
>
> 检查：
>
> 1. 场景里是否有 `TileMapLayer`。
> 2. `TileMapLayer` 节点名是否就是 `TileMapLayer`。
> 3. 脚本是否挂在 `Main` 根节点上。
> 4. 控制台是否有错误。
> 5. `Camera2D` 是否存在。
>
> ---
>
> ## 问题 2：报错说找不到 TileMapLayer
>
> 脚本里有：
>
> ```gdscript
> @onready var tile_layer: TileMapLayer = $TileMapLayer
> ```
>
> 所以节点路径必须是：
>
> ```text
> Main/TileMapLayer
> ```
>
> 如果你把节点改名成：
>
> ```text
> GroundLayer
> ```
>
> 那么脚本要改成：
>
> ```gdscript
> @onready var tile_layer: TileMapLayer = $GroundLayer
> ```
>
> ---
>
> ## 问题 3：地图显示了，但入口/出口没显示
>
> 检查：
>
> 1. `use_placeholder_tileset` 是否为 `true`。
> 2. `_pick_entrance_and_exit()` 是否被调用。
> 3. `_build_tilemap()` 最后是否覆盖了入口/出口。
> 4. 入口和出口是否被后续错误覆盖。
>
> 当前代码顺序是：
>
> ```text
> 先画所有地板/墙壁
> 再画入口
> 再画出口
> ```
>
> 所以入口/出口会覆盖原来的地板。
>
> ---
>
> ## 问题 4：地图太大或太小
>
> 可以调整：
>
> ```text
> Map Width
> Map Height
> Cell Size
> Camera2D Zoom
> ```
>
> 如果地图太大，可以把 `Camera2D` 的 `Zoom` 设置为：
>
> ```text
> 0.5, 0.5
> ```
>
> 或者在 `_center_camera()` 里加：
>
> ```gdscript
> cam.zoom = Vector2(0.7, 0.7)
> ```
>
> ---
>
> ## 问题 5：按 R 没反应
>
> 检查：
>
> - 游戏窗口是否获得焦点。
> - 是否运行的是当前场景。
> - 是否有脚本错误导致节点未初始化。
> - 输入是否被其他节点吞掉。
>
> ---
>
> # 12. 课后作业
>
> ---
>
> ## 作业 1：让入口和出口更明显
>
> 现在入口和出口只是不同颜色的瓦片。
>
> 你可以尝试：
>
> - 在入口位置加一个 `Marker2D`。
> - 在出口位置加一个 `Marker2D`。
> - 或者添加 `Sprite2D`。
> - 或者添加简单的 `Polygon2D`。
>
> 目标：
>
> ```text
> 入口和出口不仅存在于地图数据里，也能作为游戏对象被引用。
> ```
>
> ---
>
> ## 作业 2：给入口和出口增加场景节点
>
> 在 `generate()` 最后添加两个节点：
>
> ```gdscript
> var entrance_marker := Marker2D.new()
> entrance_marker.name = "EntranceMarker"
> entrance_marker.position = get_entrance_local_position()
> add_child(entrance_marker)
> ```
>
> 出口同理。
>
> 注意：
>
> 重新生成前最好先删除旧节点，否则会越加越多。
>
> 你可以用：
>
> ```gdscript
> for child in get_children():
> 	if child is Marker2D:
> 		child.queue_free()
> ```
>
> ---
>
> ## 作业 3：让出口一定不是入口
>
> 当前如果只有一个房间，入口和出口会相同。
>
> 尝试修改逻辑：
>
> ```text
> 如果 rooms.size() == 1：
>     在房间里随机选两个不同格子作为入口和出口
> ```
>
> 这会让你开始处理：
>
> - 房间内合法点选择。
> - 避免重合。
> - 地图边界。
>
> ---
>
> ## 作业 4：让出口选择“最远路径”，而不是直线最远
>
> 现在出口是直线距离最远：
>
> ```gdscript
> entrance_cell.distance_squared_to(center)
> ```
>
> 但地牢里直线最远不一定走路最远。
>
> 你可以尝试后续结合：
>
> ```gdscript
> AStarGrid2D
> ```
>
> 计算：
>
> ```text
> 从入口到每个房间中心的实际路径长度
> ```
>
> 然后选择路径最长的房间作为出口。
>
> 这会是很好的下一课方向。
>
> ---
>
> ## 作业 5：换成真实瓦片
>
> 使用任意一张简单瓦片图，例如：
>
> ```text
> 地板
> 墙壁
> 门
> 楼梯
> ```
>
> 然后关闭：
>
> ```text
> Use Placeholder Tileset
> ```
>
> 手动配置：
>
> ```text
> Tile Source Id
> Floor Atlas Coords
> Wall Atlas Coords
> Entrance Atlas Coords
> Exit Atlas Coords
> ```
>
> 这一步非常重要。  
> 只有完成这一步，你才算真正接入了美术工作流。
>
> ---
>
> # 13. 你现在已经掌握了什么？
>
> 你现在已经完成了：
>
> ```text
> 随机地牢数据生成
> + TileMapLayer 输出
> + 入口选择
> + 出口选择
> + Seed 复现
> + 可视化地图
> ```
>
> 这已经是一个可以进一步做 RPG 内容的地基。
>
> 下一课建议做：
>
> ```text
> AStarGrid2D 连通性验证
> + 玩家出生点
> + 简单移动
> + 入口/出口触发区域
> ```
>
> 也就是让地牢从“看起来像地图”，变成“可以玩的地图”。