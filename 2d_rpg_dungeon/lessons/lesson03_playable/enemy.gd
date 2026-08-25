extends CharacterBody2D

# =========================
# 第 5 课：简单巡逻敌人
# 行为：出生点 <-> 房间中心 来回巡逻（数据驱动查询，不穿墙）
#       玩家进入 Hitbox → 直调 take_damage（掉血+击退+无敌，逻辑在玩家侧）
# =========================

@export var speed: float = 70.0

# 到点停顿随机区间（运行期随机——每次玩不同，打破机械节奏）
@export var wait_time_min: float = 0.4
@export var wait_time_max: float = 1.2

@export var arrival_distance: float = 4.0
@export var collision_radius: float = 4.0
@export var contact_damage: int = 1

# 作业 3：发现玩家追击（半径 80px；脱离需 1.25 倍——滞回防抖，边缘反复横跳）
@export var chase_radius: float = 80.0
@export var chase_speed_multiplier: float = 1.4

# 接触伤害判定半径（≈ Hitbox 6.4 + 玩家碰撞体 5）
@export var contact_range: float = 11.0

# 第 6 课：生命（作业 4（第 5 课）补完——敌人可被攻击消灭）
@export var max_health: int = 2

# 作业 3（第 6 课）：敌人类型（normal/fast/tank——setup 时按类型重塑属性与配色）
@export var enemy_type: String = "normal"

# 类型配色（Sprite2D modulate 基色；受击/追击时在此基础上叠加）
const TYPE_COLOR := {
	"normal": Color.WHITE,
	"fast": Color(0.75, 0.85, 1.0),   # 偏蓝（敏捷）
	"tank": Color(1.0, 0.78, 0.55),   # 偏橙（厚重）
}

var chase_speed: float = 0.0

var dungeon: Node
var patrol_points: Array = []
var player: Node2D = null

var current_point_index: int = 0
var is_waiting: bool = false
var wait_remaining: float = 0.0
var is_chasing: bool = false

# 第 6 课：生命与受击
var health: int = 2
var dead: bool = false
var _flash_t: float = 0.0  # 受击闪烁剩余时间（>0 时 modulate 优先级最高）

# 呼吸动画计时
var _t := 0.0

# 张望状态机（仅等待中触发；运行期随机，不进种子序列）
var _look_cool := 0.0  # 距下次张望的倒计时
var _look_t := 0.0     # 张望进行中的剩余时间（>0 = 张望中）
var _look_dir := 1.0

@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	pass  # 接触伤害改为 _physics_process 每帧距离检测；Hitbox 保留供未来攻击判定


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
	elif is_waiting:
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

	# 作业 3：玩家引用（追击目标）
	# 踩坑：敌人 setup 在玩家生成之前执行（generate 顺序 spawn_poi → player），
	# 此刻查找必为 null——改为懒获取：首次需要时找一次，缓存后续直用
	_get_player_ref()

	_look_cool = randf_range(1.0, 2.5)

	if patrol_points.is_empty():
		return

	global_position = patrol_points[0]
	current_point_index = 0

	if patrol_points.size() > 1:
		current_point_index = 1

	is_waiting = false
	wait_remaining = 0.0


func _apply_type_template() -> void:
	# 作业 3：类型模板（个体差异/巡逻参数等后续修改叠加其上）
	match enemy_type:
		"fast":
			speed = 110.0
			max_health = 1
			contact_damage = 1
			chase_radius = 100.0
		"tank":
			speed = 45.0
			max_health = 4
			contact_damage = 2
			chase_radius = 70.0
		_:
			# normal：保持导出默认（70 / 2 / 1 / 80）
			pass

	health = max_health


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	# 第 6 课：被玩家攻击（dead 后不再响应，防尸体补刀）
	if dead:
		return

	health -= amount

	print("敌人受击，剩余生命：", health)

	if health <= 0:
		dead = true
		_die()
		return

	_flash_t = 0.12  # 受击闪烁（_process 里按优先级渲染）


func _die() -> void:
	# 死亡处理交 Main（掉落判定/动态实体移除）；敌人只负责自己消失
	if dungeon and dungeon.has_method("on_enemy_died"):
		dungeon.on_enemy_died(self, global_position)

	queue_free()


func _get_player_ref() -> Node2D:
	if player == null and dungeon is Node:
		player = dungeon.get_node_or_null("Player")
	return player


func _physics_process(delta: float) -> void:
	if dead or dungeon == null or not dungeon.has_method("is_world_position_walkable"):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 作业 3：追击判定（滞回：进入 80px，脱离 100px——防止边缘反复横跳）
	var player_ref := _get_player_ref()
	if is_instance_valid(player_ref):
		# 接触伤害：每帧距离检测（踩坑：body_entered 只在进入瞬间触发一次，
		# 玩家站不动持续重叠时永不重发 → 无敌结束后不再扣血。
		# take_damage 自带无敌检查，每帧调用在无敌期零伤害，结束后立即补刀）
		if global_position.distance_to(player_ref.global_position) < contact_range:
			if player_ref.has_method("take_damage"):
				player_ref.take_damage(contact_damage, global_position)

		var dist := global_position.distance_to(player_ref.global_position)

		if not is_chasing and dist < chase_radius:
			is_chasing = true
			is_waiting = false  # 立刻中断停顿扑向玩家
		elif is_chasing and dist > chase_radius * 1.25:
			is_chasing = false

	if is_chasing and is_instance_valid(player_ref):
		_chase_move(delta)
		move_and_slide()
		return

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
	var direction: Vector2 = target - global_position
	var distance: float = direction.length()

	if distance <= arrival_distance:
		# 到点：随机停顿后换下一个巡逻点（每点时长不同 → 打破节奏）
		is_waiting = true
		wait_remaining = randf_range(wait_time_min, wait_time_max)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var desired_velocity := direction.normalized() * speed
	_move_with_wall_check(desired_velocity, delta)
	move_and_slide()


func _chase_move(delta: float) -> void:
	# 作业 3：直线扑向玩家（数据驱动 + 贴墙滑动——被墙挡也能绕）
	var direction: Vector2 = player.global_position - global_position
	var desired_velocity := direction.normalized() * chase_speed
	_move_with_wall_check(desired_velocity, delta)


func _move_with_wall_check(desired_velocity: Vector2, delta: float) -> void:
	# 通用移动：目标位置可走直走；被挡则尝试单轴滑动（巡逻/追击共用）
	var next_position := global_position + desired_velocity * delta

	if dungeon.is_world_position_walkable(next_position, collision_radius):
		velocity = desired_velocity
		return

	var x_only := Vector2(next_position.x, global_position.y)
	var y_only := Vector2(global_position.x, next_position.y)

	if dungeon.is_world_position_walkable(x_only, collision_radius):
		velocity = Vector2(desired_velocity.x, 0.0)
	elif dungeon.is_world_position_walkable(y_only, collision_radius):
		velocity = Vector2(0.0, desired_velocity.y)
	else:
		velocity = Vector2.ZERO
