using Godot;

namespace RpgDungeon;

// =========================
// 第 8 课：HUD 状态面板（独立场景，C# 版）
// 职责单一：只管显示，不持有游戏状态——
// DungeonPlayable 通过 Update* 方法推送数据，玩家生命经 HealthChanged 信号 → Main 转发进来
// 作业 2/3：钥匙/金币图标（TextureRect + 状态点亮）
// 作业 4/5：受伤红屏渐隐 + 死亡大字
// =========================
public partial class Hud : CanvasLayer
{
	// 红屏参数：瞬间拉到 0.25 透明度，每秒衰减 0.5（约 0.5s 消退）
	private const float HurtFlashAlpha = 0.25f;
	private const float HurtFadeSpeed = 0.5f;

	// 死亡提示显示时长（秒）
	private const float DeathShowTime = 1.2f;

	private static readonly Texture2D HeartFullTexture =
		GD.Load<Texture2D>("res://assets/sprites/heart_full.png");
	private static readonly Texture2D HeartEmptyTexture =
		GD.Load<Texture2D>("res://assets/sprites/heart_empty.png");

	private VBoxContainer _vbox = null!;
	private HBoxContainer _healthUi = null!;
	private Label _goldLabel = null!;
	private Label _keyLabel = null!;
	private Label _floorLabel = null!;
	// 作业 1（第 10 课）：死亡计数行（与第 8 课 DeathLabel 死亡大字是两个节点，勿混淆）
	private Label _deathsLabel = null!;
	private Label _treasureLabel = null!;
	private Label _exploreLabel = null!;

	// 作业 2：钥匙图标（未获得时灰暗剪影，获得时点亮）
	private TextureRect _keyIcon = null!;

	// 作业 4/5：红屏覆盖层 + 死亡大字
	private ColorRect _hurtOverlay = null!;
	private Label _deathLabel = null!;

	// 作业 2（第 11 课）：死亡提示副标题（损失比例 + 按键提示）
	private Label _deathHintLabel = null!;

	// 死亡提示会话令牌：新 ShowDeath/HideDeath 使挂起中的旧协程失效
	// （防旧协程 1.2s 后恢复时误关持续模式的新大字）
	private int _deathToken;

	public override void _Ready()
	{
		_vbox = GetNode<VBoxContainer>("VBoxContainer");
		_healthUi = GetNode<HBoxContainer>("VBoxContainer/HealthUI");
		_goldLabel = GetNode<Label>("VBoxContainer/GoldRow/GoldLabel");
		_keyLabel = GetNode<Label>("VBoxContainer/KeyRow/KeyLabel");
		_floorLabel = GetNode<Label>("VBoxContainer/FloorLabel");
		_deathsLabel = GetNode<Label>("VBoxContainer/DeathLabel");
		_treasureLabel = GetNode<Label>("VBoxContainer/TreasureLabel");
		_exploreLabel = GetNode<Label>("VBoxContainer/ExploreLabel");
		_keyIcon = GetNode<TextureRect>("VBoxContainer/KeyRow/KeyIcon");
		_hurtOverlay = GetNode<ColorRect>("HurtOverlay");
		_deathLabel = GetNode<Label>("DeathLabel");
		_deathHintLabel = GetNode<Label>("DeathHintLabel");
	}

	public override void _Process(double delta)
	{
		// 作业 4：红屏渐隐（每帧把红色 alpha 往 0 衰减）
		if (_hurtOverlay.Color.A > 0.0f)
		{
			var c = _hurtOverlay.Color;
			_hurtOverlay.Color = new Color(c.R, c.G, c.B, Mathf.Max(0.0f, c.A - HurtFadeSpeed * (float)delta));
		}
	}

	public void UpdateHealth(int currentHealth, int maxHealth)
	{
		// 心形数量随 maxHealth 动态同步（场景里预置 3 颗，运行时按需增减）
		SyncHeartCount(maxHealth);

		// 作业 1（第 5 课）：i < current 满心，否则空心
		for (int i = 0; i < _healthUi.GetChildCount(); i++)
		{
			if (_healthUi.GetChildOrNull<TextureRect>(i) is not { } heart)
			{
				continue;
			}

			heart.Texture = i < currentHealth ? HeartFullTexture : HeartEmptyTexture;
		}
	}

	public void UpdateGold(int gold)
	{
		// 作业 3：金币图标已在行首，文字只留数量
		_goldLabel.Text = $"× {gold}";
		_goldLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.85f, 0.3f));
	}

	public void UpdateKey(bool hasKey)
	{
		// 作业 2：图标即语义——拿到前灰暗剪影，拿到瞬间点亮
		_keyIcon.Modulate = hasKey
			? new Color(1.0f, 1.0f, 1.0f)
			: new Color(0.35f, 0.35f, 0.4f);

		if (hasKey)
		{
			_keyLabel.Text = "已获得 ✓ 出口已解锁";
			_keyLabel.AddThemeColorOverride("font_color", new Color(0.5f, 1.0f, 0.6f));
		}
		else
		{
			_keyLabel.Text = "未获得";
			_keyLabel.AddThemeColorOverride("font_color", new Color(1.0f, 1.0f, 1.0f));
		}
	}

	public void ShowKeyLockedHint()
	{
		// 第 4 课资产迁移：踩到锁定出口时的红字提示（覆盖 UpdateKey 的常规文案）
		_keyLabel.Text = "出口被锁住了！去寻找金钥匙…";
		_keyLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.5f, 0.4f));
	}

	public void UpdateFloor(int floorNumber, int bestFloorNumber = 1)
	{
		// 第 8 课：层数显示（出口进入下一层时 +1）
		// 第 10 课：并列最佳层数（长期纪录，来自存档）
		_floorLabel.Text = $"层数：第 {floorNumber} 层 | 最佳：第 {bestFloorNumber} 层";
		_floorLabel.AddThemeColorOverride("font_color", new Color(0.55f, 0.8f, 1.0f));
	}

	public void UpdateDeaths(int deaths)
	{
		// 作业 1（第 10 课）：死亡次数（长期纪录，来自存档）
		_deathsLabel.Text = $"💀 死亡：{deaths}";
		_deathsLabel.AddThemeColorOverride("font_color", new Color(0.85f, 0.55f, 0.65f));
	}

	public void UpdateTreasure(int opened, int total)
	{
		// 第 5 课格式迁移：已开 / 总数（宝箱拾取后不回收格子，总数稳定）
		_treasureLabel.Text = $"宝箱：{opened}/{total}";
		_treasureLabel.AddThemeColorOverride("font_color", new Color(1.0f, 0.67f, 0.43f));
	}

	public void UpdateExplore(int explored, int total)
	{
		// 作业 5（第 9 课）：探索进度（走进过的房间数 / 总房间数）
		_exploreLabel.Text = $"探索：{explored} / {total}";
		_exploreLabel.AddThemeColorOverride("font_color", new Color(0.65f, 0.85f, 1.0f));
	}

	public void FlashHurt()
	{
		// 作业 4：受伤瞬间红屏（透明度瞬间拉满，_Process 里负责消退）
		var c = _hurtOverlay.Color;
		_hurtOverlay.Color = new Color(c.R, c.G, c.B, HurtFlashAlpha);
	}

	public async void ShowDeath(string hintText = "", bool autoHide = true)
	{
		// 作业 5（第 8 课）：死亡大字
		// 作业 2（第 11 课）：autoHide=false 持续显示（死亡等按键回商店，场景切换时随 HUD 销毁）；
		// hintText 非空时副标题同步显示（损失比例提示）
		int myToken = ++_deathToken;

		_deathLabel.Visible = true;

		if (hintText != "" && _deathHintLabel != null)
		{
			_deathHintLabel.Text = hintText;
			_deathHintLabel.Visible = true;
		}

		if (!autoHide)
		{
			return;
		}

		await ToSignal(GetTree().CreateTimer(DeathShowTime), SceneTreeTimer.SignalName.Timeout);

		// 会话已被更新的 Show/Hide 取代——不再动界面
		if (myToken != _deathToken)
		{
			return;
		}

		HideDeath();
	}

	public void HideDeath()
	{
		// 隐藏大字与副标题；递增令牌作废所有挂起中的旧协程
		_deathToken++;
		_deathLabel.Visible = false;

		if (_deathHintLabel != null)
		{
			_deathHintLabel.Visible = false;
		}
	}

	private void SyncHeartCount(int count)
	{
		// 动态增减心形节点（maxHealth 改变时 HUD 自动跟上）
		while (_healthUi.GetChildCount() < count)
		{
			var heart = new TextureRect
			{
				CustomMinimumSize = new Vector2(16, 16),
				Texture = HeartEmptyTexture,
			};
			_healthUi.AddChild(heart);
		}

		// QueueFree 到帧末才真正移除，GetChildCount 不会立即下降——缩容循环天然只跑一次
		while (_healthUi.GetChildCount() > count)
		{
			_healthUi.GetChild(_healthUi.GetChildCount() - 1).QueueFree();
		}
	}
}
