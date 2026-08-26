using Godot;

namespace RpgDungeon;

// =========================
// 第 3 课：简单地牢玩家移动（C# 版）
// 第 4 课：四向行走动画 + 滚轮镜头缩放
// 使用地图数据判断是否可以移动，而不是依赖墙体物理碰撞。
// =========================
public partial class Player : CharacterBody2D
{
	// 第 8 课：生命变化信号（受伤/治疗/重置/死亡时发射，Main 接收后转发 HUD）
	[Signal]
	public delegate void HealthChangedEventHandler(int currentHealth, int maxHealth);

	// 作业 4/5（第 8 课）：事件信号——与 HealthChanged（状态量）互补的"瞬间事件"。
	// HealthChanged 治疗也会发，无法区分"掉血"和"回血"；红屏/死亡提示只在真事件发生时闪
	[Signal]
	public delegate void DamagedEventHandler(int amount);

	[Signal]
	public delegate void DiedEventHandler();

	[Export] public float Speed { get; set; } = 140.0f;

	// 作业 5：移动阻挡方式开关（运行时对比手感用）
	// true  = 真实物理碰撞：穿墙由 TileSet 物理层的碰撞体阻止（MoveAndSlide 解算）
	// false = 数据驱动查询：IsWorldPositionWalkable 采样判断（第 3 课主体方案）
	[Export] public bool UsePhysicsCollision { get; set; } = true;

	// 碰撞采样半径刻意小于视觉半径（8px）：
	// 视觉饱满 + 碰撞宽松是经典手感设计，也避免 16px 走廊里大采样半径卡死
	// （仅数据驱动模式使用；物理模式下由 CollisionShape2D 的 CircleShape r=5 参与解算）
	[Export] public float CollisionRadius { get; set; } = 5.0f;

	// 由 Main 场景注入
	public DungeonPlayable Dungeon { get; set; }

	// =========================
	// 第 5 课：生命与受伤
	// =========================

	[Export] public int MaxHealth { get; set; } = 3;
	[Export] public float InvincibilityTime { get; set; } = 0.8f;

	// =========================
	// 第 6 课：攻击（临时 Area2D 方案——生成→存在 0.08s→销毁）
	// =========================

	[Export] public int AttackDamage { get; set; } = 1;
	[Export] public float AttackCooldown { get; set; } = 0.35f;
	[Export] public float AttackDuration { get; set; } = 0.08f;
	[Export] public float AttackRadius { get; set; } = 12.0f;
	[Export] public float AttackOffset { get; set; } = 16.0f;

	// 作业 1（第 6 课）：自定义攻击动作 attack（鼠标左键/空格/J，Input Map 配置）
	private const string AttackAction = "attack";

	public int Health { get; private set; } = 3;
	public bool Invincible { get; private set; }
	public Vector2 Knockback { get; private set; }

	// 朝向（动画用随移动；攻击朝向独立——鼠标指哪砍哪）
	public Vector2 Facing { get; private set; } = Vector2.Right;
	private float _attackCooldownRemaining;

	// =========================
	// 四向行走动画（spritesheet 3 列 = 迈A/站立/迈B，3 行 = 下/上/侧面）
	// =========================

	// 步态循环：迈A → 站立 → 迈B → 站立（经典 RPG 四拍）
	private static readonly int[] FrameSeq = { 0, 1, 2, 1 };

	[Export] public float WalkFps { get; set; } = 11.0f;

	// 滚轮缩放：步长与范围（默认 zoom=2）
	private const float ZoomStep = 0.25f;
	private const float ZoomMin = 0.75f;
	private const float ZoomMax = 6.0f;

	private float _animT;
	private Sprite2D _sprite;
	private Camera2D _camera;

	public override void _Ready()
	{
		_sprite = GetNode<Sprite2D>("Sprite2D");
		_camera = GetNode<Camera2D>("Camera2D");
		Health = MaxHealth;

		// 第 8 课：初始生命广播（Main 连接后 HUD 显示满心）
		EmitSignal(SignalName.HealthChanged, Health, MaxHealth);
	}

	public void ResetForNewLayer()
	{
		Health = MaxHealth;
		Invincible = false;
		Knockback = Vector2.Zero;
		Modulate = new Color(Modulate.R, Modulate.G, Modulate.B, 1.0f);

		EmitSignal(SignalName.HealthChanged, Health, MaxHealth);
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		// 滚轮推近/拉远（观察用）：上=推近，下=拉远
		if (@event is InputEventMouseButton { Pressed: true } mb)
		{
			switch (mb.ButtonIndex)
			{
				case MouseButton.WheelUp:
					ZoomCamera(1.0f);
					break;
				case MouseButton.WheelDown:
					ZoomCamera(-1.0f);
					break;
			}
		}
	}

	private void ZoomCamera(float direction)
	{
		float z = Mathf.Clamp(_camera.Zoom.X + direction * ZoomStep, ZoomMin, ZoomMax);
		_camera.Zoom = new Vector2(z, z);
	}

	private void UpdateSpriteAnimation(Vector2 inputVector, float delta)
	{
		// 方向判定：水平优先（与斜向移动的视觉直觉一致）；左右共用侧面行
		int row;
		bool flip = false;

		if (Mathf.Abs(inputVector.X) > Mathf.Abs(inputVector.Y))
		{
			row = 2; // side
			flip = inputVector.X < 0.0f;
		}
		else if (!Mathf.IsZeroApprox(inputVector.Y))
		{
			row = inputVector.Y < 0.0f ? 1 : 0; // up / down
		}
		else
		{
			row = 0;
		}

		_sprite.FlipH = flip;

		if (inputVector == Vector2.Zero)
		{
			_animT = 0.0f;
			_sprite.Frame = row * 3 + 1; // idle = 中间列
		}
		else
		{
			_animT += delta;
			int col = FrameSeq[(int)(_animT * WalkFps) % FrameSeq.Length];
			_sprite.Frame = row * 3 + col;
		}
	}

	public override void _PhysicsProcess(double delta)
	{
		float dt = (float)delta;

		if (Dungeon == null)
		{
			Velocity = Vector2.Zero;
			MoveAndSlide();
			UpdateSpriteAnimation(Vector2.Zero, dt);
			return;
		}

		// 作业 1：自定义动作 move_*（WASD + 方向键双绑定，Input Map 中配置）
		Vector2 inputVector = Input.GetVector(
			"move_left",
			"move_right",
			"move_up",
			"move_down"
		);

		Vector2 desiredVelocity = inputVector == Vector2.Zero
			? Vector2.Zero
			: inputVector.Normalized() * Speed;

		// 朝向（动画用）随移动更新；攻击朝向独立——见 Attack()（鼠标指向）
		if (inputVector != Vector2.Zero)
		{
			Facing = inputVector.Normalized();
		}

		// 第 6 课：攻击（冷却中不可发）
		_attackCooldownRemaining = Mathf.Max(0.0f, _attackCooldownRemaining - dt);

		if (Input.IsActionJustPressed(AttackAction) && _attackCooldownRemaining <= 0.0f)
		{
			Attack();
		}

		// 第 5 课：移动 = 意图速度 + 击退速度（击退随时间衰减）
		Vector2 moveVelocity = desiredVelocity + Knockback;
		Knockback = Knockback.MoveToward(Vector2.Zero, 500.0f * dt);

		if (moveVelocity == Vector2.Zero)
		{
			Velocity = Vector2.Zero;
			MoveAndSlide();
			UpdateSpriteAnimation(inputVector, dt);
			return;
		}

		// 第 3 课作业 5：物理碰撞模式——阻挡交给 TileSet 物理层 + MoveAndSlide
		if (UsePhysicsCollision)
		{
			Velocity = moveVelocity;
			MoveAndSlide();
			UpdateSpriteAnimation(inputVector, dt);
			return;
		}

		// 数据驱动模式（第 3 课主体）：查询地图数据判断可走性
		Vector2 nextPosition = GlobalPosition + moveVelocity * dt;

		if (Dungeon.IsWorldPositionWalkable(nextPosition, CollisionRadius))
		{
			Velocity = moveVelocity;
		}
		else
		{
			Vector2 xOnlyPosition = new(nextPosition.X, GlobalPosition.Y);
			Vector2 yOnlyPosition = new(GlobalPosition.X, nextPosition.Y);

			if (Dungeon.IsWorldPositionWalkable(xOnlyPosition, CollisionRadius))
			{
				Velocity = new Vector2(moveVelocity.X, 0.0f);
			}
			else if (Dungeon.IsWorldPositionWalkable(yOnlyPosition, CollisionRadius))
			{
				Velocity = new Vector2(0.0f, moveVelocity.Y);
			}
			else
			{
				Velocity = Vector2.Zero;
			}
		}

		MoveAndSlide();
		UpdateSpriteAnimation(inputVector, dt);
	}

	// =========================
	// 第 5 课：受伤 / 死亡 / 无敌
	// =========================

	public void TakeDamage(int amount, Vector2 sourcePosition)
	{
		if (Invincible)
		{
			return;
		}

		Health -= amount;

		GD.Print("玩家受伤，剩余生命：", Health);

		EmitSignal(SignalName.HealthChanged, Health, MaxHealth);
		EmitSignal(SignalName.Damaged, amount); // 作业 4：红屏闪烁（喝药水不发此信号）

		if (Health <= 0)
		{
			Die();
			return;
		}

		ApplyKnockback(sourcePosition);
		StartInvincibility(InvincibilityTime);
	}

	private void Die()
	{
		GD.Print("玩家死亡，回到入口。");

		EmitSignal(SignalName.Died); // 作业 5：HUD 大字提示

		Health = MaxHealth;
		Knockback = Vector2.Zero;

		EmitSignal(SignalName.HealthChanged, Health, MaxHealth);

		// 作业 5（第 5 课）：死亡重置本层；无此方法时回退轻惩罚
		if (Dungeon != null)
		{
			Dungeon.ResetCurrentLayer();
		}
	}

	private void ApplyKnockback(Vector2 sourcePosition)
	{
		Vector2 direction = GlobalPosition - sourcePosition;

		if (direction == Vector2.Zero)
		{
			direction = Vector2.Right;
		}

		Knockback = direction.Normalized() * 180.0f;
	}

	private async void StartInvincibility(float duration)
	{
		Invincible = true;
		Modulate = new Color(Modulate.R, Modulate.G, Modulate.B, 0.45f);

		await ToSignal(GetTree().CreateTimer(duration), SceneTreeTimer.SignalName.Timeout);

		if (IsInsideTree())
		{
			Invincible = false;
			Modulate = new Color(Modulate.R, Modulate.G, Modulate.B, 1.0f);
		}
	}

	// =========================
	// 第 6 课：攻击与治疗
	// =========================

	public void Heal(int amount)
	{
		Health = Mathf.Min(MaxHealth, Health + amount);
		GD.Print("恢复生命，当前生命：", Health);

		EmitSignal(SignalName.HealthChanged, Health, MaxHealth);
	}

	private void Attack()
	{
		// 攻击朝向与移动朝向解耦：鼠标指哪砍哪（后退反手砍，风筝战术成立）
		Vector2 aim = GetGlobalMousePosition() - GlobalPosition;
		if (aim.LengthSquared() > 1.0f)
		{
			Facing = aim.Normalized();
		}
		// 鼠标贴在玩家身上（零向量）→ 沿用上次 Facing

		_attackCooldownRemaining = AttackCooldown;

		var hitbox = new Area2D
		{
			// 只检测敌人（Enemy 根节点在 Layer 2）
			CollisionLayer = 0,
			CollisionMask = 2,
			Position = Facing * AttackOffset,
		};

		var collision = new CollisionShape2D
		{
			Shape = new CircleShape2D { Radius = AttackRadius },
		};
		hitbox.AddChild(collision);

		// 攻击可视化（作业 2：朝向扇形——圆心在玩家、顶点指向攻击方向）
		float halfArc = Mathf.DegToRad(60.0f);
		Vector2[] fan =
		{
			Vector2.Zero,
			new Vector2(AttackRadius, 0).Rotated(-halfArc),
			new Vector2(AttackRadius, 0).Rotated(-halfArc * 0.5f),
			new Vector2(AttackRadius, 0),
			new Vector2(AttackRadius, 0).Rotated(halfArc * 0.5f),
			new Vector2(AttackRadius, 0).Rotated(halfArc),
		};

		var visual = new Polygon2D
		{
			Polygon = fan,
			Rotation = Facing.Angle(),
			Position = -Facing * AttackOffset,
			Color = new Color(1.0f, 1.0f, 1.0f, 0.35f),
		};
		hitbox.AddChild(visual);

		hitbox.BodyEntered += body =>
		{
			// 踩坑：C# 方法对引擎暴露为 PascalCase 原名（HasMethod("take_damage")
			// 永远 false）——跨语言动态调用必须强类型 is 转换
			if (body is Enemy enemy)
			{
				enemy.TakeDamage(AttackDamage, GlobalPosition);
			}
		};

		AddChild(hitbox);

		_ = DisposeHitboxAfter(hitbox, AttackDuration);
	}

	private async System.Threading.Tasks.Task DisposeHitboxAfter(Area2D hitbox, float delay)
	{
		await ToSignal(GetTree().CreateTimer(delay), SceneTreeTimer.SignalName.Timeout);

		if (GodotObject.IsInstanceValid(hitbox))
		{
			hitbox.QueueFree();
		}
	}
}
