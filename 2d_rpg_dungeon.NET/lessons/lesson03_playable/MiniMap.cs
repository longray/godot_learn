using Godot;
using System.Collections.Generic;

namespace RpgDungeon;

// =========================
// 第 9 课方案 C：走廊段数据（DungeonPlayable 收集，MiniMap 消费）
// =========================
public sealed record CorridorSegment(IReadOnlyList<Vector2I> Cells, int RoomA, int RoomB);

// =========================
// 第 9 课：简单地牢小地图（C# 版）
// 纯 _Draw() 绘制（方块/圆点/边框/编号），零图片资源；
// 数据全部由 Main 推送（Setup + UpdateState），自身不查游戏状态
// 作业 2/3/4：钥匙房探索门槛 + 房间编号 + 类型配色
// =========================
public partial class MiniMap : Control
{
	// 作业 4：房间类型（Main 构建类型表用同一组常量；优先级 入口>出口>宝箱>怪物>普通）
	public const int RoomNormal = 0;
	public const int RoomTreasure = 1;
	public const int RoomMonster = 2;
	public const int RoomEntrance = 3;
	public const int RoomExit = 4;

	// 作业 3：房间编号字号（180x130 小地图上房间块约 20px，9px 恰好）
	private const int NumberFontSize = 9;

	// 迷雾判定用（-1 = 不在任何房间）
	private static readonly Vector2I InvalidCell = new(-1, -1);

	[Export] public Vector2 MapDisplaySize { get; set; } = new(180, 130);
	[Export] public float Margin { get; set; } = 12.0f;

	// 打开后小地图显示钥匙位置（默认关闭——探索型地牢保持迷雾）
	[Export] public bool ShowKey { get; set; } = false;

	private int _mapWidth = 1;
	private int _mapHeight = 1;

	private IReadOnlyList<Rect2I> _rooms = new List<Rect2I>();
	private IReadOnlyList<CorridorSegment> _corridors = new List<CorridorSegment>();
	private int[] _roomTypes = System.Array.Empty<int>();

	private HashSet<int> _exploredRooms = new();
	private int _currentRoomIndex = -1;

	private Vector2I _entranceCell = InvalidCell;
	private Vector2I _exitCell = InvalidCell;
	private Vector2I _keyCell = InvalidCell;
	private bool _hasKey;

	// 作业 1/2：出口/钥匙所在房间索引（探索过才画点）
	private int _exitRoomIndex = -1;
	private int _keyRoomIndex = -1;

	public override void _Ready()
	{
		// UI 不应该挡住鼠标输入（攻击点击会落在小地图区域上）
		MouseFilter = MouseFilterEnum.Ignore;

		Layout();
	}

	private void Layout()
	{
		// 固定在屏幕右上角（CanvasLayer 下不随相机移动）
		Vector2 viewportSize = GetViewportRect().Size;

		Size = MapDisplaySize;
		Position = new Vector2(viewportSize.X - Size.X - Margin, Margin);
	}

	public void Setup(int worldWidth, int worldHeight, IReadOnlyList<Rect2I> roomData,
		IReadOnlyList<CorridorSegment> corridorData, int[] typeData)
	{
		// Generate() 末尾调用：注入世界尺寸、房间矩形、走廊数据与类型表
		_mapWidth = Mathf.Max(1, worldWidth);
		_mapHeight = Mathf.Max(1, worldHeight);

		_rooms = roomData;
		_corridors = corridorData;
		_roomTypes = typeData ?? System.Array.Empty<int>();

		QueueRedraw();
	}

	public void UpdateState(HashSet<int> explored, int currentIndex, Vector2I entrance, Vector2I exitC,
		bool keyOwned, Vector2I keyPos, int exitRoomIdx = -1, int keyRoomIdx = -1)
	{
		// Main 每次房间变化/钥匙拾取时推送最新状态
		_exploredRooms = explored;
		_currentRoomIndex = currentIndex;
		_entranceCell = entrance;
		_exitCell = exitC;
		_hasKey = keyOwned;
		_keyCell = keyPos;
		_exitRoomIndex = exitRoomIdx;
		_keyRoomIndex = keyRoomIdx;

		QueueRedraw();
	}

	public override void _Draw()
	{
		// 背景 + 边框
		DrawRect(new Rect2(Vector2.Zero, Size), new Color(0.04f, 0.04f, 0.07f, 0.65f));
		DrawRect(new Rect2(Vector2.Zero, Size), new Color(1.0f, 1.0f, 1.0f, 0.18f), false, 1.0f);

		if (_rooms.Count == 0 || _mapWidth <= 0 || _mapHeight <= 0)
		{
			return;
		}

		// 世界格子 → 小地图像素的缩放
		Vector2 scale = Size / new Vector2(_mapWidth, _mapHeight);

		// 方案 C：画走廊（先画，房间块覆盖在其上形成层次；两端任一探索过整条点亮）
		foreach (CorridorSegment corridor in _corridors)
		{
			if (!(_exploredRooms.Contains(corridor.RoomA) || _exploredRooms.Contains(corridor.RoomB)))
			{
				continue;
			}

			foreach (Vector2I cell in corridor.Cells)
			{
				DrawRect(
					new Rect2(new Vector2(cell.X, cell.Y) * scale, scale),
					new Color(0.35f, 0.35f, 0.42f, 0.85f));
			}
		}

		// 画已探索房间（未探索的不画——迷雾）
		for (int i = 0; i < _rooms.Count; i++)
		{
			if (!_exploredRooms.Contains(i))
			{
				continue;
			}

			Rect2I room = _rooms[i];
			var rect = new Rect2(new Vector2(room.Position.X, room.Position.Y) * scale,
				new Vector2(room.Size.X, room.Size.Y) * scale);

			// 作业 4：类型配色；当前房间提亮 + 黄框
			bool isCurrent = i == _currentRoomIndex;
			DrawRect(rect, RoomColor(RoomTypeAt(i), isCurrent));

			// 作业 3：房间编号（白字黑描边，任意底色可读；水平垂直居中）
			Vector2 center = rect.Position + rect.Size * 0.5f;
			string text = (i + 1).ToString();
			var textPos = new Vector2(rect.Position.X, center.Y + NumberFontSize * 0.36f);
			Font font = ThemeDB.FallbackFont;
			DrawStringOutline(font, textPos, text, HorizontalAlignment.Center,
				rect.Size.X, NumberFontSize, 2, new Color(0, 0, 0, 0.85f));
			DrawString(font, textPos, text, HorizontalAlignment.Center,
				rect.Size.X, NumberFontSize, new Color(1, 1, 1, 0.92f));

			if (isCurrent)
			{
				DrawRect(rect, new Color(1.0f, 0.9f, 0.3f, 0.9f), false, 1.5f);
			}
		}

		// 入口（绿点）
		if (_entranceCell != InvalidCell)
		{
			DrawCircle(CellToMinimapPosition(_entranceCell, scale), 3.0f, new Color(0.2f, 0.9f, 0.4f));
		}

		// 出口（红点；作业 1：探索过出口房间才显示）
		if (_exitCell != InvalidCell && _exploredRooms.Contains(_exitRoomIndex))
		{
			DrawCircle(CellToMinimapPosition(_exitCell, scale), 3.0f, new Color(0.9f, 0.25f, 0.25f));
		}

		// 钥匙（黄点；作业 2：探索过钥匙房间才显示，拿到后消失）
		if (ShowKey && _keyCell != InvalidCell && !_hasKey && _exploredRooms.Contains(_keyRoomIndex))
		{
			DrawCircle(CellToMinimapPosition(_keyCell, scale), 3.0f, new Color(1.0f, 0.9f, 0.2f));
		}
	}

	private int RoomTypeAt(int index)
	{
		// 作业 4：类型表越界/未注入时按普通房处理
		return index >= 0 && index < _roomTypes.Length ? _roomTypes[index] : RoomNormal;
	}

	private static Color RoomColor(int roomType, bool isCurrent)
	{
		// 作业 4：类型配色；当前房间向白色 lerp 0.35 提亮（类型仍可辨）
		Color basis = roomType switch
		{
			RoomTreasure => new Color(0.82f, 0.58f, 0.28f, 0.92f),
			RoomMonster => new Color(0.58f, 0.40f, 0.75f, 0.92f),
			RoomEntrance => new Color(0.25f, 0.65f, 0.40f, 0.92f),
			RoomExit => new Color(0.72f, 0.30f, 0.30f, 0.92f),
			_ => new Color(0.45f, 0.45f, 0.52f, 0.9f),
		};

		return isCurrent ? basis.Lerp(Colors.White, 0.35f) : basis;
	}

	private static Vector2 CellToMinimapPosition(Vector2I cell, Vector2 scale)
	{
		// 格子中心（+0.5）映射到小地图像素
		return (new Vector2(cell.X, cell.Y) + new Vector2(0.5f, 0.5f)) * scale;
	}
}
