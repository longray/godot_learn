using Godot;

namespace RpgDungeon;

// =========================
// 第 11 课：全局游戏数据与存档（Autoload 单例，C# 版）
// 金币/纪录/永久等级的唯一真源——商店与地牢都读写这里；
// 场景切换不销毁（挂在 /root 下），存档职责从 DungeonPlayable 迁移至此
// =========================
public partial class GameData : Node
{
	private const string SavePath = "user://rpg_dungeon_save.json";

	// 长期资源
	public int Gold { get; set; }
	public int BestFloor { get; set; } = 1;
	public int TotalDeaths { get; set; }

	// 第 12 课：测试跳层通道（商店写入 → 地牢 Generate 消费即清零；不进存档）
	public int DebugStartFloor { get; set; }

	// 永久升级等级
	public int MaxHealthLevel { get; set; }
	public int AttackLevel { get; set; }
	public int SpeedLevel { get; set; }

	public override void _Ready()
	{
		LoadGame();
	}

	// =========================
	// 升级效果（玩家 ApplyUpgrades 消费）
	// =========================

	public int GetMaxHealthBonus() => MaxHealthLevel;

	public int GetAttackBonus() => AttackLevel;

	public float GetSpeedMultiplier() => 1.0f + SpeedLevel * 0.1f;

	// =========================
	// 升级购买（作业 4：指数涨价 base × 1.5^Lv——后期一等级 = 前几级之和）
	// =========================

	public int GetUpgradeCost(string type)
	{
		return type switch
		{
			"max_health" => (int)(10.0 * Mathf.Pow(1.5f, MaxHealthLevel)),
			"attack" => (int)(15.0 * Mathf.Pow(1.5f, AttackLevel)),
			"speed" => (int)(12.0 * Mathf.Pow(1.5f, SpeedLevel)),
			_ => 999999,
		};
	}

	public bool CanAfford(string type) => Gold >= GetUpgradeCost(type);

	public bool TryBuy(string type)
	{
		int cost = GetUpgradeCost(type);

		if (Gold < cost)
		{
			return false;
		}

		Gold -= cost;

		switch (type)
		{
			case "max_health":
				MaxHealthLevel += 1;
				break;
			case "attack":
				AttackLevel += 1;
				break;
			case "speed":
				SpeedLevel += 1;
				break;
		}

		SaveGame();

		return true;
	}

	// =========================
	// 调试删档（Main 的 Backspace 快捷键调用）
	// =========================

	public void ResetProgress()
	{
		DeleteSave();
		Gold = 0;
		BestFloor = 1;
		TotalDeaths = 0;
		MaxHealthLevel = 0;
		AttackLevel = 0;
		SpeedLevel = 0;
	}

	// =========================
	// 存档（第 10 课自 Main 迁移；旧档缺升级字段按 Lv.0 兜底）
	// =========================

	public void SaveGame()
	{
		var data = new Godot.Collections.Dictionary
		{
			["gold"] = Gold,
			["best_floor"] = BestFloor,
			["total_deaths"] = TotalDeaths,
			["max_health_level"] = MaxHealthLevel,
			["attack_level"] = AttackLevel,
			["speed_level"] = SpeedLevel,
		};

		using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Write);

		if (file == null)
		{
			GD.PushWarning("无法打开存档文件进行写入。");
			return;
		}

		file.StoreString(Json.Stringify(data, "  "));
	}

	public void LoadGame()
	{
		if (!FileAccess.FileExists(SavePath))
		{
			return;
		}

		using FileAccess file = FileAccess.Open(SavePath, FileAccess.ModeFlags.Read);

		if (file == null)
		{
			GD.PushWarning("无法打开存档文件。");
			return;
		}

		var json = new Json();
		Error error = json.Parse(file.GetAsText());

		if (error != Error.Ok)
		{
			GD.PushWarning("存档解析失败。");
			return;
		}

		if (json.Data.VariantType != Variant.Type.Dictionary)
		{
			GD.PushWarning("存档格式错误。");
			return;
		}

		var data = json.Data.AsGodotDictionary();

		// Get 缺省兜底：第 10 课旧档没有升级字段 → 默认 0 级，零迁移成本
		// （Godot.Collections.Dictionary 无 GetValueOr，用 ContainsKey 手写）
		Gold = data.ContainsKey("gold") ? (int)(double)data["gold"] : Gold;
		BestFloor = data.ContainsKey("best_floor") ? (int)(double)data["best_floor"] : BestFloor;
		TotalDeaths = data.ContainsKey("total_deaths") ? (int)(double)data["total_deaths"] : TotalDeaths;
		MaxHealthLevel = data.ContainsKey("max_health_level") ? (int)(double)data["max_health_level"] : MaxHealthLevel;
		AttackLevel = data.ContainsKey("attack_level") ? (int)(double)data["attack_level"] : AttackLevel;
		SpeedLevel = data.ContainsKey("speed_level") ? (int)(double)data["speed_level"] : SpeedLevel;
	}

	public void DeleteSave()
	{
		if (FileAccess.FileExists(SavePath))
		{
			DirAccess.RemoveAbsolute(SavePath);
		}
	}
}
