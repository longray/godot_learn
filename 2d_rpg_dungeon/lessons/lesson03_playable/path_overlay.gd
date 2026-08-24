extends Node2D

# =========================
# 作业 3：A* 路径可视化覆盖层
# 由 Main 在 generate() 末尾喂数据；树序在 TileMapLayer 之后，画在瓦片之上
# =========================

var path_cells: Array = []
var cell_size: int = 16

var line_color := Color(1.0, 0.6, 0.1, 0.85)


func set_path(cells: Array, size: int) -> void:
	path_cells = cells
	cell_size = size
	queue_redraw()


func _draw() -> void:
	if path_cells.size() < 2:
		return

	# 格子坐标 → 像素中心（与 Marker/玩家同一换算）
	var points := PackedVector2Array()
	for cell in path_cells:
		points.append(Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5)

	# 路径折线
	draw_polyline(points, line_color, 2.0)

	# 起点（入口）绿圈 / 终点（出口）红圈
	draw_circle(points[0], 4.0, Color(0.2, 0.9, 0.4))
	draw_circle(points[points.size() - 1], 4.0, Color(0.9, 0.25, 0.25))
