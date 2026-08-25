using Godot;

namespace RpgDungeon;

// =========================
// 第 3 课：简单地牢玩家移动（C# 版）
// 第 4 课：四向行走动画 + 滚轮镜头缩放
// 使用地图数据判断是否可以移动，而不是依赖墙体物理碰撞。
// =========================
public partial class Player : CharacterBody2D
{
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

		if (inputVector == Vector2.Zero)
		{
			Velocity = Vector2.Zero;
			MoveAndSlide();
			UpdateSpriteAnimation(Vector2.Zero, dt);
			return;
		}

		Vector2 desiredVelocity = inputVector.Normalized() * Speed;

		// 作业 5：物理碰撞模式——直接设速度，阻挡交给 TileSet 物理层 + MoveAndSlide
		if (UsePhysicsCollision)
		{
			Velocity = desiredVelocity;
			MoveAndSlide();
			UpdateSpriteAnimation(inputVector, dt);
			return;
		}

		// 数据驱动模式（第 3 课主体）：查询地图数据判断可走性
		Vector2 nextPosition = GlobalPosition + desiredVelocity * dt;

		// 如果目标位置可走，直接移动
		if (Dungeon.IsWorldPositionWalkable(nextPosition, CollisionRadius))
		{
			Velocity = desiredVelocity;
		}
		else
		{
			// 如果整体移动被挡住，尝试只移动 X 或只移动 Y
			// 这样可以实现简单的贴墙滑动
			Vector2 xOnlyPosition = new(nextPosition.X, GlobalPosition.Y);
			Vector2 yOnlyPosition = new(GlobalPosition.X, nextPosition.Y);

			if (Dungeon.IsWorldPositionWalkable(xOnlyPosition, CollisionRadius))
			{
				Velocity = new Vector2(desiredVelocity.X, 0.0f);
			}
			else if (Dungeon.IsWorldPositionWalkable(yOnlyPosition, CollisionRadius))
			{
				Velocity = new Vector2(0.0f, desiredVelocity.Y);
			}
			else
			{
				Velocity = Vector2.Zero;
			}
		}

		MoveAndSlide();
		UpdateSpriteAnimation(inputVector, dt);
	}
}
