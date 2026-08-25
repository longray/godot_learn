extends CharacterBody2D

# =========================
# 第 3 课：简单地牢玩家移动
# 使用地图数据判断是否可以移动，而不是依赖墙体物理碰撞。
# =========================

@export var speed: float = 140.0

# 作业 5：移动阻挡方式开关（运行时对比手感用）
# true  = 真实物理碰撞：穿墙由 TileSet 物理层的碰撞体阻止（move_and_slide 解算）
# false = 数据驱动查询：is_world_position_walkable 采样判断（第 3 课主体方案）
@export var use_physics_collision: bool = true

# 碰撞采样半径刻意小于视觉半径（8px）：
# 视觉饱满 + 碰撞宽松是经典手感设计，也避免 16px 走廊里大采样半径卡死
# （仅数据驱动模式使用；物理模式下由 CollisionShape2D 的 CircleShape r=5 参与解算）
@export var collision_radius: float = 5.0

# 由 Main 场景注入
var dungeon: Node

# =========================
# 四向行走动画（作业延伸：spritesheet 3 列 = 迈A/站立/迈B，3 行 = 下/上/侧面）
# =========================

const DIR_ROW := {"down": 0, "up": 1, "side": 2}

# 步态循环：迈A → 站立 → 迈B → 站立（经典 RPG 四拍）
const FRAME_SEQ := [0, 1, 2, 1]

@export var walk_fps: float = 8.0

var _anim_t := 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _update_sprite_animation(input_vector: Vector2, delta: float) -> void:
	# 方向判定：水平优先（与斜向移动的视觉直觉一致）；左右共用侧面行
	var row := 0
	var flip := false

	if absf(input_vector.x) > absf(input_vector.y):
		row = DIR_ROW["side"]
		flip = input_vector.x < 0.0
	elif not is_zero_approx(input_vector.y):
		row = DIR_ROW["up"] if input_vector.y < 0.0 else DIR_ROW["down"]

	sprite.flip_h = flip

	if input_vector == Vector2.ZERO:
		_anim_t = 0.0
		sprite.frame = row * 3 + 1  # idle = 中间列
	else:
		_anim_t += delta
		var col: int = FRAME_SEQ[floori(_anim_t * walk_fps) % FRAME_SEQ.size()]
		sprite.frame = row * 3 + col


func _physics_process(delta: float) -> void:
	if dungeon == null or not dungeon.has_method("is_world_position_walkable"):
		velocity = Vector2.ZERO
		move_and_slide()
		_update_sprite_animation(Vector2.ZERO, delta)
		return

	# 作业 1：自定义动作 move_*（WASD + 方向键双绑定，Input Map 中配置）
	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	if input_vector == Vector2.ZERO:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_sprite_animation(Vector2.ZERO, delta)
		return

	var desired_velocity := input_vector.normalized() * speed

	# 作业 5：物理碰撞模式——直接设速度，阻挡交给 TileSet 物理层 + move_and_slide
	if use_physics_collision:
		velocity = desired_velocity
		move_and_slide()
		_update_sprite_animation(input_vector, delta)
		return

	# 数据驱动模式（第 3 课主体）：查询地图数据判断可走性
	var next_position := global_position + desired_velocity * delta

	# 如果目标位置可走，直接移动
	if dungeon.is_world_position_walkable(next_position, collision_radius):
		velocity = desired_velocity
	else:
		# 如果整体移动被挡住，尝试只移动 X 或只移动 Y
		# 这样可以实现简单的贴墙滑动
		var x_only_position := Vector2(next_position.x, global_position.y)
		var y_only_position := Vector2(global_position.x, next_position.y)

		if dungeon.is_world_position_walkable(x_only_position, collision_radius):
			velocity = Vector2(desired_velocity.x, 0.0)
		elif dungeon.is_world_position_walkable(y_only_position, collision_radius):
			velocity = Vector2(0.0, desired_velocity.y)
		else:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_sprite_animation(input_vector, delta)
