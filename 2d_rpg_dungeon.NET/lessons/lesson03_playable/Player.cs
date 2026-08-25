using Godot;

namespace RpgDungeon;

// =========================
// 第 3 课：简单地牢玩家移动（C# 版）
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

	public override void _PhysicsProcess(double delta)
	{
		if (Dungeon == null)
		{
			Velocity = Vector2.Zero;
			MoveAndSlide();
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
			return;
		}

		Vector2 desiredVelocity = inputVector.Normalized() * Speed;

		// 作业 5：物理碰撞模式——直接设速度，阻挡交给 TileSet 物理层 + MoveAndSlide
		if (UsePhysicsCollision)
		{
			Velocity = desiredVelocity;
			MoveAndSlide();
			return;
		}

		// 数据驱动模式（第 3 课主体）：查询地图数据判断可走性
		Vector2 nextPosition = GlobalPosition + desiredVelocity * (float)delta;

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
	}
}
