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

var dungeon: Node
var patrol_points: Array = []

var current_point_index: int = 0
var is_waiting: bool = false
var wait_remaining: float = 0.0

# 呼吸动画计时
var _t := 0.0

# 张望状态机（仅等待中触发；运行期随机，不进种子序列）
var _look_cool := 0.0  # 距下次张望的倒计时
var _look_t := 0.0     # 张望进行中的剩余时间（>0 = 张望中）
var _look_dir := 1.0

@onready var hitbox: Area2D = $Hitbox
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)


func _process(delta: float) -> void:
	# 史莱姆呼吸：轻微正弦缩放；移动时呼吸加速加剧（赶路感），停顿时慢喘
	# 只缩 Sprite2D 不缩根节点——根 scale 会连带缩放子节点碰撞体，破坏触发半径
	_t += delta * (2.2 if velocity != Vector2.ZERO else 1.0)
	var amp := 0.10 if velocity != Vector2.ZERO else 0.08
	var s := 1.0 + amp * sin(_t * 3.0)
	sprite.scale = Vector2(s, s)

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

	# 速度个体差异 ±15%（运行期随机：每次玩都不同，群体不齐步）
	speed *= randf_range(0.85, 1.15)

	_look_cool = randf_range(1.0, 2.5)

	if patrol_points.is_empty():
		return

	global_position = patrol_points[0]
	current_point_index = 0

	if patrol_points.size() > 1:
		current_point_index = 1

	is_waiting = false
	wait_remaining = 0.0


func _physics_process(delta: float) -> void:
	if dungeon == null or not dungeon.has_method("is_world_position_walkable"):
		velocity = Vector2.ZERO
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
	var next_position := global_position + desired_velocity * delta

	if dungeon.is_world_position_walkable(next_position, collision_radius):
		velocity = desired_velocity
	else:
		# 前方不可走（被地图数据挡住）：切换巡逻点
		velocity = Vector2.ZERO
		current_point_index = (current_point_index + 1) % patrol_points.size()

	move_and_slide()


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(contact_damage, global_position)
