using Godot;

namespace RpgDungeon;

// =========================
// 第 4 课作业 5：真正的敌人场景（C# 版）
// 根节点 CharacterBody2D（为下一课移动 AI / 战斗预留架构）
// 本课行为与"怪物危险区"一致：玩家触碰 → 信号通知 Main → 传送回入口
// =========================
public partial class Enemy : CharacterBody2D
{
	// 玩家触碰信号（解耦：敌人只报告事件，惩罚逻辑归 Main）
	[Signal]
	public delegate void PlayerTouchedEventHandler();

	// 呼吸动画计时
	private float _t;
	private Sprite2D _sprite;

	public override void _Ready()
	{
		_sprite = GetNode<Sprite2D>("Sprite2D");
		var hazard = GetNode<Area2D>("HazardArea");
		hazard.BodyEntered += OnHazardBodyEntered;
	}

	public override void _Process(double delta)
	{
		// 史莱姆呼吸：轻微正弦缩放
		// 只缩 Sprite2D 不缩根节点——根 scale 会连带缩放子节点碰撞体，破坏触发半径
		_t += (float)delta;
		float s = 1.0f + 0.08f * Mathf.Sin(_t * 3.0f);
		_sprite.Scale = new Vector2(s, s);
	}

	private void OnHazardBodyEntered(Node2D body)
	{
		if (body.IsInGroup("player"))
		{
			EmitSignal(SignalName.PlayerTouched);
		}
	}
}
