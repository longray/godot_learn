extends CharacterBody2D

# =========================
# 第 3 课：简单地牢玩家移动
# 第 4 课：四向行走动画 + 滚轮缩放
# 第 5 课：生命值 + 受伤击退 + 无敌帧 + 死亡重生
# 第 8 课：health_changed 信号——生命变化主动广播（HUD/任何关心者自行连接）
# =========================

# 第 8 课：生命变化信号（受伤/治疗/重置/死亡时 emit，Main 接收后转发 HUD）
signal health_changed(current_health: int, max_health: int)

# 作业 4/5（第 8 课）：事件信号——与 health_changed（状态量）互补的"瞬间事件"。
# health_changed 治疗也会发，无法区分"掉血"和"回血"；红屏/死亡提示只在真事件发生时闪
signal damaged(amount: int)
signal died()

# 第 11 课：基础属性（商店永久升级在此之上叠加；调平衡改这三个）
@export var base_max_health: int = 3
@export var base_speed: float = 140.0
@export var base_attack_damage: int = 1

# 作业 5（第 3 课）：移动阻挡方式开关（运行时对比手感用）
# true  = 真实物理碰撞：穿墙由 TileSet 物理层的碰撞体阻止（move_and_slide 解算）
# false = 数据驱动查询：is_world_position_walkable 采样判断（第 3 课主体方案）
@export var use_physics_collision: bool = true

# 碰撞采样半径刻意小于视觉半径（8px）：
# 视觉饱满 + 碰撞宽松是经典手感设计，也避免 16px 走廊里大采样半径卡死
# （仅数据驱动模式使用；物理模式下由 CollisionShape2D 的 CircleShape r=5 参与解算）
@export var collision_radius: float = 5.0

# 第 5 课：生命与受伤参数（max_health 由 apply_upgrades 计算，不再是 @export）
@export var invincibility_time: float = 0.8

# 第 6 课：攻击参数（临时 Area2D 方案——生成→存在 0.08s→销毁）
# attack_damage 由 apply_upgrades 计算，不再是 @export
@export var attack_cooldown: float = 0.35
@export var attack_duration: float = 0.08
@export var attack_radius: float = 12.0
@export var attack_offset: float = 16.0

# 作业 1（第 6 课）：自定义攻击动作 attack（鼠标左键/空格/J，Input Map 配置）
const ATTACK_ACTION := "attack"

# 由 Main 场景注入
var dungeon: Node

var health: int = 3
var invincible: bool = false
var knockback := Vector2.ZERO

# 第 11 课：最终属性 = base_* + GameData 永久等级（apply_upgrades 每次进图/换层刷新）
var max_health: int = 3
var speed: float = 140.0
var attack_damage: int = 1

# 第 6 课：朝向（攻击方向）与攻击冷却
var facing := Vector2.RIGHT
var attack_cooldown_remaining: float = 0.0

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
	# 第 11 课：先应用商店升级再取生命（顺序反了当前血不会满——文档问题 5 的坑）
	apply_upgrades()

	health = max_health

	# 第 8 课：初始生命广播（Main 连接后 HUD 显示满心）
	health_changed.emit(health, max_health)


func reset_for_new_layer() -> void:
	# 第 11 课：每次换层刷新升级（商店购买后下一层立即生效）
	apply_upgrades()

	health = max_health
	invincible = false
	knockback = Vector2.ZERO
	modulate.a = 1.0

	health_changed.emit(health, max_health)


func apply_upgrades() -> void:
	# 第 11 课：基础值 + GameData 永久等级 = 最终属性（Autoload 未注册时回退基础值）
	var game_data := get_node_or_null("/root/GameData")

	if game_data == null:
		max_health = base_max_health
		speed = base_speed
		attack_damage = base_attack_damage
		return

	max_health = base_max_health + game_data.get_max_health_bonus()
	speed = base_speed * game_data.get_speed_multiplier()
	attack_damage = base_attack_damage + game_data.get_attack_bonus()


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
		# 朝向（动画用）随移动更新；攻击朝向独立——见 _attack()（鼠标指向）
		facing = input_vector.normalized()

	# 第 6 课：攻击（冷却中不可发）
	attack_cooldown_remaining = maxf(0.0, attack_cooldown_remaining - delta)

	if Input.is_action_just_pressed(ATTACK_ACTION) and attack_cooldown_remaining <= 0.0:
		_attack()

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

	# 第 11 课作业 2：世界暂停（死亡等待按键）期间伤害无效——
	# SceneTreeTimer 的 process_always 默认 true，无敌 1.2s 到期在 paused 下照常解除，
	# 此处短路是"等待期不被连杀"的最终防线
	if get_tree().paused:
		return

	health -= amount

	print("玩家受伤，剩余生命：", health)

	health_changed.emit(health, max_health)
	damaged.emit(amount)  # 作业 4：红屏闪烁（喝药水不发此信号）

	if health <= 0:
		die()
		return

	_apply_knockback(source_position)
	_start_invincibility(invincibility_time)


func die() -> void:
	print("玩家死亡，回到入口。")

	died.emit()  # 作业 5：HUD 大字提示

	health = max_health
	knockback = Vector2.ZERO

	health_changed.emit(health, max_health)

	# 作业 5（第 5 课）：死亡重置本层（钥匙/宝箱/怪物复原）；
	# 无此方法时回退轻惩罚（仅回入口）。generate 内部会重置位置与状态
	if dungeon and dungeon.has_method("reset_current_layer"):
		dungeon.reset_current_layer()
	elif dungeon and dungeon.has_method("respawn_player"):
		dungeon.respawn_player()

	# 死亡重生保护比普通无敌稍长
	_start_invincibility(invincibility_time * 1.5)


func heal(amount: int) -> void:
	# 第 6 课：药水回血（上限 max_health）
	health = mini(max_health, health + amount)
	print("恢复生命，当前生命：", health)

	health_changed.emit(health, max_health)


func _attack() -> void:
	# 第 6 课：朝向前方生成临时攻击 Area2D（存在 attack_duration 后销毁）
	# 攻击朝向与移动朝向解耦：鼠标指哪砍哪（后退反手砍，风筝战术成立）
	var aim := get_global_mouse_position() - global_position
	if aim.length_squared() > 1.0:
		facing = aim.normalized()
	# 鼠标贴在玩家身上（零向量）→ 沿用上次 facing

	attack_cooldown_remaining = attack_cooldown

	var hitbox := Area2D.new()

	# 只检测敌人（Enemy 根节点在 Layer 2）
	hitbox.collision_layer = 0
	hitbox.collision_mask = 2

	hitbox.position = facing * attack_offset

	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = attack_radius
	collision.shape = circle
	hitbox.add_child(collision)

	# 攻击可视化（作业 2：朝向扇形——圆心在玩家、顶点指向攻击方向）
	var visual := Polygon2D.new()
	var r := attack_radius
	var half_arc := deg_to_rad(60.0)  # ±60° 扇形

	visual.polygon = PackedVector2Array([
		Vector2.ZERO,  # 圆心（相对 hitbox）
		Vector2(r, 0).rotated(-half_arc),
		Vector2(r, 0).rotated(-half_arc * 0.5),
		Vector2(r, 0),
		Vector2(r, 0).rotated(half_arc * 0.5),
		Vector2(r, 0).rotated(half_arc),
	])

	# 扇形默认朝 +X 绘制，旋转到实际朝向；圆心回移 offset 使扇形从脚下展开
	visual.rotation = facing.angle()
	visual.position = -facing * attack_offset
	visual.color = Color(1.0, 1.0, 1.0, 0.35)
	hitbox.add_child(visual)

	hitbox.body_entered.connect(_on_attack_hitbox_body_entered.bind(hitbox))

	add_child(hitbox)

	await get_tree().create_timer(attack_duration).timeout

	if is_instance_valid(hitbox):
		hitbox.queue_free()


func _on_attack_hitbox_body_entered(body: Node2D, hitbox: Area2D) -> void:
	# 命中敌人：直调 take_damage（敌人 Layer 2 已被 mask 过滤）
	if body.has_method("take_damage"):
		body.take_damage(attack_damage, global_position)


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
