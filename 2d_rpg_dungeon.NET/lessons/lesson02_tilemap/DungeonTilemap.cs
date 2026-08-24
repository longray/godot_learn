using Godot;
using System.Collections.Generic;

namespace RpgDungeon;

// =========================
// 第 2 课：接入 TileMapLayer 和入口/出口（C# 版）
// 与 GDScript 版算法逐行对应，同种子应产出相同地图
// =========================
public partial class DungeonTilemap : Node2D
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

	// 如果为 true，脚本会自动创建一个临时 TileSet（学习用，无需美术资源）
	[Export] public bool UsePlaceholderTileset { get; set; } = true;

	// 作业 5 方案 B：尊重手工配置的 TileSet，跳过脚本装配逻辑
	[Export] public bool UseExternalTiles { get; set; } = false;

	// 作业 5 方案 A：外部图集路径（存在则优先加载，否则回退纯色生成）
	[Export] public string ExternalTilesPath { get; set; } = "res://assets/tiles/dungeon_tiles.png";

	[Export] public int TileSourceId { get; set; } = 0;

	[Export] public Vector2I FloorAtlasCoords { get; set; } = new(0, 0);
	[Export] public Vector2I WallAtlasCoords { get; set; } = new(1, 0);
	[Export] public Vector2I EntranceAtlasCoords { get; set; } = new(2, 0);
	[Export] public Vector2I ExitAtlasCoords { get; set; } = new(3, 0);

	// ---------- 数据 ----------

	private const int CellWall = 0;
	private const int CellFloor = 1;

	private readonly RandomNumberGenerator _rng = new();

	// C# 强类型二维数组（对比 GDScript 嵌套 Array）
	private int[,] _grid = new int[0, 0];

	private readonly List<Rect2I> _rooms = new();

	public Vector2I EntranceCell { get; private set; }
	public Vector2I ExitCell { get; private set; }

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

	// ---------- 生命周期 ----------

	public override void _Ready()
	{
		TileLayer = GetNode<TileMapLayer>("TileMapLayer");
		if (TileLayer == null)
		{
			GD.PushError("找不到 TileMapLayer，请确认场景里有名为 TileMapLayer 的子节点。");
			return;
		}

		Generate();
	}

	// GDScript 的 @onready var tile_layer —— C# 惯例放 _Ready 里赋值，这里保留字段便于测试直接注入
	private TileMapLayer TileLayer { get; set; }

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
		ClearMap();
		PlaceRooms();
		ConnectRooms();
		PickEntranceAndExit();

		SetupTilemap();
		BuildTilemap();

		CenterCamera();
		SpawnMarkers();
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

	private void ClearMap()
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

		// 作业 5 成果：增量式最近邻连接
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
			// 如果参数太严格导致没有房间，做一个保底地板点
			EntranceCell = new Vector2I(MapWidth / 2, MapHeight / 2);
			ExitCell = EntranceCell;
			SetCell(EntranceCell.X, EntranceCell.Y, CellFloor);
			return;
		}

		// 作业 3：单房间时在房间内随机选两个不同格子
		if (_rooms.Count == 1)
		{
			Rect2I room = _rooms[0];
			EntranceCell = RandomCellInRoom(room);
			ExitCell = RandomCellInRoom(room);
			int retries = 0;
			while (ExitCell == EntranceCell && retries < 8)
			{
				ExitCell = RandomCellInRoom(room);
				retries++;
			}
			return;
		}

		// 入口：第一个房间中心
		EntranceCell = RoomCenter(_rooms[0]);

		// 作业 4：出口 = 从入口出发「实际路径」最长的房间中心（AStarGrid2D）
		AStarGrid2D astar = BuildAStarGrid();

		ExitCell = EntranceCell;
		int bestPathLen = -1;

		foreach (Rect2I room in _rooms)
		{
			Vector2I center = RoomCenter(room);
			int pathLen = astar.GetIdPath(EntranceCell, center).Count;

			if (pathLen > bestPathLen)
			{
				bestPathLen = pathLen;
				ExitCell = center;
			}
		}
	}

	private Vector2I RandomCellInRoom(Rect2I room)
	{
		return new Vector2I(
			_rng.RandiRange(room.Position.X, room.Position.X + room.Size.X - 1),
			_rng.RandiRange(room.Position.Y, room.Position.Y + room.Size.Y - 1)
		);
	}

	private AStarGrid2D BuildAStarGrid()
	{
		// 用 grid 数据构建寻路网格：默认全墙，地板格才可通行
		var astar = new AStarGrid2D
		{
			Region = new Rect2I(0, 0, MapWidth, MapHeight),
			CellSize = new Vector2I(1, 1),
			DiagonalMode = AStarGrid2D.DiagonalModeEnum.Never,
		};
		astar.Update();

		astar.FillSolidRegion(astar.Region, true);

		for (int y = 0; y < MapHeight; y++)
		{
			for (int x = 0; x < MapWidth; x++)
			{
				if (_grid[y, x] == CellFloor)
				{
					astar.SetPointSolid(new Vector2I(x, y), false);
				}
			}
		}

		return astar;
	}

	public Vector2 GetEntranceLocalPosition()
	{
		return CellToCenterLocal(EntranceCell);
	}

	public Vector2 GetExitLocalPosition()
	{
		return CellToCenterLocal(ExitCell);
	}

	private Vector2 CellToCenterLocal(Vector2I cell)
	{
		return new Vector2(cell.X, cell.Y) * CellSize + new Vector2(CellSize, CellSize) * 0.5f;
	}

	// =========================
	// TileMap
	// =========================

	private void SetupTilemap()
	{
		if (UseExternalTiles)
		{
			// 方案 B：尊重手工配置的 TileSet，脚本不碰 tile_set
			if (TileLayer.TileSet == null)
			{
				GD.PushWarning("use_external_tiles 开着，但 TileMapLayer 上没有手工 TileSet。");
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
			if (TileLayer.TileSet == null)
			{
				GD.PushWarning("你关闭了 use_placeholder_tileset，但 TileMapLayer 上没有设置 TileSet。");
			}
		}
	}

	private int CreatePlaceholderTileset()
	{
		// 作业 5 方案 A：优先加载外部图集，文件缺失则回退代码生成
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

		TileLayer.TileSet = tileSet;

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
		if (TileLayer == null)
		{
			return;
		}

		if (TileSourceId < 0)
		{
			GD.PushError("tile_source_id 无效，无法写入 TileMapLayer。");
			return;
		}

		TileLayer.Clear();

		// 先写入整个地图
		for (int y = 0; y < MapHeight; y++)
		{
			for (int x = 0; x < MapWidth; x++)
			{
				Vector2I atlasCoords = _grid[y, x] == CellFloor
					? FloorAtlasCoords
					: WallAtlasCoords;

				TileLayer.SetCell(new Vector2I(x, y), TileSourceId, atlasCoords);
			}
		}

		// 最后覆盖入口和出口
		TileLayer.SetCell(EntranceCell, TileSourceId, EntranceAtlasCoords);
		TileLayer.SetCell(ExitCell, TileSourceId, ExitAtlasCoords);
	}

	// =========================
	// 入口 / 出口标记（作业 1+2）
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
				// 先脱离树再延迟释放：RemoveChild 立即解除名字占用，防同帧同名匿名化
				RemoveChild(child);
				child.QueueFree();
			}
		}
	}

	// =========================
	// Camera
	// =========================

	private void CenterCamera()
	{
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
