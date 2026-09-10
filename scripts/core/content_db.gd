extends Node

var generals: Dictionary = {}
var balance: Dictionary = {}
var cards: Dictionary = {}
var equipment: Dictionary = {}
var skin_memory: Dictionary = {}
var loaded := false

func load_all() -> void:
	if loaded:
		return
	generals = _load_json("res://data/generals.json")
	balance = _load_json("res://data/balance.json")
	cards = _load_json("res://data/cards.json")
	equipment = _load_json("res://data/equipment.json")
	skin_memory = _load_json("res://data/skin_memory.json")
	loaded = true

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("缺少数据文件: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON 格式错误: %s" % path)
		return {}
	return parsed

func get_general(id: String) -> Dictionary:
	load_all()
	return generals.get(id, {})

func get_general_ids() -> Array[String]:
	load_all()
	var out: Array[String] = []
	for key in generals.keys():
		out.append(String(key))
	return out

func get_card(id: String) -> Dictionary:
	load_all()
	return cards.get(id, {})

func get_general_skill_version(id: String, star: int = 1) -> Dictionary:
	var general := get_general(id)
	var versions: Array = general.get("skill_versions", [])
	if versions.is_empty():
		return {"star": star, "name": String(general.get("skill_name", "技能")), "description": String(general.get("skill_description", "")), "skill_scale": 1.0, "trigger_bonus": 0.0, "combat_bonus": {}}
	var index := clampi(star - 1, 0, versions.size() - 1)
	return versions[index]
