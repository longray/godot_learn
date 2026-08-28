using Godot;
using System.Collections.Generic;

namespace RpgDungeon;

// =========================
// 第 7 课：三态状态机敌人（C# 版）
// PATROL 巡逻 → CHASE 追击 → RETURN 返回（显式 enum + 转换层）
// 视线检测：沿线 8px 采样查墙（隔墙不发现）；发现需面向 ±75°
// AStar 追击：0.3s 重算路径绕墙；进展检测卡住兜底
// 保留资产：多点环游/随机停顿/张望/呼吸三速/接触轮询/类型系统
// =========================
public partial class Enemy : CharacterBody2D
{
	public enum EnemyState
	{
		Patrol,
		Chase,
		Return,
	}

	// ---------- 基础移动 ----------

	[Export] public float Speed { get; set; } = 70.0f;

	// 到点停顿随机区间（运行期随机——每次玩不同，打破机械节奏）
	[Export] public float WaitTimeMin { get; set; } = 0.4f;
	[Export] public float WaitTimeMax { get; set; } = 1.2f;

	[Export] public float ArrivalDistance { get; set; } = 4.0f;
	[Export] public float CollisionRadius { get; set; } = 4.0f;

	// ---------- 接触伤害 ----------

	[Export] public int ContactDamage { get; set; } = 1;

	// 接触伤害判定半径（≈ Hitbox 6.4 + 玩家碰撞体 5）
	[Export] public float ContactRange { get; set; } = 11.0f;

	// ---------- 生命 ----------

	[Export] public int MaxHealth { get; set; } = 2;

	// 作业 3（第 6 课）：敌人类型（normal/fast/tank——Setup 时按类型重塑属性与配色）
	[Export] public string EnemyType { get; set; } = "normal";

	// 类型配色（Sprite2D modulate 基色；受击/追击/返回时在此基础上叠加）
	private static readonly Dictionary<string, Color> TypeColor = new()
	{
		["normal"] = Colors.White,
		["fast"] = new Color(0.75f, 0.85f, 1.0f),   // 偏蓝（敏捷）
		["tank"] = new Color(1.0f, 0.78f, 0.55f),   // 偏橙（厚重）
	};

	// ---------- 追击参数（第 7 课：发现/脱离分离 + 视线 + 角度） ----------

	[Export] public float DetectionRange { get; set; } = 90.0f;
	[Export] public float LoseRange { get; set; } = 150.0f;
	[Export] public float LoseSightTime { get; set; } = 0.8f;

	// 作业 2：视野半角（度）——仅"发现"需要面向玩家；
	// CHASE 中的保持判定不加角度（防绕背瞬间丢失→状态抖动）
	[Export] public float DetectionHalfAngle { get; set; } = 75.0f;

	// 倍率 1.15：fast 126 / normal 80 / tank 52——全员低于玩家 140，风筝普适
	[Export] public float ChaseSpeedMultiplier { get; set; } = 1.15f;

	// ---------- 外部数据 ----------

	public Node Dungeon { get; set; }
	public Vector2[] PatrolPoints { get; private set; } = System.Array.Empty<Vector2>();

	// ---------- 巡逻状态 ----------

	private int _currentPointIndex;
	private bool _isWaiting;
	private float _waitRemaining;

	// ---------- 生命状态 ----------

	public int Health { get; private set; } = 2;
	public bool Dead { get; private set; }
	private float _flashT;  // 受击闪烁剩余时间（>0 时 modulate 优先级最高）

	// ---------- AI 状态（第 7 课） ----------

	public EnemyState State { get; private set; } = EnemyState.Patrol;
	public bool IsChasing { get; private set; }  // 视觉用（呼吸加速/泛红）——CHASE 态镜像

	private Player _player;
	public Vector2 LastKnownPlayerPosition { get; set; }
	private float _timeSinceSeen;

	// 卡住检测（三通道）：停滞累积 + 每秒净位移 + 每秒目标接近量
	// （顶墙滑 velocity≠0、蠕动、贴墙绕圈——距目标永不减小——全覆盖）
	private float _stuckTime;
	private Vector2 _lastProgressPos;
	private float _progressCheckT;
	private Vector2 _progressCheckPos;
	private float _targetCheckD = -1.0f;

	private Vector2 _homePosition;
	private float _chaseSpeed;

	// 作业 2：朝向（随移动更新；发现判定用）
	public Vector2 Facing { get; private set; } = Vector2.Right;

	// 作业 4：AStar 追击——0.3s 重算路径，沿路点绕墙
	private readonly List<Vector2> _pathWorld = new();
	private float _repathTimer;

	// 追击足迹（面包屑）：CHASE 记录走过的格子，RETURN 原路回溯——
	// 来时的路必然通，比 AStar 更符合"原路返回"直觉且零卡死
	private readonly List<Vector2I> _breadcrumb = new();
	private const int BreadcrumbMax = 512;

	// 作业 3：警报叹号剩余显示时间
	private float _alertT;

	// 呼吸动画计时
	private float _t;

	// 张望状态机（仅等待中触发；运行期随机，不进种子序列）
	private float _lookCool;
	private float _lookT;
	private float _lookDir = 1.0f;

	private Sprite2D _sprite;
	private Sprite2D _alert;

	// 作业 1+2（第 12 课）：精英星标 + 受击血条（GetNodeOrNull——场景缺节点不崩）
	private Sprite2D _eliteStar;
	private ColorRect _healthBar;
	private ColorRect _healthBarFill;

	// 第 12 课：精英标记（任何类型的强化贴膜——金色 lerp + 体型 ×1.25 + 属性强化）
	public bool IsElite { get; set; }
	// 体型系数（呼吸动画每帧乘它——直接设 Scale 会被 _Process 覆盖）
	public float SizeScale { get; set; } = 1.0f;
	// 掉落属性（Main 的 OnEnemyDied 消费——差异化掉落由数据驱动）
	public int DropCount { get; set; } = 1;
	public float DropChanceMultiplier { get; set; } = 1.0f;
	public float PotionChanceBonus { get; set; }

	private static readonly System.Random RuntimeRand = new();

	private static float RandRange(float min, float max)
	{
		return min + (float)RuntimeRand.NextDouble() * (max - min);
	}

	public override void _Ready()
	{
		_sprite = GetNode<Sprite2D>("Sprite2D");
		_alert = GetNodeOrNull<Sprite2D>("Alert");
		_eliteStar = GetNodeOrNull<Sprite2D>("EliteStar");
		_healthBar = GetNodeOrNull<ColorRect>("HealthBar");
		_healthBarFill = GetNodeOrNull<ColorRect>("HealthBar/Fill");
	}

	public override void _Process(double delta)
	{
		float dt = (float)delta;

		// 史莱姆呼吸：轻微正弦缩放；移动加速加剧（赶路感），追击最快最猛（兴奋感）
		// 只缩 Sprite2D 不缩根节点——根 scale 会连带缩放子节点碰撞体，破坏触发半径
		float rate = 1.0f;
		float amp = 0.08f;
		if (IsChasing)
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
		// 第 12 课：体型系数乘进呼吸动画（精英 ×1.25——直接设 Scale 会被本行每帧覆盖）
		_sprite.Scale = new Vector2(s, s) * SizeScale;

		// modulate 四态协调（作业 1：受击红 > 追击粉 > 返回蓝 > 类型基色）
		Color baseColor = TypeColor.TryGetValue(EnemyType, out Color c) ? c : Colors.White;
		// 第 12 课：精英金色渗染（45% 向金色 lerp——四态变色逻辑不变，只改基色）
		if (IsElite)
		{
			baseColor = baseColor.Lerp(new Color(1.0f, 0.85f, 0.3f), 0.45f);
		}
		if (_flashT > 0.0f)
		{
			_flashT -= dt;
			_sprite.Modulate = new Color(1.0f, 0.35f, 0.35f);
		}
		else if (IsChasing)
		{
			_sprite.Modulate = new Color(1.0f, 0.6f, 0.6f);
		}
		else if (State == EnemyState.Return)
		{
			_sprite.Modulate = new Color(0.65f, 0.8f, 1.0f);
		}
		else
		{
			_sprite.Modulate = baseColor;
		}

		// 警报叹号倒计时（作业 3：发现玩家头顶显示 0.3s）
		if (_alertT > 0.0f && _alert != null)
		{
			_alertT -= dt;
			_alert.Visible = _alertT > 0.0f;
		}

		// 作业 1（第 12 课）：精英星标常驻（每帧同步——星标位置高于 Alert 不打架）
		if (_eliteStar != null)
		{
			_eliteStar.Visible = IsElite;
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
		else if (_isWaiting && State == EnemyState.Patrol)
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

		// 第 7 课：AI 状态复位
		State = EnemyState.Patrol;
		IsChasing = false;
		_timeSinceSeen = 0.0f;
		_stuckTime = 0.0f;
		_lastProgressPos = GlobalPosition;
		_progressCheckT = 0.0f;
		_progressCheckPos = GlobalPosition;

		if (PatrolPoints.Length == 0)
		{
			_homePosition = GlobalPosition;
			LastKnownPlayerPosition = GlobalPosition;
			return;
		}

		GlobalPosition = PatrolPoints[0];
		_homePosition = PatrolPoints[0];
		LastKnownPlayerPosition = GlobalPosition;

		_currentPointIndex = 0;

		if (PatrolPoints.Length > 1)
		{
			_currentPointIndex = 1;
		}

		_isWaiting = false;
		_waitRemaining = 0.0f;
	}

	// 第 12 课：Main 配置流最终覆盖——在 Setup（基础模板 + 个体差异）之后调用，
	// 拥有最后决定权（层数成长 / 精英强化都已折算进 config）
	public void ApplyConfig(EnemyConfig config)
	{
		EnemyType = config.Name;
		IsElite = config.IsElite;

		MaxHealth = config.MaxHealth;
		Health = MaxHealth;

		Speed = config.Speed;
		ContactDamage = config.ContactDamage;

		DetectionRange = config.DetectionRange;
		LoseRange = config.LoseRange;
		ChaseSpeedMultiplier = config.ChaseSpeedMultiplier;

		CollisionRadius = config.CollisionRadius;

		DropCount = config.DropCount;
		DropChanceMultiplier = config.DropChanceMultiplier;
		PotionChanceBonus = config.PotionChanceBonus;

		SizeScale = config.SizeScale;

		// 精英碰撞体微放大（上限 6：16px 走廊不卡死）
		if (IsElite)
		{
			CollisionRadius = Mathf.Min(CollisionRadius * 1.15f, 6.0f);
		}

		// Setup 的个体差异已被上面覆盖——按最终速度重掷（运行期随机源，保持群体不齐步）
		Speed *= RandRange(0.85f, 1.15f);
		_chaseSpeed = Speed * ChaseSpeedMultiplier;

		UpdateHealthBar();
	}

	// 作业 2（第 12 课）：满血/死亡隐藏，受伤才显示（一眼读出"这怪打过几下"）
	private void UpdateHealthBar()
	{
		if (_healthBar == null || _healthBarFill == null)
		{
			return;
		}

		if (Dead || Health <= 0 || Health >= MaxHealth)
		{
			_healthBar.Visible = false;
			return;
		}

		_healthBar.Visible = true;
		_healthBarFill.Scale = _healthBarFill.Scale with { X = Mathf.Clamp((float)Health / MaxHealth, 0.0f, 1.0f) };
	}


	private void ApplyTypeTemplate()
	{
		// 类型模板 + 第 7 课参数（detection/lose_range）
		switch (EnemyType)
		{
			case "fast":
				Speed = 110.0f;
				MaxHealth = 1;
				ContactDamage = 1;
				DetectionRange = 110.0f;
				LoseRange = 170.0f;
				break;
			case "tank":
				Speed = 45.0f;
				MaxHealth = 4;
				ContactDamage = 2;
				DetectionRange = 70.0f;
				LoseRange = 120.0f;
				break;
			default:
				// normal：保持导出默认（70 / 2 / 1 / 90 / 150）
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

		UpdateHealthBar();

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

	// =========================
	// 主循环：状态机调度（第 7 课）
	// =========================

	public override void _PhysicsProcess(double delta)
	{
		float dt = (float)delta;

		if (Dead || Dungeon is not DungeonPlayable dungeon)
		{
			Velocity = Vector2.Zero;
			MoveAndSlide();
			return;
		}

		Player playerRef = GetPlayerRef();

		// 接触伤害：每帧距离检测（踩坑：body_entered 持续重叠不重发）
		if (GodotObject.IsInstanceValid(playerRef)
			&& GlobalPosition.DistanceTo(playerRef.GlobalPosition) < ContactRange)
		{
			playerRef.TakeDamage(ContactDamage, GlobalPosition);
		}

		UpdateState(dt, playerRef);

		switch (State)
		{
			case EnemyState.Patrol:
				ProcessPatrol(dt);
				break;
			case EnemyState.Chase:
				ProcessChase(dt);
				break;
			case EnemyState.Return:
				ProcessReturn(dt);
				break;
		}
	}

	private Player GetPlayerRef()
	{
		if (_player == null && Dungeon is Node node)
		{
			_player = node.GetNodeOrNull<Player>("Player");
		}
		return _player;
	}

	// =========================
	// 状态转换（第 7 课核心）
	// =========================

	private void UpdateState(float dt, Player playerRef)
	{
		switch (State)
		{
			case EnemyState.Patrol:
				if (IsPlayerVisible(playerRef, DetectionRange))
				{
					StartChase(playerRef);
				}
				break;

			case EnemyState.Chase:
				if (playerRef == null || !GodotObject.IsInstanceValid(playerRef))
				{
					State = EnemyState.Return;
					IsChasing = false;
					_stuckTime = 0.0f;
					return;
				}

				// 作业 2：CHASE 保持判定用全向视线（无角度）——玩家绕背不瞬间丢失
				if (GlobalPosition.DistanceTo(playerRef.GlobalPosition) <= LoseRange
					&& HasLineOfSight(playerRef))
				{
					LastKnownPlayerPosition = playerRef.GlobalPosition;
					_timeSinceSeen = 0.0f;
				}
				else
				{
					_timeSinceSeen += dt;
				}

				float distanceToPlayer = GlobalPosition.DistanceTo(playerRef.GlobalPosition);

				if (distanceToPlayer > LoseRange || _timeSinceSeen > LoseSightTime)
				{
					State = EnemyState.Return;
					IsChasing = false;
					_stuckTime = 0.0f;
				}
				break;

			case EnemyState.Return:
				if (IsPlayerVisible(playerRef, DetectionRange))
				{
					StartChase(playerRef);
				}
				break;
		}
	}

	private void StartChase(Player targetPlayer)
	{
		State = EnemyState.Chase;
		IsChasing = true;
		_isWaiting = false;
		_stuckTime = 0.0f;
		_timeSinceSeen = 0.0f;
		LastKnownPlayerPosition = targetPlayer.GlobalPosition;

		// 面包屑：新一轮追击重新记录足迹（起点入栈）
		_breadcrumb.Clear();
		_breadcrumb.Add(CurrentCell());

		// 作业 3：发现玩家！头顶警报 0.3s
		_alertT = 0.3f;
		if (_alert != null)
		{
			_alert.Visible = true;
		}
	}

	private Vector2I CurrentCell()
	{
		if (Dungeon is DungeonPlayable dungeon && dungeon.TileLayer != null)
		{
			var tl = dungeon.TileLayer;
			return tl.LocalToMap(tl.ToLocal(GlobalPosition));
		}
		return new Vector2I(-1, -1);
	}

	// =========================
	// 巡逻（保留：多点环游 + 随机停顿）
	// =========================

	private void ProcessPatrol(float dt)
	{
		if (PatrolPoints.Length <= 1)
		{
			// 无路径或单点：原地待机
			Velocity = Vector2.Zero;
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
		bool arrived = MoveTowards(target, Speed, dt);

		if (arrived)
		{
			_isWaiting = true;
			_waitRemaining = RandRange(WaitTimeMin, WaitTimeMax);
			Velocity = Vector2.Zero;
		}
		else if (Velocity == Vector2.Zero)
		{
			// 巡逻被墙卡住：切换下一个巡逻点
			_currentPointIndex = (_currentPointIndex + 1) % PatrolPoints.Length;
		}

		MoveAndSlide();
	}

	// =========================
	// 追击（第 7 课：奔向最后所见位置；作业 4：AStar 寻路绕墙）
	// =========================

	private void RepathTo(Vector2 targetWorld)
	{
		// 作业 4：格子级 AStar 寻路 → 世界坐标路点序列（不含起点）
		_repathTimer = 0.3f;
		_pathWorld.Clear();

		if (Dungeon is not DungeonPlayable dungeon || dungeon.TileLayer == null)
		{
			return;
		}

		var tl = dungeon.TileLayer;
		Vector2I fromCell = tl.LocalToMap(tl.ToLocal(GlobalPosition));
		Vector2I toCell = tl.LocalToMap(tl.ToLocal(targetWorld));

		// 保底：贴墙时自身格可能是墙格（AStar 墙起点返回空路径）
		// → 用邻域最近地板格作起点
		if (!dungeon.IsCellWalkable(fromCell))
		{
			bool snapped = false;
			Vector2I[] neighbors =
			{
				new(1, 0), new(-1, 0), new(0, 1), new(0, -1),
				new(1, 1), new(-1, -1), new(1, -1), new(-1, 1),
			};
			foreach (Vector2I d in neighbors)
			{
				if (dungeon.IsCellWalkable(fromCell + d))
				{
					fromCell += d;
					snapped = true;
					break;
				}
			}
			if (!snapped)
			{
				return;
			}
		}

		if (!dungeon.IsCellWalkable(toCell))
		{
			return;  // 目标格是墙：留空路径，调用方回退直线冲
		}

		Godot.Collections.Array<Vector2I> cells = dungeon.AstarGrid.GetIdPath(fromCell, toCell);

		for (int i = 1; i < cells.Count; i++)  // 跳过起点自身
		{
			_pathWorld.Add(tl.ToGlobal(tl.MapToLocal(cells[i])));
		}
	}

	private void ProcessChase(float dt)
	{
		// 作业 4：0.3s 重算 AStar 路径；沿路点走（自动绕墙），无路径回退直线
		_repathTimer -= dt;
		if (_repathTimer <= 0.0f)
		{
			RepathTo(LastKnownPlayerPosition);
		}

		Vector2 target = LastKnownPlayerPosition;
		if (_pathWorld.Count > 0)
		{
			target = _pathWorld[0];

			if (GlobalPosition.DistanceTo(target) <= ArrivalDistance)
			{
				_pathWorld.RemoveAt(0);
				target = _pathWorld.Count > 0 ? _pathWorld[0] : LastKnownPlayerPosition;
			}
		}

		bool arrived = MoveTowards(target, _chaseSpeed, dt);
		UpdateStuck(dt, target);

		// 面包屑：进入新格子记录；去环——浅层重复截断（防绕圈追击重复入栈）
		Vector2I cell = CurrentCell();
		if (cell != _breadcrumb[^1] && cell.X >= 0)
		{
			int loopAt = _breadcrumb.LastIndexOf(cell);
			if (loopAt >= 0 && _breadcrumb.Count - loopAt <= 8)
			{
				_breadcrumb.RemoveRange(loopAt + 1, _breadcrumb.Count - loopAt - 1);
			}
			else
			{
				_breadcrumb.Add(cell);
				if (_breadcrumb.Count > BreadcrumbMax)
				{
					_breadcrumb.RemoveAt(0);
				}
			}
		}

		if (arrived)
		{
			// 到达最终目标但看不到玩家：转返回
			if (_timeSinceSeen > 0.05f)
			{
				State = EnemyState.Return;
				IsChasing = false;
				_stuckTime = 0.0f;
			}
		}
		else if (_stuckTime > 0.5f)
		{
			// 无进展超 0.5s（含贴墙滑）：放弃追击
			State = EnemyState.Return;
			IsChasing = false;
			_stuckTime = 0.0f;
		}

		MoveAndSlide();
	}

	// =========================
	// 返回（第 7 课定稿：面包屑原路回溯优先，AStar 兜底）
	// 踩坑：固定目标下沿用 CHASE 的 0.3s 高频重算会引发起点振荡
	//       （每次重算首点可能在身后 → 来回走）——改为路径空才重算
	// =========================

	private void ProcessReturn(float dt)
	{
		// 阶段 1：还没到过最后所见位置 → 先去搜一圈（近距，AStar 一次算好）
		Vector2 target;
		bool searching = false;

		if (GlobalPosition.DistanceTo(LastKnownPlayerPosition) > ArrivalDistance * 2.0f)
		{
			target = LastKnownPlayerPosition;
			searching = true;
		}
		else if (_breadcrumb.Count > 0)
		{
			// 阶段 2a：有足迹 → 原路回溯（来时的路必然通）
			target = BreadcrumbWorld(_breadcrumb[^1]);
		}
		else if (PatrolPoints.Length > 0)
		{
			// 阶段 2b：无足迹 → AStar 回最近巡逻点
			target = PatrolPoints[GetClosestPatrolPointIndex()];
		}
		else
		{
			target = _homePosition;
		}

		Vector2 moveTarget = target;

		if (searching || _breadcrumb.Count == 0)
		{
			// AStar 模式：路径空才重算（固定目标高频重算会振荡）
			if (_pathWorld.Count == 0)
			{
				RepathTo(target);
			}

			if (_pathWorld.Count > 0)
			{
				moveTarget = _pathWorld[0];

				if (GlobalPosition.DistanceTo(moveTarget) <= ArrivalDistance)
				{
					_pathWorld.RemoveAt(0);
					moveTarget = _pathWorld.Count > 0 ? _pathWorld[0] : target;
				}
			}
		}

		bool arrived = MoveTowards(moveTarget, Speed, dt);
		UpdateStuck(dt, moveTarget);

		if (arrived)
		{
			if (searching)
			{
				// 搜完没发现 → 标记搜索完成，走回家
				LastKnownPlayerPosition = GlobalPosition;
			}
			else if (_breadcrumb.Count > 0)
			{
				// 回溯到达一格：弹出继续下一格
				_breadcrumb.RemoveAt(_breadcrumb.Count - 1);
			}
			else
			{
				ReturnComplete();
			}
		}

		if (_stuckTime > 1.0f)
		{
			if (_breadcrumb.Count > 0)
			{
				// 面包屑走不通（理论不会，防御）：清空换 AStar
				_breadcrumb.Clear();
				_stuckTime = 0.0f;
			}
			else if (_stuckTime > 2.0f)
			{
				// 终极保底：瞬移回巡逻点（正常游戏几乎不触发）
				int idx = GetClosestPatrolPointIndex();
				GlobalPosition = PatrolPoints.Length > 0 ? PatrolPoints[idx] : _homePosition;
				ReturnComplete();
			}
		}

		MoveAndSlide();
	}

	private Vector2 BreadcrumbWorld(Vector2I cell)
	{
		var tl = (Dungeon as DungeonPlayable)?.TileLayer;
		return tl != null ? tl.ToGlobal(tl.MapToLocal(cell)) : GlobalPosition;
	}

	private void ReturnComplete()
	{
		State = EnemyState.Patrol;
		_currentPointIndex = GetClosestPatrolPointIndex();
		_isWaiting = false;
		_stuckTime = 0.0f;
		_breadcrumb.Clear();
		_pathWorld.Clear();
	}

	private int GetClosestPatrolPointIndex()
	{
		if (PatrolPoints.Length == 0)
		{
			return 0;
		}

		int bestIndex = 0;
		float bestDistance = 999999999.0f;

		for (int i = 0; i < PatrolPoints.Length; i++)
		{
			float distance = GlobalPosition.DistanceSquaredTo(PatrolPoints[i]);

			if (distance < bestDistance)
			{
				bestDistance = distance;
				bestIndex = i;
			}
		}

		return bestIndex;
	}

	// =========================
	// 卡住检测（三通道）：停滞 / 净位移 / 目标接近量（抓贴墙绕圈）
	// =========================

	private void UpdateStuck(float dt, Vector2 target)
	{
		// 通道 1：即时停滞
		if (GlobalPosition.DistanceTo(_lastProgressPos) < 2.0f)
		{
			_stuckTime += dt;
		}
		else
		{
			_lastProgressPos = GlobalPosition;
		}

		// 通道 2+3：每 1s 健康检查（净位移 + 目标接近量）
		_progressCheckT += dt;
		if (_progressCheckT >= 1.0f)
		{
			float netMoved = GlobalPosition.DistanceTo(_progressCheckPos);
			float targetD = GlobalPosition.DistanceTo(target);
			float targetProgress = _targetCheckD - targetD;  // 正值=接近了

			if (netMoved >= 6.0f && (targetProgress >= 6.0f || targetD < ArrivalDistance * 3.0f))
			{
				_stuckTime = 0.0f;  // 在走且在接近目标（或已很近）→ 健康
			}
			else
			{
				_stuckTime += 1.0f;  // 停滞/蠕动/绕圈 → 顶格
			}

			_progressCheckT = 0.0f;
			_progressCheckPos = GlobalPosition;
			_targetCheckD = targetD;
		}
	}

	// =========================
	// 移动辅助（arrived 布尔 + 贴墙滑动；facing 随移动更新）
	// =========================

	private bool MoveTowards(Vector2 target, float moveSpeed, float dt)
	{
		if (Dungeon is not DungeonPlayable dungeon)
		{
			Velocity = Vector2.Zero;
			return false;
		}

		Vector2 direction = target - GlobalPosition;
		float distance = direction.Length();

		if (distance <= ArrivalDistance)
		{
			Velocity = Vector2.Zero;
			return true;
		}

		Vector2 desiredVelocity = direction.Normalized() * moveSpeed;
		Facing = direction.Normalized();  // 作业 2：朝向随移动更新
		Vector2 nextPosition = GlobalPosition + desiredVelocity * dt;

		if (dungeon.IsWorldPositionWalkable(nextPosition, CollisionRadius))
		{
			Velocity = desiredVelocity;
			return false;
		}

		// 贴墙滑动
		Vector2 xOnly = new(nextPosition.X, GlobalPosition.Y);
		Vector2 yOnly = new(GlobalPosition.X, nextPosition.Y);

		if (dungeon.IsWorldPositionWalkable(xOnly, CollisionRadius))
		{
			Velocity = new Vector2(desiredVelocity.X, 0.0f);
			return false;
		}

		if (dungeon.IsWorldPositionWalkable(yOnly, CollisionRadius))
		{
			Velocity = new Vector2(0.0f, desiredVelocity.Y);
			return false;
		}

		Velocity = Vector2.Zero;
		return false;
	}

	// =========================
	// 视线检测（第 7 课核心：沿线采样查墙）
	// =========================

	private bool IsPlayerVisible(Player target, float rangeLimit)
	{
		if (target == null || !GodotObject.IsInstanceValid(target))
		{
			return false;
		}

		float distance = GlobalPosition.DistanceTo(target.GlobalPosition);

		if (distance > rangeLimit)
		{
			return false;
		}

		// 作业 2：发现判定加视野半角——只有面向玩家 ±75° 才"发现"
		Vector2 toPlayer = (target.GlobalPosition - GlobalPosition).Normalized();
		if (Mathf.Abs(Mathf.RadToDeg(Facing.AngleTo(toPlayer))) > DetectionHalfAngle)
		{
			return false;
		}

		return HasLineOfSight(target);
	}

	private bool HasLineOfSight(Player target)
	{
		// 纯视线采样（无角度/距离检查）——CHASE 保持判定复用
		if (Dungeon is not DungeonPlayable dungeon)
		{
			return false;
		}

		float distance = GlobalPosition.DistanceTo(target.GlobalPosition);
		int steps = (int)(distance / 8.0f) + 1;

		for (int i = 0; i <= steps; i++)
		{
			float t = (float)i / steps;
			Vector2 sample = GlobalPosition.Lerp(target.GlobalPosition, t);

			if (!dungeon.IsWorldPositionWalkable(sample, 0.0f))
			{
				return false;
			}
		}

		return true;
	}
}

// =========================
// 第 12 课：敌人类型配置（C# 用强类型类表达"基因"——与 GD 版 Dictionary 字段一一对应：
// name/is_elite/size_scale/max_health/speed/contact_damage/detection_range/lose_range/
// chase_speed_multiplier/collision_radius/drop_count/drop_chance_multiplier/potion_chance_bonus）
// =========================
public class EnemyConfig
{
	public string Name = "normal";
	public bool IsElite;
	public float SizeScale = 1.0f;

	public int MaxHealth = 2;
	public float Speed = 70.0f;
	public int ContactDamage = 1;
	public float DetectionRange = 90.0f;
	public float LoseRange = 150.0f;
	public float ChaseSpeedMultiplier = 1.15f;
	public float CollisionRadius = 4.0f;

	public int DropCount = 1;
	public float DropChanceMultiplier = 1.0f;
	public float PotionChanceBonus;
}
