using Godot;

namespace RpgDungeon;

// =========================
// 第 5 课：简单巡逻敌人（C# 版）
// 行为：房间内多点环游巡逻（数据驱动查询，不穿墙）
//       发现玩家（80px）追击（1.4x 速 + 泛红）；接触伤害每帧距离检测
// 活性：速度个体差异 ±15%、随机停顿、等待张望、移动/追击呼吸加速
// =========================
public partial class Enemy : CharacterBody2D
{
	[Export] public float Speed { get; set; } = 70.0f;

	// 到点停顿随机区间（运行期随机——每次玩不同，打破机械节奏）
	[Export] public float WaitTimeMin { get; set; } = 0.4f;
	[Export] public float WaitTimeMax { get; set; } = 1.2f;

	[Export] public float ArrivalDistance { get; set; } = 4.0f;
	[Export] public float CollisionRadius { get; set; } = 4.0f;
	[Export] public int ContactDamage { get; set; } = 1;

	// 作业 3：发现玩家追击（滞回：进入 80px，脱离 1.25 倍——防边缘反复横跳）
	[Export] public float ChaseRadius { get; set; } = 80.0f;
	[Export] public float ChaseSpeedMultiplier { get; set; } = 1.4f;

	// 接触伤害判定半径（≈ Hitbox 6.4 + 玩家碰撞体 5）
	[Export] public float ContactRange { get; set; } = 11.0f;

	// 第 6 课：生命（可被攻击消灭）
	[Export] public int MaxHealth { get; set; } = 2;

	// 作业 3（第 6 课）：敌人类型（normal/fast/tank——Setup 时按类型重塑属性与配色）
	[Export] public string EnemyType { get; set; } = "normal";

	// 类型配色（Sprite2D modulate 基色；受击/追击时在此基础上叠加）
	private static readonly System.Collections.Generic.Dictionary<string, Color> TypeColor = new()
	{
		["normal"] = Colors.White,
		["fast"] = new Color(0.75f, 0.85f, 1.0f),   // 偏蓝（敏捷）
		["tank"] = new Color(1.0f, 0.78f, 0.55f),   // 偏橙（厚重）
	};

	public int Health { get; private set; } = 2;
	public bool Dead { get; private set; }
	private float _flashT;  // 受击闪烁剩余时间（>0 时 modulate 优先级最高）

	public Node Dungeon { get; set; }
	public Vector2[] PatrolPoints { get; private set; } = System.Array.Empty<Vector2>();

	private int _currentPointIndex;
	private bool _isWaiting;
	private float _waitRemaining;
	private bool _isChasing;
	private float _chaseSpeed;

	// 玩家引用（追击目标；懒获取——setup 早于玩家生成，当场查找必为 null）
	private Player _player;

	// 呼吸动画计时
	private float _t;

	// 张望状态机（仅等待中触发；运行期随机，不进种子序列）
	private float _lookCool;
	private float _lookT;
	private float _lookDir = 1.0f;

	private Sprite2D _sprite;

	private static readonly System.Random RuntimeRand = new();

	public override void _Ready()
	{
		_sprite = GetNode<Sprite2D>("Sprite2D");
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;

		// 史莱姆呼吸：轻微正弦缩放；移动加速加剧（赶路感），追击最快最猛（兴奋感）
		// 只缩 Sprite2D 不缩根节点——根 scale 会连带缩放子节点碰撞体，破坏触发半径
		float rate = 1.0f;
		float amp = 0.08f;
		if (_isChasing)
		{
			rate = 3.0f;
			amp = 0.13f;
		}
		else if (Velocity != Vector2.Zero)
		{
			rate = 2.2f;
			amp = 0.10f;
		}

		_t += dt * rate;
		float s = 1.0f + amp * Mathf.Sin(_t * 3.0f);
		_sprite.Scale = new Vector2(s, s);

		// modulate 三态协调（优先级：受击红 > 追击粉 > 类型基色）
		Color baseColor = TypeColor.TryGetValue(EnemyType, out Color c) ? c : Colors.White;
		if (_flashT > 0.0f)
		{
			_flashT -= dt;
			_sprite.Modulate = new Color(1.0f, 0.35f, 0.35f);
		}
		else if (_isChasing)
		{
			_sprite.Modulate = new Color(1.0f, 0.6f, 0.6f);
		}
		else
		{
			_sprite.Modulate = baseColor;
		}

		// 张望：等待中偶尔左右瞥一眼（身体微偏移模拟探头）
		if (_lookT > 0.0f)
		{
			_lookT -= dt;
			_sprite.Position = new Vector2(_lookDir * 1.5f, _sprite.Position.Y);

			if (_lookT <= 0.0f)
			{
				// 50% 概率紧接着看另一边（更像警觉）
				if (RuntimeRand.NextDouble() < 0.5)
				{
					_lookDir = -_lookDir;
					_lookT = RandRange(0.3f, 0.5f);
				}
				else
				{
					_sprite.Position = new Vector2(0.0f, _sprite.Position.Y);
					_lookCool = RandRange(1.5f, 3.5f);
				}
			}
		}
		else if (_isWaiting)
		{
			_lookCool -= dt;

			if (_lookCool <= 0.0f)
			{
				_lookDir = RuntimeRand.NextDouble() < 0.5 ? 1.0f : -1.0f;
				_lookT = RandRange(0.35f, 0.55f);
			}
		}
		else
		{
			// 移动中不该有偏移残留
			_sprite.Position = new Vector2(0.0f, _sprite.Position.Y);
		}
	}

	// 运行期随机（不进种子序列，每次玩都不同）
	private static float RandRange(float min, float max)
	{
		return min + (float)RuntimeRand.NextDouble() * (max - min);
	}

	// Main 生成后调用：注入地图引用 + 巡逻路径，并瞬移到首个巡逻点
	public void Setup(Node dungeonReference, Vector2[] points)
	{
		Dungeon = dungeonReference;
		PatrolPoints = points;

		// 第 6 课：每只满血出场
		Health = MaxHealth;
		Dead = false;
		_flashT = 0.0f;

		// 作业 3：按类型重塑（在速度个体差异之前应用基础模板）
		ApplyTypeTemplate();

		// 速度个体差异 ±15%（运行期随机：每次玩都不同，群体不齐步）
		Speed *= RandRange(0.85f, 1.15f);
		_chaseSpeed = Speed * ChaseSpeedMultiplier;

		_lookCool = RandRange(1.0f, 2.5f);

		if (PatrolPoints.Length == 0)
		{
			return;
		}

		GlobalPosition = PatrolPoints[0];
		_currentPointIndex = 0;

		if (PatrolPoints.Length > 1)
		{
			_currentPointIndex = 1;
		}

		_isWaiting = false;
		_waitRemaining = 0.0f;
	}

	private void ApplyTypeTemplate()
	{
		// 作业 3：类型模板（个体差异/巡逻参数等后续修改叠加其上）
		switch (EnemyType)
		{
			case "fast":
				Speed = 110.0f;
				MaxHealth = 1;
				ContactDamage = 1;
				ChaseRadius = 100.0f;
				break;
			case "tank":
				Speed = 45.0f;
				MaxHealth = 4;
				ContactDamage = 2;
				ChaseRadius = 70.0f;
				break;
			default:
				// normal：保持导出默认（70 / 2 / 1 / 80）
				break;
		}

		Health = MaxHealth;
	}

	// =========================
	// 第 6 课：受击 / 死亡
	// =========================

	public void TakeDamage(int amount, Vector2 sourcePosition = default)
	{
		// dead 后不再响应，防尸体补刀
		if (Dead)
		{
			return;
		}

		Health -= amount;

		GD.Print("敌人受击，剩余生命：", Health);

		if (Health <= 0)
		{
			Dead = true;
			Die();
			return;
		}

		_flashT = 0.12f;
	}

	private void Die()
	{
		// 死亡处理交 Main（掉落判定/动态实体移除）；敌人只负责自己消失
		if (Dungeon is DungeonPlayable dungeon)
		{
			dungeon.OnEnemyDied(this, GlobalPosition);
		}

		QueueFree();
	}

	private Player GetPlayerRef()
	{
		if (_player == null && Dungeon is Node node)
		{
			_player = node.GetNodeOrNull<Player>("Player");
		}
		return _player;
	}

	public override void _PhysicsProcess(double delta)
	{
		float dt = (float)delta;

		if (Dead || Dungeon is not DungeonPlayable dungeon
			|| PatrolPoints.Length <= 1)
		{
			Velocity = Vector2.Zero;
			MoveAndSlide();
			return;
		}

		// 作业 3：追击判定（滞回）
		Player playerRef = GetPlayerRef();
		if (GodotObject.IsInstanceValid(playerRef))
		{
			// 接触伤害：每帧距离检测（body_entered 持续重叠不重发，轮询兜底）
			if (GlobalPosition.DistanceTo(playerRef.GlobalPosition) < ContactRange)
			{
				playerRef.TakeDamage(ContactDamage, GlobalPosition);
			}

			float dist = GlobalPosition.DistanceTo(playerRef.GlobalPosition);

			if (!_isChasing && dist < ChaseRadius)
			{
				_isChasing = true;
				_isWaiting = false;
			}
			else if (_isChasing && dist > ChaseRadius * 1.25f)
			{
				_isChasing = false;
			}
		}

		if (_isChasing && GodotObject.IsInstanceValid(playerRef))
		{
			ChaseMove(dt);
			MoveAndSlide();
			return;
		}

		if (_isWaiting)
		{
			_waitRemaining -= dt;
			Velocity = Vector2.Zero;

			if (_waitRemaining <= 0.0f)
			{
				_isWaiting = false;
				_currentPointIndex = (_currentPointIndex + 1) % PatrolPoints.Length;
			}

			MoveAndSlide();
			return;
		}

		Vector2 target = PatrolPoints[_currentPointIndex];
		Vector2 direction = target - GlobalPosition;
		float distance = direction.Length();

		if (distance <= ArrivalDistance)
		{
			// 到点：随机停顿后换下一个巡逻点
			_isWaiting = true;
			_waitRemaining = RandRange(WaitTimeMin, WaitTimeMax);
			Velocity = Vector2.Zero;
			MoveAndSlide();
			return;
		}

		Vector2 desiredVelocity = direction.Normalized() * Speed;
		MoveWithWallCheck(dungeon, desiredVelocity, dt);
		MoveAndSlide();
	}

	private void ChaseMove(float dt)
	{
		// 作业 3：直线扑向玩家（数据驱动 + 贴墙滑动——被墙挡也能绕）
		Vector2 direction = _player.GlobalPosition - GlobalPosition;
		Vector2 desiredVelocity = direction.Normalized() * _chaseSpeed;
		MoveWithWallCheck(Dungeon as DungeonPlayable, desiredVelocity, dt);
	}

	private void MoveWithWallCheck(DungeonPlayable dungeon, Vector2 desiredVelocity, float dt)
	{
		// 通用移动：目标位置可走直走；被挡则尝试单轴滑动（巡逻/追击共用）
		Vector2 nextPosition = GlobalPosition + desiredVelocity * dt;

		if (dungeon.IsWorldPositionWalkable(nextPosition, CollisionRadius))
		{
			Velocity = desiredVelocity;
			return;
		}

		Vector2 xOnly = new(nextPosition.X, GlobalPosition.Y);
		Vector2 yOnly = new(GlobalPosition.X, nextPosition.Y);

		if (dungeon.IsWorldPositionWalkable(xOnly, CollisionRadius))
		{
			Velocity = new Vector2(desiredVelocity.X, 0.0f);
		}
		else if (dungeon.IsWorldPositionWalkable(yOnly, CollisionRadius))
		{
			Velocity = new Vector2(0.0f, desiredVelocity.Y);
		}
		else
		{
			Velocity = Vector2.Zero;
		}
	}
}
