extends CharacterBody2D

# =========================
# 第 7 课：三态状态机敌人
# PATROL 巡逻 → CHASE 追击 → RETURN 返回（显式 enum + 转换层）
# 视线检测：沿线 8px 采样查墙（隔墙不发现）
# 保留资产：多点环游/随机停顿/张望/呼吸三速/接触轮询/类型系统/受击三态
# =========================

enum EnemyState {
	PATROL,
	CHASE,
	RETURN,
}

# ---------- 基础移动 ----------

@export var speed: float = 70.0

# 到点停顿随机区间（运行期随机——每次玩不同，打破机械节奏）
@export var wait_time_min: float = 0.4
@export var wait_time_max: float = 1.2

@export var arrival_distance: float = 4.0
@export var collision_radius: float = 4.0

# ---------- 接触伤害 ----------

@export var contact_damage: int = 1

# 接触伤害判定半径（≈ Hitbox 6.4 + 玩家碰撞体 5）
@export var contact_range: float = 11.0

# ---------- 生命 ----------

@export var max_health: int = 2

# 作业 3（第 6 课）：敌人类型（normal/fast/tank——setup 时按类型重塑属性与配色）
# 第 12 课：Main 配置流经 apply_config 最终覆盖（文档的 grunt/runner/brute ≙ 本仓库命名）
@export var enemy_type: String = "normal"

# 第 12 课：精英标记（任何类型的强化贴膜——金色 lerp + 体型 ×1.25 + 属性强化）
var is_elite: bool = false

# 第 12 课：体型系数（呼吸动画每帧重写 sprite.scale——本系数乘进动画，见 _process）
var size_scale: float = 1.0

# 第 12 课：掉落属性（Main 的 on_enemy_died 消费——差异化掉落由数据驱动）
var drop_count: int = 1
var drop_chance_multiplier: float = 1.0
var potion_chance_bonus: float = 0.0

# 类型配色（Sprite2D modulate 基色；受击/追击时在此基础上叠加）
const TYPE_COLOR := {
	"normal": Color.WHITE,
	"fast": Color(0.75, 0.85, 1.0),   # 偏蓝（敏捷）
	"tank": Color(1.0, 0.78, 0.55),   # 偏橙（厚重）
}

# ---------- 追击参数（第 7 课：发现/脱离分离 + 视线） ----------

@export var detection_range: float = 90.0
@export var lose_range: float = 150.0
@export var lose_sight_time: float = 0.8

# 作业 2（第 7 课）：视野半角（度）——仅"发现"需要面向玩家；
# CHASE 中的保持判定不加角度（防绕背瞬间丢失→状态抖动）
@export var detection_half_angle: float = 75.0
# 倍率 1.15：fast 126 / normal 80 / tank 52——全员低于玩家 140，风筝普适
@export var chase_speed_multiplier: float = 1.15

# ---------- 外部数据 ----------

var dungeon: Node
var patrol_points: Array = []

# ---------- 巡逻状态 ----------

var current_point_index: int = 0
var is_waiting: bool = false
var wait_remaining: float = 0.0

# ---------- 生命状态 ----------

var health: int = 2
var dead: bool = false
var _flash_t: float = 0.0  # 受击闪烁剩余时间（>0 时 modulate 优先级最高）

# ---------- AI 状态（第 7 课） ----------

var state: EnemyState = EnemyState.PATROL
var is_chasing: bool = false  # 视觉用（呼吸加速/泛红）——CHASE 态镜像

var player: Node2D = null
var last_known_player_position := Vector2.ZERO
var time_since_seen: float = 0.0

# 卡住检测（第 7 课修复版）：双通道——
# 踩坑 1：贴墙滑动 velocity≠0 但无位移（velocity==0 判定失效）
# 踩坑 2：贴墙"蠕动"（每 0.8s 挪 2.1px）恰好清零 2px 进展判定 → 永不卡死
# 方案：停滞累积 + 每 1s 净位移健康检查（<6px/秒 = 卡死，理论应 ~speed px/秒）
var stuck_time: float = 0.0
var _last_progress_pos := Vector2.ZERO
var _progress_check_t: float = 0.0
var _progress_check_pos := Vector2.ZERO
var _target_check_d: float = -1.0

var home_position := Vector2.ZERO

var chase_speed: float = 0.0

# 作业 2：朝向（随移动更新；发现判定用）
var facing := Vector2.RIGHT

# 作业 4（第 7 课）：AStar 追击——0.3s 重算路径，沿路点绕墙
var _path_world: Array[Vector2] = []
var _repath_timer: float = 0.0

# 追击足迹（面包屑）：CHASE 时记录走过的格子，RETURN 原路回溯——
# 来时的路必然通，比 AStar 更符合"原路返回"直觉且零卡死
var _breadcrumb: Array[Vector2i] = []
const BREADCRUMB_MAX := 512

# 呼吸动画计时
var _t := 0.0

# 张望状态机（仅等待中触发；运行期随机，不进种子序列）
var _look_cool := 0.0
var _look_t := 0.0
var _look_dir := 1.0

@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Sprite2D = $Sprite2D
@onready var alert: Sprite2D = $Alert

# 作业 3（第 7 课）：警报叹号剩余显示时间（>0 显示，_start_chase 触发）
var _alert_t: float = 0.0


func _ready() -> void:
	pass  # 接触伤害为 _physics_process 每帧距离检测；Hitbox 保留供未来扩展


func _process(delta: float) -> void:
	# 史莱姆呼吸：轻微正弦缩放；移动时加速加剧（赶路感），追击时最快最猛（兴奋感）
	# 只缩 Sprite2D 不缩根节点——根 scale 会连带缩放子节点碰撞体，破坏触发半径
	var rate := 1.0
	var amp := 0.08
	if is_chasing:
		rate = 3.0
		amp = 0.13
	elif velocity != Vector2.ZERO:
		rate = 2.2
		amp = 0.10

	_t += delta * rate
	var s := 1.0 + amp * sin(_t * 3.0)
	# 第 12 课：体型系数乘进呼吸动画（精英 ×1.25——直接设 scale 会被本行每帧覆盖）
	sprite.scale = Vector2(s, s) * size_scale

	# modulate 四态协调（作业 1：状态可视化——受击红 > 追击粉 > 返回蓝 > 类型基色）
	# 踩坑：不能在受击回调里直接赋 modulate——本函数每帧覆盖会立刻冲掉闪烁
	var base_color: Color = TYPE_COLOR.get(enemy_type, Color.WHITE)
	# 第 12 课：精英金色渗染（45% 向金色 lerp——四态变色逻辑不变，只改基色）
	if is_elite:
		base_color = base_color.lerp(Color(1.0, 0.85, 0.3), 0.45)
	if _flash_t > 0.0:
		_flash_t -= delta
		sprite.modulate = Color(1.0, 0.35, 0.35)
	elif is_chasing:
		sprite.modulate = Color(1.0, 0.6, 0.6)
	elif state == EnemyState.RETURN:
		sprite.modulate = Color(0.65, 0.8, 1.0)
	else:
		sprite.modulate = base_color

	# 警报叹号倒计时（作业 3：发现玩家头顶显示 0.3s）
	if _alert_t > 0.0:
		_alert_t -= delta
		alert.visible = _alert_t > 0.0

	# 张望：等待中偶尔左右瞥一眼（身体微偏移模拟探头）
	if _look_t > 0.0:
		_look_t -= delta
		sprite.position.x = _look_dir * 1.5

		if _look_t <= 0.0:
			# 50% 概率紧接着看另一边（更像警觉）
			if randf() < 0.5:
				_look_dir = -_look_dir
				_look_t = randf_range(0.3, 0.5)
			else:
				sprite.position.x = 0.0
				_look_cool = randf_range(1.5, 3.5)
	elif is_waiting and state == EnemyState.PATROL:
		_look_cool -= delta

		if _look_cool <= 0.0:
			_look_dir = 1.0 if randf() < 0.5 else -1.0
			_look_t = randf_range(0.35, 0.55)
	else:
		# 移动中不该有偏移残留
		sprite.position.x = 0.0


# Main 生成后调用：注入地图引用 + 巡逻路径，并瞬移到首个巡逻点
func setup(dungeon_reference: Node, points: Array) -> void:
	dungeon = dungeon_reference
	patrol_points = points

	# 第 6 课：每只满血出场
	health = max_health
	dead = false
	_flash_t = 0.0

	# 作业 3：按类型重塑（在速度个体差异之前应用基础模板）
	_apply_type_template()

	# 速度个体差异 ±15%（运行期随机：每次玩都不同，群体不齐步）
	speed *= randf_range(0.85, 1.15)
	chase_speed = speed * chase_speed_multiplier

	_look_cool = randf_range(1.0, 2.5)


func apply_config(config: Dictionary) -> void:
	# 第 12 课：Main 配置流最终覆盖——在 setup（基础模板 + 个体差异）之后调用，
	# 拥有最后决定权（层数成长 / 精英强化都已折算进 config）
	enemy_type = str(config.get("name", enemy_type))
	is_elite = bool(config.get("is_elite", false))

	max_health = int(config.get("max_health", max_health))
	health = max_health

	speed = float(config.get("speed", speed))
	contact_damage = int(config.get("contact_damage", contact_damage))

	detection_range = float(config.get("detection_range", detection_range))
	lose_range = float(config.get("lose_range", lose_range))
	chase_speed_multiplier = float(config.get("chase_speed_multiplier", chase_speed_multiplier))

	collision_radius = float(config.get("collision_radius", collision_radius))

	drop_count = int(config.get("drop_count", drop_count))
	drop_chance_multiplier = float(config.get("drop_chance_multiplier", drop_chance_multiplier))
	potion_chance_bonus = float(config.get("potion_chance_bonus", potion_chance_bonus))

	# 体型（Main 侧精英已 ×1.25 折算进 size_scale；呼吸动画每帧乘用它）
	size_scale = float(config.get("size_scale", 1.0))

	# 精英碰撞体微放大（上限 6：16px 走廊不卡死——文档问题 5 的预防）
	if is_elite:
		collision_radius = minf(collision_radius * 1.15, 6.0)

	# setup 的个体差异已被上面覆盖——按最终速度重掷（运行期随机源，保持群体不齐步）
	speed *= randf_range(0.85, 1.15)
	chase_speed = speed * chase_speed_multiplier

	# 第 7 课：AI 状态复位
	state = EnemyState.PATROL
	is_chasing = false
	time_since_seen = 0.0
	stuck_time = 0.0
	_last_progress_pos = global_position
	_progress_check_t = 0.0
	_progress_check_pos = global_position
	_target_check_d = -1.0

	if patrol_points.is_empty():
		home_position = global_position
		last_known_player_position = global_position
		return

	global_position = patrol_points[0]
	home_position = patrol_points[0]
	last_known_player_position = global_position

	current_point_index = 0

	if patrol_points.size() > 1:
		current_point_index = 1

	is_waiting = false
	wait_remaining = 0.0


func _apply_type_template() -> void:
	# 作业 3（第 6 课）：类型模板 + 第 7 课参数迁移（detection/lose_range）
	match enemy_type:
		"fast":
			speed = 110.0
			max_health = 1
			contact_damage = 1
			detection_range = 110.0
			lose_range = 170.0
		"tank":
			speed = 45.0
			max_health = 4
			contact_damage = 2
			detection_range = 70.0
			lose_range = 120.0
		_:
			# normal：保持导出默认（70 / 2 / 1 / 90 / 150）
			pass

	health = max_health


# =========================
# 第 6 课：受击 / 死亡
# =========================

func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if dead:
		return

	health -= amount

	print("敌人受击，剩余生命：", health)

	if health <= 0:
		dead = true
		_die()
		return

	_flash_t = 0.12


func _die() -> void:
	# 死亡处理交 Main（掉落判定/动态实体移除）；敌人只负责自己消失
	if dungeon and dungeon.has_method("on_enemy_died"):
		dungeon.on_enemy_died(self, global_position)

	queue_free()


# =========================
# 主循环：状态机调度（第 7 课）
# =========================

func _physics_process(delta: float) -> void:
	if dead or dungeon == null or not dungeon.has_method("is_world_position_walkable"):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var player_ref := _get_player_ref()

	# 接触伤害：每帧距离检测（踩坑：body_entered 持续重叠不重发）
	if is_instance_valid(player_ref):
		if global_position.distance_to(player_ref.global_position) < contact_range:
			if player_ref.has_method("take_damage"):
				player_ref.take_damage(contact_damage, global_position)

	_update_state(delta, player_ref)

	match state:
		EnemyState.PATROL:
			_process_patrol(delta)
		EnemyState.CHASE:
			_process_chase(delta)
		EnemyState.RETURN:
			_process_return(delta)


func _get_player_ref() -> Node2D:
	if player == null and dungeon is Node:
		player = dungeon.get_node_or_null("Player")
	return player


# =========================
# 状态转换（第 7 课核心）
# =========================

func _update_state(delta: float, player_ref: Node2D) -> void:
	match state:
		EnemyState.PATROL:
			if _is_player_visible(player_ref, detection_range):
				_start_chase(player_ref)

		EnemyState.CHASE:
			if player_ref == null or not is_instance_valid(player_ref):
				state = EnemyState.RETURN
				is_chasing = false
				stuck_time = 0.0
				return

			# 作业 2：CHASE 保持判定用全向视线（无角度）——玩家绕背不瞬间丢失
			if player_ref != null and is_instance_valid(player_ref) \
					and global_position.distance_to(player_ref.global_position) <= lose_range \
					and _has_line_of_sight(player_ref):
				last_known_player_position = player_ref.global_position
				time_since_seen = 0.0
			else:
				time_since_seen += delta

			var distance_to_player := global_position.distance_to(player_ref.global_position)

			if distance_to_player > lose_range or time_since_seen > lose_sight_time:
				state = EnemyState.RETURN
				is_chasing = false
				stuck_time = 0.0

		EnemyState.RETURN:
			if _is_player_visible(player_ref, detection_range):
				_start_chase(player_ref)


func _start_chase(target_player: Node2D) -> void:
	state = EnemyState.CHASE
	is_chasing = true
	is_waiting = false
	stuck_time = 0.0
	time_since_seen = 0.0
	last_known_player_position = target_player.global_position

	# 面包屑：新一轮追击重新记录足迹（起点入栈）
	_breadcrumb.clear()
	_breadcrumb.append(_current_cell())

	# 作业 3：发现玩家！头顶警报 0.3s
	_alert_t = 0.3
	alert.visible = true


func _current_cell() -> Vector2i:
	var tl: TileMapLayer = dungeon.tile_layer
	return tl.local_to_map(tl.to_local(global_position)) if tl else Vector2i(-1, -1)


# =========================
# 巡逻（保留：多点环游 + 随机停顿）
# =========================

func _process_patrol(delta: float) -> void:
	if patrol_points.size() <= 1:
		# 无路径或单点：原地待机
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_waiting:
		wait_remaining -= delta
		velocity = Vector2.ZERO

		if wait_remaining <= 0.0:
			is_waiting = false
			current_point_index = (current_point_index + 1) % patrol_points.size()

		move_and_slide()
		return

	var target: Vector2 = patrol_points[current_point_index]
	var arrived := _move_towards(target, speed, delta)

	if arrived:
		is_waiting = true
		wait_remaining = randf_range(wait_time_min, wait_time_max)
		velocity = Vector2.ZERO
	elif velocity == Vector2.ZERO:
		# 巡逻被墙卡住：切换下一个巡逻点
		current_point_index = (current_point_index + 1) % patrol_points.size()

	move_and_slide()


# =========================
# 追击（第 7 课：奔向最后已知位置；作业 4：AStar 寻路绕墙）
# =========================

func _repath_to(target_world: Vector2) -> void:
	# 作业 4：格子级 AStar 寻路 → 世界坐标路点序列（不含起点）
	_repath_timer = 0.3
	_path_world.clear()

	var tl: TileMapLayer = dungeon.tile_layer
	if tl == null or not dungeon.has_method("is_cell_walkable"):
		return

	var from_cell := tl.local_to_map(tl.to_local(global_position))
	var to_cell := tl.local_to_map(tl.to_local(target_world))

	# 保底：贴墙时自身格可能是墙格（AStar 墙起点返回空路径）
	# → 用邻域最近地板格作起点
	if not dungeon.is_cell_walkable(from_cell):
		var snapped := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			if dungeon.is_cell_walkable(from_cell + d):
				from_cell = from_cell + d
				snapped = true
				break
		if not snapped:
			return

	if not dungeon.is_cell_walkable(to_cell):
		return  # 目标格是墙：留空路径，调用方回退直线冲

	var cells: Array = dungeon.astar_grid.get_id_path(from_cell, to_cell)

	for i in range(1, cells.size()):  # 跳过起点自身
		_path_world.append(tl.to_global(tl.map_to_local(cells[i])))


func _process_chase(delta: float) -> void:
	# 作业 4：0.3s 重算 AStar 路径；沿路点走（自动绕墙），无路径回退直线
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_to(last_known_player_position)

	var target := last_known_player_position
	if not _path_world.is_empty():
		target = _path_world[0]

		if global_position.distance_to(target) <= arrival_distance:
			_path_world.pop_front()
			target = _path_world[0] if not _path_world.is_empty() else last_known_player_position

	var arrived := _move_towards(target, chase_speed, delta)
	_update_stuck(delta, target)

	# 面包屑：进入新格子记录；去环——若新格已在栈浅层出现，
	# 截断到该处（防绕圈追击时 A→B→A→B 重复入栈导致回溯打转）
	var cell := _current_cell()
	if cell != _breadcrumb.back() and cell.x >= 0:
		var loop_at := _breadcrumb.rfind(cell)
		if loop_at >= 0 and _breadcrumb.size() - loop_at <= 8:
			_breadcrumb.resize(loop_at + 1)
		else:
			_breadcrumb.append(cell)
			if _breadcrumb.size() > BREADCRUMB_MAX:
				_breadcrumb.pop_front()

	if arrived:
		# 到达最终目标但看不到玩家：转返回
		if time_since_seen > 0.05:
			state = EnemyState.RETURN
			is_chasing = false
			stuck_time = 0.0
	elif stuck_time > 0.5:
		# 无进展超 0.5s（含贴墙滑）：放弃追击
		state = EnemyState.RETURN
		is_chasing = false
		stuck_time = 0.0

	move_and_slide()


# =========================
# 返回（第 7 课定稿：面包屑原路回溯优先，AStar 兜底）
# 踩坑：固定目标下沿用 CHASE 的 0.3s 高频重算会引发起点振荡
#       （每次重算首点可能在身后 → 来回走）——改为路径空才重算
# =========================

func _process_return(delta: float) -> void:
	# 阶段 1：还没到过最后所见位置 → 先去搜一圈（近距，AStar 一次算好）
	var target: Vector2
	var searching := false

	if global_position.distance_to(last_known_player_position) > arrival_distance * 2.0:
		target = last_known_player_position
		searching = true
	elif not _breadcrumb.is_empty():
		# 阶段 2a：有足迹 → 原路回溯（来时的路必然通）
		target = _breadcrumb_world(_breadcrumb.back())
	elif not patrol_points.is_empty():
		# 阶段 2b：无足迹 → AStar 回最近巡逻点
		target = patrol_points[_get_closest_patrol_point_index()]
	else:
		target = home_position

	var move_target := target

	if searching or _breadcrumb.is_empty():
		# AStar 模式：路径空才重算（固定目标高频重算会振荡）
		if _path_world.is_empty():
			_repath_to(target)

		if not _path_world.is_empty():
			move_target = _path_world[0]

			if global_position.distance_to(move_target) <= arrival_distance:
				_path_world.pop_front()
				move_target = _path_world[0] if not _path_world.is_empty() else target

	var arrived := _move_towards(move_target, speed, delta)
	_update_stuck(delta, move_target)

	if arrived:
		if searching:
			# 搜完没发现 → 标记搜索完成，走回家
			last_known_player_position = global_position
		elif not _breadcrumb.is_empty():
			# 回溯到达一格：弹出继续下一格
			_breadcrumb.pop_back()
		else:
			_return_complete()

	if stuck_time > 1.0:
		if not _breadcrumb.is_empty():
			# 面包屑走不通（理论不会，防御）：清空换 AStar
			_breadcrumb.clear()
			stuck_time = 0.0
		elif stuck_time > 2.0:
			# 终极保底：瞬移回巡逻点（正常游戏几乎不会触发）
			var idx := _get_closest_patrol_point_index()
			global_position = patrol_points[idx] if not patrol_points.is_empty() else home_position
			_return_complete()

	move_and_slide()


func _breadcrumb_world(cell: Vector2i) -> Vector2:
	var tl: TileMapLayer = dungeon.tile_layer
	return tl.to_global(tl.map_to_local(cell))


func _return_complete() -> void:
	state = EnemyState.PATROL
	current_point_index = _get_closest_patrol_point_index()
	is_waiting = false
	stuck_time = 0.0
	_breadcrumb.clear()
	_path_world.clear()


# =========================
# 卡住检测（三通道）：
# 1 停滞累积（<2px）；2 每秒净位移（<6px）；
# 3 每秒目标接近量（<6px）——抓"贴墙绕圈"：每帧有位移、净位移也可能过，
#   但距目标永不减小（绕着墙角转圈够不着路点）
# =========================

func _update_stuck(delta: float, target: Vector2) -> void:
	# 通道 1：即时停滞
	if global_position.distance_to(_last_progress_pos) < 2.0:
		stuck_time += delta
	else:
		_last_progress_pos = global_position

	# 通道 2+3：每 1s 健康检查（净位移 + 目标接近量）
	_progress_check_t += delta
	if _progress_check_t >= 1.0:
		var net_moved := global_position.distance_to(_progress_check_pos)
		var target_d := global_position.distance_to(target)
		var target_progress := _target_check_d - target_d  # 正值=接近了

		if net_moved >= 6.0 and (target_progress >= 6.0 or target_d < arrival_distance * 3.0):
			stuck_time = 0.0  # 在走且在接近目标（或已很近）→ 健康
		else:
			stuck_time += 1.0  # 停滞/蠕动/绕圈 → 顶格

		_progress_check_t = 0.0
		_progress_check_pos = global_position
		_target_check_d = target_d


func _get_closest_patrol_point_index() -> int:
	if patrol_points.is_empty():
		return 0

	var best_index := 0
	var best_distance := 999999999.0

	for i in patrol_points.size():
		var distance := global_position.distance_squared_to(patrol_points[i])

		if distance < best_distance:
			best_distance = distance
			best_index = i

	return best_index


# =========================
# 移动辅助（文档版：返回 arrived 布尔 + 贴墙滑动）
# =========================

func _move_towards(target: Vector2, move_speed: float, delta: float) -> bool:
	var direction := target - global_position
	var distance := direction.length()

	if distance <= arrival_distance:
		velocity = Vector2.ZERO
		return true

	var desired_velocity := direction.normalized() * move_speed
	facing = direction.normalized()  # 作业 2：朝向随移动更新
	var next_position := global_position + desired_velocity * delta

	if dungeon.is_world_position_walkable(next_position, collision_radius):
		velocity = desired_velocity
		return false

	# 贴墙滑动
	var x_only := Vector2(next_position.x, global_position.y)
	var y_only := Vector2(global_position.x, next_position.y)

	if dungeon.is_world_position_walkable(x_only, collision_radius):
		velocity = Vector2(desired_velocity.x, 0.0)
		return false

	if dungeon.is_world_position_walkable(y_only, collision_radius):
		velocity = Vector2(0.0, desired_velocity.y)
		return false

	velocity = Vector2.ZERO
	return false


# =========================
# 视线检测（第 7 课核心：沿线采样查墙）
# =========================

func _is_player_visible(target: Node2D, range_limit: float) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var distance := global_position.distance_to(target.global_position)

	if distance > range_limit:
		return false

	# 作业 2：发现判定加视野半角——只有面向玩家 ±75° 才"发现"
	# （由 _update_state 的调用方决定是否做角度检查；CHASE 保持用全向版）
	var to_player := (target.global_position - global_position).normalized()
	if absf(rad_to_deg(facing.angle_to(to_player))) > detection_half_angle:
		return false

	return _has_line_of_sight(target)


func _has_line_of_sight(target: Node2D) -> bool:
	# 纯视线采样（无角度/距离检查）——CHASE 保持判定复用
	var distance := global_position.distance_to(target.global_position)
	var steps := int(distance / 8.0) + 1

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var sample := global_position.lerp(target.global_position, t)

		if not dungeon.is_world_position_walkable(sample, 0.0):
			return false

	return true
