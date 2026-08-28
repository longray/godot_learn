using Godot;

namespace RpgDungeon;

// =========================
// 第 11 课：商店与永久升级（C# 版）
// 数据全部走 GameData（Autoload）——本场景只做展示与购买入口
// =========================
public partial class Shop : Control
{
	private const string MainScene = "res://lessons/lesson03_playable/lesson03.tscn";

	private Label _goldLabel = null!;
	private Button _healthButton = null!;
	private Button _attackButton = null!;
	private Button _speedButton = null!;
	private Button _startButton = null!;

	// 第 12 课：测试跳层（输入层数直入地牢——测精英/层数成长用；正常游戏请走"进入地牢"）
	private LineEdit _floorEdit = null!;
	private Button _jumpButton = null!;
	private Label _eliteHintLabel = null!;

	public override void _Ready()
	{
		_goldLabel = GetNodeOrNull<Label>("MarginContainer/VBoxContainer/GoldLabel");
		_healthButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/HealthButton");
		_attackButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/AttackButton");
		_speedButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/SpeedButton");
		_startButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/StartButton");
		_floorEdit = GetNodeOrNull<LineEdit>("MarginContainer/VBoxContainer/DebugHBox/FloorEdit");
		_jumpButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/DebugHBox/JumpButton");
		_eliteHintLabel = GetNodeOrNull<Label>("MarginContainer/VBoxContainer/EliteHintLabel");

		_healthButton.Pressed += OnHealthButtonPressed;
		_attackButton.Pressed += OnAttackButtonPressed;
		_speedButton.Pressed += OnSpeedButtonPressed;
		_startButton.Pressed += OnStartButtonPressed;

		// 测试跳层：按钮 + 输入实时刷新精英率提示
		if (_jumpButton != null && _floorEdit != null)
		{
			_jumpButton.Pressed += OnJumpButtonPressed;
			_floorEdit.TextChanged += OnFloorTextChanged;
			_floorEdit.TextSubmitted += _ => OnJumpButtonPressed();
		}

		UpdateUi();
	}

	private GameData GetGameData()
	{
		return GetNodeOrNull<GameData>("/root/GameData");
	}

	private void UpdateUi()
	{
		var gameData = GetGameData();

		if (gameData == null)
		{
			GD.PushWarning("找不到 GameData，请确认已经注册 Autoload。");
			return;
		}

		_goldLabel.Text = $"金币：{gameData.Gold}";

		_healthButton.Text = $"最大生命 +1（Lv.{gameData.MaxHealthLevel} → {gameData.MaxHealthLevel + 1}）  花费：{gameData.GetUpgradeCost("max_health")}";
		_healthButton.Disabled = !gameData.CanAfford("max_health");

		_attackButton.Text = $"攻击伤害 +1（Lv.{gameData.AttackLevel} → {gameData.AttackLevel + 1}）  花费：{gameData.GetUpgradeCost("attack")}";
		_attackButton.Disabled = !gameData.CanAfford("attack");

		_speedButton.Text = $"移动速度 +10%（Lv.{gameData.SpeedLevel} → {gameData.SpeedLevel + 1}）  花费：{gameData.GetUpgradeCost("speed")}";
		_speedButton.Disabled = !gameData.CanAfford("speed");
	}

	private void Buy(string type)
	{
		var gameData = GetGameData();

		if (gameData == null)
		{
			return;
		}

		if (gameData.TryBuy(type))
		{
			GD.Print("购买成功：", type);
			UpdateUi();
		}
		else
		{
			GD.Print("金币不足。");
		}
	}

	private void OnHealthButtonPressed() => Buy("max_health");

	private void OnAttackButtonPressed() => Buy("attack");

	private void OnSpeedButtonPressed() => Buy("speed");

	private void OnStartButtonPressed()
	{
		// 进入地牢（GameData 常驻，切换场景数据不丢）
		GetTree().ChangeSceneToFile(MainScene);
	}

	// =========================
	// 第 12 课：测试跳层
	// =========================

	private int ParseFloorInput()
	{
		// 解析输入层数：非数字回退 1，范围钳制 1..99
		if (!int.TryParse(_floorEdit.Text.Trim(), out int f))
		{
			f = 1;
		}

		return Mathf.Clamp(f, 1, 99);
	}

	private void OnFloorTextChanged(string newText)
	{
		// 实时提示该层精英率（公式与 DungeonPlayable 三导出属性同步——仅提示用）
		if (_eliteHintLabel == null)
		{
			return;
		}

		int n = int.TryParse(newText.Trim(), out int v) ? Mathf.Clamp(v, 1, 99) : 1;

		float chance = Mathf.Clamp(0.05f + 0.02f * n, 0.0f, 0.25f);
		_eliteHintLabel.Text = $"第 {n} 层：精英率 {chance * 100.0f:F0}%（血 +1/2层 伤 +1/4层）";
	}

	private void OnJumpButtonPressed()
	{
		// 跳层测试：写 GameData 通道 → 地牢 Generate 消费即清零（不影响正常流程/存档）
		var gameData = GetGameData();

		if (gameData != null)
		{
			gameData.DebugStartFloor = ParseFloorInput();
			GD.Print($"跳层测试：第 {gameData.DebugStartFloor} 层");
		}

		GetTree().ChangeSceneToFile(MainScene);
	}
}
