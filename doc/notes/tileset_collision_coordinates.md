# TileSet 碰撞多边形坐标系统

## 踩坑
物理碰撞模式下，碰撞体（青色线框）与视觉墙壁整体偏移约半个 tile，导致：
- 右下方向移动时穿墙
- 左上方向移动时被过度阻挡

## 根本原因
Godot 4 的 TileSet 碰撞多边形坐标**相对于 tile 中心**，而非左上角。

一个 16×16 的 tile：
- 左上角坐标：`(-8, -8)`
- 右下角坐标：`(8, 8)`
- 中心点：`(0, 0)`

## 错误配置
```
# 这是相对于左上角的坐标（错误）
1:0/0/physics_layer_0/polygon_0/points = PackedVector2Array(0, 0, 16, 0, 16, 16, 0, 16)
```

## 正确配置
```
# 这是相对于 tile 中心的坐标（正确）
1:0/0/physics_layer_0/polygon_0/points = PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)
```

## 修复文件
`assets/tiles/dungeon_tiles.tres`

## 参考
- [Bugnet Blog: Fix Godot TileMap Collision Shape Offset](https://bugnet.io/blog/fix-godot-tilemap-collision-shape-offset-wrong)
- Godot 官方文档未明确说明此坐标系统

## 教训
- 在 TileSet 编辑器中绘制碰撞多边形时，编辑器会自动处理坐标转换
- 但手写 `.tres` 文件时必须使用相对于 tile 中心的坐标
- 启用 **Debug > Visible Collision Shapes** 可快速验证碰撞体位置
