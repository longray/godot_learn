using Godot;
using System.Collections.Generic;

namespace RpgDungeon;

// =========================
// 第 3 课：连通性验证、玩家出生点、简单移动、出口触发（C# 版）
// 在第 2 课基础上新增：A* 可达性验证与自动修复、玩家、网格移动阻挡、出口 Area2D 触发
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

	[Export] public float ExitRadiusMultiplier { get; set; } = 0.45f;
	[Export] public bool DebugPrintPath { get; set; } = false;

	// ---------- 数据 ----------

	private const int CellWall = 0;
	private const int CellFloor = 1;

	private readonly RandomNumberGenerator _rng = new();

	// C# 强类型二维数组（对比 GDScript 嵌套 Array）
	private int[,] _grid = new int[0, 0];

	private readonly List<Rect2I> _rooms = new();

	public Vector2I EntranceCell { get; private set; }
	public Vector2I ExitCell { get; private set; }

	private AStarGrid2D _astarGrid = new();

	private Player _playerInstance;
	private Area2D _exitArea;

	// 作业 4：钥匙门状态
	private bool _hasKey;
	private Area2D _keyArea;

	// ---------- 节点 ----------

	private TileMapLayer _tileLayer;

	// 作业 3：路径可视化覆盖层（画在 TileMapLayer 之上）
	private PathOverlay _pathOverlay;

	// HUD 引用（场景里的 CanvasLayer > Label）
	private Label _keyLabel;

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

	public bool HasKey => _hasKey;

	// ---------- 生命周期 ----------

	public override void _Ready()
	{
		_tileLayer = GetNode<TileMapLayer>("TileMapLayer");
		_pathOverlay = GetNodeOrNull<PathOverlay>("PathOverlay");
		_keyLabel = GetNodeOrNull<Label>("HUD/KeyLabel");

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

		SetupRng();
		ClearMapData();
		PlaceRooms();
		ConnectRooms();
		BuildAStar();
		PickEntranceAndExit();
		EnsureExitReachable();

		SetupTilemap();
		BuildTilemap();

		UpdateOrSpawnExit();
		UpdateOrSpawnPlayer();
		SpawnMarkers();
		CenterCamera();

		// 作业 3：把最终的入口→出口路径交给覆盖层绘制（修复后的最新路径）
		_pathOverlay?.SetPath(ToArray(_astarGrid.GetIdPath(EntranceCell, ExitCell)), CellSize);

		// 作业 4：每层重新放钥匙 + 重置钥匙状态（放最后，避免影响既有 RNG 锚点）
		_hasKey = false;
		UpdateOrSpawnKey();
		UpdateHud();

		if (DebugPrintPath)
		{
			GD.Print("入口：", EntranceCell, "  出口：", ExitCell);
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

		// 第 1 课作业 5 成果：增量式最近邻连接（文档此处为旧版链式，按仓库现状保留本版）
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
			// （第 3 课文档改进：候选列表法，保证与入口不同）
			ExitCell = PickRandomFloorCellInRoom(_rooms[0], EntranceCell);
		}
		else
		{
			// 第 2 课作业 4 成果：出口 = 从入口出发「实际路径」最长的房间中心
			// （文档此处为直线最远版，按仓库现状保留 A* 版；astar 已在 Generate 流程中先行构建）
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
			// 第 2 课方案 B：尊重手工配置的 TileSet，脚本不碰 tile_set
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
		// 第 2 课方案 A：优先加载外部图集，文件缺失则回退代码生成
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

			_tileLayer.AddChild(_exitArea);
		}
		else
		{
			if (_exitArea.GetChild(0) is CollisionShape2D collision
				&& collision.Shape is CircleShape2D circle)
			{
				circle.Radius = CellSize * ExitRadiusMultiplier;
			}
		}

		_exitArea.Position = GetExitLocalPosition();
	}

	private void OnExitBodyEntered(Node2D body)
	{
		if (body.IsInGroup("player"))
		{
			// 作业 4：门控——没钥匙进不了出口
			if (!_hasKey)
			{
				GD.Print("出口被锁住了，需要钥匙！");
				UpdateHud(true);
				return;
			}

			GD.Print("玩家到达出口，重新生成地牢。");
			// 物理回调中不能直接改场景树，延迟到帧末安全执行
			CallDeferred(MethodName.Generate);
		}
	}

	// =========================
	// 钥匙（作业 4）
	// =========================

	private void UpdateOrSpawnKey()
	{
		if (_tileLayer == null)
		{
			return;
		}

		// 删旧钥匙（RemoveChild 先解除树，防同帧匿名坑）
		if (_keyArea != null && GodotObject.IsInstanceValid(_keyArea))
		{
			_tileLayer.RemoveChild(_keyArea);
			_keyArea.QueueFree();
		}

		Vector2I keyCell = PickKeyCell();

		_keyArea = new Area2D
		{
			Name = "KeyArea",
			Monitoring = true,
		};

		var collision = new CollisionShape2D();
		var circle = new CircleShape2D
		{
			Radius = CellSize * 0.45f,
		};
		collision.Shape = circle;
		_keyArea.AddChild(collision);

		// 金色菱形可视化（比玩家小一号）
		var visual = new Polygon2D
		{
			Polygon = new Vector2[]
			{
				new(0, -6), new(5, 0), new(0, 6), new(-5, 0)
			},
			Color = new Color(1.0f, 0.8f, 0.0f),
		};
		_keyArea.AddChild(visual);

		_keyArea.BodyEntered += OnKeyBodyEntered;

		_tileLayer.AddChild(_keyArea);
		_keyArea.Position = CellToCenterLocal(keyCell);
	}

	private Vector2I PickKeyCell()
	{
		// 钥匙优先放「既非入口也非出口」的房间 → 强制玩家绕支路探索
		if (_rooms.Count == 0)
		{
			return EntranceCell;
		}

		// 找出口所在房间
		int exitRoomIdx = -1;
		for (int i = 0; i < _rooms.Count; i++)
		{
			if (RoomCenter(_rooms[i]) == ExitCell)
			{
				exitRoomIdx = i;
				break;
			}
		}

		// 候选：非入口(0)、非出口的房间
		List<int> candidates = new();
		for (int i = 1; i < _rooms.Count; i++)
		{
			if (i != exitRoomIdx)
			{
				candidates.Add(i);
			}
		}

		if (candidates.Count == 0)
		{
			// 只有入口+出口两个房间：钥匙放出口房间内（避开出口格）
			if (exitRoomIdx >= 0)
			{
				return PickRandomFloorCellInRoom(_rooms[exitRoomIdx], ExitCell);
			}
			return PickRandomFloorCellInRoom(_rooms[0], EntranceCell);
		}

		int roomIdx = candidates[_rng.RandiRange(0, candidates.Count - 1)];
		return RoomCenter(_rooms[roomIdx]);
	}

	private void OnKeyBodyEntered(Node2D body)
	{
		if (body.IsInGroup("player") && !_hasKey)
		{
			_hasKey = true;
			GD.Print("获得钥匙！出口已解锁。");
			// 拾取后钥匙消失；monitoring 属物理状态，物理回调中必须 SetDeferred
			_keyArea.SetDeferred(Area2D.PropertyName.Monitoring, false);
			_keyArea.Visible = false;
			UpdateHud();
		}
	}

	private void UpdateHud(bool lockedHint = false)
	{
		if (_keyLabel == null)
		{
			return;
		}

		if (_hasKey)
		{
			_keyLabel.Text = "钥匙：已获得 ✓ 出口已解锁";
			_keyLabel.AddThemeColorOverride("font_color", new Color(0.5f, 1.0f, 0.6f));
		}
		else if (lockedHint)
		{
			_keyLabel.Text = "出口被锁住了！去寻找金色钥匙…";
			_keyLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.5f, 0.4f));
		}
		else
		{
			_keyLabel.Text = "钥匙：未获得（找金色菱形）";
			_keyLabel.AddThemeColorOverride("font_color", new Color(1.0f, 1.0f, 1.0f));
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
