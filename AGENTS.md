# AGENTS.md — Godot 学习仓库

用**简体中文**交流与思考（思考也必须用中文，节省用户 token）。

## 仓库性质

Godot 4.7 程序化 RPG 地图生成的**学习仓库**（git 仓库，已推送 github.com/longray/godot_learn；无 pnpm/CI/测试框架——`D:\AGENTS.md` 的 TS 规则在此不适用）。

```text
doc/lession/          课程文档（用户逐课提供，先审核再执行）
2d_rpg_dungeon/       GDScript 项目（当前活跃，含 addons/godot_ai MCP 插件）
2d_rpg_dungeon.NET/   C# 版（**每课完成后立即同步重写**，非等大课程结束）
```

## 引擎（两套，勿混用）

- 默认：`D:\Godot_v4.7.1-stable`（GDScript 版）
- C# 同步重写用：`D:\Godot_v4.7.1-stable_mono`（对比双版本开发/调试体验）

## 核心约定

- **Godot 操作一律优先用 godot-ai MCP**（node/script/scene/project_run 等工具），用户强制要求；纯批量任务（如参数扫描）才用无头命令行
- 课程循环：审核文档 → 建文件 → 无头验证 → 用户运行确认 → 作业**一次只做 1~2 个**、展示 diff 讲解 → **一作业一提交**
- 每课 GDScript 版完成后，立即在 `.NET/` 用 C# 重写同课内容（增量迁移，避免大课程后一次性迁移的复杂度风险）
- 临时验证脚本（`tmp_*.gd`）用后必须删除，不得修改 `addons/` 与 `addons` 之外的既有逻辑除非作业要求

## 无头验证（必须用 `_console.exe`，GUI 版在 Windows 无控制台输出）

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;  # 每条命令都要（Godot 输出含中文）
$g = "D:\Godot_v4.7.1-stable\Godot_v4.7.1-stable_win64_console.exe"
$p = "D:\AboutGame\learn\2d_rpg_dungeon"
& $g --headless --path $p --import                                   # 1. 导入（生成 .godot/）
& $g --headless --path $p --check-only --script "res://xxx.gd"       # 2. 语法检查（exit 0 = 过）
& $g --headless --path $p --quit-after 10                            # 3. 冒烟运行（任何 SCRIPT ERROR = 失败）
```

## mono/C# 版（2d_rpg_dungeon.NET）工具链要点

- csproj 必须与 project.godot 同目录；project.godot 需 `[dotnet] project/assembly_name="..."` 段
- TFM 用 `net8.0`（Godot 4.7 官方支持上限；本机运行时 8.0.26 + hostfxr 10.x 可正常 host）
- **无头 `--import` 不触发 C# 构建**：每次改 `.cs` 后必须先 `dotnet build`，否则冒烟必报 "Cannot instantiate C# script / class could not be found"
- 删 `.godot/` 会连 `temp/bin/Debug` 里的项目 DLL 一起删掉，之后需重新 build
- C# 类必须 `partial`；`Rect2I` 无 `Zero` 静态属性（用 `default`）；`int[,]` 等多维数组**不能**与 GDScript 互操作（Variant 只编组一维数组），跨语言读取需公有属性/方法
- 同种子 + 同 RNG 调用序列 = GDScript 与 C# 产出**逐格相同**的地图（RandomNumberGenerator 是同一 C++ 实现，已实测验证）

## GDScript/.tscn 硬格式（错了直接解析失败）

- `.gd` 缩进**只能用 TAB**，UTF-8 无 BOM（注释含中文）
- 手写 `.tscn` 时：脚本引用用 `[ext_resource type="Script" path="res://..." id="..."]`；若脚本用 `^"NodeName"` 查找节点，该节点必须有 `unique_name_in_owner = true`

## 已踩过的坑（验证过的事实）

- 无头 `-s` 脚本里 `add_child()` 后 `_ready()` **不会立即触发**（消息队列未刷新即 `quit()`）——测试要直接调 `generate()` 等方法，勿依赖 `_ready`
- 无头测试中 `make_current()` 报 `!enabled || !is_inside_tree()` 属预期（节点不在树），RID 泄漏警告同理，均无害
- MCP `project_run` 后 game helper 注册慢于 3 秒就绪窗口：等 ~10s 再轮询 `editor_state`，见 `helper_live=true` 才做按键/截图
- `project_run` 会弹出游戏窗口——需提前告知用户**不要手动关窗**
- **`game_eval` 运行时改节点属性后必须恢复原值**（改回再退出），否则下次 `project_run`（autosave 默认开）会把内存里的改动连同场景一起落盘 `.tscn`（已实测污染过 max_rooms=1）；同理用户在 Inspector 改参数保存也会持久化——验证前先查 `.tscn` 是否有属性覆盖
- `project_manage` 的 `settings_set` 键必须带完整段路径（`application/run/main_scene` 而非 `run/main_scene`）；且引擎出于安全拒绝写启动场景键，只能手工改 `project.godot` + `scene_open(force_reload=true)` 让编辑器重载
- 截图工具返回的图像当前模型不可读；运行时验证用 `game_eval` 读数据（如统计 grid 地板格数）代替
- 教程代码 `dungeon_debug.gd:171-172` 有整数除法警告（`_room_center` 的 `size / 2`，取整是本意）——**有意保留**，勿修（C# 版整数除法无警告）
- PowerShell 查询输出**不要用 `-Last N` 截断**环境类列表（曾因此误判运行时版本，选错 TFM 绕远路）

## 课程语境

第 1 课（`lessons/lesson01_small_dungeon/`）已完成（GDScript + C# 双版本）：随机房间 + L 走廊 + 最近邻连接（作业 5）+ 固定种子 + `_draw()` 可视化。种子复现性 = RNG 状态机原理（同种子 + 同调用顺序 = 同地图，跨语言亦然）。后续课程见 `doc/lession/`。

