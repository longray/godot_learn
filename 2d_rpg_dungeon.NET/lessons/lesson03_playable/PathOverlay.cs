using Godot;

namespace RpgDungeon;

// =========================
// 作业 3：A* 路径可视化覆盖层（C# 版）
// 由 Main 在 Generate() 末尾喂数据；树序在 TileMapLayer 之后，画在瓦片之上
// =========================
public partial class PathOverlay : Node2D
{
	private Vector2I[] _pathCells = System.Array.Empty<Vector2I>();
	private int _cellSize = 16;

	private static readonly Color LineColor = new(1.0f, 0.6f, 0.1f, 0.85f);

	public void SetPath(Vector2I[] cells, int size)
	{
		_pathCells = cells;
		_cellSize = size;
		QueueRedraw();
	}

	public override void _Draw()
	{
		if (_pathCells.Length < 2)
		{
			return;
		}

		// 格子坐标 → 像素中心（与 Marker/玩家同一换算）
		Vector2[] points = new Vector2[_pathCells.Length];
		for (int i = 0; i < _pathCells.Length; i++)
		{
			Vector2I cell = _pathCells[i];
			points[i] = new Vector2(cell.X, cell.Y) * _cellSize
				+ new Vector2(_cellSize, _cellSize) * 0.5f;
		}

		// 路径折线
		DrawPolyline(points, LineColor, 2.0f);

		// 起点（入口）绿圈 / 终点（出口）红圈
		DrawCircle(points[0], 4.0f, new Color(0.2f, 0.9f, 0.4f));
		DrawCircle(points[^1], 4.0f, new Color(0.9f, 0.25f, 0.25f));
	}
}
