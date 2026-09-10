extends Node

signal changed
signal log_added(text: String)
signal inventory_changed
signal gacha_finished(results: Array)
signal offline_applied(summary: Dictionary)

const CORE_UNLOCKS := ["guanyu", "zhangfei", "zhaoyun", "caocao", "sunquan", "lvbu"]

var cultivation: float = 0.0
var coins: float = 2500.0
var spirit_stones: int = 2200
var soul_dust: int = 0
var immortal_fate: float = 0.0
var ascensions: int = 0
var last_ascension_floor: int = 0
var legacy_fate: float = 0.0
var ascension_bonuses: Dictionary = {"attack":0.0,"hp":0.0,"defense":0.0,"resource":0.0,"fate":0.0}
var realm_index: int = 0
var realm_stage: int = 1
var tower_floor: int = 1
var highest_floor: int = 1
var total_play_seconds: float = 0.0
var active_general_id: String = "guanyu"
var general_progress: Dictionary = {}
var inventory: Array = []
var equipped: Dictionary = {"helmet":"", "armor":"", "bracer":"", "boots":"", "ring":"", "talisman":""}
var pity_count: int = 0
var total_pulls: int = 0
var last_saved_unix: int = 0
var dark_mode: bool = false
var battle_speed: float = 1.0
var auto_battle: bool = true
var battle_log: Array[String] = []
var gacha_history: Array = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func reset_new_game() -> void:
	ContentDB.load_all()
	cultivation = 0.0
	coins = 2500.0
	spirit_stones = 2200
	soul_dust = 0
	immortal_fate = 0
	ascensions = 0
	last_ascension_floor = 0
	legacy_fate = 0
	for key in ascension_bonuses: ascension_bonuses[key] = 0.0
	realm_index = 0
	realm_stage = 1
	tower_floor = 1
	highest_floor = 1
	total_play_seconds = 0.0
	active_general_id = "guanyu"
	general_progress.clear()
	for id in ContentDB.get_general_ids():
		general_progress[id] = {"unlocked": CORE_UNLOCKS.has(id), "level":1, "stars":1, "soul":0, "soul_rank":0}
	inventory.clear()
	equipped = {"helmet":"", "armor":"", "bracer":"", "boots":"", "ring":"", "talisman":""}
	pity_count = 0
	total_pulls = 0
	dark_mode = false
	battle_speed = 1.0
	auto_battle = true
	battle_log.clear()
	gacha_history.clear()
	last_saved_unix = int(Time.get_unix_time_from_system())
	for i in range(5):
		add_random_equipment(max(1, i + 1))
	equip_best()
	add_log("三国杀挂机塔已开启。六名核心武将已解锁用于原型测试。")
	changed.emit()

func tick_passive(delta: float) -> void:
	total_play_seconds += delta
	cultivation += cultivation_rate_per_sec() * delta
	coins += coin_rate_per_sec() * delta
	changed.emit()

func cultivation_rate_per_sec() -> float:
	return 1.2 * pow(1.42, min(realm_index, 120)) * (1.0 + legacy_fate * 0.05) * (1.0 + float(ascension_bonuses.resource))

func coin_rate_per_sec() -> float:
	return 3.0 * pow(1.38, min(realm_index, 120)) * (1.0 + max(0, tower_floor - 1) * 0.008) * (1.0 + legacy_fate * 0.04) * (1.0 + float(ascension_bonuses.resource))

func cultivation_required() -> float:
	return 80.0 * pow(1.72, min(realm_index, 120)) * pow(1.28, realm_stage - 1)

func realm_name() -> String:
	ContentDB.load_all()
	var names: Array = ContentDB.balance.get("realm_names", [])
	if realm_index < names.size():
		return "%s %d层" % [String(names[realm_index]), realm_stage]
	return "超脱 %d重 · %d层" % [realm_index - names.size() + 1, realm_stage]

func try_breakthrough() -> bool:
	var need := cultivation_required()
	if cultivation < need:
		return false
	cultivation -= need
	realm_stage += 1
	if realm_stage > 10:
		realm_stage = 1
		realm_index += 1
		add_log("境界突破！踏入 %s。" % realm_name())
	else:
		add_log("修为精进：%s。" % realm_name())
	changed.emit()
	return true

func general_state(id: String) -> Dictionary:
	if not general_progress.has(id):
		general_progress[id] = {"unlocked":false, "level":1, "stars":1, "soul":0, "soul_rank":0}
	return general_progress[id]

func is_general_unlocked(id: String) -> bool:
	return bool(general_state(id).get("unlocked", false))

func set_active_general(id: String) -> bool:
	if not is_general_unlocked(id):
		return false
	active_general_id = id
	add_log("主将切换为 %s。" % String(ContentDB.get_general(id).get("name", id)))
	changed.emit()
	return true

func active_general_level() -> int:
	return int(general_state(active_general_id).get("level", 1))

func general_upgrade_cost(id: String) -> float:
	var level := int(general_state(id).get("level", 1))
	return 85.0 * pow(level, 1.36)

func upgrade_active_general() -> bool:
	var cost := general_upgrade_cost(active_general_id)
	if coins < cost:
		return false
	coins -= cost
	general_progress[active_general_id]["level"] = active_general_level() + 1
	add_log("%s 升至 Lv.%d。" % [String(ContentDB.get_general(active_general_id).get("name", "主将")), active_general_level()])
	changed.emit()
	return true

func upgrade_active_general_bulk(max_levels: int = 10000) -> int:
	var count := 0
	while count < max_levels:
		var cost := general_upgrade_cost(active_general_id)
		if coins < cost:
			break
		coins -= cost
		general_progress[active_general_id]["level"] = active_general_level() + 1
		count += 1
	if count > 0:
		add_log("%s 一键提升 %d 级，达到 Lv.%d。" % [String(ContentDB.get_general(active_general_id).get("name", "主将")), count, active_general_level()])
		changed.emit()
	return count

func breakthrough_all(max_steps: int = 100) -> int:
	var count := 0
	while count < max_steps and cultivation >= cultivation_required():
		var need := cultivation_required()
		cultivation -= need
		realm_stage += 1
		if realm_stage > 10:
			realm_stage = 1
			realm_index += 1
		count += 1
	if count > 0:
		add_log("一键突破 %d 次，当前境界：%s。" % [count, realm_name()])
		changed.emit()
	return count

func general_soul_cost(id: String) -> int:
	var state := general_state(id)
	var stars := int(state.get("stars", 1))
	var soul_rank := int(state.get("soul_rank", 0))
	if stars < 5:
		var costs := [0, 30, 60, 120, 240]
		return int(costs[stars])
	return 100 + soul_rank * 20

func breakthrough_active_general() -> bool:
	var state := general_state(active_general_id)
	var cost := general_soul_cost(active_general_id)
	if int(state.get("soul", 0)) < cost:
		return false
	state["soul"] = int(state.get("soul", 0)) - cost
	if int(state.get("stars", 1)) < 5:
		state["stars"] = int(state.get("stars", 1)) + 1
		var skill_version := ContentDB.get_general_skill_version(active_general_id, int(state.get("stars", 1)))
		add_log("%s 武魂突破至 %d 星，技能升级为【%s】。" % [String(ContentDB.get_general(active_general_id).get("name", "主将")), int(state.get("stars",1)), String(skill_version.get("name", "技能"))])
	else:
		state["soul_rank"] = int(state.get("soul_rank", 0)) + 1
		add_log("%s 神魂超越至 %d 重。" % [String(ContentDB.get_general(active_general_id).get("name", "主将")), int(state.get("soul_rank",0))])
	changed.emit()
	return true

func breakthrough_active_general_bulk(max_steps: int = 1000) -> int:
	var count := 0
	while count < max_steps:
		var state := general_state(active_general_id)
		var cost := general_soul_cost(active_general_id)
		if int(state.get("soul", 0)) < cost:
			break
		state["soul"] = int(state.get("soul", 0)) - cost
		if int(state.get("stars", 1)) < 5:
			state["stars"] = int(state.get("stars", 1)) + 1
		else:
			state["soul_rank"] = int(state.get("soul_rank", 0)) + 1
		count += 1
	if count > 0:
		var state := general_state(active_general_id)
		add_log("%s 一键武魂突破 %d 次：%d星 / 神魂%d重。" % [String(ContentDB.get_general(active_general_id).get("name", "主将")), count, int(state.get("stars",1)), int(state.get("soul_rank",0))])
		changed.emit()
	return count

func _gear_power_total() -> float:
	var total := 0.0
	for slot in equipped.keys():
		var uid := String(equipped[slot])
		if uid.is_empty():
			continue
		for item in inventory:
			if String(item.get("uid", "")) == uid:
				total += float(item.get("power", 0.0))
				break
	return total

func player_attack_log10() -> float:
	var data := ContentDB.get_general(active_general_id)
	var base := max(1.0, float(data.get("base_attack", 100.0)))
	var level := active_general_level()
	var stars := int(general_state(active_general_id).get("stars", 1))
	var soul_rank := int(general_state(active_general_id).get("soul_rank", 0))
	var gear_mult := 1.0 + _gear_power_total() / 750.0
	var regular := base * pow(1.055, level - 1) * (1.0 + (stars - 1) * 0.14) * gear_mult * (1.0 + legacy_fate * 0.12) * (1.0 + float(ascension_bonuses.attack)) * (1.0 + soul_rank * 0.01)
	return log(max(1.0, regular)) / log(10.0) + realm_index * 0.48 + (realm_stage - 1) * 0.042

func player_hp_log10() -> float:
	var data := ContentDB.get_general(active_general_id)
	var base := max(1.0, float(data.get("base_hp", 1000.0)))
	var level := active_general_level()
	var gear_mult := 1.0 + _gear_power_total() / 900.0
	var regular := base * pow(1.050, level - 1) * gear_mult * (1.0 + legacy_fate * 0.10) * (1.0 + float(ascension_bonuses.hp))
	return log(max(1.0, regular)) / log(10.0) + realm_index * 0.46 + (realm_stage - 1) * 0.040

func combat_power_text() -> String:
	return BigNum.from_log10(player_attack_log10() + 0.7).short()

func on_floor_cleared() -> Dictionary:
	var cleared := tower_floor
	var reward_cult := 10.0 + pow(cleared, 1.12) * 1.6
	var reward_coins := 24.0 + pow(cleared, 1.16) * 4.0
	cultivation += reward_cult
	coins += reward_coins
	if rng.randf() < 0.10:
		spirit_stones += 1 + int(cleared / 100)
	var drop := false
	if rng.randf() < 0.38:
		add_random_equipment(max(1, int(cleared / 20) + 1))
		drop = true
	tower_floor += 1
	highest_floor = max(highest_floor, tower_floor)
	if cleared % 10 == 0:
		add_log("突破第 %d 层，获得额外修为与装备掉落加成。" % cleared)
	changed.emit()
	return {"floor":cleared, "cultivation":reward_cult, "coins":reward_coins, "drop":drop}

func _rarity_index(name: String) -> int:
	ContentDB.load_all()
	var arr: Array = ContentDB.balance.get("gear_rarities", [])
	return max(0, arr.find(name))

func add_random_equipment(tier: int = 1) -> Dictionary:
	ContentDB.load_all()
	var slots := ["helmet", "armor", "bracer", "boots", "ring", "talisman"]
	var slot: String = slots[rng.randi_range(0, slots.size() - 1)]
	var roll := rng.randf()
	var rarity := "普通"
	if roll < 0.006 + min(0.02, tier * 0.0003): rarity = "仙品"
	elif roll < 0.018 + min(0.03, tier * 0.0004): rarity = "神话"
	elif roll < 0.055 + min(0.05, tier * 0.0005): rarity = "传说"
	elif roll < 0.14: rarity = "史诗"
	elif roll < 0.34: rarity = "稀有"
	elif roll < 0.64: rarity = "精良"
	var r_idx := _rarity_index(rarity)
	var names := {"weapon":["青锋","断岳刀","玄铁枪"], "armor":["云纹袍","玄甲","护心铠"], "accessory":["玉佩","战印","灵珠"]}
	var prefixes := ["朴素", "灵纹", "湛蓝", "紫霄", "赤金", "神铸", "仙蕴"]
	var uid := "%d_%d" % [Time.get_ticks_usec(), rng.randi_range(1000, 999999)]
	var power := max(1.0, tier * 18.0 * pow(r_idx + 1.0, 1.55) * rng.randf_range(0.88, 1.12))
	var affixes := ["暴击", "杀强化", "摸牌", "锦囊", "减伤", "回复"]
	var item := {
		"uid":uid,
		"name":"%s%s" % [prefixes[r_idx], names[slot][rng.randi_range(0, 2)]],
		"slot":slot,
		"rarity":rarity,
		"tier":tier,
		"power":power,
		"affix":affixes[rng.randi_range(0, affixes.size() - 1)],
		"locked":false
	}
	inventory.append(item)
	inventory_changed.emit()
	return item

func toggle_lock(uid: String) -> void:
	for item in inventory:
		if String(item.get("uid", "")) == uid:
			item["locked"] = not bool(item.get("locked", false))
			break
	inventory_changed.emit()
	changed.emit()

func equip_item(uid: String) -> bool:
	for item in inventory:
		if String(item.get("uid", "")) == uid:
			var slot := String(item.get("slot", ""))
			if not equipped.has(slot):
				return false
			equipped[slot] = uid
			add_log("已装备 %s。" % String(item.get("name", "装备")))
			inventory_changed.emit()
			changed.emit()
			return true
	return false

func equip_best() -> int:
	var changes := 0
	for slot in ["helmet", "armor", "bracer", "boots", "ring", "talisman"]:
		var best_uid := ""
		var best_power := -1.0
		for item in inventory:
			if String(item.get("slot", "")) == slot and float(item.get("power", 0.0)) > best_power:
				best_power = float(item.get("power", 0.0))
				best_uid = String(item.get("uid", ""))
		if not best_uid.is_empty() and String(equipped.get(slot, "")) != best_uid:
			equipped[slot] = best_uid
			changes += 1
	if changes > 0:
		add_log("已自动换装 %d 个部位。" % changes)
	inventory_changed.emit()
	changed.emit()
	return changes

func _is_protected(item: Dictionary) -> bool:
	if bool(item.get("locked", false)):
		return true
	var uid := String(item.get("uid", ""))
	return equipped.values().has(uid)

func one_click_upgrade() -> int:
	var upgrades := 0
	var did_merge := true
	while did_merge:
		did_merge = false
		var groups: Dictionary = {}
		for item in inventory:
			if _is_protected(item):
				continue
			var key := "%s|%s|%d" % [String(item.get("slot", "")), String(item.get("rarity", "普通")), int(item.get("tier", 1))]
			if not groups.has(key): groups[key] = []
			groups[key].append(item)
		for key in groups.keys():
			var group: Array = groups[key]
			if group.size() < 3:
				continue
			group.sort_custom(func(a, b): return float(a.get("power", 0.0)) < float(b.get("power", 0.0)))
			var used: Array = [group[0], group[1], group[2]]
			var seed_item: Dictionary = used[2]
			for item in used:
				inventory.erase(item)
			var upgraded := seed_item.duplicate(true)
			upgraded["uid"] = "%d_%d" % [Time.get_ticks_usec(), rng.randi_range(1000, 999999)]
			upgraded["tier"] = int(seed_item.get("tier", 1)) + 1
			upgraded["power"] = float(seed_item.get("power", 1.0)) * 1.38
			upgraded["name"] = String(seed_item.get("name", "装备"))
			upgraded["locked"] = false
			inventory.append(upgraded)
			upgrades += 1
			did_merge = true
			break
	if upgrades > 0:
		add_log("一键升阶完成：合成 %d 次。" % upgrades)
	inventory_changed.emit()
	changed.emit()
	return upgrades

func one_click_decompose(max_rarity_index: int = 1) -> Dictionary:
	var removed := 0
	var essence_gain := 0
	var coin_gain := 0.0
	var keep: Array = []
	for item in inventory:
		var r_idx := _rarity_index(String(item.get("rarity", "普通")))
		if not _is_protected(item) and r_idx <= max_rarity_index:
			removed += 1
			var tier := int(item.get("tier", 1))
			essence_gain += (r_idx + 1) * tier * 3
			coin_gain += tier * (r_idx + 1) * 8.0
		else:
			keep.append(item)
	inventory = keep
	soul_dust += essence_gain
	coins += coin_gain
	if removed > 0:
		add_log("一键分解 %d 件装备，获得武魂精华 %d。" % [removed, essence_gain])
	inventory_changed.emit()
	changed.emit()
	return {"count":removed, "essence":essence_gain, "coins":coin_gain}

func gacha_pull(count: int) -> Array:
	ContentDB.load_all()
	var cfg: Dictionary = ContentDB.balance.get("gacha", {})
	var cost := int(cfg.get("ten_cost", 900)) if count == 10 else int(cfg.get("single_cost", 100)) * count
	if spirit_stones < cost:
		return []
	spirit_stones -= cost
	var results: Array = []
	var got_high := false
	for i in range(count):
		pity_count += 1
		total_pulls += 1
		var rarity := "R"
		if pity_count >= int(cfg.get("pity_ssr", 50)):
			rarity = "SSR"
		elif rng.randf() < float(cfg.get("rates", {}).get("SSR", 0.03)):
			rarity = "SSR"
		elif rng.randf() < 0.19 / 0.97:
			rarity = "SR"
		if count == 10 and i == count - 1 and not got_high and rarity == "R":
			rarity = "SR"
		if rarity != "R": got_high = true
		if rarity == "SSR": pity_count = 0
		var candidates: Array[String] = []
		for id in ContentDB.get_general_ids():
			if String(ContentDB.get_general(id).get("rarity", "R")) == rarity:
				candidates.append(id)
		if candidates.is_empty():
			candidates = ContentDB.get_general_ids()
		var id := candidates[rng.randi_range(0, candidates.size() - 1)]
		var state := general_state(id)
		var is_new := not bool(state.get("unlocked", false))
		if is_new:
			state["unlocked"] = true
		else:
			var soul_gain := 40 if rarity == "SSR" else (20 if rarity == "SR" else 10)
			state["soul"] = int(state.get("soul", 0)) + soul_gain
		results.append({"id":id, "rarity":rarity, "new":is_new})
	gacha_history = results.duplicate(true)
	gacha_finished.emit(results)
	changed.emit()
	return results

func next_ascension_floor() -> int:
	if ascensions == 0: return 2000
	for milestone in [2000, 3000, 5000, 8000]:
		if milestone > last_ascension_floor: return milestone
	return int(ceil(last_ascension_floor * 1.5 / 100.0)) * 100

func ascension_reward() -> Dictionary:
	ContentDB.load_all()
	var anchors: Array = ContentDB.balance.ascension.reward_anchors
	var target: float = clamp(float(highest_floor), 0.0, 8000.0)
	var right: int = 1
	while right < anchors.size() - 1 and float(anchors[right][0]) < target: right += 1
	var low: Array = anchors[right - 1]
	var high: Array = anchors[right]
	var weight: float = (target - float(low[0])) / float(high[0] - low[0])
	var keys: Array = ["attack", "hp", "defense", "resource", "fate"]
	var result: Dictionary = {}
	for i in range(keys.size()):
		result[keys[i]] = lerp(float(low[i + 1]), float(high[i + 1]), weight) / (1.0 + ascensions * 0.25)
	return result

func ascension_preview_text() -> String:
	var r: Dictionary = ascension_reward()
	var text: String = "当前最高层：%d\n飞升次数：%d\n距离推荐飞升：%d层\n" % [highest_floor, ascensions, max(0, next_ascension_floor() - highest_floor)]
	text += "本次预计：攻击 +%.1f%% / 生命 +%.1f%% / 防御 +%.1f%%\n资源 +%.1f%% / 仙缘效率 +%.1f%%\n" % [r.attack * 100, r.hp * 100, r.defense * 100, r.resource * 100, r.fate * 100]
	text += "累计：攻击 +%.1f%% / 生命 +%.1f%% / 防御 +%.1f%% / 资源 +%.1f%% / 仙缘 +%.1f%%\n" % [ascension_bonuses.attack * 100, ascension_bonuses.hp * 100, ascension_bonuses.defense * 100, ascension_bonuses.resource * 100, ascension_bonuses.fate * 100]
	return text + ("已达到飞升条件。" if can_ascend() else "尚未达到建议层数。")

func can_ascend() -> bool:
	return highest_floor >= next_ascension_floor()

func add_immortal_fate(amount: float) -> float:
	var gained: float = max(0.0, amount) * (1.0 + float(ascension_bonuses.fate))
	immortal_fate += gained
	return gained

func perform_ascension() -> int:
	if not can_ascend(): return 0
	var reward: Dictionary = ascension_reward()
	for key in reward: ascension_bonuses[key] += reward[key]
	ascensions += 1
	last_ascension_floor = highest_floor
	add_log("飞升完成！永久属性与收益提升，所有养成进度保留。")
	changed.emit()
	return 1

func predicted_floor_cap() -> int:
	var enemy_base_log := log(120.0) / log(10.0)
	var growth := log(1.035) / log(10.0)
	return max(tower_floor, int((player_attack_log10() + 1.05 - enemy_base_log) / growth))

func apply_offline(raw_seconds: int) -> Dictionary:
	if raw_seconds <= 5:
		return {}
	ContentDB.load_all()
	var cap := int(float(ContentDB.balance.get("offline_cap_hours", 48)) * 3600.0)
	var clipped := min(raw_seconds, cap)
	var full := min(clipped, 12 * 3600)
	var reduced := max(0, clipped - full)
	var effective := float(full) + float(reduced) * 0.35
	var cult_gain := cultivation_rate_per_sec() * effective
	var coin_gain := coin_rate_per_sec() * effective
	cultivation += cult_gain
	coins += coin_gain
	var possible_advance := int(effective / 12.0)
	var cap_floor := predicted_floor_cap()
	var advance := clamp(possible_advance, 0, max(0, cap_floor - tower_floor))
	if advance > 0:
		tower_floor += advance
		highest_floor = max(highest_floor, tower_floor)
		cultivation += advance * 12.0
		coins += advance * 30.0
	var retained_gear := min(8, int(effective / 1200.0))
	for i in range(retained_gear):
		add_random_equipment(max(1, int(tower_floor / 20) + 1))
	var auto_scrapped := max(0, int(effective / 240.0) - retained_gear)
	var dust_gain := auto_scrapped * max(1, int(tower_floor / 50) + 1)
	soul_dust += dust_gain
	var stone_gain := int(effective / 1800.0)
	spirit_stones += stone_gain
	var summary := {
		"raw_seconds":raw_seconds,
		"effective_seconds":int(effective),
		"cultivation":cult_gain,
		"coins":coin_gain,
		"floor_advance":advance,
		"gear":retained_gear,
		"auto_scrapped":auto_scrapped,
		"dust":dust_gain,
		"stones":stone_gain
	}
	add_log("离线结算：%s，推进 %d 层，保留装备 %d 件。" % [_format_duration(raw_seconds), advance, retained_gear])
	offline_applied.emit(summary)
	changed.emit()
	return summary

func _format_duration(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	if h > 0: return "%d小时%d分" % [h, m]
	return "%d分钟" % max(1, m)

func add_log(text: String) -> void:
	battle_log.push_front(text)
	while battle_log.size() > 80:
		battle_log.pop_back()
	log_added.emit(text)

func to_dict() -> Dictionary:
	return {
		"cultivation":cultivation, "coins":coins, "spirit_stones":spirit_stones,
		"soul_dust":soul_dust, "immortal_fate":immortal_fate,
		"ascensions":ascensions, "last_ascension_floor":last_ascension_floor, "ascension_bonuses":ascension_bonuses, "legacy_fate":legacy_fate,
		"realm_index":realm_index, "realm_stage":realm_stage,
		"tower_floor":tower_floor, "highest_floor":highest_floor,
		"total_play_seconds":total_play_seconds, "active_general_id":active_general_id,
		"general_progress":general_progress, "inventory":inventory, "equipped":equipped,
		"pity_count":pity_count, "total_pulls":total_pulls,
		"last_saved_unix":last_saved_unix, "dark_mode":dark_mode,
		"battle_speed":battle_speed, "auto_battle":auto_battle,
		"battle_log":battle_log
	}

func from_dict(data: Dictionary) -> void:
	ContentDB.load_all()
	cultivation = float(data.get("cultivation", 0.0))
	coins = float(data.get("coins", 2500.0))
	spirit_stones = int(data.get("spirit_stones", 2200))
	soul_dust = int(data.get("soul_dust", 0))
	immortal_fate = float(data.get("immortal_fate", 0))
	legacy_fate = float(data.get("legacy_fate", immortal_fate))
	ascensions = max(0, int(data.get("ascensions", 0)))
	last_ascension_floor = int(data.get("last_ascension_floor", 0))
	for key in ascension_bonuses: ascension_bonuses[key] = max(0.0, float(data.get("ascension_bonuses", {}).get(key, 0.0)))
	realm_index = int(data.get("realm_index", 0))
	realm_stage = int(data.get("realm_stage", 1))
	tower_floor = int(data.get("tower_floor", 1))
	highest_floor = int(data.get("highest_floor", tower_floor))
	total_play_seconds = float(data.get("total_play_seconds", 0.0))
	active_general_id = String(data.get("active_general_id", "guanyu"))
	var loaded_progress: Dictionary = data.get("general_progress", {})
	general_progress = loaded_progress.duplicate(true)
	for id in ContentDB.get_general_ids():
		if not general_progress.has(id):
			general_progress[id] = {"unlocked":false, "level":1, "stars":1, "soul":0, "soul_rank":0}
		elif not general_progress[id].has("soul_rank"):
			general_progress[id]["soul_rank"] = 0
	var loaded_inventory: Array = data.get("inventory", [])
	inventory = loaded_inventory.duplicate(true)
	var loaded_equipped: Dictionary = data.get("equipped", {"weapon":"", "armor":"", "accessory":""})
	equipped = loaded_equipped.duplicate(true)
	pity_count = int(data.get("pity_count", 0))
	total_pulls = int(data.get("total_pulls", 0))
	last_saved_unix = int(data.get("last_saved_unix", int(Time.get_unix_time_from_system())))
	dark_mode = bool(data.get("dark_mode", false))
	battle_speed = float(data.get("battle_speed", 1.0))
	auto_battle = bool(data.get("auto_battle", true))
	battle_log.clear()
	for line in Array(data.get("battle_log", [])):
		battle_log.append(String(line))
	if not is_general_unlocked(active_general_id):
		active_general_id = "guanyu"
	changed.emit()
