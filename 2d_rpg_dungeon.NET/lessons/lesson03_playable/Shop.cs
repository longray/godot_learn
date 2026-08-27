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

	public override void _Ready()
	{
		_goldLabel = GetNodeOrNull<Label>("MarginContainer/VBoxContainer/GoldLabel");
		_healthButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/HealthButton");
		_attackButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/AttackButton");
		_speedButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/SpeedButton");
		_startButton = GetNodeOrNull<Button>("MarginContainer/VBoxContainer/StartButton");

		_healthButton.Pressed += OnHealthButtonPressed;
		_attackButton.Pressed += OnAttackButtonPressed;
		_speedButton.Pressed += OnSpeedButtonPressed;
		_startButton.Pressed += OnStartButtonPressed;

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
}
