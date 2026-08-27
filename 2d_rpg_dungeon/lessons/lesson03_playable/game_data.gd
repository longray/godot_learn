extends Node

# =========================
# 第 11 课：全局游戏数据与存档（Autoload 单例）
# 金币/纪录/永久等级的唯一真源——商店与地牢都读写这里；
# 场景切换不销毁（挂在 /root 下），存档职责从 Main 迁移至此
# （死亡惩罚参数保留在 Main 的 @export——第 10 课验证过的资产，算完后 _sync_game_data 同步过来）
# =========================

const SAVE_PATH := "user://rpg_dungeon_save.json"

# 长期资源
var gold: int = 0
var best_floor: int = 1
var total_deaths: int = 0

# 永久升级等级
var max_health_level: int = 0
var attack_level: int = 0
var speed_level: int = 0


func _ready() -> void:
	load_game()


# =========================
# 升级效果（玩家 apply_upgrades 消费）
# =========================

func get_max_health_bonus() -> int:
	return max_health_level


func get_attack_bonus() -> int:
	return attack_level


func get_speed_multiplier() -> float:
	return 1.0 + speed_level * 0.1


# =========================
# 升级购买（线性涨价：越买越贵，防止一夜变强）
# =========================

func get_upgrade_cost(type: String) -> int:
	# 作业 4（第 11 课）：指数涨价 base × 1.5^Lv——后期一等级 = 前几级之和，逼玩家取舍
	# （Lv0 价格与线性版一致：10/15/12；Lv2 起 22/33/27 明显陡升）
	match type:
		"max_health":
			return int(10.0 * pow(1.5, max_health_level))
		"attack":
			return int(15.0 * pow(1.5, attack_level))
		"speed":
			return int(12.0 * pow(1.5, speed_level))

	return 999999


func can_afford(type: String) -> bool:
	return gold >= get_upgrade_cost(type)


func try_buy(type: String) -> bool:
	var cost := get_upgrade_cost(type)

	if gold < cost:
		return false

	gold -= cost

	match type:
		"max_health":
			max_health_level += 1
		"attack":
			attack_level += 1
		"speed":
			speed_level += 1

	save_game()

	return true


# =========================
# 调试删档（Main 的 Backspace 快捷键调用）
# =========================

func reset_progress() -> void:
	# 删文件 + 变量归零（金币/纪录/升级等级全部清空）
	delete_save()
	gold = 0
	best_floor = 1
	total_deaths = 0
	max_health_level = 0
	attack_level = 0
	speed_level = 0


# =========================
# 存档（第 10 课自 Main 迁移；旧档缺升级字段按 Lv.0 兜底）
# =========================

func save_game() -> void:
	var data := {
		"gold": gold,
		"best_floor": best_floor,
		"total_deaths": total_deaths,
		"max_health_level": max_health_level,
		"attack_level": attack_level,
		"speed_level": speed_level
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if file == null:
		push_warning("无法打开存档文件进行写入。")
		return

	file.store_string(JSON.stringify(data, "  "))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)

	if file == null:
		push_warning("无法打开存档文件。")
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())

	if error != OK:
		push_warning("存档解析失败。")
		return

	if typeof(json.data) != TYPE_DICTIONARY:
		push_warning("存档格式错误。")
		return

	# get 缺省兜底：第 10 课旧档没有升级字段 → 默认 0 级，零迁移成本
	gold = int(json.data.get("gold", gold))
	best_floor = int(json.data.get("best_floor", best_floor))
	total_deaths = int(json.data.get("total_deaths", total_deaths))
	max_health_level = int(json.data.get("max_health_level", max_health_level))
	attack_level = int(json.data.get("attack_level", attack_level))
	speed_level = int(json.data.get("speed_level", speed_level))


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
