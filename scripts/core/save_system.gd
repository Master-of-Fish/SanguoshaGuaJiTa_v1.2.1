extends Node

signal save_loaded
signal save_written
signal import_finished(ok: bool, message: String)

const SAVE_PATH := "user://save_main.json"
const SAVE_VERSION := 9
const AUTOSAVE_SEC := 12.0
const BACKUP_KEEP := 5

var _autosave_accum := 0.0
var _loaded := false

func _process(delta: float) -> void:
	if not _loaded:
		return
	_autosave_accum += delta
	if _autosave_accum >= AUTOSAVE_SEC:
		_autosave_accum = 0.0
		save_now(false)

func load_or_init() -> Dictionary:
	ContentDB.load_all()
	var offline_summary: Dictionary = {}
	if not FileAccess.file_exists(SAVE_PATH):
		GameState.reset_new_game()
		save_now(true)
		_loaded = true
		save_loaded.emit()
		return offline_summary
	var decoded := _read_wrapper(SAVE_PATH)
	if not bool(decoded.get("ok", false)):
		push_warning("存档损坏，创建新存档：%s" % String(decoded.get("message", "未知错误")))
		_backup_raw_file(SAVE_PATH, "corrupt")
		GameState.reset_new_game()
		save_now(true)
		_loaded = true
		save_loaded.emit()
		return offline_summary
	var raw_payload: Dictionary = decoded.get("payload", {})
	var payload: Dictionary = migrate(raw_payload)
	var gs: Dictionary = payload.get("game_state", {})
	GameState.from_dict(gs)
	var now := int(Time.get_unix_time_from_system())
	var last := int(payload.get("saved_at", GameState.last_saved_unix))
	offline_summary = GameState.apply_offline(max(0, now - last))
	GameState.last_saved_unix = now
	_loaded = true
	save_loaded.emit()
	return offline_summary

func save_now(force: bool = false) -> bool:
	if not force and not _loaded:
		return false
	GameState.last_saved_unix = int(Time.get_unix_time_from_system())
	var payload := _make_payload()
	var text := _encode_wrapper(payload)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入存档：%s" % SAVE_PATH)
		return false
	file.store_string(text)
	file.close()
	save_written.emit()
	return true

func _make_payload() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"game_state": GameState.to_dict()
	}

func _encode_wrapper(payload: Dictionary) -> String:
	var payload_text := JSON.stringify(payload)
	var wrapper := {
		"format":"DXT_SAVE",
		"checksum":payload_text.sha256_text(),
		"payload_text":payload_text
	}
	return JSON.stringify(wrapper, "\t")

func _decode_wrapper_text(raw: String) -> Dictionary:
	var wrapper_var: Variant = JSON.parse_string(raw)
	if typeof(wrapper_var) != TYPE_DICTIONARY:
		return {"ok":false, "message":"不是有效的三国杀挂机塔存档"}
	var wrapper: Dictionary = wrapper_var
	if String(wrapper.get("format", "")) != "DXT_SAVE":
		return {"ok":false, "message":"存档格式标记不匹配"}
	var payload_text := String(wrapper.get("payload_text", ""))
	if payload_text.is_empty():
		return {"ok":false, "message":"存档内容为空"}
	if String(wrapper.get("checksum", "")) != payload_text.sha256_text():
		return {"ok":false, "message":"校验失败，文件可能损坏"}
	var payload_var: Variant = JSON.parse_string(payload_text)
	if typeof(payload_var) != TYPE_DICTIONARY:
		return {"ok":false, "message":"存档主体无法解析"}
	var payload: Dictionary = payload_var
	var version := int(payload.get("version", 0))
	if version > SAVE_VERSION:
		return {"ok":false, "message":"该存档来自更新版本（v%d），当前版本仅支持 v%d" % [version, SAVE_VERSION]}
	return {"ok":true, "payload":payload}

func _read_wrapper(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok":false, "message":"无法打开文件"}
	var raw := file.get_as_text()
	file.close()
	return _decode_wrapper_text(raw)

func migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("version", 1))
	while version < SAVE_VERSION:
		match version:
			8:
				pass # v1.1.1 fields migrate in GameState.from_dict; preserve legacy fate once.
			_:
				push_warning("缺少从 v%d 开始的存档迁移规则" % version)
				break
		version += 1
	payload["version"] = SAVE_VERSION
	return payload

func export_to_file(path: String) -> bool:
	save_now(true)
	var source := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if source == null:
		return false
	var raw := source.get_as_text()
	source.close()
	var target_path := path
	if not target_path.to_lower().ends_with(".json"):
		target_path += ".json"
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string(raw)
	target.close()
	return true

func import_from_file(path: String) -> Dictionary:
	var decoded := _read_wrapper(path)
	if not bool(decoded.get("ok", false)):
		return decoded
	_backup_current("pre_import")
	var raw_payload: Dictionary = decoded.get("payload", {})
	var payload := migrate(raw_payload)
	var gs: Dictionary = payload.get("game_state", {})
	GameState.from_dict(gs)
	GameState.last_saved_unix = int(Time.get_unix_time_from_system())
	save_now(true)
	return {"ok":true, "message":"导入成功，当前存档已自动备份"}

func get_save_code() -> String:
	save_now(true)
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var raw := file.get_as_text()
	file.close()
	return "DXT1-" + Marshalls.raw_to_base64(raw.to_utf8_buffer())

func import_save_code(code: String) -> Dictionary:
	var clean := code.strip_edges()
	if not clean.begins_with("DXT1-"):
		return {"ok":false, "message":"存档码前缀不正确"}
	var bytes := Marshalls.base64_to_raw(clean.trim_prefix("DXT1-"))
	if bytes.is_empty():
		return {"ok":false, "message":"存档码无法解码"}
	var decoded := _decode_wrapper_text(bytes.get_string_from_utf8())
	if not bool(decoded.get("ok", false)):
		return decoded
	_backup_current("pre_code_import")
	var raw_payload: Dictionary = decoded.get("payload", {})
	var payload := migrate(raw_payload)
	var gs: Dictionary = payload.get("game_state", {})
	GameState.from_dict(gs)
	GameState.last_saved_unix = int(Time.get_unix_time_from_system())
	save_now(true)
	return {"ok":true, "message":"存档码导入成功"}

func _backup_current(label: String) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_backup_raw_file(SAVE_PATH, label)

func _backup_raw_file(source_path: String, label: String) -> void:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return
	var raw := source.get_as_text()
	source.close()
	var dir_global := ProjectSettings.globalize_path("user://backups")
	DirAccess.make_dir_recursive_absolute(dir_global)
	var backup_path := "user://backups/save_%s_%d.json" % [label, int(Time.get_unix_time_from_system())]
	var out := FileAccess.open(backup_path, FileAccess.WRITE)
	if out != null:
		out.store_string(raw)
		out.close()
	_trim_backups()

func _trim_backups() -> void:
	var dir := DirAccess.open("user://backups")
	if dir == null:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".json"):
			files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	while files.size() > BACKUP_KEEP:
		dir.remove(files.pop_front())
