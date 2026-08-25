extends CharacterBody2D

# =========================
# 第 3 课：简单地牢玩家移动
# 第 4 课：四向行走动画 + 滚轮缩放
# 第 5 课：生命值 + 受伤击退 + 无敌帧 + 死亡重生
# =========================

@export var speed: float = 140.0

# 作业 5（第 3 课）：移动阻挡方式开关（运行时对比手感用）
# true  = 真实物理碰撞：穿墙由 TileSet 物理层的碰撞体阻止（move_and_slide 解算）
# false = 数据驱动查询：is_world_position_walkable 采样判断（第 3 课主体方案）
@export var use_physics_collision: bool = true

# 碰撞采样半径刻意小于视觉半径（8px）：
# 视觉饱满 + 碰撞宽松是经典手感设计，也避免 16px 走廊里大采样半径卡死
# （仅数据驱动模式使用；物理模式下由 CollisionShape2D 的 CircleShape r=5 参与解算）
@export var collision_radius: float = 5.0

# 第 5 课：生命与受伤参数
@export var max_health: int = 3
@export var invincibility_time: float = 0.8

# 由 Main 场景注入
var dungeon: Node

var health: int = 3
var invincible: bool = false
var knockback := Vector2.ZERO

# =========================
# 四向行走动画（spritesheet 3 列 = 迈A/站立/迈B，3 行 = 下/上/侧面）
# =========================

const DIR_ROW := {"down": 0, "up": 1, "side": 2}

# 步态循环：迈A → 站立 → 迈B → 站立（经典 RPG 四拍）
const FRAME_SEQ := [0, 1, 2, 1]

@export var walk_fps: float = 11.0

# 滚轮缩放：步长与范围（默认 zoom=2，观察影子可拉到很近）
const ZOOM_STEP := 0.25
const ZOOM_MIN := 0.75
const ZOOM_MAX := 6.0

var _anim_t := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	health = max_health


func reset_for_new_layer() -> void:
	health = max_health
	invincible = false
	knockback = Vector2.ZERO
	modulate.a = 1.0

	_notify_health_ui()


func _unhandled_input(event: InputEvent) -> void:
	# 滚轮推近/拉远（观察用）：上=推近，下=拉远
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-1.0)


func _zoom_camera(direction: float) -> void:
	var z: float = clampf(camera.zoom.x + direction * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


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

	# 作业 1（第 3 课）：自定义动作 move_*（WASD + 方向键双绑定）
	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	var desired_velocity := Vector2.ZERO
	if input_vector != Vector2.ZERO:
		desired_velocity = input_vector.normalized() * speed

	# 第 5 课：移动 = 意图速度 + 击退速度（击退随时间衰减）
	var move_velocity := desired_velocity + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 500.0 * delta)

	if move_velocity == Vector2.ZERO:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_sprite_animation(input_vector, delta)
		return

	# 第 3 课作业 5：物理碰撞模式——阻挡交给 TileSet 物理层 + move_and_slide
	if use_physics_collision:
		velocity = move_velocity
		move_and_slide()
		_update_sprite_animation(input_vector, delta)
		return

	# 数据驱动模式（第 3 课主体）：查询地图数据判断可走性
	var next_position := global_position + move_velocity * delta

	if dungeon.is_world_position_walkable(next_position, collision_radius):
		velocity = move_velocity
	else:
		# 如果整体移动被挡住，尝试只移动 X 或只移动 Y（贴墙滑动）
		var x_only_position := Vector2(next_position.x, global_position.y)
		var y_only_position := Vector2(global_position.x, next_position.y)

		if dungeon.is_world_position_walkable(x_only_position, collision_radius):
			velocity = Vector2(move_velocity.x, 0.0)
		elif dungeon.is_world_position_walkable(y_only_position, collision_radius):
			velocity = Vector2(0.0, move_velocity.y)
		else:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_sprite_animation(input_vector, delta)


# =========================
# 第 5 课：受伤 / 死亡 / 无敌
# =========================

func take_damage(amount: int, source_position: Vector2) -> void:
	if invincible:
		return

	health -= amount

	print("玩家受伤，剩余生命：", health)

	_notify_health_ui()

	if health <= 0:
		die()
		return

	_apply_knockback(source_position)
	_start_invincibility(invincibility_time)


func die() -> void:
	print("玩家死亡，回到入口。")

	health = max_health
	knockback = Vector2.ZERO

	_notify_health_ui()

	if dungeon and dungeon.has_method("respawn_player"):
		dungeon.respawn_player()

	# 死亡重生保护比普通无敌稍长
	_start_invincibility(invincibility_time * 1.5)


func _notify_health_ui() -> void:
	# 作业 1（第 5 课）：通知 HUD 刷新心形（dungeon 可能未注入，防御性检查）
	if dungeon and dungeon.has_method("update_health_ui"):
		dungeon.update_health_ui(health, max_health)


func _apply_knockback(source_position: Vector2) -> void:
	var direction := global_position - source_position

	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	knockback = direction.normalized() * 180.0


func _start_invincibility(duration: float) -> void:
	invincible = true
	modulate.a = 0.45

	await get_tree().create_timer(duration).timeout

	if is_inside_tree():
		invincible = false
		modulate.a = 1.0
