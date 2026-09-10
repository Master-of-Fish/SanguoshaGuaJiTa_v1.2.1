extends Control

const BLUE := Color("#2080f0")
const GREEN := Color("#18a058")
const RED := Color("#d03050")
const ORANGE := Color("#f0a020")
const PURPLE := Color("#8a2be2")

var current_page := "登塔"
var page_host: VBoxContainer
var background: ColorRect
var nav_buttons: Dictionary = {}
var stat_labels: Dictionary = {}
var notice_dialog: AcceptDialog
var passive_accum := 0.0
var dynamic_accum := 0.0

var battle_refs: Dictionary = {}
var cultivation_refs: Dictionary = {}

func _ready() -> void:
	ContentDB.load_all()
	var offline_summary := SaveSystem.load_or_init()
	_build_shell()
	_connect_signals()
	BattleSimulator.start()
	_render_page()
	_refresh_header()
	if not offline_summary.is_empty():
		call_deferred("_show_offline_summary", offline_summary)

func _process(delta: float) -> void:
	passive_accum += delta
	dynamic_accum += delta
	if passive_accum >= 0.25:
		GameState.tick_passive(passive_accum)
		passive_accum = 0.0
	if dynamic_accum >= 0.25:
		dynamic_accum = 0.0
		_refresh_dynamic()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_now(true)
		get_tree().quit()

func _connect_signals() -> void:
	GameState.changed.connect(_refresh_header)
	GameState.log_added.connect(_on_log_added)
	BattleSimulator.battle_updated.connect(_refresh_battle)
	BattleSimulator.floor_won.connect(_on_floor_changed)
	BattleSimulator.floor_lost.connect(_on_floor_changed)

func _build_shell() -> void:
	background = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 26)
	outer.add_theme_constant_override("margin_right", 26)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	add_child(outer)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	outer.add_child(shell)

	var header_content := VBoxContainer.new()
	header_content.add_theme_constant_override("separation", 8)
	var top_row := HBoxContainer.new()
	var title_box := VBoxContainer.new()
	var title := Label.new()
	title.text = "三国杀挂机塔"
	title.add_theme_font_size_override("font_size", 24)
	var subtitle := Label.new()
	subtitle.text = "挂机修仙 × 三国武将自动战策"
	subtitle.add_theme_font_size_override("font_size", 12)
	title_box.add_child(title)
	title_box.add_child(subtitle)
	top_row.add_child(title_box)
	top_row.add_spacer(false)
	for key in ["realm", "floor", "coins", "stones", "power"]:
		var lab := Label.new()
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.custom_minimum_size = Vector2(118, 0)
		stat_labels[key] = lab
		top_row.add_child(lab)
	header_content.add_child(top_row)
	var header_panel := _wrap_panel(header_content, 16)
	header_panel.custom_minimum_size.y = 78
	shell.add_child(header_panel)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	for page in ["登塔", "修炼", "武将", "抽卡", "背包", "设置"]:
		var page_name: String = page
		var btn := Button.new()
		btn.text = page_name
		btn.custom_minimum_size = Vector2(100, 38)
		btn.pressed.connect(func(): _switch_page(page_name))
		nav_buttons[page] = btn
		nav.add_child(btn)
	nav.add_spacer(false)
	shell.add_child(nav)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	page_host = VBoxContainer.new()
	page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_host.add_theme_constant_override("separation", 12)
	scroll.add_child(page_host)

	notice_dialog = AcceptDialog.new()
	notice_dialog.title = "三国杀挂机塔"
	add_child(notice_dialog)
	_apply_theme()

func _apply_theme() -> void:
	var dark := GameState.dark_mode
	background.color = Color("#101014") if dark else Color("#f4f6f8")
	var text := Color("#e8e8e8") if dark else Color("#1f2329")
	var muted := Color("#9aa0a6") if dark else Color("#646a73")
	var base_panel := Color("#18181c") if dark else Color("#ffffff")
	var button_bg := Color("#242429") if dark else Color("#ffffff")
	var button_hover := Color("#2d2d33") if dark else Color("#f2f6fc")
	var theme_obj := Theme.new()
	theme_obj.set_font_size("font_size", "Label", 14)
	theme_obj.set_font_size("font_size", "Button", 14)
	theme_obj.set_color("font_color", "Label", text)
	theme_obj.set_color("font_color", "Button", text)
	theme_obj.set_color("font_hover_color", "Button", BLUE)
	theme_obj.set_color("font_pressed_color", "Button", BLUE)
	theme_obj.set_color("font_disabled_color", "Button", muted)
	var btn_normal := _style_box(button_bg, Color("#33333a") if dark else Color("#dcdfe6"), 1)
	var btn_hover := _style_box(button_hover, BLUE, 1)
	var btn_pressed := _style_box(Color("#1c2735") if dark else Color("#e8f3ff"), BLUE, 1)
	theme_obj.set_stylebox("normal", "Button", btn_normal)
	theme_obj.set_stylebox("hover", "Button", btn_hover)
	theme_obj.set_stylebox("pressed", "Button", btn_pressed)
	theme_obj.set_stylebox("focus", "Button", _style_box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	var panel_style := _style_box(base_panel, Color("#2c2c32") if dark else Color("#e5e7eb"), 1)
	theme_obj.set_stylebox("panel", "PanelContainer", panel_style)
	theme_obj.set_color("font_color", "LineEdit", text)
	theme_obj.set_color("font_placeholder_color", "LineEdit", muted)
	theme_obj.set_stylebox("normal", "LineEdit", _style_box(Color("#202025") if dark else Color("#ffffff"), Color("#3a3a42") if dark else Color("#dcdfe6"), 1))
	theme_obj.set_stylebox("read_only", "LineEdit", _style_box(Color("#202025") if dark else Color("#f7f8fa"), Color("#3a3a42") if dark else Color("#dcdfe6"), 1))
	theme_obj.set_color("font_color", "RichTextLabel", text)
	theme_obj.set_color("default_color", "RichTextLabel", text)
	theme_obj.set_stylebox("background", "RichTextLabel", _style_box(Color("#141418") if dark else Color("#fafafa"), Color("#2f2f35") if dark else Color("#eeeeee"), 1))
	theme_obj.set_stylebox("background", "ProgressBar", _style_box(Color("#25252a") if dark else Color("#e8eef7"), Color.TRANSPARENT, 0))
	theme_obj.set_stylebox("fill", "ProgressBar", _style_box(BLUE, Color.TRANSPARENT, 0))
	theme = theme_obj
	for node in _find_all_labels(self):
		if node.has_meta("muted"):
			node.add_theme_color_override("font_color", muted)
	for page in nav_buttons.keys():
		_style_nav_button(nav_buttons[page], page == current_page)

func _find_all_labels(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Label:
			out.append(child)
		out.append_array(_find_all_labels(child))
	return out

func _style_nav_button(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_stylebox_override("normal", _style_box(BLUE, BLUE, 1))
		btn.add_theme_stylebox_override("hover", _style_box(Color("#4098f7"), BLUE, 1))
	else:
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_stylebox_override("hover")

func _style_box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_left = 8
	box.corner_radius_bottom_right = 8
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func _wrap_panel(content: Control, padding: int = 14, border_color: Color = Color.TRANSPARENT) -> PanelContainer:
	var panel := PanelContainer.new()
	if border_color != Color.TRANSPARENT:
		var bg := Color("#18181c") if GameState.dark_mode else Color.WHITE
		panel.add_theme_stylebox_override("panel", _style_box(bg, border_color, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", padding)
	margin.add_theme_constant_override("margin_right", padding)
	margin.add_theme_constant_override("margin_top", padding)
	margin.add_theme_constant_override("margin_bottom", padding)
	panel.add_child(margin)
	margin.add_child(content)
	return panel

func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.set_meta("muted", true)
	label.add_theme_color_override("font_color", Color("#8b9199"))
	return label

func _section_title(text: String, desc: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	if not desc.is_empty():
		var sub := _muted_label(desc)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(sub)
	return box

func _primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(44, 44)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _style_box(BLUE, BLUE, 1))
	btn.add_theme_stylebox_override("hover", _style_box(Color("#4098f7"), BLUE, 1))
	btn.add_theme_stylebox_override("pressed", _style_box(Color("#106dc0"), BLUE, 1))
	return btn

func _danger_button(text: String) -> Button:
	var btn := _primary_button(text)
	btn.add_theme_stylebox_override("normal", _style_box(RED, RED, 1))
	btn.add_theme_stylebox_override("hover", _style_box(Color("#de576d"), RED, 1))
	return btn

func _switch_page(page: String) -> void:
	current_page = page
	for key in nav_buttons.keys():
		_style_nav_button(nav_buttons[key], key == current_page)
	_render_page()

func _clear_page() -> void:
	battle_refs.clear()
	cultivation_refs.clear()
	for child in page_host.get_children():
		child.queue_free()

func _render_page() -> void:
	_clear_page()
	match current_page:
		"登塔": _render_tower_page()
		"修炼": _render_cultivation_page()
		"武将": _render_generals_page()
		"抽卡": _render_gacha_page()
		"背包": _render_inventory_page()
		"设置": _render_settings_page()
	_apply_theme()
	_refresh_dynamic()

func _refresh_header() -> void:
	if stat_labels.is_empty():
		return
	stat_labels["realm"].text = "境界\n%s" % GameState.realm_name()
	stat_labels["floor"].text = "三国杀挂机塔\n%d 层" % GameState.tower_floor
	stat_labels["coins"].text = "铜钱\n%s" % _short_float(GameState.coins)
	stat_labels["stones"].text = "灵石\n%d" % GameState.spirit_stones
	stat_labels["power"].text = "战力\n%s" % GameState.combat_power_text()

func _refresh_dynamic() -> void:
	_refresh_header()
	_refresh_battle()
	_refresh_cultivation()

func _render_tower_page() -> void:
	page_host.add_child(_section_title("自动登塔", "战斗底层保留摸牌、出牌、响应、转化等机制，但由 AI 自动执行。挂机与离线不要求玩家手动出牌。"))
	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", 10)
	for item in [["当前层", str(GameState.tower_floor)], ["最高层", str(GameState.highest_floor)], ["主将", _hero_name()], ["战斗速度", "×%.0f" % GameState.battle_speed]]:
		var box := VBoxContainer.new()
		var val := Label.new(); val.text = item[1]; val.add_theme_font_size_override("font_size", 22)
		box.add_child(_muted_label(item[0])); box.add_child(val)
		var p := _wrap_panel(box, 13)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.add_child(p)
	page_host.add_child(summary)

	var battle := HBoxContainer.new()
	battle.add_theme_constant_override("separation", 16)
	var hero_box := VBoxContainer.new()
	var hero_name := Label.new(); hero_name.text = _hero_name(); hero_name.add_theme_font_size_override("font_size", 23)
	var hero_skill := Label.new(); hero_skill.text = "【%s】%s" % [String(ContentDB.get_general(GameState.active_general_id).get("skill_name", "")), String(ContentDB.get_general(GameState.active_general_id).get("archetype", ""))]
	hero_skill.add_theme_color_override("font_color", BLUE)
	var hero_hp_label := Label.new()
	var hero_bar := ProgressBar.new(); hero_bar.show_percentage = false; hero_bar.custom_minimum_size = Vector2(0, 18)
	var hand := Label.new(); hand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_box.add_child(hero_name); hero_box.add_child(hero_skill); hero_box.add_child(hero_hp_label); hero_box.add_child(hero_bar); hero_box.add_child(hand)
	var hero_panel := _wrap_panel(hero_box, 18, BLUE); hero_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle.add_child(hero_panel)

	var vs := VBoxContainer.new(); vs.custom_minimum_size.x = 140
	var floor_badge := Label.new(); floor_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; floor_badge.add_theme_font_size_override("font_size", 16)
	var vs_label := Label.new(); vs_label.text = "VS"; vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vs_label.add_theme_font_size_override("font_size", 30)
	var auto_label := _muted_label("全自动战策"); auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.add_spacer(false); vs.add_child(floor_badge); vs.add_child(vs_label); vs.add_child(auto_label); vs.add_spacer(false)
	battle.add_child(vs)

	var enemy_box := VBoxContainer.new()
	var enemy_name := Label.new(); enemy_name.add_theme_font_size_override("font_size", 23)
	var enemy_tag := Label.new(); enemy_tag.text = "三国杀挂机塔守层者"; enemy_tag.add_theme_color_override("font_color", RED)
	var enemy_hp_label := Label.new()
	var enemy_bar := ProgressBar.new(); enemy_bar.show_percentage = false; enemy_bar.custom_minimum_size = Vector2(0, 18)
	var enemy_hand := Label.new(); enemy_hand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_box.add_child(enemy_name); enemy_box.add_child(enemy_tag); enemy_box.add_child(enemy_hp_label); enemy_box.add_child(enemy_bar); enemy_box.add_child(enemy_hand)
	var enemy_panel := _wrap_panel(enemy_box, 18, RED); enemy_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle.add_child(enemy_panel)
	page_host.add_child(battle)

	battle_refs = {"hero_hp_label":hero_hp_label, "hero_bar":hero_bar, "hand":hand, "enemy_name":enemy_name, "enemy_hp_label":enemy_hp_label, "enemy_bar":enemy_bar, "enemy_hand":enemy_hand, "floor_badge":floor_badge}

	var controls := HBoxContainer.new(); controls.add_theme_constant_override("separation", 8)
	var auto_btn := _primary_button("暂停自动战斗" if GameState.auto_battle else "继续自动战斗")
	auto_btn.pressed.connect(func():
		GameState.auto_battle = not GameState.auto_battle
		GameState.changed.emit()
		_render_page()
	)
	controls.add_child(auto_btn)
	for speed in [1.0, 2.0, 4.0]:
		var speed_value: float = speed
		var btn := Button.new(); btn.text = "×%d" % int(speed_value); btn.custom_minimum_size = Vector2(70, 38)
		btn.pressed.connect(func():
			GameState.battle_speed = speed_value
			GameState.changed.emit()
			_render_page()
		)
		controls.add_child(btn)
	var step_btn := Button.new(); step_btn.text = "单步测试"; step_btn.custom_minimum_size = Vector2(96, 38)
	step_btn.pressed.connect(func(): BattleSimulator.advance_turn())
	controls.add_child(step_btn)
	controls.add_spacer(false)
	var upgrade_btn := _primary_button("一键升级 · 起价%s铜钱" % _short_float(GameState.general_upgrade_cost(GameState.active_general_id)))
	upgrade_btn.pressed.connect(_upgrade_general)
	controls.add_child(upgrade_btn)
	page_host.add_child(controls)

	var log_box := VBoxContainer.new()
	var log_head := HBoxContainer.new(); var log_title := Label.new(); log_title.text = "战斗日志"; log_title.add_theme_font_size_override("font_size", 17)
	log_head.add_child(log_title); log_head.add_spacer(false); log_head.add_child(_muted_label("仅显示最近 14 条"))
	var log := RichTextLabel.new(); log.bbcode_enabled = true; log.fit_content = false; log.custom_minimum_size.y = 230
	log_box.add_child(log_head); log_box.add_child(log)
	page_host.add_child(_wrap_panel(log_box, 14))
	battle_refs["log"] = log
	_refresh_battle()
	_refresh_log()

func _refresh_battle() -> void:
	if current_page != "登塔" or battle_refs.is_empty(): return
	if not is_instance_valid(battle_refs.get("hero_bar")): return
	battle_refs["hero_bar"].value = BattleSimulator.hero_hp.ratio_to(BattleSimulator.hero_max_hp) * 100.0
	battle_refs["enemy_bar"].value = BattleSimulator.enemy_hp.ratio_to(BattleSimulator.enemy_max_hp) * 100.0
	battle_refs["hero_hp_label"].text = "生命 %s / %s" % [BattleSimulator.hero_hp.short(), BattleSimulator.hero_max_hp.short()]
	battle_refs["enemy_hp_label"].text = "生命 %s / %s" % [BattleSimulator.enemy_hp.short(), BattleSimulator.enemy_max_hp.short()]
	battle_refs["enemy_name"].text = "守层者 · %d" % GameState.tower_floor
	battle_refs["floor_badge"].text = "第 %d 层" % GameState.tower_floor
	battle_refs["hand"].text = "手牌：%s" % _hand_text(BattleSimulator.hero_hand)
	battle_refs["enemy_hand"].text = "敌方手牌：%d 张" % BattleSimulator.enemy_hand.size()

func _hand_text(hand: Array) -> String:
	if hand.is_empty(): return "空"
	var names: Array[String] = []
	for card in hand:
		names.append(String(card.get("name", "牌")))
	return " · ".join(names)

func _refresh_log() -> void:
	if current_page != "登塔" or not battle_refs.has("log"): return
	var log: RichTextLabel = battle_refs["log"]
	if not is_instance_valid(log): return
	var lines: Array[String] = []
	var count := min(14, GameState.battle_log.size())
	for i in range(count - 1, -1, -1):
		lines.append("• " + GameState.battle_log[i])
	log.text = "\n".join(lines)

func _on_log_added(_text: String) -> void:
	_refresh_log()

func _on_floor_changed(_floor: int) -> void:
	_refresh_header()
	_refresh_battle()

func _upgrade_general() -> void:
	var count := GameState.upgrade_active_general_bulk()
	if count <= 0:
		_notice("铜钱不足。挂机、推塔或分解装备可获得铜钱。")
	else:
		_notice("一键升级 %d 级。" % count)
	_render_page()
	BattleSimulator.reset_floor()

func _breakthrough_general() -> void:
	var count := GameState.breakthrough_active_general_bulk()
	if count <= 0:
		_notice("武魂不足。重复抽到该武将会转化为武魂。")
	else:
		_notice("一键武魂突破 %d 次。" % count)
		BattleSimulator.reset_floor()
		SaveSystem.save_now(true)
	_render_page()

func _render_cultivation_page() -> void:
	page_host.add_child(_section_title("修炼与飞升", "修仙系统负责长期倍率与无限成长；武将决定战斗规则。飞升只增加永久成长，保留全部养成进度。"))
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 10)
	var realm := Label.new(); realm.add_theme_font_size_override("font_size", 26)
	var cult_lab := Label.new()
	var progress := ProgressBar.new(); progress.show_percentage = false; progress.custom_minimum_size.y = 20
	var rate := _muted_label("")
	var break_btn := _primary_button("一键突破")
	break_btn.pressed.connect(_try_breakthrough_all)
	box.add_child(realm); box.add_child(cult_lab); box.add_child(progress); box.add_child(rate); box.add_child(break_btn)
	page_host.add_child(_wrap_panel(box, 18, BLUE))
	cultivation_refs = {"realm":realm, "cult":cult_lab, "progress":progress, "rate":rate, "break":break_btn}

	var growth := HBoxContainer.new(); growth.add_theme_constant_override("separation", 10)
	for pair in [["当前战力", GameState.combat_power_text()], ["仙缘", str(GameState.immortal_fate)], ["修炼速度", "%s/秒" % _short_float(GameState.cultivation_rate_per_sec())], ["挂机铜钱", "%s/秒" % _short_float(GameState.coin_rate_per_sec())]]:
		var vb := VBoxContainer.new(); vb.add_child(_muted_label(pair[0])); var v:=Label.new(); v.text=pair[1]; v.add_theme_font_size_override("font_size",20); vb.add_child(v)
		var p:=_wrap_panel(vb,14); p.size_flags_horizontal=Control.SIZE_EXPAND_FILL; growth.add_child(p)
	page_host.add_child(growth)

	var ascend := VBoxContainer.new(); ascend.add_theme_constant_override("separation", 8)
	var at := Label.new(); at.text = "飞升"; at.add_theme_font_size_override("font_size", 20)
	ascend.add_child(at)
	ascend.add_child(_muted_label("首次飞升建议最高2000层；按钮随时可查看，确认后保留塔层、境界和全部养成进度。"))
	var status := Label.new()
	status.text = GameState.ascension_preview_text()
	cultivation_refs["ascension"] = status
	ascend.add_child(status)
	var asc_btn := _primary_button("查看飞升")
	asc_btn.disabled = false
	asc_btn.pressed.connect(_ascend)
	ascend.add_child(asc_btn)
	page_host.add_child(_wrap_panel(ascend, 18, ORANGE))
	_refresh_cultivation()

func _refresh_cultivation() -> void:
	if current_page != "修炼" or cultivation_refs.is_empty(): return
	if not is_instance_valid(cultivation_refs.get("progress")): return
	var need := GameState.cultivation_required()
	cultivation_refs["realm"].text = GameState.realm_name()
	cultivation_refs["cult"].text = "修为 %s / %s" % [_short_float(GameState.cultivation), _short_float(need)]
	cultivation_refs["progress"].value = clamp(GameState.cultivation / max(1.0, need) * 100.0, 0.0, 100.0)
	cultivation_refs["rate"].text = "自动修炼：%s 修为/秒 · 境界突破会显著提高战斗倍率" % _short_float(GameState.cultivation_rate_per_sec())
	if cultivation_refs.has("ascension"): cultivation_refs["ascension"].text = GameState.ascension_preview_text()

func _try_breakthrough_all() -> void:
	var count := GameState.breakthrough_all()
	if count <= 0:
		_notice("修为尚未达到突破要求。")
	else:
		_notice("连续突破 %d 次，达到 %s。" % [count, GameState.realm_name()])
	BattleSimulator.reset_floor()
	_render_page()

func _ascend() -> void:
	if not GameState.can_ascend():
		_notice(GameState.ascension_preview_text())
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认飞升"
	dialog.dialog_text = GameState.ascension_preview_text() + "\n永久保留所有养成进度。"
	dialog.confirmed.connect(func():
		var before: Dictionary = GameState.to_dict().duplicate(true)
		if GameState.perform_ascension() > 0:
			if not SaveSystem.save_now(true):
				GameState.from_dict(before)
				_notice("飞升未完成：保存失败。")
				dialog.queue_free()
				return
			var hp_scale: float = (1.0 + float(GameState.ascension_bonuses.hp)) / (1.0 + float(before.ascension_bonuses.hp))
			BattleSimulator.hero_hp = BattleSimulator.hero_hp.multiplied_scalar(hp_scale)
			BattleSimulator.hero_max_hp = BattleSimulator.hero_max_hp.multiplied_scalar(hp_scale)
			_notice("飞升成功，永久属性与收益提升。")
			_render_page()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(580, 380))

func _render_generals_page() -> void:
	page_host.add_child(_section_title("武将", "32 将全部接入自动战策；HTML 测试入口已进一步加入手牌、花色、点数、判定区、装备牌与攻击范围。"))
	var top := HBoxContainer.new()
	var active := Label.new(); active.text = "当前主将：%s · Lv.%d" % [_hero_name(), GameState.active_general_level()]; active.add_theme_font_size_override("font_size", 18)
	top.add_child(active); top.add_spacer(false)
	var soul_state := GameState.general_state(GameState.active_general_id)
	var soul_btn := Button.new()
	soul_btn.text = "一键武魂突破 · %d/%d" % [int(soul_state.get("soul",0)), GameState.general_soul_cost(GameState.active_general_id)]
	soul_btn.pressed.connect(_breakthrough_general)
	top.add_child(soul_btn)
	var up := _primary_button("一键升级 · 起价%s铜钱" % _short_float(GameState.general_upgrade_cost(GameState.active_general_id)))
	up.pressed.connect(_upgrade_general)
	top.add_child(up)
	page_host.add_child(_wrap_panel(top, 14))
	var grid := GridContainer.new(); grid.columns = 4; grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	for faction in ["蜀", "魏", "吴", "群"]:
		for id in ContentDB.get_general_ids():
			var data := ContentDB.get_general(id)
			if String(data.get("faction", "")) != faction: continue
			grid.add_child(_general_card(id, data))
	page_host.add_child(grid)

func _general_card(id: String, data: Dictionary) -> PanelContainer:
	var unlocked := GameState.is_general_unlocked(id)
	var state := GameState.general_state(id)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 5)
	var head := HBoxContainer.new()
	var name := Label.new(); name.text = "%s · %s" % [String(data.get("name", id)), String(data.get("faction", ""))]; name.add_theme_font_size_override("font_size", 18)
	head.add_child(name); head.add_spacer(false)
	var rarity := Label.new(); rarity.text = String(data.get("rarity", "R")); rarity.add_theme_color_override("font_color", _general_rarity_color(String(data.get("rarity", "R"))))
	head.add_child(rarity); vb.add_child(head)
	var skill := Label.new(); skill.text = "【%s】%s" % [String(data.get("skill_name", "")), String(data.get("archetype", ""))]; skill.add_theme_color_override("font_color", BLUE); vb.add_child(skill)
	var desc := _muted_label(String(data.get("description", ""))); desc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; desc.custom_minimum_size.y=42; vb.add_child(desc)
	var status_text := "未获得"
	if unlocked:
		status_text = "Lv.%d · %d星 · 武魂 %d" % [int(state.get("level",1)), int(state.get("stars",1)), int(state.get("soul",0))]
		if int(state.get("soul_rank",0)) > 0:
			status_text += " · 神魂%d重" % int(state.get("soul_rank",0))
	var status := _muted_label(status_text)
	vb.add_child(status)
	var impl := Label.new(); impl.text = "完整机制" if bool(data.get("implemented", false)) else "基础自动战斗"; impl.add_theme_font_size_override("font_size", 12); impl.add_theme_color_override("font_color", BLUE if bool(data.get("implemented", false)) else Color("#8b9199")); vb.add_child(impl)
	var btn := Button.new(); btn.text = "当前主将" if id == GameState.active_general_id else ("设为主将" if unlocked else "抽卡解锁"); btn.disabled = (not unlocked) or id == GameState.active_general_id
	var general_id := id
	btn.pressed.connect(func():
		GameState.set_active_general(general_id)
		BattleSimulator.reset_floor()
		_render_page()
	)
	vb.add_child(btn)
	var panel := _wrap_panel(vb, 13, BLUE if id == GameState.active_general_id else _general_rarity_color(String(data.get("rarity", "R"))))
	panel.custom_minimum_size = Vector2(250, 210)
	return panel

func _general_rarity_color(rarity: String) -> Color:
	match rarity:
		"SSR": return ORANGE
		"SR": return PURPLE
		_: return Color("#8b9199")

func _render_gacha_page() -> void:
	page_host.add_child(_section_title("英魂召唤", "重复武将不会变成废卡：自动转化为武魂。原型概率：SSR 3%、SR 19%、R 78%；50 抽必出 SSR，十连至少 SR。"))
	var info := HBoxContainer.new(); info.add_theme_constant_override("separation", 10)
	for pair in [["灵石", str(GameState.spirit_stones)], ["累计召唤", str(GameState.total_pulls)], ["SSR保底", "%d / 50" % GameState.pity_count], ["已解锁", "%d / 32" % _unlocked_count()]]:
		var vb:=VBoxContainer.new(); vb.add_child(_muted_label(pair[0])); var v:=Label.new(); v.text=pair[1]; v.add_theme_font_size_override("font_size",22); vb.add_child(v); var p:=_wrap_panel(vb,14); p.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_child(p)
	page_host.add_child(info)
	var summon := VBoxContainer.new(); summon.add_theme_constant_override("separation", 12)
	var title := Label.new(); title.text="群英召唤"; title.add_theme_font_size_override("font_size", 24); summon.add_child(title)
	summon.add_child(_muted_label("常驻池 · 魏 / 蜀 / 吴 / 群。当前阶段用于验证收集、重复武魂与保底循环。"))
	var buttons := HBoxContainer.new(); buttons.add_theme_constant_override("separation", 8)
	var one := Button.new(); one.text="召唤 1 次 · 100灵石"; one.custom_minimum_size.y=42; one.pressed.connect(func(): _do_gacha(1)); buttons.add_child(one)
	var ten := _primary_button("召唤 10 次 · 900灵石"); ten.size_flags_horizontal=Control.SIZE_EXPAND_FILL; ten.pressed.connect(func(): _do_gacha(10)); buttons.add_child(ten)
	summon.add_child(buttons)
	page_host.add_child(_wrap_panel(summon, 22, ORANGE))
	if not GameState.gacha_history.is_empty():
		var result_box := VBoxContainer.new(); result_box.add_child(_section_title("最近召唤结果"))
		var grid := GridContainer.new(); grid.columns=5; grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8)
		for res in GameState.gacha_history:
			var data:=ContentDB.get_general(String(res.get("id",""))); var vb:=VBoxContainer.new(); var n:=Label.new(); n.text=String(data.get("name","武将")); n.add_theme_font_size_override("font_size",18); vb.add_child(n)
			var r:=Label.new(); r.text=String(res.get("rarity","R")) + (" · NEW" if bool(res.get("new",false)) else " · 武魂"); r.add_theme_color_override("font_color",_general_rarity_color(String(res.get("rarity","R")))); vb.add_child(r); vb.add_child(_muted_label("【%s】" % String(data.get("skill_name",""))))
			var p:=_wrap_panel(vb,12,_general_rarity_color(String(res.get("rarity","R")))); p.custom_minimum_size=Vector2(180,100); grid.add_child(p)
		result_box.add_child(grid); page_host.add_child(result_box)

func _do_gacha(count: int) -> void:
	var results := GameState.gacha_pull(count)
	if results.is_empty():
		_notice("灵石不足。挂机、登塔和离线结算都会持续产出灵石。")
	else:
		var ssr := 0
		for r in results:
			if String(r.get("rarity", "")) == "SSR": ssr += 1
		if ssr > 0: _notice("召唤出现 %d 名 SSR！" % ssr)
	SaveSystem.save_now(true)
	_render_page()

func _unlocked_count() -> int:
	var count:=0
	for id in ContentDB.get_general_ids():
		if GameState.is_general_unlocked(id): count+=1
	return count

func _render_inventory_page() -> void:
	page_host.add_child(_section_title("背包", "挂机掉落越多，操作越少：先升阶、再筛选分解；已装备与锁定装备永远受到保护。"))
	var actions := HBoxContainer.new(); actions.add_theme_constant_override("separation",8)
	var best:=_primary_button("一键换装")
	best.pressed.connect(func():
		var n=GameState.equip_best()
		_notice("已更换 %d 个更强部位。" % n)
		_render_page()
	)
	actions.add_child(best)
	var upgrade:=Button.new()
	upgrade.text="一键升阶（3合1）"
	upgrade.custom_minimum_size.y=38
	upgrade.pressed.connect(func():
		var n=GameState.one_click_upgrade()
		_notice("升阶完成：%d 次合成。" % n)
		_render_page()
	)
	actions.add_child(upgrade)
	var decomp:=_danger_button("一键分解 普通/精良")
	decomp.pressed.connect(func():
		var r=GameState.one_click_decompose(1)
		_notice("分解 %d 件，获得武魂精华 %d。" % [r.get("count",0),r.get("essence",0)])
		_render_page()
	)
	actions.add_child(decomp)
	actions.add_spacer(false); actions.add_child(_muted_label("装备 %d 件 · 武魂精华 %d" % [GameState.inventory.size(), GameState.soul_dust])); page_host.add_child(actions)

	var equipped_row := HBoxContainer.new(); equipped_row.add_theme_constant_override("separation",10)
	for slot in ["weapon","armor","accessory"]:
		var item := _find_item(String(GameState.equipped.get(slot,"")))
		var vb:=VBoxContainer.new(); vb.add_child(_muted_label(String(ContentDB.balance.get("gear_slots",{}).get(slot,slot))))
		var n:=Label.new(); n.text=String(item.get("name","未装备")) if not item.is_empty() else "未装备"; n.add_theme_font_size_override("font_size",18); vb.add_child(n)
		if not item.is_empty(): vb.add_child(_muted_label("%s · %d阶 · 评分 %s" % [String(item.get("rarity","")), int(item.get("tier",1)), _short_float(float(item.get("power",0.0)))]))
		var p:=_wrap_panel(vb,14, _gear_color(String(item.get("rarity","普通"))) if not item.is_empty() else Color.TRANSPARENT); p.size_flags_horizontal=Control.SIZE_EXPAND_FILL; equipped_row.add_child(p)
	page_host.add_child(equipped_row)

	var items: Array = GameState.inventory.duplicate(true)
	items.sort_custom(func(a,b): return float(a.get("power",0.0)) > float(b.get("power",0.0)))
	var grid := GridContainer.new(); grid.columns=2; grid.add_theme_constant_override("h_separation",10); grid.add_theme_constant_override("v_separation",8)
	var show_count := min(60, items.size())
	for i in range(show_count):
		grid.add_child(_equipment_card(items[i]))
	page_host.add_child(grid)
	if items.size() > show_count:
		page_host.add_child(_muted_label("为保持原型界面流畅，仅显示评分最高的 %d / %d 件装备；一键处理会处理全部背包。" % [show_count,items.size()]))

func _equipment_card(item: Dictionary) -> PanelContainer:
	var vb:=VBoxContainer.new(); vb.add_theme_constant_override("separation",4)
	var head:=HBoxContainer.new(); var n:=Label.new(); n.text=String(item.get("name","装备")); n.add_theme_font_size_override("font_size",17); head.add_child(n); head.add_spacer(false)
	var r:=Label.new(); r.text=String(item.get("rarity","普通")); r.add_theme_color_override("font_color",_gear_color(String(item.get("rarity","普通")))); head.add_child(r); vb.add_child(head)
	vb.add_child(_muted_label("%d阶 · 评分 %s · 词条：%s" % [int(item.get("tier",1)), _short_float(float(item.get("power",0.0))), String(item.get("affix",""))]))
	var actions:=HBoxContainer.new()
	var equip:=Button.new()
	equip.text="装备"
	equip.disabled=GameState.equipped.values().has(String(item.get("uid","")))
	var equip_uid := String(item.get("uid",""))
	equip.pressed.connect(func():
		GameState.equip_item(equip_uid)
		BattleSimulator.reset_floor()
		_render_page()
	)
	actions.add_child(equip)
	var lock:=Button.new()
	lock.text="解锁" if bool(item.get("locked",false)) else "锁定"
	var lock_uid := String(item.get("uid",""))
	lock.pressed.connect(func():
		GameState.toggle_lock(lock_uid)
		_render_page()
	)
	actions.add_child(lock)
	actions.add_spacer(false)
	if GameState.equipped.values().has(String(item.get("uid",""))): actions.add_child(_muted_label("已装备"))
	vb.add_child(actions)
	return _wrap_panel(vb,12,_gear_color(String(item.get("rarity","普通"))))

func _find_item(uid: String) -> Dictionary:
	if uid.is_empty(): return {}
	for item in GameState.inventory:
		if String(item.get("uid",""))==uid: return item
	return {}

func _gear_color(rarity: String) -> Color:
	var hex := String(ContentDB.balance.get("rarity_colors",{}).get(rarity,"#8a8a8a"))
	return Color(hex)

func _render_settings_page() -> void:
	page_host.add_child(_section_title("设置与存档", "自动保存每 12 秒执行一次；导入前会自动备份当前进度，最多保留 5 个备份。"))
	var save_box:=VBoxContainer.new(); save_box.add_theme_constant_override("separation",8)
	var loc:=_muted_label("本地存档：%s" % ProjectSettings.globalize_path("user://save_main.json")); loc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; save_box.add_child(loc)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",8)
	var save:=_primary_button("立即保存")
	save.pressed.connect(func():
		SaveSystem.save_now(true)
		_notice("存档已写入。")
	)
	row.add_child(save)
	var export:=Button.new(); export.text="导出存档文件"; export.pressed.connect(_open_export_dialog); row.add_child(export)
	var import:=Button.new(); import.text="导入存档文件"; import.pressed.connect(_open_import_dialog); row.add_child(import)
	var copy:=Button.new(); copy.text="复制存档码"; copy.pressed.connect(_copy_save_code); row.add_child(copy)
	save_box.add_child(row)
	var code:=LineEdit.new(); code.placeholder_text="粘贴 DXT1- 开头的存档码"; code.set_meta("save_code_input",true); save_box.add_child(code)
	var import_code:=Button.new(); import_code.text="从存档码导入"; import_code.pressed.connect(func(): _import_code(code.text)); save_box.add_child(import_code)
	page_host.add_child(_wrap_panel(save_box,18,BLUE))

	var display:=VBoxContainer.new(); display.add_theme_constant_override("separation",8)
	var dt:=Label.new(); dt.text="界面"; dt.add_theme_font_size_override("font_size",19); display.add_child(dt)
	var dark:=CheckButton.new(); dark.text="深色模式"; dark.button_pressed=GameState.dark_mode; dark.toggled.connect(_toggle_dark); display.add_child(dark)
	var auto:=CheckButton.new()
	auto.text="自动登塔"
	auto.button_pressed=GameState.auto_battle
	auto.toggled.connect(func(v):
		GameState.auto_battle=v
		GameState.changed.emit()
	)
	display.add_child(auto)
	page_host.add_child(_wrap_panel(display,18))

	var test:=VBoxContainer.new(); test.add_theme_constant_override("separation",8)
	var tt:=Label.new(); tt.text="原型测试工具"; tt.add_theme_font_size_override("font_size",19); test.add_child(tt)
	test.add_child(_muted_label("用于快速验证抽卡、背包和成长节奏；正式版本会移除。"))
	var gift:=Button.new(); gift.text="领取测试资源（+10,000灵石 / +1,000,000铜钱 / +20件装备）"; gift.pressed.connect(_give_test_resources); test.add_child(gift)
	var asc_test := Button.new()
	asc_test.text = "飞升流程测试：前往金丹 · 第1990层"
	asc_test.pressed.connect(_prepare_ascension_test)
	test.add_child(asc_test)
	page_host.add_child(_wrap_panel(test,18,ORANGE))

func _open_export_dialog() -> void:
	var dialog:=FileDialog.new(); dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.filters=PackedStringArray(["*.json ; 三国杀挂机塔存档"]); dialog.current_file="三国杀挂机塔_save.json"; add_child(dialog)
	dialog.file_selected.connect(func(path):
		var ok=SaveSystem.export_to_file(path)
		_notice("导出成功。" if ok else "导出失败，请检查目录权限。")
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered_ratio(0.72)

func _open_import_dialog() -> void:
	var dialog:=FileDialog.new(); dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.filters=PackedStringArray(["*.json ; 三国杀挂机塔存档"]); add_child(dialog)
	dialog.file_selected.connect(func(path):
		var result=SaveSystem.import_from_file(path)
		_notice(String(result.get("message","导入完成")))
		if bool(result.get("ok",false)):
			BattleSimulator.reset_floor()
			_render_page()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered_ratio(0.72)

func _copy_save_code() -> void:
	var code:=SaveSystem.get_save_code()
	if code.is_empty(): _notice("生成存档码失败。"); return
	DisplayServer.clipboard_set(code)
	_notice("存档码已复制到剪贴板。")

func _import_code(code: String) -> void:
	var result:=SaveSystem.import_save_code(code)
	_notice(String(result.get("message","导入完成")))
	if bool(result.get("ok",false)):
		BattleSimulator.reset_floor(); _render_page()

func _toggle_dark(value: bool) -> void:
	GameState.dark_mode=value
	GameState.changed.emit()
	_render_page()

func _give_test_resources() -> void:
	GameState.spirit_stones += 10000
	GameState.coins += 1000000.0
	for i in range(20): GameState.add_random_equipment(max(1,int(GameState.tower_floor/20)+1))
	GameState.add_log("已领取原型测试资源。")
	SaveSystem.save_now(true)
	_notice("测试资源已发放。")
	_render_page()

func _prepare_ascension_test() -> void:
	GameState.realm_index = max(GameState.realm_index, 2)
	GameState.realm_stage = max(GameState.realm_stage, 1)
	GameState.tower_floor = max(GameState.tower_floor, 1990)
	GameState.highest_floor = max(GameState.highest_floor, GameState.tower_floor)
	GameState.coins += 3000000.0
	GameState.cultivation += GameState.cultivation_required() * 8.0
	GameState.add_log("已进入飞升测试环境：金丹 / 第1990层。")
	GameState.changed.emit()
	BattleSimulator.reset_floor()
	SaveSystem.save_now(true)
	_notice("已前往金丹 · 第1990层，并补充成长资源。请回到登塔页突破到2000层，再测试飞升。")
	_render_page()

func _show_offline_summary(summary: Dictionary) -> void:
	_notice("离线 %s\n修为 +%s\n铜钱 +%s\n自动推进 +%d 层\n保留装备 %d 件，自动分解 %d 件\n灵石 +%d" % [
		_format_duration(int(summary.get("raw_seconds",0))), _short_float(float(summary.get("cultivation",0.0))), _short_float(float(summary.get("coins",0.0))), int(summary.get("floor_advance",0)), int(summary.get("gear",0)), int(summary.get("auto_scrapped",0)), int(summary.get("stones",0))])

func _notice(text: String) -> void:
	notice_dialog.dialog_text=text
	notice_dialog.popup_centered(Vector2i(480,220))

func _hero_name() -> String:
	return String(ContentDB.get_general(GameState.active_general_id).get("name","主将"))

func _short_float(value: float) -> String:
	if value < 1000.0: return "%.0f" % value
	if value < 1000000.0: return "%.2fK" % (value/1000.0)
	if value < 1000000000.0: return "%.2fM" % (value/1000000.0)
	return BigNum.from_float(value).short()

func _format_duration(seconds: int) -> String:
	var h:=int(seconds/3600); var m:=int((seconds%3600)/60)
	if h>0: return "%d小时%d分" % [h,m]
	return "%d分钟" % max(1,m)
