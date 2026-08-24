using Godot;
using System.Collections.Generic;

namespace RpgDungeon;

// =========================
// 第 1 课：小规模 2D 地牢（C# 版）
// 与 GDScript 版算法逐行对应，同种子应产出相同地图
// =========================
public partial class DungeonDebug : Node2D
{
	// 地图参数（C# 用 PascalCase 属性 + [Export]，Inspector 名称即属性名）
	[Export] public int SeedValue { get; set; } = 20260824;
	[Export] public bool UseRandomSeed { get; set; } = false;

	[Export] public int MapWidth { get; set; } = 48;
	[Export] public int MapHeight { get; set; } = 32;

	// 房间参数
	[Export] public int RoomAttempts { get; set; } = 60;
	[Export] public int MaxRooms { get; set; } = 10;

	[Export] public Vector2I MinRoomSize { get; set; } = new(4, 3);
	[Export] public Vector2I MaxRoomSize { get; set; } = new(10, 7);

	// 显示参数
	[Export] public int CellSize { get; set; } = 16;

	// 地图数据：0=墙 1=地板
	// C# 用强类型二维数组（对比 GDScript 的弱类型 Array）
	// 注意：int[,] 无法与 GDScript 互操作（Variant 只编组一维数组）
	private int[,] _grid = new int[0, 0];

	// 房间列表：后续放怪物、宝箱、入口、出口
	private readonly List<Rect2I> _rooms = new();

	private readonly RandomNumberGenerator _rng = new();

	// 封装：C# 惯例不暴露字段，按需提供只读访问器（也供测试/互操作用）
	public int RoomCount => _rooms.Count;

	public int FloorCellCount
	{
		get
		{
			int count = 0;
			foreach (int v in _grid)
			{
				if (v == 1)
				{
					count++;
				}
			}
			return count;
		}
	}

	public override void _Ready()
	{
		Generate();
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		// C# 属性模式匹配：一行完成 GDScript 版的 as + null 检查 + 三条件判断
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
		CenterCamera();

		QueueRedraw();
	}

	private void SetupRng()
	{
		if (UseRandomSeed)
		{
			_rng.Randomize();
		}
		else
		{
			_rng.Seed = (ulong)SeedValue; // C# 的 Seed 是 ulong（GDScript 是 int，值域等价）
		}
	}

	private void ClearMap()
	{
		_rooms.Clear();
		// C# 二维数组创建时自动填 0（墙），无需像 GDScript 版手动 fill(0)
		_grid = new int[MapHeight, MapWidth];
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
			return default; // default(Rect2I) = 位置(0,0) 尺寸(0,0)，等价 GDScript 的 Rect2i()
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
		// 向外扩一格，让房间之间保留一点间距
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
				SetCell(x, y, 1);
			}
		}
	}

	private void ConnectRooms()
	{
		if (_rooms.Count < 2)
		{
			return;
		}

		// 作业 5：增量式最近邻连接（与 GDScript 版算法一致）
		// 每个新房间只连到「已入住房间」中离它最近的一个
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
		// 整数除法：C# 编译器不警告（GDScript 会警告，行为一致）
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
			SetCell(x, y, 1);
		}
	}

	private void CarveVCorridor(int y1, int y2, int x)
	{
		int from = Mathf.Min(y1, y2);
		int to = Mathf.Max(y1, y2);

		for (int y = from; y <= to; y++)
		{
			SetCell(x, y, 1);
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

		_grid[y, x] = value; // C# 二维数组语法 [y, x]（GDScript 是嵌套数组 [y][x]）
	}

	private void CenterCamera()
	{
		var cam = GetNodeOrNull<Camera2D>("%Camera2D");
		if (cam != null)
		{
			cam.MakeCurrent();
			cam.Position = new Vector2(
				MapWidth * CellSize * 0.5f,
				MapHeight * CellSize * 0.5f
			);
		}
	}

	public override void _Draw()
	{
		if (_grid.Length == 0)
		{
			return;
		}

		// 画格子
		for (int y = 0; y < MapHeight; y++)
		{
			for (int x = 0; x < MapWidth; x++)
			{
				var rect = new Rect2(
					x * CellSize,
					y * CellSize,
					CellSize,
					CellSize
				);

				var color = _grid[y, x] == 1
					? new Color(0.82f, 0.75f, 0.60f)
					: new Color(0.08f, 0.08f, 0.10f);

				DrawRect(rect, color);
			}
		}

		// 画房间边框，方便观察房间分布
		foreach (Rect2I room in _rooms)
		{
			var rect = new Rect2(
				room.Position.X * CellSize,
				room.Position.Y * CellSize,
				room.Size.X * CellSize,
				room.Size.Y * CellSize
			);

			DrawRect(rect, new Color(0.2f, 1.0f, 0.5f, 0.25f), filled: false, width: 2.0f);
		}

		// 作业 3：给每个房间中心画红色小圆点
		foreach (Rect2I room in _rooms)
		{
			Vector2I center = RoomCenter(room);
			var pos = new Vector2(
				center.X * CellSize + CellSize * 0.5f,
				center.Y * CellSize + CellSize * 0.5f
			);
			DrawCircle(pos, 3.0f, new Color(1.0f, 0.3f, 0.3f));
		}

		// 作业 4：显示房间编号（基线锚点：y +4 ≈ 半字形高垂直居中；x +4 紧贴圆右侧）
		Font font = ThemeDB.FallbackFont;
		for (int i = 0; i < _rooms.Count; i++)
		{
			Vector2I center = RoomCenter(_rooms[i]);
			var pos = new Vector2(
				center.X * CellSize + CellSize * 0.5f + 4.0f,
				center.Y * CellSize + CellSize * 0.5f + 4.0f
			);
			DrawString(font, pos, $"{i + 1}", HorizontalAlignment.Left, -1.0f, 10, new Color(0f, 0f, 0f));
		}
	}
}
