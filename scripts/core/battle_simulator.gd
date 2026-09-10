extends Node

signal battle_updated
signal floor_won(floor: int)
signal floor_lost(floor: int)

var hero_hp := BigNum.new()
var hero_max_hp := BigNum.new()
var enemy_hp := BigNum.new()
var enemy_max_hp := BigNum.new()
var enemy_attack := BigNum.new()
var hero_hand: Array = []
var enemy_hand: Array = []
var hero_deck: Array = []
var enemy_deck: Array = []
var turn_index := 0
var accumulator := 0.0
var running := false
var caocao_rage := 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func start() -> void:
	reset_floor()
	running = true

func reset_floor() -> void:
	turn_index = 0
	caocao_rage = 0
	hero_deck = _build_deck(false)
	enemy_deck = _build_deck(true)
	hero_hand.clear()
	enemy_hand.clear()
	hero_max_hp = BigNum.from_log10(GameState.player_hp_log10())
	hero_hp = hero_max_hp.clone()
	var floor := max(1, GameState.tower_floor)
	var hp_log := log(125.0) / log(10.0) + float(floor - 1) * (log(1.035) / log(10.0))
	var atk_log := log(15.0) / log(10.0) + float(floor - 1) * (log(1.033) / log(10.0))
	if floor % 10 == 0:
		hp_log += 0.16
		atk_log += 0.07
	enemy_max_hp = BigNum.from_log10(hp_log)
	enemy_hp = enemy_max_hp.clone()
	enemy_attack = BigNum.from_log10(atk_log)
	_draw_cards(hero_deck, hero_hand, 4, false)
	_draw_cards(enemy_deck, enemy_hand, 4, true)
	battle_updated.emit()

func _process(delta: float) -> void:
	if not running or not GameState.auto_battle:
		return
	accumulator += delta * max(0.25, GameState.battle_speed)
	if accumulator >= 0.72:
		accumulator = 0.0
		advance_turn()

func advance_turn() -> void:
	if hero_hp.is_zero() or enemy_hp.is_zero():
		reset_floor()
		return
	turn_index += 1
	_draw_cards(hero_deck, hero_hand, 2, false)
	_draw_cards(enemy_deck, enemy_hand, 2, true)
	_apply_start_turn_general()
	_hero_action()
	if enemy_hp.is_zero():
		_resolve_win()
		return
	_enemy_action()
	if hero_hp.is_zero():
		_resolve_loss()
		return
	battle_updated.emit()

func _build_deck(enemy: bool) -> Array:
	var deck: Array = []
	for i in range(5):
		deck.append(_card("slash", "red" if i % 2 == 0 else "black"))
	for i in range(3):
		deck.append(_card("dodge", "red" if i == 0 else "black"))
	deck.append(_card("peach", "red"))
	for i in range(3):
		deck.append(_card("tactic", "red" if i == 0 else "black"))
	if enemy:
		deck.append(_card("dodge", "black"))
	deck.shuffle()
	return deck

func _card(type_name: String, color: String) -> Dictionary:
	var data := ContentDB.get_card(type_name)
	return {"type":type_name, "name":String(data.get("name", type_name)), "color":color}

func _draw_cards(deck: Array, hand: Array, count: int, enemy: bool = false) -> void:
	for i in range(count):
		if deck.is_empty():
			deck.append_array(_build_deck(enemy))
		if not deck.is_empty():
			hand.append(deck.pop_back())
	while hand.size() > 10:
		hand.pop_front()

func _apply_start_turn_general() -> void:
	var id := GameState.active_general_id
	if id == "sunquan" and turn_index % 2 == 0 and hero_hand.size() >= 4:
		var removed := 0
		for idx in range(hero_hand.size() - 1, -1, -1):
			if removed >= 2: break
			var card: Dictionary = hero_hand[idx]
			if String(card.get("type", "")) == "tactic" or String(card.get("type", "")) == "peach":
				continue
			hero_hand.remove_at(idx)
			removed += 1
		if removed > 0:
			_draw_cards(hero_deck, hero_hand, removed + 1, false)
			GameState.add_log("【制衡】弃置低价值手牌，重新摸取 %d 张。" % (removed + 1))
	elif id == "caocao" and caocao_rage > 0:
		GameState.add_log("【奸雄】反击层数 %d，本回合伤害提高。" % caocao_rage)

func _hero_action() -> void:
	if hero_hp.ratio_to(hero_max_hp) < 0.42:
		var peach_idx := _find_card(hero_hand, "peach")
		if peach_idx >= 0:
			hero_hand.remove_at(peach_idx)
			var heal := hero_max_hp.multiplied_scalar(0.24)
			hero_hp = hero_hp.added(heal)
			if hero_hp.compare_to(hero_max_hp) > 0: hero_hp = hero_max_hp.clone()
			GameState.add_log("%s 使用【桃】，恢复生命。" % _hero_name())
	var attacks := 0
	var max_attacks := 3 if GameState.active_general_id == "zhangfei" else 1
	while attacks < max_attacks:
		var attack_info := _take_attack_card()
		if attack_info.is_empty():
			break
		attacks += 1
		var multiplier := float(attack_info.get("mult", 1.0))
		var star := int(GameState.general_state(GameState.active_general_id).get("stars", 1))
		var skill_version := ContentDB.get_general_skill_version(GameState.active_general_id, star)
		multiplier *= float(skill_version.get("skill_scale", 1.0))
		if GameState.active_general_id == "zhangfei":
			multiplier *= 1.0 + (attacks - 1) * 0.22
			if attacks >= 2:
				GameState.add_log("【咆哮】第 %d 次连续出杀！" % attacks)
		if GameState.active_general_id == "caocao":
			multiplier *= 1.0 + caocao_rage * 0.10
		var hero_attack := BigNum.from_log10(GameState.player_attack_log10()).multiplied_scalar(multiplier)
		var crit := rng.randf() < 0.12 + min(0.18, GameState.active_general_level() * 0.002)
		if crit:
			hero_attack = hero_attack.multiplied_scalar(1.8)
		var required_dodges := 2 if GameState.active_general_id == "lvbu" else 1
		var dodges := _consume_cards(enemy_hand, "dodge", required_dodges)
		if dodges >= required_dodges:
			GameState.add_log("%s 的【%s】被敌人%s抵消。" % [_hero_name(), String(attack_info.get("name", "杀")), "连续响应" if required_dodges > 1 else "【闪】"])
		else:
			if GameState.active_general_id == "lvbu" and dodges > 0:
				GameState.add_log("【无双】敌人只有一张【闪】，防御被击穿！")
			enemy_hp = enemy_hp.subtracted(hero_attack)
			GameState.add_log("%s 使用【%s】造成 %s%s。" % [_hero_name(), String(attack_info.get("name", "杀")), hero_attack.short(), " 暴击" if crit else ""])
		if enemy_hp.is_zero():
			break
	if attacks == 0:
		var tactic_idx := _find_card(hero_hand, "tactic")
		if tactic_idx >= 0:
			hero_hand.remove_at(tactic_idx)
			var dmg := BigNum.from_log10(GameState.player_attack_log10()).multiplied_scalar(1.28)
			enemy_hp = enemy_hp.subtracted(dmg)
			GameState.add_log("%s 使用【锦囊】造成 %s。" % [_hero_name(), dmg.short()])
		else:
			GameState.add_log("%s 暂无合适战牌，蓄势一回合。" % _hero_name())

func _take_attack_card() -> Dictionary:
	var slash_idx := _find_card(hero_hand, "slash")
	if slash_idx >= 0:
		var card: Dictionary = hero_hand[slash_idx]
		hero_hand.remove_at(slash_idx)
		var display_name := String(card.get("name", "杀"))
		var card_mult := 1.12 if GameState.active_general_id == "caocao" and display_name != "杀" else 1.0
		return {"name":display_name, "mult":card_mult, "card":card}
	var id := GameState.active_general_id
	if id == "zhaoyun":
		var dodge_idx := _find_card(hero_hand, "dodge")
		if dodge_idx >= 0:
			hero_hand.remove_at(dodge_idx)
			GameState.add_log("【龙胆】将【闪】转化为【杀】。")
			return {"name":"龙胆·杀", "mult":1.12}
	if id == "guanyu":
		for i in range(hero_hand.size()):
			var card: Dictionary = hero_hand[i]
			if String(card.get("color", "")) == "red":
				hero_hand.remove_at(i)
				GameState.add_log("【武圣】红色战牌转化为强化【杀】。")
				return {"name":"武圣·杀", "mult":1.36}
	return {}

func _enemy_action() -> void:
	var slash_idx := _find_card(enemy_hand, "slash")
	if slash_idx < 0 and turn_index % 2 == 1:
		return
	if slash_idx >= 0:
		enemy_hand.remove_at(slash_idx)
	var defended := false
	var dodge_idx := _find_card(hero_hand, "dodge")
	if dodge_idx >= 0:
		hero_hand.remove_at(dodge_idx)
		defended = true
	elif GameState.active_general_id == "zhaoyun":
		var hero_slash_idx := _find_card(hero_hand, "slash")
		if hero_slash_idx >= 0:
			hero_hand.remove_at(hero_slash_idx)
			defended = true
			GameState.add_log("【龙胆】将【杀】转化为【闪】。")
	if defended:
		GameState.add_log("%s 使用【闪】避开敌方攻击。" % _hero_name())
		return
	var damage := enemy_attack.clone()
	if GameState.active_general_id == "caocao":
		caocao_rage = min(8, caocao_rage + 1)
		hero_hand.append({"type":"slash", "name":"战法映像", "color":"black"})
		GameState.add_log("【奸雄】受到伤害后复制一张攻击战牌。")
	if GameState.active_general_id == "lvbu":
		damage = damage.multiplied_scalar(0.92)
	damage = damage.multiplied_scalar(1.0 / (1.0 + float(GameState.ascension_bonuses.defense)))
	hero_hp = hero_hp.subtracted(damage)
	GameState.add_log("敌人命中 %s，造成 %s。" % [_hero_name(), damage.short()])

func _resolve_win() -> void:
	var cleared := GameState.tower_floor
	GameState.on_floor_cleared()
	floor_won.emit(cleared)
	reset_floor()

func _resolve_loss() -> void:
	var floor := GameState.tower_floor
	GameState.add_log("第 %d 层挑战失败，自动在当前层继续挂机积累。" % floor)
	floor_lost.emit(floor)
	reset_floor()

func _find_card(hand: Array, type_name: String) -> int:
	for i in range(hand.size()):
		if String(hand[i].get("type", "")) == type_name:
			return i
	return -1

func _consume_cards(hand: Array, type_name: String, count: int) -> int:
	var consumed := 0
	while consumed < count:
		var idx := _find_card(hand, type_name)
		if idx < 0: break
		hand.remove_at(idx)
		consumed += 1
	return consumed

func _hero_name() -> String:
	return String(ContentDB.get_general(GameState.active_general_id).get("name", "主将"))
