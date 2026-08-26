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
@export var enemy_type: String = "normal"

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
var stuck_time: float = 0.0
var home_position := Vector2.ZERO

var chase_speed: float = 0.0

# 呼吸动画计时
var _t := 0.0

# 张望状态机（仅等待中触发；运行期随机，不进种子序列）
var _look_cool := 0.0
var _look_t := 0.0
var _look_dir := 1.0

@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Sprite2D = $Sprite2D


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
	sprite.scale = Vector2(s, s)

	# modulate 三态协调（优先级：受击红 > 追击粉 > 类型基色）
	# 踩坑：不能在受击回调里直接赋 modulate——本函数每帧覆盖会立刻冲掉闪烁
	var base_color: Color = TYPE_COLOR.get(enemy_type, Color.WHITE)
	if _flash_t > 0.0:
		_flash_t -= delta
		sprite.modulate = Color(1.0, 0.35, 0.35)
	elif is_chasing:
		sprite.modulate = Color(1.0, 0.6, 0.6)
	else:
		sprite.modulate = base_color

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

	# 第 7 课：AI 状态复位
	state = EnemyState.PATROL
	is_chasing = false
	time_since_seen = 0.0
	stuck_time = 0.0

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

			if _is_player_visible(player_ref, lose_range):
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
# 追击（第 7 课：奔向最后已知位置，非玩家实时坐标）
# =========================

func _process_chase(delta: float) -> void:
	var target := last_known_player_position
	var arrived := _move_towards(target, chase_speed, delta)

	if arrived:
		# 到达最后已知位置但看不到玩家：转返回
		if time_since_seen > 0.05:
			state = EnemyState.RETURN
			is_chasing = false
			stuck_time = 0.0
	elif velocity == Vector2.ZERO:
		# 卡住检测：持续无法移动超过 0.5s 放弃
		stuck_time += delta

		if stuck_time > 0.5:
			state = EnemyState.RETURN
			is_chasing = false
			stuck_time = 0.0
	else:
		stuck_time = 0.0

	move_and_slide()


# =========================
# 返回（第 7 课：先去最后所见位置搜索 → 再回最近巡逻点）
# =========================

func _process_return(delta: float) -> void:
	# 阶段 1：还没到过最后所见位置 → 先去搜一圈
	var target: Vector2
	var searching := false

	if global_position.distance_to(last_known_player_position) > arrival_distance * 2.0:
		target = last_known_player_position
		searching = true
	else:
		# 阶段 2：搜索过了 → 回最近巡逻点
		var target_index := _get_closest_patrol_point_index()
		target = patrol_points[target_index] if not patrol_points.is_empty() else home_position

	var arrived := _move_towards(target, speed, delta)

	if arrived:
		if searching:
			# 搜完没发现 → 标记搜索完成，继续走回家
			last_known_player_position = global_position
		else:
			state = EnemyState.PATROL
			current_point_index = _get_closest_patrol_point_index()
			is_waiting = false
			stuck_time = 0.0
	elif velocity == Vector2.ZERO:
		stuck_time += delta

		if stuck_time > 0.8:
			# 返回路径一直被卡：强制回巡逻
			state = EnemyState.PATROL
			stuck_time = 0.0
	else:
		stuck_time = 0.0

	move_and_slide()


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

	# 沿敌人与玩家之间每 8px 采样，任一点是墙 → 视线被挡
	var steps := int(distance / 8.0) + 1

	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var sample := global_position.lerp(target.global_position, t)

		if not dungeon.is_world_position_walkable(sample, 0.0):
			return false

	return true
