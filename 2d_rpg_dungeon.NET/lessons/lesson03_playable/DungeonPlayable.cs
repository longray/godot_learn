using Godot;
using System.Collections.Generic;

namespace RpgDungeon;

// =========================
// 第 3 课：连通性验证、玩家出生点、简单移动、出口触发（C# 版）
// 第 4 课：钥匙、宝箱、怪物出生点、出口锁（POI 体系，含全部作业）
// 与 GDScript 版算法逐行对应，同种子应产出相同地图（RNG 调用序列严格对齐）
// =========================
public partial class DungeonPlayable : Node2D
{
	// ---------- 基础生成参数 ----------

	[Export] public int SeedValue { get; set; } = 20260824;
	[Export] public bool UseRandomSeed { get; set; } = false;

	[Export] public int MapWidth { get; set; } = 48;
	[Export] public int MapHeight { get; set; } = 32;

	[Export] public int RoomAttempts { get; set; } = 60;
	[Export] public int MaxRooms { get; set; } = 10;

	[Export] public Vector2I MinRoomSize { get; set; } = new(4, 3);
	[Export] public Vector2I MaxRoomSize { get; set; } = new(10, 7);

	[Export] public int CellSize { get; set; } = 16;

	// ---------- TileMap 参数 ----------

	[ExportGroup("TileMap")]

	[Export] public bool UsePlaceholderTileset { get; set; } = true;

	// 作业 5 方案 B（第 2 课）：尊重手工配置的 TileSet
	[Export] public bool UseExternalTiles { get; set; } = false;

	// 作业 5 方案 A（第 2 课）：外部图集路径
	[Export] public string ExternalTilesPath { get; set; } = "res://assets/tiles/dungeon_tiles.png";

	[Export] public int TileSourceId { get; set; } = 0;

	[Export] public Vector2I FloorAtlasCoords { get; set; } = new(0, 0);
	[Export] public Vector2I WallAtlasCoords { get; set; } = new(1, 0);
	[Export] public Vector2I EntranceAtlasCoords { get; set; } = new(2, 0);
	[Export] public Vector2I ExitAtlasCoords { get; set; } = new(3, 0);

	// ---------- Gameplay 参数 ----------

	[ExportGroup("Gameplay")]

	// 把你的 player.tscn 拖到这里
	[Export] public PackedScene PlayerScene { get; set; }

	// 作业 5：把 enemy.tscn 拖到这里（未设置时怪物回退为旧版危险区）
	[Export] public PackedScene EnemyScene { get; set; }

	[Export] public float ExitRadiusMultiplier { get; set; } = 0.45f;
	[Export] public bool DebugPrintPath { get; set; } = false;

	// ---------- POI 参数（第 4 课：钥匙、宝箱、怪物出生点） ----------

	[ExportGroup("POI")]

	[Export(PropertyHint.Range, "0,10")] public int MinTreasures { get; set; } = 2;
	[Export(PropertyHint.Range, "0,10")] public int MaxTreasures { get; set; } = 5;

	[Export(PropertyHint.Range, "0,12")] public int MinMonsters { get; set; } = 2;
	[Export(PropertyHint.Range, "0,12")] public int MaxMonsters { get; set; } = 6;

	// 第 6 课：掉落参数（死亡掉率 0.7；掉落物中 0.25 是药水、0.75 是金币）
	[Export(PropertyHint.Range, "0.0,1.0")] public float EnemyDropChance { get; set; } = 0.7f;
	[Export(PropertyHint.Range, "0.0,1.0")] public float EnemyPotionChance { get; set; } = 0.25f;

	// ---------- 数据 ----------

	private const int CellWall = 0;
	private const int CellFloor = 1;

	private static readonly Vector2I InvalidCell = new(-1, -1);

	// 作业 2：怪物出生点距入口的最小距离（平方距离，36 = 欧氏 6 格）
	private const int MonsterMinDistanceSq = 36;

	// 作业 3：POI 不可达时的重选上限（防极端情况死循环）
	private const int PoiReachableRetries = 16;

	private readonly RandomNumberGenerator _rng = new();

	// C# 强类型二维数组（对比 GDScript 嵌套 Array）
	private int[,] _grid = new int[0, 0];

	private readonly List<Rect2I> _rooms = new();

	public Vector2I EntranceCell { get; private set; }
	public Vector2I ExitCell { get; private set; }

	public Vector2I KeyCell { get; private set; } = InvalidCell;
	public readonly List<Vector2I> TreasureCells = new();
	public readonly List<Vector2I> MonsterCells = new();

	// 已被占用的格子，避免钥匙/宝箱/怪物重叠
	private readonly HashSet<Vector2I> _usedCells = new();

	// 当前地牢里生成的钥匙、宝箱、怪物节点（玩家和出口不在此列，仍复用）
	private readonly List<Node> _dynamicEntities = new();

	private AStarGrid2D _astarGrid = new();

	private Player _playerInstance;
	private Area2D _exitArea;

	public bool HasKey { get; private set; }
	public int TreasureCount { get; private set; }

	// ---------- 节点 ----------

	private TileMapLayer _tileLayer;

	// 作业 3：路径可视化覆盖层（画在 TileMapLayer 之上）
	private PathOverlay _pathOverlay;

	// HUD 引用（场景里的 CanvasLayer > Label）
	private Label _keyLabel;
	private Label _treasureLabel;
	private Label _goldLabel;
	private HBoxContainer _healthUi;

	// 作业 1（第 5 课）：心形图标纹理
	private static readonly Texture2D HeartFullTexture =
		GD.Load<Texture2D>("res://assets/sprites/heart_full.png");
	private static readonly Texture2D HeartEmptyTexture =
		GD.Load<Texture2D>("res://assets/sprites/heart_empty.png");

	// 像素素材（assets/sprites/generate_sprites.ps1 生成，16x16 透明背景）
	private static readonly Texture2D KeyTexture =
		GD.Load<Texture2D>("res://assets/sprites/key.png");
	private static readonly Texture2D ChestTexture =
		GD.Load<Texture2D>("res://assets/sprites/chest.png");
	private static readonly Texture2D MonsterTexture =
		GD.Load<Texture2D>("res://assets/sprites/monster.png");
	private static readonly Texture2D GoldTexture =
		GD.Load<Texture2D>("res://assets/sprites/gold.png");
	private static readonly Texture2D PotionTexture =
		GD.Load<Texture2D>("res://assets/sprites/potion.png");

	// 第 6 课：金币计数（跨层保留——玩家长期资源）
	public int GoldCount { get; private set; }

	// ---------- 互操作/测试访问器（int[,] 不能直接编组给 GDScript） ----------

	public int RoomCount => _rooms.Count;

	public int FloorCellCount
	{
		get
		{
			int count = 0;
			foreach (int v in _grid)
			{
				if (v == CellFloor)
				{
					count++;
				}
			}
			return count;
		}
	}

	public int UsedCellCount => _usedCells.Count;

	public int EntityCount => _dynamicEntities.Count;

	// GDScript 互操作访问器（私有 List 不编组；验证/调试用）
	public Node GetEntity(int index) => _dynamicEntities[index];

	// GDScript 互操作访问器（C# List 属性不自动编组，需方法暴露）
	public int TreasureCellCount => TreasureCells.Count;

	public int MonsterCellCount => MonsterCells.Count;

	// ---------- 生命周期 ----------

	public override void _Ready()
	{
		_tileLayer = GetNode<TileMapLayer>("TileMapLayer");
		_pathOverlay = GetNodeOrNull<PathOverlay>("PathOverlay");
		_keyLabel = GetNodeOrNull<Label>("HUD/KeyLabel");
		_treasureLabel = GetNodeOrNull<Label>("HUD/TreasureLabel");
		_goldLabel = GetNodeOrNull<Label>("HUD/GoldLabel");
		_healthUi = GetNodeOrNull<HBoxContainer>("HUD/HealthUI");

		if (_tileLayer == null)
		{
			GD.PushError("找不到 TileMapLayer，请确认场景里有名为 TileMapLayer 的子节点。");
			return;
		}

		Generate();
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		if (@event is InputEventKey { Pressed: true, Echo: false, Keycode: Key.R })
		{
			Generate();
		}
	}

	public void Generate()
	{
		// 防止地图太小
		MapWidth = Mathf.Max(20, MapWidth);
		MapHeight = Mathf.Max(16, MapHeight);

		// 第 4 课：每层重置玩家状态
		HasKey = false;
		TreasureCount = 0;

		SetupRng();

		// 第 4 课：清理上一层的钥匙、宝箱、怪物（玩家和出口仍复用）
		ClearDynamicEntities();

		ClearMapData();
		PlaceRooms();
		ConnectRooms();
		BuildAStar();
		PickEntranceAndExit();
		EnsureExitReachable();

		// 第 4 课：生成钥匙、宝箱、怪物位置
		PickPoiCells();

		SetupTilemap();
		BuildTilemap();

		UpdateOrSpawnExit();
		SpawnPoiNodes();
		UpdateOrSpawnPlayer();
		SpawnMarkers();
		CenterCamera();

		// 作业 3：把最终的入口→出口路径交给覆盖层绘制（修复后的最新路径）
		_pathOverlay?.SetPath(ToArray(_astarGrid.GetIdPath(EntranceCell, ExitCell)), CellSize);

		UpdateHud();

		if (DebugPrintPath)
		{
			GD.Print("入口：", EntranceCell, "  出口：", ExitCell);
			GD.Print("钥匙：", KeyCell, "  宝箱数：", TreasureCells.Count, "  怪物数：", MonsterCells.Count);
		}
	}

	private static Vector2I[] ToArray(Godot.Collections.Array<Vector2I> path)
	{
		var result = new Vector2I[path.Count];
		for (int i = 0; i < path.Count; i++)
		{
			result[i] = path[i];
		}
		return result;
	}

	// =========================
	// RNG
	// =========================

	private void SetupRng()
	{
		if (UseRandomSeed)
		{
			_rng.Randomize();
		}
		else
		{
			_rng.Seed = (ulong)SeedValue;
		}
	}

	// =========================
	// 地图数据
	// =========================

	private void ClearMapData()
	{
		_rooms.Clear();

		EntranceCell = Vector2I.Zero;
		ExitCell = Vector2I.Zero;

		_grid = new int[MapHeight, MapWidth]; // C# 数组创建即填 0（墙）
	}

	private void PlaceRooms()
	{
		for (int i = 0; i < RoomAttempts; i++)
		{
			if (_rooms.Count >= MaxRooms)
			{
				break;
			}

			Rect2I room = MakeRandomRoom();

			if (room.Size.X <= 0 || room.Size.Y <= 0)
			{
				continue;
			}

			if (!OverlapsExistingRoom(room))
			{
				_rooms.Add(room);
				CarveRoom(room);
			}
		}
	}

	private Rect2I MakeRandomRoom()
	{
		int maxW = Mathf.Min(MaxRoomSize.X, MapWidth - 3);
		int maxH = Mathf.Min(MaxRoomSize.Y, MapHeight - 3);

		if (maxW < 2 || maxH < 2)
		{
			return default;
		}

		int minW = Mathf.Clamp(MinRoomSize.X, 2, maxW);
		int minH = Mathf.Clamp(MinRoomSize.Y, 2, maxH);

		int w = _rng.RandiRange(minW, maxW);
		int h = _rng.RandiRange(minH, maxH);

		int x = _rng.RandiRange(1, MapWidth - w - 2);
		int y = _rng.RandiRange(1, MapHeight - h - 2);

		return new Rect2I(x, y, w, h);
	}

	private bool OverlapsExistingRoom(Rect2I room)
	{
		// 向外扩一格，让房间之间保留间距
		Rect2I expanded = new(
			room.Position.X - 1,
			room.Position.Y - 1,
			room.Size.X + 2,
			room.Size.Y + 2
		);

		foreach (Rect2I existing in _rooms)
		{
			if (Rect2IIntersects(expanded, existing))
			{
				return true;
			}
		}

		return false;
	}

	private static bool Rect2IIntersects(Rect2I a, Rect2I b)
	{
		return a.Position.X < b.Position.X + b.Size.X
			&& a.Position.X + a.Size.X > b.Position.X
			&& a.Position.Y < b.Position.Y + b.Size.Y
			&& a.Position.Y + a.Size.Y > b.Position.Y;
	}

	private void CarveRoom(Rect2I room)
	{
		for (int y = room.Position.Y; y < room.Position.Y + room.Size.Y; y++)
		{
			for (int x = room.Position.X; x < room.Position.X + room.Size.X; x++)
			{
				SetCell(x, y, CellFloor);
			}
		}
	}

	private void ConnectRooms()
	{
		if (_rooms.Count < 2)
		{
			return;
		}

		// 第 1 课作业 5 成果：增量式最近邻连接
		for (int i = 1; i < _rooms.Count; i++)
		{
			Vector2I from = RoomCenter(_rooms[i]);
			int bestJ = 0;
			int bestDist = from.DistanceSquaredTo(RoomCenter(_rooms[0]));

			for (int j = 1; j < i; j++)
			{
				int d = from.DistanceSquaredTo(RoomCenter(_rooms[j]));
				if (d < bestDist)
				{
					bestDist = d;
					bestJ = j;
				}
			}

			Vector2I b = RoomCenter(_rooms[bestJ]);

			if (_rng.Randf() < 0.5f)
			{
				CarveHCorridor(from.X, b.X, from.Y);
				CarveVCorridor(from.Y, b.Y, b.X);
			}
			else
			{
				CarveVCorridor(from.Y, b.Y, from.X);
				CarveHCorridor(from.X, b.X, b.Y);
			}
		}
	}

	private static Vector2I RoomCenter(Rect2I room)
	{
		return new Vector2I(
			room.Position.X + room.Size.X / 2,
			room.Position.Y + room.Size.Y / 2
		);
	}

	private void CarveHCorridor(int x1, int x2, int y)
	{
		int from = Mathf.Min(x1, x2);
		int to = Mathf.Max(x1, x2);

		for (int x = from; x <= to; x++)
		{
			SetCell(x, y, CellFloor);
		}
	}

	private void CarveVCorridor(int y1, int y2, int x)
	{
		int from = Mathf.Min(y1, y2);
		int to = Mathf.Max(y1, y2);

		for (int y = from; y <= to; y++)
		{
			SetCell(x, y, CellFloor);
		}
	}

	private void SetCell(int x, int y, int value)
	{
		if (x < 0 || x >= MapWidth)
		{
			return;
		}
		if (y < 0 || y >= MapHeight)
		{
			return;
		}

		_grid[y, x] = value;
	}

	// =========================
	// 入口 / 出口
	// =========================

	private void PickEntranceAndExit()
	{
		if (_rooms.Count == 0)
		{
			// 保底：如果参数太严格没有生成房间，就在地图中心挖一块地板
			EntranceCell = new Vector2I(MapWidth / 2, MapHeight / 2);
			ExitCell = EntranceCell;
			SetCell(EntranceCell.X, EntranceCell.Y, CellFloor);
			return;
		}

		// 入口：第一个房间中心
		EntranceCell = RoomCenter(_rooms[0]);

		if (_rooms.Count == 1)
		{
			// 只有一个房间时，在同一个房间里选一个不同的地板点作为出口
			// （候选列表法，保证与入口不同）
			ExitCell = PickRandomFloorCellInRoom(_rooms[0], EntranceCell);
		}
		else
		{
			// 出口 = 从入口出发「实际路径」最长的房间中心（A* 版）
			ExitCell = EntranceCell;
			int bestPathLen = -1;

			foreach (Rect2I room in _rooms)
			{
				Vector2I center = RoomCenter(room);
				int pathLen = _astarGrid.GetIdPath(EntranceCell, center).Count;

				if (pathLen > bestPathLen)
				{
					bestPathLen = pathLen;
					ExitCell = center;
				}
			}
		}

		// 极端情况下，确保出口不要和入口完全重合
		if (ExitCell == EntranceCell)
		{
			ExitCell = PickRandomFloorCellInRoom(_rooms[0], EntranceCell);
		}
	}

	private Vector2I PickRandomFloorCellInRoom(Rect2I room, Vector2I avoid)
	{
		// 枚举房间内所有地板格（排除 avoid），从中随机选一个——保证不重合
		List<Vector2I> candidates = new();

		for (int y = room.Position.Y; y < room.Position.Y + room.Size.Y; y++)
		{
			for (int x = room.Position.X; x < room.Position.X + room.Size.X; x++)
			{
				var cell = new Vector2I(x, y);

				if (cell == avoid)
				{
					continue;
				}

				if (_grid[y, x] == CellFloor)
				{
					candidates.Add(cell);
				}
			}
		}

		if (candidates.Count == 0)
		{
			return avoid;
		}

		return candidates[_rng.RandiRange(0, candidates.Count - 1)];
	}

	public Vector2 GetEntranceLocalPosition()
	{
		return CellToCenterLocal(EntranceCell);
	}

	public Vector2 GetExitLocalPosition()
	{
		return CellToCenterLocal(ExitCell);
	}

	public Vector2 GetEntranceWorldPosition()
	{
		if (_tileLayer == null)
		{
			return GetEntranceLocalPosition();
		}

		return _tileLayer.ToGlobal(GetEntranceLocalPosition());
	}

	private Vector2 CellToCenterLocal(Vector2I cell)
	{
		return new Vector2(cell.X, cell.Y) * CellSize + new Vector2(CellSize, CellSize) * 0.5f;
	}

	// =========================
	// AStarGrid2D 连通性
	// =========================

	private void BuildAStar()
	{
		_astarGrid = new AStarGrid2D
		{
			Region = new Rect2I(0, 0, MapWidth, MapHeight),
			CellSize = new Vector2I(1, 1), // 直接用格子坐标作点 id
			DiagonalMode = AStarGrid2D.DiagonalModeEnum.Never,
		};
		_astarGrid.Update();

		// 全图设墙（批量），地板格才解锁为可通行
		_astarGrid.FillSolidRegion(_astarGrid.Region, true);

		for (int y = 0; y < MapHeight; y++)
		{
			for (int x = 0; x < MapWidth; x++)
			{
				if (_grid[y, x] == CellFloor)
				{
					_astarGrid.SetPointSolid(new Vector2I(x, y), false);
				}
			}
		}
	}

	private void EnsureExitReachable()
	{
		if (IsExitReachable())
		{
			return;
		}

		GD.PushWarning("入口到出口不可达，正在自动修复。");

		// 简单修复：直接从入口到出口挖一条 L 型通道
		if (_rng.Randf() < 0.5f)
		{
			CarveHCorridor(EntranceCell.X, ExitCell.X, EntranceCell.Y);
			CarveVCorridor(EntranceCell.Y, ExitCell.Y, ExitCell.X);
		}
		else
		{
			CarveVCorridor(EntranceCell.Y, ExitCell.Y, EntranceCell.X);
			CarveHCorridor(EntranceCell.X, ExitCell.X, ExitCell.Y);
		}

		BuildAStar();

		if (!IsExitReachable())
		{
			GD.PushError("修复后入口到出口仍然不可达。");
		}
	}

	private bool IsExitReachable()
	{
		if (EntranceCell == ExitCell)
		{
			return true;
		}

		int pathLen = _astarGrid.GetIdPath(EntranceCell, ExitCell).Count;

		if (DebugPrintPath)
		{
			GD.Print("AStar path length: ", pathLen);
		}

		return pathLen > 0;
	}

	// =========================
	// TileMap
	// =========================

	private void SetupTilemap()
	{
		if (UseExternalTiles)
		{
			// 方案 B：尊重手工配置的 TileSet，脚本不碰 tile_set
			if (_tileLayer.TileSet == null)
			{
				GD.PushWarning("UseExternalTiles 开着，但 TileMapLayer 上没有手工 TileSet。");
			}
			return;
		}

		if (UsePlaceholderTileset)
		{
			TileSourceId = CreatePlaceholderTileset();

			FloorAtlasCoords = new Vector2I(0, 0);
			WallAtlasCoords = new Vector2I(1, 0);
			EntranceAtlasCoords = new Vector2I(2, 0);
			ExitAtlasCoords = new Vector2I(3, 0);
		}
		else
		{
			if (_tileLayer.TileSet == null)
			{
				GD.PushWarning("你关闭了 UsePlaceholderTileset，但 TileMapLayer 上没有设置 TileSet。");
			}
		}
	}

	private int CreatePlaceholderTileset()
	{
		// 方案 A：优先加载外部图集，文件缺失则回退代码生成
		Texture2D texture;

		if (ExternalTilesPath != "" && ResourceLoader.Exists(ExternalTilesPath))
		{
			texture = GD.Load<Texture2D>(ExternalTilesPath);
		}
		else
		{
			texture = GeneratePlaceholderTexture();
		}

		var tileSet = new TileSet
		{
			TileSize = new Vector2I(CellSize, CellSize),
		};

		var source = new TileSetAtlasSource
		{
			Texture = texture,
			TextureRegionSize = new Vector2I(CellSize, CellSize),
		};

		int sourceId = tileSet.AddSource(source);

		if (sourceId < 0)
		{
			GD.PushError("创建 placeholder TileSet source 失败。");
			return -1;
		}

		source.CreateTile(new Vector2I(0, 0)); // floor
		source.CreateTile(new Vector2I(1, 0)); // wall
		source.CreateTile(new Vector2I(2, 0)); // entrance
		source.CreateTile(new Vector2I(3, 0)); // exit

		// 踩坑：如需添加物理碰撞层，碰撞多边形坐标必须相对于 tile 中心（而非左上角）
		// Pitfall: TileSet collision polygon coordinates are relative to tile center, not top-left
		// 例如 16×16 tile 的碰撞多边形应为：(-8,-8, 8,-8, 8,8, -8,8)
		// 详见：doc/notes/tileset_collision_coordinates.md

		_tileLayer.TileSet = tileSet;

		return sourceId;
	}

	private Texture2D GeneratePlaceholderTexture()
	{
		// 代码生成纯色图集（外部素材缺失时的回退路径）
		Image image = Image.Create(CellSize * 4, CellSize, false, Image.Format.Rgba8);

		image.FillRect(new Rect2I(0, 0, CellSize, CellSize), new Color(0.82f, 0.75f, 0.60f));
		image.FillRect(new Rect2I(CellSize, 0, CellSize, CellSize), new Color(0.12f, 0.12f, 0.16f));
		image.FillRect(new Rect2I(CellSize * 2, 0, CellSize, CellSize), new Color(0.20f, 0.90f, 0.40f));
		image.FillRect(new Rect2I(CellSize * 3, 0, CellSize, CellSize), new Color(0.90f, 0.25f, 0.25f));

		return ImageTexture.CreateFromImage(image);
	}

	private void BuildTilemap()
	{
		if (_tileLayer == null)
		{
			return;
		}

		if (TileSourceId < 0)
		{
			GD.PushError("TileSourceId 无效，无法写入 TileMapLayer。");
			return;
		}

		_tileLayer.Clear();

		for (int y = 0; y < MapHeight; y++)
		{
			for (int x = 0; x < MapWidth; x++)
			{
				Vector2I atlasCoords = _grid[y, x] == CellFloor
					? FloorAtlasCoords
					: WallAtlasCoords;

				_tileLayer.SetCell(new Vector2I(x, y), TileSourceId, atlasCoords);
			}
		}

		_tileLayer.SetCell(EntranceCell, TileSourceId, EntranceAtlasCoords);
		_tileLayer.SetCell(ExitCell, TileSourceId, ExitAtlasCoords);
	}

	// =========================
	// 出口触发区域
	// =========================

	private void UpdateOrSpawnExit()
	{
		if (_tileLayer == null)
		{
			return;
		}

		if (_exitArea == null || !GodotObject.IsInstanceValid(_exitArea))
		{
			_exitArea = new Area2D
			{
				Name = "ExitArea",
				Monitoring = true,
			};

			var collision = new CollisionShape2D();
			var circle = new CircleShape2D
			{
				Radius = CellSize * ExitRadiusMultiplier,
			};
			collision.Shape = circle;

			_exitArea.AddChild(collision);
			_exitArea.BodyEntered += OnExitBodyEntered;

			// 作业 4：出口锁状态覆盖层（红=锁定 / 绿=解锁，UpdateExitLockVisual 刷新颜色）
			var lockOverlay = new Polygon2D
			{
				Name = "LockOverlay",
			};
			float half = CellSize * 0.5f;
			lockOverlay.Polygon = new Vector2[]
			{
				new(-half, -half),
				new(half, -half),
				new(half, half),
				new(-half, half),
			};
			_exitArea.AddChild(lockOverlay);

			_tileLayer.AddChild(_exitArea);
		}
		else
		{
			if (_exitArea.GetChildOrNull<CollisionShape2D>(0) is { Shape: CircleShape2D circle })
			{
				circle.Radius = CellSize * ExitRadiusMultiplier;
			}
		}

		_exitArea.Position = GetExitLocalPosition();
		UpdateExitLockVisual();
	}

	private void UpdateExitLockVisual()
	{
		// 作业 4：出口覆盖层随钥匙状态变色（锁定=红半透明，解锁=绿半透明）
		if (_exitArea == null || !GodotObject.IsInstanceValid(_exitArea))
		{
			return;
		}

		var overlay = _exitArea.GetNodeOrNull<Polygon2D>("LockOverlay");
		if (overlay == null)
		{
			return;
		}

		overlay.Color = HasKey
			? new Color(0.3f, 1.0f, 0.4f, 0.45f)
			: new Color(1.0f, 0.25f, 0.25f, 0.45f);
	}

	private void OnExitBodyEntered(Node2D body)
	{
		if (!body.IsInGroup("player"))
		{
			return;
		}

		// 第 4 课：出口锁——必须先拿到钥匙
		if (HasKey)
		{
			GD.Print("使用钥匙，进入下一层。");
			// 物理回调中不能直接改场景树，延迟到帧末安全执行
			CallDeferred(MethodName.Generate);
		}
		else
		{
			GD.Print("出口被锁住了，需要钥匙。");
			UpdateHud(true);
		}
	}

	// =========================
	// 第 4 课：POI 选点（钥匙、宝箱、怪物）
	// =========================

	private void PickPoiCells()
	{
		_usedCells.Clear();

		KeyCell = InvalidCell;
		TreasureCells.Clear();
		MonsterCells.Clear();

		// 入口和出口不能被内容点占用
		MarkCellUsed(EntranceCell);
		MarkCellUsed(ExitCell);

		// 先选钥匙（最远房策略 + 作业 3 可达性验证）
		KeyCell = PickReachableCell(PickKeyCell(), false);
		if (KeyCell != InvalidCell)
		{
			MarkCellUsed(KeyCell);
		}

		// 再选宝箱（作业 3：带可达性验证的重选循环）
		int minT = Mathf.Min(MinTreasures, MaxTreasures);
		int maxT = Mathf.Max(MinTreasures, MaxTreasures);
		int treasureAmount = _rng.RandiRange(minT, maxT);

		for (int i = 0; i < treasureAmount; i++)
		{
			Vector2I cell = PickReachableCell(PickRandomAvailableCellInRooms(), false);
			if (cell == InvalidCell)
			{
				break;
			}

			TreasureCells.Add(cell);
			MarkCellUsed(cell);
		}

		// 最后选怪物（作业 2 距离过滤 + 作业 3 可达验证）
		int minM = Mathf.Min(MinMonsters, MaxMonsters);
		int maxM = Mathf.Max(MinMonsters, MaxMonsters);
		int monsterAmount = _rng.RandiRange(minM, maxM);

		for (int i = 0; i < monsterAmount; i++)
		{
			Vector2I cell = PickReachableCell(PickMonsterCell(), true);
			if (cell == InvalidCell)
			{
				break;
			}

			MonsterCells.Add(cell);
			MarkCellUsed(cell);
		}
	}

	private void MarkCellUsed(Vector2I cell)
	{
		if (cell == InvalidCell)
		{
			return;
		}

		_usedCells.Add(cell);
	}

	private bool IsCellAvailable(Vector2I cell)
	{
		if (cell == InvalidCell)
		{
			return false;
		}

		if (cell.X < 0 || cell.X >= MapWidth)
		{
			return false;
		}
		if (cell.Y < 0 || cell.Y >= MapHeight)
		{
			return false;
		}

		if (_grid[cell.Y, cell.X] != CellFloor)
		{
			return false;
		}

		if (_usedCells.Contains(cell))
		{
			return false;
		}

		return true;
	}

	private Vector2I PickKeyCell()
	{
		// 第 4 课策略：排除入口房和出口房，选离入口最远的房间
		// → 强制玩家探索
		if (_rooms.Count == 0)
		{
			return InvalidCell;
		}

		List<Rect2I> candidateRooms = new();

		// 优先排除入口房和出口房
		foreach (Rect2I room in _rooms)
		{
			Vector2I center = RoomCenter(room);

			if (center == EntranceCell)
			{
				continue;
			}
			if (center == ExitCell)
			{
				continue;
			}

			candidateRooms.Add(room);
		}

		if (candidateRooms.Count == 0)
		{
			candidateRooms.AddRange(_rooms);
		}

		// 在候选房间里选择离入口最远的房间
		Rect2I bestRoom = candidateRooms[0];
		int bestDistance = -1;

		foreach (Rect2I room in candidateRooms)
		{
			Vector2I center = RoomCenter(room);
			int distance = EntranceCell.DistanceSquaredTo(center);

			if (distance > bestDistance)
			{
				bestDistance = distance;
				bestRoom = room;
			}
		}

		Vector2I cell = PickRandomAvailableCellInRoom(bestRoom);

		if (cell != InvalidCell)
		{
			return cell;
		}

		// 如果这个房间没有合适位置，就全局找一个
		return PickRandomAvailableCellInGrid();
	}

	private Vector2I PickReachableCell(Vector2I firstTry, bool isMonster)
	{
		// 作业 3：验证 firstTry 从入口可达；不可达则重选（重试有上限）
		// 每次重选同样消耗一次 RNG —— 同种子序列稳定（重试次数由地图决定，可复现）
		if (IsCellReachable(firstTry))
		{
			return firstTry;
		}

		for (int retry = 0; retry < PoiReachableRetries; retry++)
		{
			Vector2I candidate = isMonster
				? PickMonsterCell()
				: PickRandomAvailableCellInRooms();

			if (candidate == InvalidCell)
			{
				break;
			}

			if (IsCellReachable(candidate))
			{
				return candidate;
			}
		}

		// 重试用尽：接受原格（地图整体已连通，此分支理论上不触发，仅保底）
		return firstTry;
	}

	private bool IsCellReachable(Vector2I cell)
	{
		// 作业 3：astar 已在 Generate 流程中先行构建，此处直接查询
		if (cell == InvalidCell)
		{
			return false;
		}

		return _astarGrid.GetIdPath(EntranceCell, cell).Count > 0;
	}

	private Vector2I PickRandomAvailableCellInRoom(Rect2I room)
	{
		List<Vector2I> candidates = new();

		for (int y = room.Position.Y; y < room.Position.Y + room.Size.Y; y++)
		{
			for (int x = room.Position.X; x < room.Position.X + room.Size.X; x++)
			{
				var cell = new Vector2I(x, y);

				if (IsCellAvailable(cell))
				{
					candidates.Add(cell);
				}
			}
		}

		if (candidates.Count == 0)
		{
			return InvalidCell;
		}

		return candidates[_rng.RandiRange(0, candidates.Count - 1)];
	}

	private Vector2I PickRandomAvailableCellInRooms()
	{
		List<Vector2I> candidates = new();

		foreach (Rect2I room in _rooms)
		{
			for (int y = room.Position.Y; y < room.Position.Y + room.Size.Y; y++)
			{
				for (int x = room.Position.X; x < room.Position.X + room.Size.X; x++)
				{
					var cell = new Vector2I(x, y);

					if (IsCellAvailable(cell))
					{
						candidates.Add(cell);
					}
				}
			}
		}

		if (candidates.Count == 0)
		{
			return PickRandomAvailableCellInGrid();
		}

		return candidates[_rng.RandiRange(0, candidates.Count - 1)];
	}

	private Vector2I PickMonsterCell()
	{
		// 作业 2：怪物出生点远离入口（避免玩家一出生就撞怪被传送）
		List<Vector2I> candidates = new();

		foreach (Rect2I room in _rooms)
		{
			for (int y = room.Position.Y; y < room.Position.Y + room.Size.Y; y++)
			{
				for (int x = room.Position.X; x < room.Position.X + room.Size.X; x++)
				{
					var cell = new Vector2I(x, y);

					if (!IsCellAvailable(cell))
					{
						continue;
					}

					if (EntranceCell.DistanceSquaredTo(cell) <= MonsterMinDistanceSq)
					{
						continue;
					}

					candidates.Add(cell);
				}
			}
		}

		// 小地图/极端情况：达标格子耗尽时回退原逻辑，保证怪物仍能生成
		if (candidates.Count == 0)
		{
			return PickRandomAvailableCellInRooms();
		}

		return candidates[_rng.RandiRange(0, candidates.Count - 1)];
	}

	private Vector2I PickRandomAvailableCellInGrid()
	{
		List<Vector2I> candidates = new();

		for (int y = 0; y < MapHeight; y++)
		{
			for (int x = 0; x < MapWidth; x++)
			{
				var cell = new Vector2I(x, y);

				if (IsCellAvailable(cell))
				{
					candidates.Add(cell);
				}
			}
		}

		if (candidates.Count == 0)
		{
			return InvalidCell;
		}

		return candidates[_rng.RandiRange(0, candidates.Count - 1)];
	}

	// =========================
	// 第 4 课：POI 节点生成（Area2D + 像素素材）
	// =========================

	private void ClearDynamicEntities()
	{
		foreach (Node entity in _dynamicEntities)
		{
			if (GodotObject.IsInstanceValid(entity))
			{
				entity.QueueFree();
			}
		}

		_dynamicEntities.Clear();
	}

	private void SpawnPoiNodes()
	{
		if (_tileLayer == null)
		{
			return;
		}

		if (KeyCell != InvalidCell)
		{
			CreatePickupArea(
				KeyCell,
				"key",
				KeyTexture,
				0.35f
			);
		}

		foreach (Vector2I cell in TreasureCells)
		{
			CreatePickupArea(
				cell,
				"treasure",
				ChestTexture,
				0.30f
			);
		}

		foreach (Vector2I cell in MonsterCells)
		{
			SpawnMonsterAtCell(cell);
		}
	}

	private void CreatePickupArea(
		Vector2I cell,
		string pickupType,
		Texture2D texture,
		float radiusMultiplier
	) => CreatePoiAreaInternal(cell, texture, radiusMultiplier, pickupType);

	private Area2D CreatePoiAreaInternal(
		Vector2I cell,
		Texture2D texture,
		float radiusMultiplier,
		string group
	)
	{
		var area = new Area2D
		{
			Position = CellToCenterLocal(cell),
			Monitoring = true,
		};

		var collision = new CollisionShape2D();
		var circle = new CircleShape2D
		{
			Radius = CellSize * radiusMultiplier,
		};
		collision.Shape = circle;
		area.AddChild(collision);

		// 像素素材可视化（Sprite2D 默认居中，16x16 原尺寸 = 满格）
		var visual = new Sprite2D
		{
			Texture = texture,
		};
		area.AddChild(visual);

		area.AddToGroup(group);
		area.BodyEntered += body =>
		{
			if (!body.IsInGroup("player"))
			{
				return;
			}

			switch (group)
			{
				case "key":
					OnKeyBodyEntered(body, area);
					break;
				case "treasure":
					OnTreasureBodyEntered(body, area);
					break;
			}
		};

		_tileLayer.AddChild(area);
		_dynamicEntities.Add(area);

		return area;
	}

	private void SpawnMonsterAtCell(Vector2I cell)
	{
		// 第 5 课：实例化巡逻敌人（Setup 注入地图引用 + 巡逻路径）
		if (EnemyScene != null)
		{
			var enemy = EnemyScene.Instantiate<CharacterBody2D>();

			if (enemy is Enemy e)
			{
				AddChild(e);

				e.GlobalPosition = GetCellWorldPosition(cell);

				// 作业 3（第 6 课）：加权随机分配类型（60% 普通 / 25% 敏捷 / 15% 坦克）
				float roll = _rng.Randf();
				e.EnemyType = roll switch
				{
					< 0.60f => "normal",
					< 0.85f => "fast",
					_ => "tank",
				};

				e.Setup(this, MakePatrolPoints(cell));

				_dynamicEntities.Add(e);
				return;
			}
		}

		// 回退：未配置敌人场景时用旧版危险区（保底不断更）
		GD.PushWarning("EnemyScene 未设置，怪物回退为危险区。");
		CreateHazardArea(cell);
	}

	private void CreateHazardArea(Vector2I cell)
	{
		var area = new Area2D
		{
			Position = CellToCenterLocal(cell),
			Monitoring = true,
		};

		var collision = new CollisionShape2D();
		var circle = new CircleShape2D
		{
			Radius = CellSize * 0.40f,
		};
		collision.Shape = circle;
		area.AddChild(collision);

		var visual = new Sprite2D
		{
			Texture = MonsterTexture,
		};
		area.AddChild(visual);

		area.AddToGroup("monster");
		area.BodyEntered += (body) =>
		{
			if (body.IsInGroup("player"))
			{
				OnMonsterBodyEntered(body);
			}
		};

		_tileLayer.AddChild(area);
		_dynamicEntities.Add(area);
	}

	// =========================
	// 第 4 课：POI 触发逻辑
	// =========================

	private void OnKeyBodyEntered(Node2D body, Area2D area)
	{
		HasKey = true;

		GD.Print("拿到了钥匙！出口已解锁。");

		UpdateHud();
		UpdateExitLockVisual();
		RemoveEntity(area);
	}

	private void OnTreasureBodyEntered(Node2D body, Area2D area)
	{
		TreasureCount++;

		GD.Print("打开宝箱，当前宝箱数：", TreasureCount);

		UpdateHud();
		RemoveEntity(area);
	}

	private void OnMonsterBodyEntered(Node2D body)
	{
		// 第 5 课（5.8）：回退危险区也走 TakeDamage（掉血+击退+无敌）
		if (body is Player p)
		{
			p.TakeDamage(1, body.GlobalPosition);
		}
		else
		{
			GD.Print("碰到怪物！回到入口。");

			if (GodotObject.IsInstanceValid(_playerInstance))
			{
				_playerInstance.GlobalPosition = GetEntranceWorldPosition();
			}
		}
	}

	private void RemoveEntity(Node entity)
	{
		if (!GodotObject.IsInstanceValid(entity))
		{
			return;
		}

		_dynamicEntities.Remove(entity);

		// 踩坑：monitoring 属物理状态，物理回调中必须 SetDeferred
		if (entity is Area2D area)
		{
			area.SetDeferred(Area2D.PropertyName.Monitoring, false);
		}

		entity.QueueFree();
	}

	// =========================
	// 第 6 课：敌人死亡掉落（金币/药水）
	// =========================

	public void RemoveDynamicEntity(Node entity)
	{
		_dynamicEntities.Remove(entity);
	}

	public void OnEnemyDied(Node enemy, Vector2 deathPosition)
	{
		// 作业 4（第 6 课）：差异化掉落——按敌人类型决定掉率与掉落表
		RemoveDynamicEntity(enemy);

		float dropChance = EnemyDropChance;
		float potionChance = EnemyPotionChance;

		string etype = enemy.Get("enemy_type").ToString();
		switch (etype)
		{
			case "fast":
				// 敏捷怪：掉率低但必掉金币（跑得快击杀难，奖励集中）
				dropChance = 0.5f;
				potionChance = 0.0f;
				break;
			case "tank":
				// 坦克怪：必掉且高概率药水（硬仗厚奖）
				dropChance = 1.0f;
				potionChance = 0.6f;
				break;
		}

		if (_rng.Randf() < dropChance)
		{
			SpawnDropAtPosition(deathPosition, potionChance);
		}
	}

	private void SpawnDropAtPosition(Vector2 worldPosition, float potionChance = -1.0f)
	{
		// potionChance < 0 时用全局默认（保持文档版调用兼容）
		if (potionChance < 0.0f)
		{
			potionChance = EnemyPotionChance;
		}

		string dropType = _rng.Randf() < potionChance ? "potion" : "gold";

		CreateDropArea(dropType, worldPosition);
	}

	private void CreateDropArea(string dropType, Vector2 worldPosition)
	{
		var area = new Area2D
		{
			Monitoring = true,
			CollisionLayer = 0,
			CollisionMask = 1,
		};

		var collision = new CollisionShape2D
		{
			Shape = new CircleShape2D { Radius = CellSize * 0.25f },
		};
		area.AddChild(collision);

		// 像素素材可视化（金币/药水）+ 上下浮动（吸引注意："地上有东西"）
		var visual = new Sprite2D
		{
			Texture = dropType == "gold" ? GoldTexture : PotionTexture,
		};
		area.AddChild(visual);

		var tween = area.CreateTween().SetLoops();
		tween.TweenProperty(visual, "position:y", -1.5f, 0.5f).SetTrans(Tween.TransitionType.Sine);
		tween.TweenProperty(visual, "position:y", 0.0f, 0.5f).SetTrans(Tween.TransitionType.Sine);

		area.AddToGroup("drop");
		area.BodyEntered += body =>
		{
			if (!body.IsInGroup("player"))
			{
				return;
			}

			if (dropType == "gold")
			{
				GoldCount++;
				GD.Print("捡到金币，当前金币：", GoldCount);
				UpdateGoldHud();
			}
			else if (dropType == "potion")
			{
				if (body.HasMethod("heal"))
				{
					body.Call("heal", 1);
				}
				GD.Print("捡到药水并恢复生命。");
			}

			RemoveEntity(area);
		};

		AddChild(area);
		area.GlobalPosition = worldPosition;

		_dynamicEntities.Add(area);
	}

	private void UpdateGoldHud()
	{
		// 作业 5（第 6 课）：金币计数（跨层保留，只在拾取时刷新）
		if (_goldLabel != null)
		{
			_goldLabel.Text = $"金币：{GoldCount}";
			_goldLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.85f, 0.3f));
		}
	}

	// =========================
	// HUD
	// =========================

	private void UpdateHud(bool lockedHint = false)
	{
		// 作业 1：钥匙状态行
		if (_keyLabel == null)
		{
			return;
		}

		if (HasKey)
		{
			_keyLabel.Text = "钥匙：已获得 ✓ 出口已解锁";
			_keyLabel.AddThemeColorOverride("font_color", new Color(0.5f, 1.0f, 0.6f));
		}
		else if (lockedHint)
		{
			_keyLabel.Text = "出口被锁住了！去寻找金钥匙…";
			_keyLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.5f, 0.4f));
		}
		else
		{
			_keyLabel.Text = "钥匙：未获得（找金钥匙）";
			_keyLabel.AddThemeColorOverride("font_color", new Color(1.0f, 1.0f, 1.0f));
		}

		// 作业 1：宝箱计数行（已开 / 总数；宝箱拾取后不回收格子，总数稳定）
		if (_treasureLabel != null)
		{
			_treasureLabel.Text = $"宝箱：{TreasureCount}/{TreasureCells.Count}";
			_treasureLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.85f, 0.4f));
		}
	}

	// =========================
	// 玩家
	// =========================

	private void UpdateOrSpawnPlayer()
	{
		if (PlayerScene == null)
		{
			GD.PushWarning("没有在 Inspector 里设置 PlayerScene，请拖入 player.tscn。");
			return;
		}

		if (_playerInstance == null || !GodotObject.IsInstanceValid(_playerInstance))
		{
			_playerInstance = PlayerScene.Instantiate<Player>();

			if (_playerInstance == null)
			{
				GD.PushError("player.tscn 的根节点必须挂 Player.cs（CharacterBody2D）。");
				return;
			}

			_playerInstance.AddToGroup("player");
			AddChild(_playerInstance);
		}

		_playerInstance.GlobalPosition = GetEntranceWorldPosition();
		_playerInstance.Dungeon = this;

		// 第 5 课（5.7）：每层重置玩家生命/无敌/击退状态
		_playerInstance.ResetForNewLayer();
	}

	// =========================
	// 入口 / 出口标记（第 2 课作业 1+2 成果，保留）
	// =========================

	private void SpawnMarkers()
	{
		ClearMarkers();

		var entranceMarker = new Marker2D
		{
			Name = "EntranceMarker",
			Position = GetEntranceLocalPosition(),
		};
		AddChild(entranceMarker);

		var exitMarker = new Marker2D
		{
			Name = "ExitMarker",
			Position = GetExitLocalPosition(),
		};
		AddChild(exitMarker);
	}

	private void ClearMarkers()
	{
		foreach (Node child in GetChildren())
		{
			if (child is Marker2D)
			{
				// 先脱离树再延迟释放：防止同帧 spawn 的同名新节点被匿名化
				RemoveChild(child);
				child.QueueFree();
			}
		}
	}

	// =========================
	// 移动阻挡查询
	// =========================

	public Vector2 GetCellWorldPosition(Vector2I cell)
	{
		if (_tileLayer == null)
		{
			return CellToCenterLocal(cell);
		}

		return _tileLayer.ToGlobal(CellToCenterLocal(cell));
	}

	private Vector2[] MakePatrolPoints(Vector2I cell)
	{
		// 第 5 课改进：房间内多点环游巡逻（A→B→C→…→A）
		// 生成期消耗 _rng（同种子可复现）；位于 POI 选点之后，不影响地图/POI 统计
		List<Vector2> points = new();

		Rect2I room = FindRoomContainingCell(cell);

		if (room.Size != Vector2I.Zero)
		{
			List<Vector2I> candidates = new();

			for (int y = room.Position.Y; y < room.Position.Y + room.Size.Y; y++)
			{
				for (int x = room.Position.X; x < room.Position.X + room.Size.X; x++)
				{
					var c = new Vector2I(x, y);
					if (c != cell && IsCellAvailable(c))
					{
						candidates.Add(c);
					}
				}
			}

			List<Vector2I> ring = new();

			Vector2I centerCell = RoomCenter(room);
			if (centerCell != cell && IsCellAvailable(centerCell))
			{
				ring.Add(centerCell);
			}

			int extra = Mathf.Clamp(candidates.Count / 4, 2, 3);
			for (int i = 0; i < extra && candidates.Count > 0; i++)
			{
				int idx = _rng.RandiRange(0, candidates.Count - 1);
				Vector2I pick = candidates[idx];
				candidates.RemoveAt(idx);
				if (!ring.Contains(pick))
				{
					ring.Add(pick);
				}
			}

			if (ring.Count > 0)
			{
				// Fisher-Yates with _rng（Array.shuffle 走全局 RNG 不受种子控制）
				for (int i = ring.Count - 1; i > 0; i--)
				{
					int j = _rng.RandiRange(0, i);
					(ring[i], ring[j]) = (ring[j], ring[i]);
				}

				points.Add(GetCellWorldPosition(cell));
				foreach (Vector2I rc in ring)
				{
					points.Add(GetCellWorldPosition(rc));
				}
				return points.ToArray();
			}
		}

		// 不在房间/候选为空：沿上下左右找可走方向做短距离巡逻
		Vector2I[] directions =
		{
			new(1, 0), new(-1, 0), new(0, 1), new(0, -1),
		};

		foreach (Vector2I dir in directions)
		{
			Vector2I[] forward = ScanWalkableCells(cell, dir, 5);

			if (forward.Length > 0)
			{
				points.Add(GetCellWorldPosition(cell));
				points.Add(GetCellWorldPosition(forward[^1]));
				return points.ToArray();
			}

			Vector2I[] backward = ScanWalkableCells(cell, -dir, 5);

			if (backward.Length > 0)
			{
				points.Add(GetCellWorldPosition(cell));
				points.Add(GetCellWorldPosition(backward[^1]));
				return points.ToArray();
			}
		}

		// 实在找不到巡逻路径，就原地站立
		points.Add(GetCellWorldPosition(cell));
		return points.ToArray();
	}

	private Rect2I FindRoomContainingCell(Vector2I cell)
	{
		foreach (Rect2I room in _rooms)
		{
			if (RoomHasCell(room, cell))
			{
				return room;
			}
		}

		return default;
	}

	private static bool RoomHasCell(Rect2I room, Vector2I cell)
	{
		return cell.X >= room.Position.X
			&& cell.X < room.Position.X + room.Size.X
			&& cell.Y >= room.Position.Y
			&& cell.Y < room.Position.Y + room.Size.Y;
	}

	private Vector2I[] ScanWalkableCells(Vector2I fromCell, Vector2I dir, int maxSteps)
	{
		List<Vector2I> result = new();

		Vector2I cell = fromCell + dir;

		for (int i = 0; i < maxSteps; i++)
		{
			if (IsCellWalkable(cell))
			{
				result.Add(cell);
				cell += dir;
			}
			else
			{
				break;
			}
		}

		return result.ToArray();
	}

	public void RespawnPlayer()
	{
		// 第 5 课：玩家死亡后重生到入口（轻惩罚版，保留）
		if (GodotObject.IsInstanceValid(_playerInstance))
		{
			_playerInstance.GlobalPosition = GetEntranceWorldPosition();
		}
	}

	public void ResetCurrentLayer()
	{
		// 作业 5（第 5 课）：死亡重置本层——钥匙/宝箱/怪物全部复原重来
		GD.Print("本层已重置！钥匙宝箱怪物全部复原。");
		Generate();
	}

	public void UpdateHealthUi(int current, int maxValue)
	{
		// 作业 1（第 5 课）：按当前生命点亮/熄灭心形
		if (_healthUi == null)
		{
			return;
		}

		for (int i = 0; i < _healthUi.GetChildCount(); i++)
		{
			if (_healthUi.GetChildOrNull<TextureRect>(i) is { } heart)
			{
				heart.Texture = i < current ? HeartFullTexture : HeartEmptyTexture;
			}
		}
	}

	public bool IsWorldPositionWalkable(Vector2 worldPosition, float radius = 0.0f)
	{
		if (_grid.Length == 0)
		{
			return false;
		}

		if (radius <= 0.0f)
		{
			return IsWorldPointWalkable(worldPosition);
		}

		// 简单采样：中心 + 四个方向
		Vector2[] offsets =
		{
			Vector2.Zero,
			new(radius, 0.0f),
			new(-radius, 0.0f),
			new(0.0f, radius),
			new(0.0f, -radius),
		};

		foreach (Vector2 offset in offsets)
		{
			if (!IsWorldPointWalkable(worldPosition + offset))
			{
				return false;
			}
		}

		return true;
	}

	private bool IsWorldPointWalkable(Vector2 worldPosition)
	{
		if (_tileLayer == null)
		{
			return false;
		}

		Vector2 localPosition = _tileLayer.ToLocal(worldPosition);

		var cell = new Vector2I(
			Mathf.FloorToInt(localPosition.X / CellSize),
			Mathf.FloorToInt(localPosition.Y / CellSize)
		);

		return IsCellWalkable(cell);
	}

	public bool IsCellWalkable(Vector2I cell)
	{
		if (cell.X < 0 || cell.X >= MapWidth)
		{
			return false;
		}
		if (cell.Y < 0 || cell.Y >= MapHeight)
		{
			return false;
		}

		return _grid[cell.Y, cell.X] == CellFloor;
	}

	// =========================
	// Camera
	// =========================

	private void CenterCamera()
	{
		// 作业 2 后：相机职责已转移给 Player 自带的 Camera2D（跟随玩家）。
		// Main 场景已无 Camera2D 节点，此函数查找返回 null 自动跳过，保留以兼容旧场景。
		var cam = GetNodeOrNull<Camera2D>("%Camera2D");
		if (cam == null)
		{
			return;
		}

		cam.MakeCurrent();
		cam.Position = new Vector2(
			MapWidth * CellSize * 0.5f,
			MapHeight * CellSize * 0.5f
		);
	}
}
