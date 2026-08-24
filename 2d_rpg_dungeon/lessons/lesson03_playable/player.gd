extends CharacterBody2D

# =========================
# 第 3 课：简单地牢玩家移动
# 使用地图数据判断是否可以移动，而不是依赖墙体物理碰撞。
# =========================

@export var speed: float = 140.0

# 碰撞采样半径刻意小于视觉半径（8px）：
# 视觉饱满 + 碰撞宽松是经典手感设计，也避免 16px 走廊里大采样半径卡死
@export var collision_radius: float = 5.0

# 由 Main 场景注入
var dungeon: Node


func _physics_process(delta: float) -> void:
	if dungeon == null or not dungeon.has_method("is_world_position_walkable"):
		velocity = Vector2.ZERO
		move_and_slide()
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
		return

	var desired_velocity := input_vector.normalized() * speed
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
