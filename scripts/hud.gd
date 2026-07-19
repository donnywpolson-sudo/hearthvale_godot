extends CanvasLayer

signal bank_deposit_requested(item_id: String, quantity: int)
signal bank_withdraw_requested(item_id: String, quantity: int)
signal shop_buy_requested(item_id: String, price: int)
signal shop_sell_requested(item_id: String, quantity: int)
signal quest_route_select_requested(quest_id: String)
signal dialogue_action_requested(npc_data: Dictionary)
signal inventory_item_action_requested(item_id: String, action: String)
signal equipment_item_action_requested(slot: String, action: String)
signal carpentry_specialization_requested(specialization: String)
signal recipe_selected_requested(action_type: String, recipe_id: String)
signal compass_reset_requested

const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const QUESTS_PATH := "res://data/quests.json"
const FALLBACK_ICON_PATH := "res://assets/icons/ui/missing.png"
const ItemTooltipButton := preload("res://scripts/item_tooltip_button.gd")
const MinimapControl := preload("res://scripts/minimap_control.gd")
const AUDIO_PATHS := {
	"ambient": "res://assets/audio/ambient.wav",
	"coin_jingle": "res://assets/audio/coin_jingle.wav",
	"combat_hit": "res://assets/audio/combat_hit.wav",
	"combat_miss": "res://assets/audio/combat_miss.wav",
	"craft_shimmer": "res://assets/audio/craft_shimmer.wav",
	"gather_thud": "res://assets/audio/gather_thud.wav",
	"level_up": "res://assets/audio/level_up.wav",
	"quest_complete": "res://assets/audio/quest_complete.wav",
	"ui_click": "res://assets/audio/ui_click.wav",
}
const INVENTORY_SLOT_LIMIT := 28
const INVENTORY_GRID_COLUMNS := 4
const INVENTORY_COMPACT_EMPTY_SLOT_FLOOR := 12
const INVENTORY_SLOT_SIZE := Vector2(58, 52)
const INVENTORY_COMPACT_SLOT_SIZE := Vector2(50, 42)
const INVENTORY_ICON_SIZE := Vector2(36, 36)
const INVENTORY_COMPACT_ICON_SIZE := Vector2(30, 30)
const EQUIPMENT_SLOTS := ["head", "cape", "amulet", "ammo", "weapon", "body", "shield", "legs", "hands", "feet", "ring"]
const EQUIPMENT_BONUS_KEYS := ["attack_bonus", "strength_bonus", "defence_bonus", "ranged_bonus", "magic_bonus"]
const USABLE_BONUS_KEYS := ["attack_bonus", "strength_bonus", "defence_bonus", "ranged_bonus", "magic_bonus", "action_speed_bonus"]
const EQUIPMENT_PANEL_SIZE := Vector2(252, 278)
const EQUIPMENT_SLOT_SIZE := Vector2(46, 46)
const RIGHT_PANEL_BASE_HEIGHT := 464.0
const RIGHT_PANEL_WIDTH := 312.0
const RIGHT_PANEL_RIGHT_MARGIN := 10.0
const RIGHT_PANEL_MIN_TOP := 240.0
const RIGHT_PANEL_COMPACT_VIEWPORT_HEIGHT := 600.0
const RIGHT_PANEL_COMPACT_MIN_TOP := 192.0
const EQUIPMENT_COMPACT_SCALE := 0.70
const TRANSACTION_NAME_COLUMN_WIDTH := 170.0
const TRANSACTION_DETAIL_COLUMN_WIDTH := 76.0
const TRANSACTION_ACTION_COLUMN_WIDTH := 142.0
const CATEGORY_ORDER := {
	"currency": 0,
	"tool": 1,
	"weapon": 2,
	"armor": 3,
	"wood": 4,
	"ore": 5,
	"bar": 6,
	"fish": 7,
	"misc": 8,
}
const CATEGORY_COLORS := {
	"currency": Color(0.98, 0.82, 0.34, 1.0),
	"tool": Color(0.84, 0.58, 0.28, 1.0),
	"weapon": Color(0.92, 0.46, 0.32, 1.0),
	"armor": Color(0.52, 0.66, 0.84, 1.0),
	"wood": Color(0.70, 0.50, 0.26, 1.0),
	"ore": Color(0.70, 0.70, 0.66, 1.0),
	"bar": Color(0.90, 0.68, 0.34, 1.0),
	"fish": Color(0.48, 0.72, 0.90, 1.0),
	"misc": Color(0.88, 0.80, 0.64, 1.0),
}
const SKILL_DISPLAY_ORDER := [
	"attack",
	"strength",
	"defence",
	"hitpoints",
	"ranged",
	"magic",
	"woodcutting",
	"mining",
	"fishing",
	"foraging",
	"cooking",
	"smithing",
	"carpentry",
	"herbalism",
]

@onready var account_label: Label = $Root/TopBar/Margin/Row/Account
@onready var tile_label: Label = $Root/TopBar/Margin/Row/Tile
@onready var selection_label: Label = $Root/TopBar/Margin/Row/Selection
@onready var feedback_label: Label = $Root/Feedback
@onready var root_control: Control = $Root

var items_data := {}
var skills_data := {}
var quests_data := {}
var current_state := {}
var active_tab := "inventory"
var chat_messages: Array[String] = []
var tab_buttons: Dictionary = {}
var tab_row: HBoxContainer
var item_icon_cache: Dictionary = {}
var panel: PanelContainer
var panel_title: Label
var panel_body: VBoxContainer
var interaction_panel: PanelContainer
var interaction_title: Label
var interaction_body: VBoxContainer
var hover_hint_panel: PanelContainer
var hover_hint_label: Label
var minimap_panel: PanelContainer
var minimap_view: Control
var compass_button: Button
var active_shop_data := {}
var active_dialogue_npc := {}
var simulation_lightweight_mode := false
var audio_streams := {}
var ambient_player: AudioStreamPlayer
var effect_player: AudioStreamPlayer


func _ready() -> void:
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	quests_data = _load_json(QUESTS_PATH)
	_build_state_panel()
	_build_interaction_panel()
	_build_hover_hint()
	_build_minimap()
	_setup_audio()
	get_tree().node_added.connect(_on_hud_node_added)
	_wire_button_tree(root_control)
	root_control.resized.connect(_update_right_panel_layout)
	root_control.resized.connect(_update_interaction_panel_layout)
	_update_right_panel_layout()
	_update_interaction_panel_layout()


func set_simulation_lightweight_mode(enabled: bool) -> void:
	simulation_lightweight_mode = enabled
	if enabled:
		_clear_interaction_body()
		if panel_body != null:
			_clear_container_children(panel_body)


func is_simulation_lightweight_mode() -> bool:
	return simulation_lightweight_mode


func set_account(username: String) -> void:
	account_label.text = "Account: %s" % username


func set_player_tile(tile: Vector2i) -> void:
	tile_label.text = "Tile: %d, %d" % [tile.x, tile.y]


func configure_minimap(data: Dictionary) -> void:
	if minimap_view != null and minimap_view.has_method("configure"):
		minimap_view.call("configure", data)


func set_minimap_player_tile(tile: Vector2i) -> void:
	if minimap_view != null and minimap_view.has_method("set_player_tile"):
		minimap_view.call("set_player_tile", tile)


func set_minimap_heading(heading_degrees: float) -> void:
	if minimap_view != null and minimap_view.has_method("set_heading"):
		minimap_view.call("set_heading", heading_degrees)


func set_selection(label: String) -> void:
	selection_label.text = "Selected: %s" % label


func set_hover_target(label: String) -> void:
	if hover_hint_panel == null or hover_hint_label == null:
		return
	var clean_label := label.strip_edges()
	hover_hint_label.text = clean_label
	hover_hint_panel.visible = not clean_label.is_empty()


func set_feedback(message: String) -> void:
	feedback_label.text = message
	if message.strip_edges().is_empty():
		return
	chat_messages.append(message)
	while chat_messages.size() > 8:
		chat_messages.pop_front()
	if active_tab == "state" and not simulation_lightweight_mode:
		_refresh_state_panel()


func _setup_audio() -> void:
	for cue in AUDIO_PATHS.keys():
		var stream = load(str(AUDIO_PATHS[cue]))
		if stream is AudioStream:
			audio_streams[str(cue)] = stream
	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "AmbientAudio"
	ambient_player.volume_db = -20.0
	if audio_streams.has("ambient"):
		ambient_player.stream = audio_streams["ambient"]
		if ambient_player.stream is AudioStreamWAV:
			ambient_player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		add_child(ambient_player)
	ambient_player.play()
	effect_player = AudioStreamPlayer.new()
	effect_player.name = "FeedbackAudio"
	effect_player.volume_db = -4.0
	add_child(effect_player)


func _on_hud_node_added(node: Node) -> void:
	if root_control != null and root_control.is_ancestor_of(node):
		_wire_button_tree(node)


func _wire_button_tree(node: Node) -> void:
	if node is BaseButton:
		var callback := Callable(self, "_on_ui_button_pressed")
		if not node.pressed.is_connected(callback):
			node.pressed.connect(callback)
	for child in node.get_children():
		_wire_button_tree(child)


func _on_ui_button_pressed() -> void:
	# Action/UI sounds are intentionally disabled. Ambient audio remains available.
	return


func audio_assets_loaded() -> bool:
	for cue in AUDIO_PATHS.keys():
		if not audio_streams.has(str(cue)):
			return false
	return true


func _play_feedback_cue(message: String) -> void:
	# Retained as a compatibility hook for callers; gameplay feedback is silent.
	return


func _feedback_cue(message: String) -> String:
	var lower := message.to_lower()
	if lower.contains("quest complete"):
		return "quest_complete"
	if lower.contains(" level ") or lower.ends_with(" level"):
		return "level_up"
	if lower.begins_with("hit ") or lower.contains("defeated "):
		return "combat_hit"
	if lower.contains("too wounded") or lower.contains("miss"):
		return "combat_miss"
	if lower.contains("bought ") or lower.contains("sold ") or lower.contains("coins"):
		return "coin_jingle"
	if lower.contains(" -> ") or lower.contains("crafted") or lower.contains("made "):
		return "craft_shimmer"
	if lower.contains(" xp") and not lower.contains("inventory is full"):
		return "gather_thud"
	return ""


func bind_state(state: Dictionary) -> void:
	current_state = state
	_refresh_top_bar_from_state()
	if not simulation_lightweight_mode:
		_refresh_state_panel()


func refresh_state() -> void:
	_refresh_top_bar_from_state()
	if not simulation_lightweight_mode:
		_refresh_state_panel()


func select_tab(tab_id: String) -> void:
	active_tab = tab_id
	for key in tab_buttons.keys():
		tab_buttons[key].disabled = key == active_tab
	_refresh_state_panel()


func _build_state_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "StatePanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -RIGHT_PANEL_WIDTH - RIGHT_PANEL_RIGHT_MARGIN
	panel.offset_top = -RIGHT_PANEL_BASE_HEIGHT - 16.0
	panel.offset_right = -RIGHT_PANEL_RIGHT_MARGIN
	panel.offset_bottom = -16.0
	panel.add_theme_stylebox_override("panel", _flat_style(Color(0.08, 0.09, 0.08, 0.96), Color(0.34, 0.30, 0.20, 1.0), 1, 8))
	root_control.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	panel_title = Label.new()
	panel_title.text = "Inventory"
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(panel_title)

	tab_row = HBoxContainer.new()
	stack.add_child(tab_row)
	_add_tab_button(tab_row, "inventory", "Inv")
	_add_tab_button(tab_row, "equipment", "Gear")
	_add_tab_button(tab_row, "skills", "Skills")
	_add_tab_button(tab_row, "quests", "Quest")
	_add_tab_button(tab_row, "state", "State")

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(246, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	panel_body = VBoxContainer.new()
	panel_body.add_theme_constant_override("separation", 6)
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_body)

	select_tab(active_tab)


func _build_interaction_panel() -> void:
	interaction_panel = PanelContainer.new()
	interaction_panel.name = "InteractionPanel"
	interaction_panel.visible = false
	interaction_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	interaction_panel.anchor_left = 0.0
	interaction_panel.anchor_right = 0.0
	interaction_panel.anchor_top = 0.0
	interaction_panel.anchor_bottom = 1.0
	interaction_panel.offset_left = 10.0
	interaction_panel.offset_top = 58.0
	interaction_panel.offset_right = 500.0
	interaction_panel.offset_bottom = -74.0
	interaction_panel.add_theme_stylebox_override("panel", _flat_style(Color(0.08, 0.09, 0.08, 0.96), Color(0.34, 0.30, 0.20, 1.0), 1, 8))
	root_control.add_child(interaction_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	interaction_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	stack.add_child(header)

	interaction_title = Label.new()
	interaction_title.text = "Interaction"
	interaction_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(interaction_title)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(hide_interaction_panel)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(458, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	interaction_body = VBoxContainer.new()
	interaction_body.add_theme_constant_override("separation", 6)
	interaction_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(interaction_body)


func _build_hover_hint() -> void:
	hover_hint_panel = PanelContainer.new()
	hover_hint_panel.name = "HoverHint"
	hover_hint_panel.visible = false
	hover_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_hint_panel.anchor_left = 0.5
	hover_hint_panel.anchor_right = 0.5
	hover_hint_panel.anchor_top = 0.0
	hover_hint_panel.anchor_bottom = 0.0
	hover_hint_panel.offset_left = -150.0
	hover_hint_panel.offset_top = 50.0
	hover_hint_panel.offset_right = 150.0
	hover_hint_panel.offset_bottom = 84.0
	root_control.add_child(hover_hint_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	hover_hint_panel.add_child(margin)

	hover_hint_label = Label.new()
	hover_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hover_hint_label.text = ""
	margin.add_child(hover_hint_label)


func _build_minimap() -> void:
	minimap_panel = PanelContainer.new()
	minimap_panel.name = "Minimap"
	minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap_panel.anchor_left = 1.0
	minimap_panel.anchor_right = 1.0
	minimap_panel.anchor_top = 0.0
	minimap_panel.anchor_bottom = 0.0
	minimap_panel.offset_left = -166.0
	minimap_panel.offset_top = 58.0
	minimap_panel.offset_right = -10.0
	minimap_panel.offset_bottom = 230.0
	minimap_panel.add_theme_stylebox_override("panel", _flat_style(Color(0.08, 0.09, 0.08, 0.92), Color(0.34, 0.30, 0.20, 1.0), 1, 8))
	root_control.add_child(minimap_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	minimap_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	stack.add_child(header)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	compass_button = Button.new()
	compass_button.text = "N"
	compass_button.tooltip_text = "Reset camera north"
	compass_button.custom_minimum_size = Vector2(32, 26)
	compass_button.pressed.connect(func() -> void: compass_reset_requested.emit())
	header.add_child(compass_button)

	minimap_view = MinimapControl.new()
	minimap_view.custom_minimum_size = Vector2(136, 124)
	minimap_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(minimap_view)


func _update_right_panel_layout() -> void:
	if panel == null or root_control == null:
		return
	var viewport_height := root_control.size.y
	var compact := viewport_height <= RIGHT_PANEL_COMPACT_VIEWPORT_HEIGHT
	_update_minimap_layout(compact)
	_update_tab_row_layout(compact)
	var min_top := RIGHT_PANEL_COMPACT_MIN_TOP if compact else RIGHT_PANEL_MIN_TOP
	var bottom_margin := 24.0 if compact else 16.0
	var target_top := maxf(min_top, viewport_height - RIGHT_PANEL_BASE_HEIGHT - bottom_margin)
	panel.offset_left = -RIGHT_PANEL_WIDTH - RIGHT_PANEL_RIGHT_MARGIN
	panel.offset_right = -RIGHT_PANEL_RIGHT_MARGIN
	panel.offset_top = target_top - viewport_height
	panel.offset_bottom = -bottom_margin


func _update_interaction_panel_layout() -> void:
	if interaction_panel == null or root_control == null:
		return
	var compact := root_control.size.y <= RIGHT_PANEL_COMPACT_VIEWPORT_HEIGHT
	interaction_panel.offset_bottom = -50.0 if compact else -74.0


func _update_tab_row_layout(compact: bool) -> void:
	if tab_row == null:
		return
	tab_row.add_theme_constant_override("separation", 2 if compact else 6)
	var font_size := 12 if compact else 14
	for button in tab_buttons.values():
		button.add_theme_font_size_override("font_size", font_size)


func _update_minimap_layout(compact: bool) -> void:
	if minimap_panel == null or minimap_view == null:
		return
	if compact:
		minimap_panel.offset_left = -134.0
		minimap_panel.offset_top = 50.0
		minimap_panel.offset_right = -10.0
		minimap_panel.offset_bottom = 182.0
		minimap_view.custom_minimum_size = Vector2(108, 82)
		if compass_button != null:
			compass_button.custom_minimum_size = Vector2(30, 24)
		return
	minimap_panel.offset_left = -166.0
	minimap_panel.offset_top = 58.0
	minimap_panel.offset_right = -10.0
	minimap_panel.offset_bottom = 230.0
	minimap_view.custom_minimum_size = Vector2(136, 124)
	if compass_button != null:
		compass_button.custom_minimum_size = Vector2(32, 26)


func hide_interaction_panel() -> void:
	if interaction_panel != null:
		interaction_panel.visible = false
	if panel != null:
		panel.visible = true


func _show_interaction_panel() -> void:
	if interaction_panel != null:
		interaction_panel.visible = true
	if panel != null:
		panel.visible = false


func show_recipe_picker(action_type: String, station_label: String, entries: Array) -> void:
	_clear_interaction_body()
	interaction_title.text = station_label
	_show_interaction_panel()
	if simulation_lightweight_mode:
		return
	if entries.is_empty():
		_add_interaction_muted("No recipes available")
		return
	for entry in entries:
		if entry is Dictionary:
			_add_recipe_picker_row(action_type, entry)


func _add_recipe_picker_row(action_type: String, entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 44)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interaction_body.add_child(row)

	var text_stack := VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_theme_constant_override("separation", 0)
	row.add_child(text_stack)
	var name_label := Label.new()
	name_label.text = str(entry.get("display_name", entry.get("recipe_id", "Recipe")))
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 13)
	text_stack.add_child(name_label)
	var details_label := Label.new()
	details_label.text = "Lv %d  ·  %s  →  %s  ·  %d XP" % [
		int(entry.get("required_level", 1)),
		_recipe_picker_inputs_text(entry.get("inputs", {})),
		_recipe_picker_output_text(entry),
		int(entry.get("xp_reward", 0)),
	]
	details_label.modulate = Color(0.72, 0.72, 0.72, 1.0)
	details_label.add_theme_font_size_override("font_size", 10)
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_stack.add_child(details_label)
	if not bool(entry.get("eligible", false)):
		var availability_label := Label.new()
		availability_label.text = str(entry.get("availability", "Unavailable"))
		availability_label.modulate = Color(0.86, 0.65, 0.42, 1.0)
		availability_label.add_theme_font_size_override("font_size", 10)
		availability_label.clip_text = true
		text_stack.add_child(availability_label)
	var craft_button := Button.new()
	craft_button.text = "Craft"
	craft_button.custom_minimum_size = Vector2(72, 28)
	craft_button.add_theme_font_size_override("font_size", 11)
	craft_button.disabled = not bool(entry.get("eligible", false))
	var selected_recipe_id := str(entry.get("recipe_id", ""))
	craft_button.pressed.connect(func() -> void:
		recipe_selected_requested.emit(action_type, selected_recipe_id)
	)
	row.add_child(craft_button)


func _recipe_picker_inputs_text(raw_inputs) -> String:
	if not (raw_inputs is Dictionary) or raw_inputs.is_empty():
		return "No inputs"
	var parts: Array[String] = []
	for item_id in raw_inputs.keys():
		var quantity := int(raw_inputs[item_id])
		parts.append("%s ×%d" % [_item_name(str(item_id)), quantity])
	return ", ".join(parts)


func _recipe_picker_output_text(entry: Dictionary) -> String:
	return "%s ×%d" % [_item_name(str(entry.get("output_item_id", ""))), int(entry.get("output_quantity", 1))]


func hover_hint_is_visible() -> bool:
	return hover_hint_panel != null and hover_hint_panel.visible


func hover_hint_text() -> String:
	return hover_hint_label.text if hover_hint_label != null else ""


func minimap_has_data_for_smoke() -> bool:
	return minimap_view != null and minimap_view.has_method("has_minimap_data") and bool(minimap_view.call("has_minimap_data"))


func minimap_player_tile_for_smoke() -> Vector2i:
	if minimap_view != null and minimap_view.has_method("player_tile_for_smoke"):
		return minimap_view.call("player_tile_for_smoke")
	return Vector2i(-1, -1)


func minimap_heading_for_smoke() -> float:
	if minimap_view != null and minimap_view.has_method("heading_for_smoke"):
		return float(minimap_view.call("heading_for_smoke"))
	return -1.0


func minimap_player_is_centered_for_smoke() -> bool:
	if minimap_view == null or not minimap_view.has_method("player_screen_position_for_smoke"):
		return false
	var player_position: Vector2 = minimap_view.call("player_screen_position_for_smoke")
	return player_position.distance_to(minimap_view.size * 0.5) <= 0.001


func emit_compass_reset_for_smoke() -> void:
	compass_reset_requested.emit()


func interaction_panel_is_visible() -> bool:
	return interaction_panel != null and interaction_panel.visible


func interaction_panel_title_text() -> String:
	return interaction_title.text if interaction_title != null else ""


func interaction_panel_row_count() -> int:
	return interaction_body.get_child_count() if interaction_body != null else 0


func show_bank_panel() -> void:
	_clear_interaction_body()
	interaction_title.text = "Bank"
	_show_interaction_panel()
	if simulation_lightweight_mode:
		return
	var inventory := _stack_mapping(current_state.get("inventory", {}))
	var bank := _stack_mapping(current_state.get("bank", {}))
	_add_interaction_section("Inventory")
	if inventory.is_empty():
		_add_interaction_muted("Nothing to deposit")
	else:
		for item_id in _sorted_item_ids(inventory):
			_add_bank_inventory_row(item_id, int(inventory[item_id]))
	_add_interaction_section("Stored")
	if bank.is_empty():
		_add_interaction_muted("Bank is empty")
	else:
		for item_id in _sorted_item_ids(bank):
			_add_bank_storage_row(item_id, int(bank[item_id]))


func show_shop_panel(shop_data: Dictionary) -> void:
	active_shop_data = shop_data.duplicate(true)
	_clear_interaction_body()
	interaction_title.text = str(shop_data.get("name", "Shop"))
	_show_interaction_panel()
	if simulation_lightweight_mode:
		return
	_new_item_interaction_row("coins", "%d carried" % int(_stack_mapping(current_state.get("inventory", {})).get("coins", 0)))
	var stock = shop_data.get("stock", [])
	_add_interaction_section("Buy")
	if not (stock is Array) or stock.is_empty():
		_add_interaction_muted("No stock available")
	else:
		for raw_item in stock:
			if raw_item is Dictionary:
				_add_shop_stock_row(str(raw_item.get("item_id", "")), int(raw_item.get("price", 0)))
	_add_interaction_section("Sell")
	var inventory := _stack_mapping(current_state.get("inventory", {}))
	var sellable_count := 0
	for item_id in _sorted_item_ids(inventory):
		if item_id == "coins":
			continue
		var price := _sell_price(item_id)
		if price <= 0:
			continue
		sellable_count += 1
		_add_shop_inventory_row(item_id, int(inventory[item_id]), price)
	if sellable_count == 0:
		_add_interaction_muted("No sellable items")


func show_dialogue_panel(npc_data: Dictionary, definition: Dictionary, quest_state: Dictionary, message: String, action_label: String) -> void:
	active_dialogue_npc = npc_data.duplicate(true)
	_clear_interaction_body()
	interaction_title.text = str(npc_data.get("label", npc_data.get("name", "NPC")))
	_show_interaction_panel()
	if simulation_lightweight_mode:
		return
	_add_interaction_row(message)
	if not definition.is_empty():
		_add_interaction_section(str(definition.get("display_name", "Quest")))
		var status: String = "Complete" if bool(quest_state.get("completed", false)) else ("Started" if bool(quest_state.get("started", false)) else "Not started")
		_add_interaction_muted("Status: %s" % status)
	if not action_label.is_empty() and action_label != "Close":
		var action_button := Button.new()
		action_button.text = action_label
		action_button.pressed.connect(func() -> void: dialogue_action_requested.emit(active_dialogue_npc.duplicate(true)))
		interaction_body.add_child(action_button)


func show_item_action_panel(item_id: String) -> void:
	if item_id.is_empty():
		return
	var inventory := _stack_mapping(current_state.get("inventory", {}))
	if int(inventory.get(item_id, 0)) <= 0:
		set_feedback("No %s" % _item_name(item_id))
		return
	var definition = items_data.get(item_id, {})
	_clear_interaction_body()
	interaction_title.text = _item_name(item_id)
	_show_interaction_panel()
	if simulation_lightweight_mode:
		return
	_new_item_interaction_row(item_id, _display_label(_item_category(item_id)))
	_add_interaction_row(_item_tooltip(item_id, int(inventory[item_id])))
	var added_action := false
	if definition is Dictionary and _definition_is_usable(definition):
		_add_inventory_action_button("Use", item_id, "use")
		added_action = true
	if definition is Dictionary and _definition_is_equipment(definition):
		_add_inventory_action_button("Equip", item_id, "equip")
		added_action = true
	_add_inventory_action_button("Examine", item_id, "examine")
	added_action = true
	_add_inventory_action_button("Drop 1", item_id, "drop")
	added_action = true
	if not added_action:
		_add_interaction_muted("No actions available")


func show_equipment_action_panel(slot: String) -> void:
	if slot.is_empty():
		return
	var equipment := _string_mapping(current_state.get("equipment", {}))
	var item_id := str(equipment.get(slot, ""))
	if item_id.is_empty():
		set_feedback("No item equipped in %s" % _display_label(slot))
		return
	_clear_interaction_body()
	interaction_title.text = "%s: %s" % [_display_label(slot), _item_name(item_id)]
	_show_interaction_panel()
	if simulation_lightweight_mode:
		return
	_new_item_interaction_row(item_id, _display_label(_item_category(item_id)))
	_add_interaction_row(_item_tooltip(item_id))
	_add_equipment_action_button("Unequip", slot, "unequip")
	_add_equipment_action_button("Examine", slot, "examine")


func _clear_interaction_body() -> void:
	if interaction_body == null:
		return
	_clear_container_children(interaction_body)


func _clear_container_children(container: Node) -> void:
	for child in container.get_children():
		if simulation_lightweight_mode:
			container.remove_child(child)
			child.free()
		else:
			child.queue_free()


func _add_bank_inventory_row(item_id: String, quantity: int) -> void:
	var actions := _new_transaction_item_row(item_id, "x%d" % quantity)
	var one := Button.new()
	one.text = "Deposit 1"
	_configure_transaction_button(one, 88.0)
	one.pressed.connect(func() -> void: bank_deposit_requested.emit(item_id, 1))
	actions.add_child(one)
	var all := Button.new()
	all.text = "All"
	_configure_transaction_button(all, 42.0)
	all.pressed.connect(func() -> void: bank_deposit_requested.emit(item_id, 0))
	actions.add_child(all)


func _add_bank_storage_row(item_id: String, quantity: int) -> void:
	var actions := _new_transaction_item_row(item_id, "x%d stored" % quantity)
	var one := Button.new()
	one.text = "Withdraw 1"
	_configure_transaction_button(one, 96.0)
	one.pressed.connect(func() -> void: bank_withdraw_requested.emit(item_id, 1))
	actions.add_child(one)
	var all := Button.new()
	all.text = "All"
	_configure_transaction_button(all, 42.0)
	all.pressed.connect(func() -> void: bank_withdraw_requested.emit(item_id, 0))
	actions.add_child(all)


func _add_shop_stock_row(item_id: String, price: int) -> void:
	if item_id.is_empty() or price <= 0:
		return
	var actions := _new_transaction_item_row(item_id, "%d coins" % price)
	var button := Button.new()
	button.text = "Buy"
	_configure_transaction_button(button, TRANSACTION_ACTION_COLUMN_WIDTH)
	button.pressed.connect(func() -> void: shop_buy_requested.emit(item_id, price))
	actions.add_child(button)


func _add_shop_inventory_row(item_id: String, quantity: int, price: int) -> void:
	var actions := _new_transaction_item_row(item_id, "x%d  %d ea" % [quantity, price])
	var one := Button.new()
	one.text = "Sell 1"
	_configure_transaction_button(one, 78.0)
	one.pressed.connect(func() -> void: shop_sell_requested.emit(item_id, 1))
	actions.add_child(one)
	var all := Button.new()
	all.text = "All"
	_configure_transaction_button(all, 42.0)
	all.pressed.connect(func() -> void: shop_sell_requested.emit(item_id, 0))
	actions.add_child(all)


func _add_inventory_action_button(label: String, item_id: String, action: String) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func() -> void: inventory_item_action_requested.emit(item_id, action))
	interaction_body.add_child(button)


func _add_equipment_action_button(label: String, slot: String, action: String) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func() -> void: equipment_item_action_requested.emit(slot, action))
	interaction_body.add_child(button)


func _new_item_interaction_row(item_id: String, detail_text: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	interaction_body.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = _item_color(item_id)
	stripe.custom_minimum_size = Vector2(4, 30)
	row.add_child(stripe)

	var icon := _new_item_icon(item_id, Vector2(28, 28))
	row.add_child(icon)

	var text_stack := VBoxContainer.new()
	text_stack.add_theme_constant_override("separation", 0)
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_stack)

	var name_label := Label.new()
	name_label.text = _item_name(item_id)
	name_label.modulate = _item_color(item_id)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_stack.add_child(name_label)

	if not detail_text.is_empty():
		var detail_label := Label.new()
		detail_label.text = detail_text
		detail_label.modulate = Color(0.72, 0.72, 0.72, 1.0)
		text_stack.add_child(detail_label)
	return row


func _new_transaction_item_row(item_id: String, detail_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 36)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interaction_body.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = _item_color(item_id)
	stripe.custom_minimum_size = Vector2(4, 32)
	row.add_child(stripe)

	var icon := _new_item_icon(item_id, Vector2(28, 28))
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = _item_name(item_id)
	name_label.modulate = _item_color(item_id)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(TRANSACTION_NAME_COLUMN_WIDTH, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var detail_label := Label.new()
	detail_label.text = detail_text
	detail_label.modulate = Color(0.72, 0.72, 0.72, 1.0)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_label.custom_minimum_size = Vector2(TRANSACTION_DETAIL_COLUMN_WIDTH, 0)
	row.add_child(detail_label)

	var action_box := HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 4)
	action_box.custom_minimum_size = Vector2(TRANSACTION_ACTION_COLUMN_WIDTH, 0)
	action_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(action_box)
	return action_box


func _configure_transaction_button(button: Button, width: float) -> void:
	button.custom_minimum_size = Vector2(width, 30)


func _new_interaction_row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	interaction_body.add_child(row)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _add_interaction_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	interaction_body.add_child(label)


func _add_interaction_muted(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.72, 0.72, 0.72, 1.0)
	interaction_body.add_child(label)


func _add_interaction_row(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interaction_body.add_child(label)


func _add_tab_button(parent: HBoxContainer, tab_id: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: select_tab(tab_id))
	parent.add_child(button)
	tab_buttons[tab_id] = button


func _refresh_state_panel() -> void:
	if panel_body == null:
		return
	if simulation_lightweight_mode:
		_clear_container_children(panel_body)
		return
	_clear_container_children(panel_body)

	match active_tab:
		"inventory":
			panel_title.text = "Inventory"
			_render_inventory_panel()
		"equipment":
			panel_title.text = "Equipment"
			_render_equipment_panel()
		"skills":
			panel_title.text = "Skills"
			_render_skills_panel()
		"quests":
			panel_title.text = "Quests"
			_render_quests_panel()
		"state":
			panel_title.text = "State"
			_render_state_summary_panel()
		_:
			panel_title.text = "Inventory"
			_render_inventory_panel()


func _refresh_top_bar_from_state() -> void:
	if current_state.is_empty():
		return
	var account = current_state.get("account", {})
	var username := str(current_state.get("username", account.get("username", "-") if account is Dictionary else "-"))
	set_account(username)
	var player_state = current_state.get("player", {})
	if player_state is Dictionary:
		set_player_tile(_array_to_tile(player_state.get("tile", [0, 0]), Vector2i.ZERO))


func _render_inventory_panel() -> void:
	var inventory := _stack_mapping(current_state.get("inventory", {}))
	var bank := _stack_mapping(current_state.get("bank", {}))
	var compact := _right_panel_uses_compact_layout()
	var grid := GridContainer.new()
	grid.columns = INVENTORY_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	panel_body.add_child(grid)
	var views := _inventory_slot_views(inventory)
	var visible_slot_count := _inventory_visible_slot_count(views.size(), compact)
	var slot_size := INVENTORY_COMPACT_SLOT_SIZE if compact else INVENTORY_SLOT_SIZE
	for index in range(visible_slot_count):
		var button := ItemTooltipButton.new()
		button.custom_minimum_size = slot_size
		button.clip_contents = true
		if index < views.size():
			var view: Dictionary = views[index]
			var item_id := str(view["item_id"])
			var quantity := int(view["quantity"])
			button.text = ""
			_apply_item_tooltip(button, item_id, quantity)
			button.set_meta("item_name", _item_name(item_id))
			button.pressed.connect(func(selected_item_id := item_id) -> void: show_item_action_panel(selected_item_id))
			_add_inventory_button_content(button, view, compact)
		else:
			button.text = ""
			button.disabled = true
		grid.add_child(button)

	_add_muted_label("Slots %d/%d" % [_inventory_slot_count(inventory), INVENTORY_SLOT_LIMIT])
	_add_section_label("Bank")
	if bank.is_empty():
		_add_muted_label("Bank is empty")
	else:
		for item_id in _sorted_item_ids(bank):
			_add_panel_item_row(item_id, "x%d stored" % int(bank[item_id]))


func _add_inventory_button_content(button: Button, view: Dictionary, compact: bool = false) -> void:
	var item_id := str(view["item_id"])
	var quantity := int(view["quantity"])

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 4.0
	center.offset_top = 4.0
	center.offset_right = -4.0
	center.offset_bottom = -5.0
	button.add_child(center)

	var icon_size := INVENTORY_COMPACT_ICON_SIZE if compact else INVENTORY_ICON_SIZE
	var icon := _new_item_icon(item_id, icon_size)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(icon)

	var color_strip := ColorRect.new()
	color_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_color := _item_color(item_id)
	strip_color.a = 0.72
	color_strip.color = strip_color
	color_strip.anchor_left = 0.0
	color_strip.anchor_right = 1.0
	color_strip.anchor_top = 1.0
	color_strip.anchor_bottom = 1.0
	color_strip.offset_left = 4.0
	color_strip.offset_right = -4.0
	color_strip.offset_top = -5.0
	color_strip.offset_bottom = -2.0
	button.add_child(color_strip)

	var count_text := _slot_count_text(quantity)
	if count_text.is_empty():
		return
	var count := Label.new()
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.text = count_text
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.modulate = Color(1.0, 0.9, 0.28, 1.0)
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	count.add_theme_constant_override("shadow_offset_x", 1)
	count.add_theme_constant_override("shadow_offset_y", 1)
	count.anchor_left = 0.0
	count.anchor_right = 1.0
	count.anchor_top = 1.0
	count.anchor_bottom = 1.0
	count.offset_left = 2.0
	count.offset_right = -4.0
	count.offset_top = -19.0
	count.offset_bottom = -2.0
	button.add_child(count)


func _add_panel_item_row(item_id: String, detail_text: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel_body.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = _item_color(item_id)
	stripe.custom_minimum_size = Vector2(4, 24)
	row.add_child(stripe)

	row.add_child(_new_item_icon(item_id, Vector2(22, 22)))

	var text := Label.new()
	text.text = _item_name(item_id) if detail_text.is_empty() else "%s %s" % [_item_name(item_id), detail_text]
	text.modulate = _item_color(item_id)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)


func _render_equipment_panel() -> void:
	var equipment := _string_mapping(current_state.get("equipment", {}))
	var panel_scale := _equipment_panel_scale()
	var scaled_size := EQUIPMENT_PANEL_SIZE * panel_scale
	var frame := PanelContainer.new()
	frame.custom_minimum_size = scaled_size
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", _equipment_frame_style())
	panel_body.add_child(frame)

	var frame_slot := Control.new()
	frame_slot.custom_minimum_size = scaled_size
	frame.add_child(frame_slot)

	var canvas := Control.new()
	canvas.custom_minimum_size = EQUIPMENT_PANEL_SIZE
	canvas.size = EQUIPMENT_PANEL_SIZE
	canvas.scale = Vector2(panel_scale, panel_scale)
	frame_slot.add_child(canvas)

	_add_equipment_connector_lines(canvas)
	_add_equipment_silhouette(canvas)
	for slot in EQUIPMENT_SLOTS:
		_add_equipment_slot_tile(canvas, slot, str(equipment.get(slot, "")))
	_add_equipment_bonus_summary(equipment)


func _equipment_panel_scale() -> float:
	if _right_panel_uses_compact_layout():
		return EQUIPMENT_COMPACT_SCALE
	return 1.0


func _right_panel_uses_compact_layout() -> bool:
	return root_control != null and root_control.size.y <= RIGHT_PANEL_COMPACT_VIEWPORT_HEIGHT


func _add_equipment_slot_tile(parent: Control, slot: String, item_id: String) -> void:
	var button := ItemTooltipButton.new()
	button.position = _equipment_slot_position(slot)
	button.size = EQUIPMENT_SLOT_SIZE
	button.custom_minimum_size = EQUIPMENT_SLOT_SIZE
	button.clip_contents = true
	button.text = ""
	if not item_id.is_empty():
		_apply_item_tooltip(button, item_id)
	else:
		button.tooltip_text = _display_label(slot)
	button.add_theme_stylebox_override("normal", _equipment_slot_style(item_id, false))
	button.add_theme_stylebox_override("hover", _equipment_slot_style(item_id, true))
	button.add_theme_stylebox_override("pressed", _equipment_slot_style(item_id, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(func(selected_slot := slot) -> void: show_equipment_action_panel(selected_slot))
	if not item_id.is_empty():
		button.set_meta("item_name", _item_name(item_id))
	parent.add_child(button)

	if item_id.is_empty():
		var slot_label := Label.new()
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_label.text = _equipment_slot_abbrev(slot)
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_label.modulate = Color(0.64, 0.64, 0.58, 1.0)
		slot_label.add_theme_font_size_override("font_size", 9)
		slot_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(slot_label)
		return

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 3.0
	center.offset_top = 3.0
	center.offset_right = -3.0
	center.offset_bottom = -5.0
	button.add_child(center)

	var icon := _new_item_icon(item_id, Vector2(34, 34))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(icon)

	var strip := ColorRect.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_color := _item_color(item_id)
	strip_color.a = 0.82
	strip.color = strip_color
	strip.anchor_left = 0.0
	strip.anchor_right = 1.0
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.offset_left = 5.0
	strip.offset_right = -5.0
	strip.offset_top = -5.0
	strip.offset_bottom = -2.0
	button.add_child(strip)


func _equipment_slot_position(slot: String) -> Vector2:
	match slot:
		"head":
			return Vector2(103, 14)
		"cape":
			return Vector2(48, 58)
		"amulet":
			return Vector2(103, 62)
		"ammo":
			return Vector2(158, 58)
		"weapon":
			return Vector2(24, 110)
		"body":
			return Vector2(103, 110)
		"shield":
			return Vector2(182, 110)
		"hands":
			return Vector2(48, 178)
		"legs":
			return Vector2(103, 164)
		"ring":
			return Vector2(182, 178)
		"feet":
			return Vector2(103, 216)
	return Vector2.ZERO


func _equipment_slot_abbrev(slot: String) -> String:
	match slot:
		"head":
			return "HEAD"
		"cape":
			return "CAPE"
		"amulet":
			return "NECK"
		"ammo":
			return "AMMO"
		"weapon":
			return "WEPN"
		"body":
			return "BODY"
		"shield":
			return "SHLD"
		"hands":
			return "HAND"
		"legs":
			return "LEGS"
		"feet":
			return "FEET"
		"ring":
			return "RING"
	return _display_label(slot).to_upper()


func _add_equipment_connector_lines(parent: Control) -> void:
	var line_color := Color(0.34, 0.31, 0.25, 0.55)
	_add_equipment_line(parent, Vector2(126, 60), Vector2(2, 184), line_color)
	_add_equipment_line(parent, Vector2(70, 132), Vector2(112, 2), line_color)
	_add_equipment_line(parent, Vector2(71, 202), Vector2(111, 2), line_color)
	_add_equipment_line(parent, Vector2(126, 84), Vector2(56, 2), line_color)
	_add_equipment_line(parent, Vector2(70, 84), Vector2(56, 2), line_color)


func _add_equipment_line(parent: Control, line_position: Vector2, line_size: Vector2, color: Color) -> void:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = line_position
	line.size = line_size
	line.color = color
	parent.add_child(line)


func _add_equipment_silhouette(parent: Control) -> void:
	var body_color := Color(0.40, 0.38, 0.33, 0.55)
	var limb_color := Color(0.32, 0.31, 0.28, 0.48)
	_add_equipment_shape(parent, Vector2(116, 84), Vector2(20, 20), body_color, 10)
	_add_equipment_shape(parent, Vector2(108, 108), Vector2(36, 54), body_color, 7)
	_add_equipment_shape(parent, Vector2(88, 118), Vector2(16, 48), limb_color, 6)
	_add_equipment_shape(parent, Vector2(148, 118), Vector2(16, 48), limb_color, 6)
	_add_equipment_shape(parent, Vector2(110, 166), Vector2(13, 48), limb_color, 6)
	_add_equipment_shape(parent, Vector2(129, 166), Vector2(13, 48), limb_color, 6)


func _add_equipment_shape(parent: Control, shape_position: Vector2, shape_size: Vector2, color: Color, radius: int) -> void:
	var shape := PanelContainer.new()
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shape.position = shape_position
	shape.size = shape_size
	shape.add_theme_stylebox_override("panel", _flat_style(color, color, 0, radius))
	parent.add_child(shape)


func _equipment_frame_style() -> StyleBoxFlat:
	return _flat_style(Color(0.13, 0.12, 0.10, 0.94), Color(0.36, 0.33, 0.27, 1.0), 2, 8)


func _equipment_slot_style(item_id: String, is_hover: bool) -> StyleBoxFlat:
	var background := Color(0.18, 0.17, 0.15, 0.96)
	var border := Color(0.36, 0.34, 0.29, 1.0)
	var border_width := 1
	if not item_id.is_empty():
		border = _item_color(item_id)
		background = Color(0.20, 0.19, 0.17, 0.98)
		border_width = 2
	if is_hover:
		background = background.lightened(0.08)
		border = border.lightened(0.18)
	return _flat_style(background, border, border_width, 5)


func _flat_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _add_equipment_bonus_summary(equipment: Dictionary) -> void:
	var totals := _equipment_bonus_totals(equipment)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel_body.add_child(row)
	_add_equipment_bonus_tile(row, "Atk", int(totals.get("attack_bonus", 0)))
	_add_equipment_bonus_tile(row, "Str", int(totals.get("strength_bonus", 0)))
	_add_equipment_bonus_tile(row, "Def", int(totals.get("defence_bonus", 0)))
	_add_equipment_bonus_tile(row, "Rng", int(totals.get("ranged_bonus", 0)))
	_add_equipment_bonus_tile(row, "Mag", int(totals.get("magic_bonus", 0)))


func _add_equipment_bonus_tile(parent: HBoxContainer, label_text: String, value: int) -> void:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(48, 30)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override("panel", _flat_style(Color(0.12, 0.12, 0.11, 0.92), Color(0.28, 0.27, 0.24, 1.0), 1, 4))
	parent.add_child(tile)

	var label := Label.new()
	label.text = "%s %s" % [label_text, _equipment_bonus_value_text(value)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	tile.add_child(label)


func _equipment_bonus_totals(equipment: Dictionary) -> Dictionary:
	var totals := {}
	for key in EQUIPMENT_BONUS_KEYS:
		totals[key] = 0
	for slot in equipment.keys():
		var item_id := str(equipment[slot])
		var definition = items_data.get(item_id, {})
		if not (definition is Dictionary):
			continue
		for key in EQUIPMENT_BONUS_KEYS:
			totals[key] = int(totals[key]) + int(definition.get(key, 0))
	return totals


func _equipment_bonus_value_text(value: int) -> String:
	if value > 0:
		return "+%d" % value
	return str(value)


func _render_skills_panel() -> void:
	var skills = current_state.get("skills", {})
	if not (skills is Dictionary):
		_add_muted_label("No skills available")
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_body.add_child(grid)
	var rendered_count := 0
	for skill_id in _sorted_skill_ids(skills):
		var values = skills[skill_id]
		if not (values is Dictionary):
			continue
		_add_skill_tile(grid, skill_id, values)
		rendered_count += 1
	if rendered_count == 0:
		grid.queue_free()
		_add_muted_label("No skills available")
	else:
		_render_carpentry_specialization_panel(skills)


func _render_carpentry_specialization_panel(skills: Dictionary) -> void:
	var carpentry_values = skills.get("carpentry", {})
	if not (carpentry_values is Dictionary) or int(carpentry_values.get("level", 1)) < 40:
		return
	var specialization := str(current_state.get("carpentry_specialization", "")).to_lower()
	_add_section_label("Carpentry specialization")
	if specialization == "weaponwright":
		_add_muted_label("Weaponwright: 15% chance to return 1 plain tool handle from selected weapon crafts.")
		return
	if specialization == "fieldwright":
		_add_muted_label("Fieldwright: 15% chance to return 1 plain plank from selected utility crafts.")
		return
	_add_muted_label("Choose once at level 40. This specialization is permanent.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel_body.add_child(row)
	var weapon_button := Button.new()
	weapon_button.text = "Weaponwright\nTool-handle recovery"
	weapon_button.tooltip_text = "15% chance to return 1 plain tool handle from selected bow and staff crafts."
	weapon_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_button.pressed.connect(func() -> void: carpentry_specialization_requested.emit("weaponwright"))
	row.add_child(weapon_button)
	var field_button := Button.new()
	field_button.text = "Fieldwright\nPlank recovery"
	field_button.tooltip_text = "15% chance to return 1 plain plank from selected utility crafts."
	field_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_button.pressed.connect(func() -> void: carpentry_specialization_requested.emit("fieldwright"))
	row.add_child(field_button)


func _render_quests_panel() -> void:
	var quest_root := _quest_root()
	var quest_states = quest_root.get("quests", {})
	if not (quest_states is Dictionary):
		quest_states = {}
	var active_quest_id := str(quest_root.get("active_quest_id", "starter_path"))
	var definitions := _quest_definitions()
	if definitions.is_empty():
		_add_muted_label("No quests available")
		return
	var shown := {}
	if definitions.has(active_quest_id):
		_add_section_label("Active")
		_add_quest_row(active_quest_id, definitions[active_quest_id], quest_states.get(active_quest_id, {}), true)
		shown[active_quest_id] = true
	_add_section_label("Started")
	var started_ids: Array[String] = []
	for quest_id in quest_states.keys():
		var clean_id := str(quest_id)
		if shown.has(clean_id):
			continue
		var state = quest_states[quest_id]
		if state is Dictionary and (bool(state.get("started", false)) or bool(state.get("completed", false))) and definitions.has(clean_id):
			started_ids.append(clean_id)
	started_ids.sort_custom(func(left: String, right: String) -> bool: return _quest_title(left, definitions) < _quest_title(right, definitions))
	for quest_id in started_ids:
		_add_quest_row(quest_id, definitions[quest_id], quest_states.get(quest_id, {}), false)
		shown[quest_id] = true
	if started_ids.is_empty() and not quest_states.has(active_quest_id):
		_add_muted_label("No started quests")
	_add_section_label("Available")
	var available_ids: Array[String] = []
	for quest_id in definitions.keys():
		var clean_id := str(quest_id)
		if quest_states.has(clean_id) or shown.has(clean_id):
			continue
		available_ids.append(clean_id)
	available_ids.sort_custom(func(left: String, right: String) -> bool: return _quest_title(left, definitions) < _quest_title(right, definitions))
	for quest_id in available_ids:
		_add_quest_row(quest_id, definitions[quest_id], {}, false)
	if available_ids.is_empty():
		_add_muted_label("All quests have been started")


func _add_skill_tile(parent: GridContainer, skill_id: String, values: Dictionary) -> void:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(119, 60)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.set_meta("skill_id", skill_id)
	tile.set_meta("skill_icon_loaded", _skill_icon_path(skill_id) != FALLBACK_ICON_PATH)
	var current_level := int(values.get("level", 1))
	tile.tooltip_text = _skill_mastery_tooltip(skill_id, current_level)
	tile.add_theme_stylebox_override("panel", _skill_tile_style(skill_id))
	parent.add_child(tile)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	tile.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	margin.add_child(row)

	var icon := _new_skill_icon(skill_id, Vector2(28, 28))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text_stack := VBoxContainer.new()
	text_stack.add_theme_constant_override("separation", 0)
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_stack)

	var name_label := Label.new()
	name_label.text = _skill_name(skill_id)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 12)
	text_stack.add_child(name_label)

	var detail_label := Label.new()
	detail_label.text = "Lv %d  XP %s" % [int(values.get("level", 1)), _compact_number(int(values.get("xp", 0)))]
	detail_label.modulate = Color(0.74, 0.74, 0.70, 1.0)
	detail_label.clip_text = true
	detail_label.add_theme_font_size_override("font_size", 10)
	text_stack.add_child(detail_label)

	var mastery_label := Label.new()
	mastery_label.text = _skill_mastery_status(skill_id, current_level)
	mastery_label.modulate = Color(0.86, 0.72, 0.40, 1.0)
	mastery_label.clip_text = true
	mastery_label.add_theme_font_size_override("font_size", 9)
	text_stack.add_child(mastery_label)


func _skill_mastery_status(skill_id: String, current_level: int) -> String:
	var definition = skills_data.get(skill_id, {})
	if not (definition is Dictionary):
		return "Mastery unavailable"
	var perks = definition.get("mastery_perks", [])
	if not (perks is Array) or perks.is_empty():
		return "No mastery perks"
	var unlocked := 0
	var next_level := 0
	for perk in perks:
		if not (perk is Dictionary):
			continue
		var level := int(perk.get("level", 0))
		if level <= current_level:
			unlocked += 1
		elif next_level == 0 or level < next_level:
			next_level = level
	if next_level > 0:
		return "Mastery %d/%d  Next %d" % [unlocked, perks.size(), next_level]
	return "Mastery %d/%d  Complete" % [unlocked, perks.size()]


func _skill_mastery_tooltip(skill_id: String, current_level: int) -> String:
	var definition = skills_data.get(skill_id, {})
	if not (definition is Dictionary):
		return ""
	var lines: Array[String] = []
	var role := str(definition.get("role", ""))
	if not role.is_empty():
		lines.append(role)
	var perks = definition.get("mastery_perks", [])
	if perks is Array:
		for perk in perks:
			if perk is Dictionary:
				var prefix := "Unlocked" if int(perk.get("level", 0)) <= current_level else "Level %d"
				lines.append("%s: %s" % [prefix, str(perk.get("label", "Mastery perk"))])
	return "\n".join(lines)


func _add_quest_row(quest_id: String, definition: Dictionary, quest_state, is_active: bool = false) -> void:
	var state: Dictionary = quest_state if quest_state is Dictionary else {}
	var title := str(definition.get("display_name", _display_label(quest_id)))
	var ready_to_return := _quest_is_ready_to_return(definition, state)
	var status := _quest_status_text(state, is_active, ready_to_return)
	var compact := _right_panel_uses_compact_layout()
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 70 if compact else 80)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _quest_row_style(status))
	panel_body.add_child(row_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4 if compact else 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4 if compact else 5)
	row_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	var stripe := ColorRect.new()
	stripe.color = _quest_status_color(status)
	stripe.custom_minimum_size = Vector2(4, 30 if compact else 36)
	row.add_child(stripe)

	var icon := _new_asset_icon("ui/quest", Vector2(22, 22) if compact else Vector2(24, 24))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text_stack := VBoxContainer.new()
	text_stack.add_theme_constant_override("separation", 1)
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_stack)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	text_stack.add_child(header)

	var title_label := Label.new()
	title_label.text = title
	title_label.clip_text = true
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var status_label := Label.new()
	status_label.text = status
	status_label.modulate = _quest_status_color(status)
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.custom_minimum_size = Vector2(62 if compact else 68, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.clip_text = true
	header.add_child(status_label)

	var objective_label := Label.new()
	objective_label.text = _quest_objective_text(definition, state)
	objective_label.modulate = Color(0.74, 0.74, 0.70, 1.0)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_font_size_override("font_size", 10)
	text_stack.add_child(objective_label)

	var reward_label := Label.new()
	reward_label.text = _quest_reward_preview(definition)
	reward_label.modulate = Color(0.82, 0.72, 0.46, 1.0)
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.add_theme_font_size_override("font_size", 9)
	text_stack.add_child(reward_label)

	if bool(state.get("started", false)) and not bool(state.get("completed", false)) and not is_active:
		var track_button := Button.new()
		track_button.text = "Track"
		track_button.tooltip_text = "Track this quest"
		track_button.custom_minimum_size = Vector2(54 if compact else 64, 28)
		track_button.add_theme_font_size_override("font_size", 10)
		track_button.pressed.connect(func() -> void: quest_route_select_requested.emit(quest_id))
		row.add_child(track_button)


func _skill_tile_style(skill_id: String) -> StyleBoxFlat:
	var accent := _skill_color(skill_id)
	return _flat_style(Color(0.11, 0.15, 0.10, 0.92), accent, 1, 5)


func _skill_color(skill_id: String) -> Color:
	match skill_id:
		"attack":
			return Color(0.92, 0.46, 0.32, 1.0)
		"strength":
			return Color(0.90, 0.60, 0.30, 1.0)
		"defence":
			return Color(0.52, 0.66, 0.84, 1.0)
		"hitpoints":
			return Color(0.78, 0.38, 0.40, 1.0)
		"ranged":
			return Color(0.48, 0.72, 0.44, 1.0)
		"magic":
			return Color(0.58, 0.52, 0.90, 1.0)
		"woodcutting", "carpentry":
			return Color(0.70, 0.50, 0.26, 1.0)
		"mining", "smithing":
			return Color(0.72, 0.70, 0.64, 1.0)
		"fishing":
			return Color(0.48, 0.72, 0.90, 1.0)
		"foraging", "herbalism":
			return Color(0.58, 0.78, 0.42, 1.0)
	return Color(0.88, 0.80, 0.64, 1.0)


func _quest_row_style(status: String) -> StyleBoxFlat:
	return _flat_style(Color(0.11, 0.15, 0.10, 0.90), _quest_status_color(status), 1, 5)


func _quest_status_color(status: String) -> Color:
	match status:
		"Complete":
			return Color(0.52, 0.80, 0.58, 1.0)
		"Ready to return":
			return Color(0.96, 0.72, 0.30, 1.0)
		"Active":
			return Color(0.98, 0.82, 0.34, 1.0)
		"Started":
			return Color(0.64, 0.72, 0.86, 1.0)
	return Color(0.60, 0.62, 0.56, 1.0)


func _render_state_summary_panel() -> void:
	_add_section_label("Character")
	var time_state = current_state.get("time", {})
	if time_state is Dictionary:
		_add_row(_time_summary(time_state))
	var combat = current_state.get("combat", {})
	if combat is Dictionary:
		var current_hp := int(combat.get("current_hitpoints", 0))
		var max_hp := int(combat.get("max_hitpoints", current_hp))
		if max_hp > current_hp:
			_add_row("HP %d / %d" % [current_hp, max_hp])
		else:
			_add_row("HP %d" % current_hp)
	_render_state_quest_summary()
	var settings = current_state.get("settings", {})
	if settings is Dictionary and not settings.is_empty():
		_add_section_label("Settings")
		for setting_id in settings.keys():
			_add_row("%s: %s" % [_display_label(str(setting_id)), str(settings[setting_id])])
	if not chat_messages.is_empty():
		_add_section_label("Recent feedback")
		var first_message: int = int(max(0, chat_messages.size() - 5))
		for index in range(first_message, chat_messages.size()):
			_add_row(str(chat_messages[index]))


func _time_summary(time_state: Dictionary) -> String:
	var day := int(time_state.get("day", 1))
	var minute_of_day := int(time_state.get("minute", 0))
	var hour := int(floor(float(minute_of_day) / 60.0)) % 24
	var minute := minute_of_day % 60
	return "Day %d, %02d:%02d" % [day, hour, minute]


func _render_state_quest_summary() -> void:
	_add_section_label("Quests")
	var quest_root := _quest_root()
	var quest_states = quest_root.get("quests", {})
	if not (quest_states is Dictionary):
		quest_states = {}
	var definitions := _quest_definitions()
	var active_quest_id := str(quest_root.get("active_quest_id", ""))
	var shown := {}
	var shown_count := 0
	if not active_quest_id.is_empty():
		if _add_state_quest_row(active_quest_id, definitions, quest_states, true):
			shown[active_quest_id] = true
			shown_count += 1
	var quest_ids: Array[String] = []
	for quest_id in quest_states.keys():
		var clean_id := str(quest_id)
		if shown.has(clean_id):
			continue
		quest_ids.append(clean_id)
	quest_ids.sort_custom(func(left: String, right: String) -> bool: return _quest_title(left, definitions) < _quest_title(right, definitions))
	for quest_id in quest_ids:
		if _add_state_quest_row(quest_id, definitions, quest_states, false):
			shown_count += 1
	if shown_count == 0:
		_add_muted_label("No quest progress")


func _add_state_quest_row(quest_id: String, definitions: Dictionary, quest_states: Dictionary, force_show: bool) -> bool:
	var state = quest_states.get(quest_id, {})
	if not (state is Dictionary):
		state = {}
	if not force_show and not _quest_state_has_progress(state):
		return false
	var definition = definitions.get(quest_id, {})
	if not (definition is Dictionary):
		definition = {}
	_add_row("%s - %s" % [_quest_title(quest_id, definitions), _quest_status_text(state)])
	if not definition.is_empty():
		_add_muted_label(_quest_objective_text(definition, state))
	var flags = state.get("flags", [])
	if flags is Array and not flags.is_empty():
		_add_muted_label("Done: %s" % _readable_flags(flags))
	return true


func _quest_title(quest_id: String, definitions: Dictionary) -> String:
	var definition = definitions.get(quest_id, {})
	if definition is Dictionary:
		return str(definition.get("display_name", _display_label(quest_id)))
	return _display_label(quest_id)


func _quest_status_text(state: Dictionary, is_active: bool = false, ready_to_return: bool = false) -> String:
	if bool(state.get("completed", false)):
		return "Complete"
	if ready_to_return:
		return "Ready to return"
	if is_active and bool(state.get("started", false)):
		return "Active"
	if bool(state.get("started", false)):
		return "Started"
	return "Available"


func _quest_is_ready_to_return(definition: Dictionary, state: Dictionary) -> bool:
	if not bool(state.get("started", false)) or bool(state.get("completed", false)):
		return false
	var missing := []
	var flags = state.get("flags", [])
	if not (flags is Array):
		flags = []
	var objectives = definition.get("objectives", [])
	if not (objectives is Array):
		return false
	for objective in objectives:
		if objective is Dictionary and not flags.has(str(objective.get("flag", ""))):
			missing.append(objective)
	return missing.is_empty()


func _quest_reward_preview(definition: Dictionary) -> String:
	var rewards: Array[String] = []
	var item_rewards = definition.get("item_rewards", [])
	if item_rewards is Array:
		for reward in item_rewards:
			if reward is Dictionary:
				var item_id := str(reward.get("item_id", ""))
				var quantity := int(reward.get("quantity", 1))
				if not item_id.is_empty() and quantity > 0:
					rewards.append("%s x%d" % [_item_name(item_id), quantity])
	var skill_rewards = definition.get("skill_rewards", [])
	if skill_rewards is Array:
		for reward in skill_rewards:
			if reward is Dictionary:
				var skill_id := str(reward.get("skill_id", ""))
				var xp := int(reward.get("xp", 0))
				if not skill_id.is_empty() and xp > 0:
					rewards.append("%s XP +%d" % [_skill_name(skill_id), xp])
	if rewards.is_empty():
		return "Reward: none"
	return "Reward: %s" % "; ".join(rewards)


func _quest_state_has_progress(state: Dictionary) -> bool:
	if bool(state.get("started", false)) or bool(state.get("completed", false)):
		return true
	var flags = state.get("flags", [])
	return flags is Array and not flags.is_empty()


func _readable_flags(flags: Array) -> String:
	var readable: PackedStringArray = []
	for flag in flags:
		readable.append(_display_label(str(flag)))
	return ", ".join(readable)


func _quest_root() -> Dictionary:
	var root = current_state.get("quest_state", {})
	if root is Dictionary and root.has("quests"):
		return root
	return {"active_quest_id": "starter_path", "quests": {}}


func _quest_definitions() -> Dictionary:
	var definitions := {}
	var quests = quests_data.get("quests", [])
	if not (quests is Array):
		return definitions
	for quest in quests:
		if quest is Dictionary:
			definitions[str(quest.get("quest_id", ""))] = quest
	return definitions


func _quest_objective_text(definition: Dictionary, quest_state: Dictionary) -> String:
	if bool(quest_state.get("completed", false)):
		return str(definition.get("completed_objective", "Complete."))
	if not bool(quest_state.get("started", false)):
		return str(definition.get("not_started_objective", "Talk to the quest giver."))
	var flags = quest_state.get("flags", [])
	if not (flags is Array):
		flags = []
	var objectives = definition.get("objectives", [])
	if not (objectives is Array):
		return str(definition.get("return_objective", "Return to the quest giver."))
	var missing := []
	for objective in objectives:
		if objective is Dictionary and not flags.has(str(objective.get("flag", ""))):
			missing.append(objective)
	if missing.is_empty():
		return str(definition.get("return_objective", "Return to the quest giver."))
	var completed: int = objectives.size() - missing.size()
	var next_objective: Dictionary = missing[0]
	return str(definition.get("progress_format", "{completed}/{total}: {objective}.")).replace("{completed}", str(completed)).replace("{total}", str(objectives.size())).replace("{objective}", str(next_objective.get("label", "")))


func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel_body.add_child(label)


func _add_muted_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = Color(0.72, 0.72, 0.72, 1.0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.add_child(label)


func _add_row(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.add_child(label)


func _inventory_slot_views(inventory: Dictionary) -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	for item_id in _sorted_item_ids(inventory):
		var quantity := int(inventory[item_id])
		if quantity <= 0:
			continue
		if _is_stackable_item(item_id):
			views.append({"item_id": item_id, "quantity": quantity, "stackable": true})
		else:
			for _index in range(quantity):
				views.append({"item_id": item_id, "quantity": 1, "stackable": false})
				if views.size() >= INVENTORY_SLOT_LIMIT:
					return views
	return views


func _inventory_slot_count(inventory: Dictionary) -> int:
	var count := 0
	for item_id in inventory.keys():
		var quantity := int(inventory[item_id])
		if quantity <= 0:
			continue
		count += 1 if _is_stackable_item(str(item_id)) else quantity
	return count


func _inventory_visible_slot_count(filled_slots: int, compact: bool) -> int:
	if not compact:
		return INVENTORY_SLOT_LIMIT
	var visible_count: int = maxi(filled_slots, INVENTORY_COMPACT_EMPTY_SLOT_FLOOR)
	visible_count = mini(visible_count, INVENTORY_SLOT_LIMIT)
	var remainder := visible_count % INVENTORY_GRID_COLUMNS
	if remainder > 0:
		visible_count = mini(visible_count + INVENTORY_GRID_COLUMNS - remainder, INVENTORY_SLOT_LIMIT)
	return visible_count


func _slot_button_text(view: Dictionary) -> String:
	var item_id := str(view["item_id"])
	if bool(view.get("stackable", false)):
		return "%s\n%d" % [_compact_item_name(item_id), int(view["quantity"])]
	return _compact_item_name(item_id)


func _slot_count_text(quantity: int) -> String:
	if quantity <= 1:
		return ""
	if quantity >= 1000000:
		return "%dm" % int(quantity / 1000000)
	if quantity >= 10000:
		return "%dk" % int(quantity / 1000)
	return str(quantity)


func _compact_number(value: int) -> String:
	if value >= 1000000:
		return "%dm" % int(value / 1000000)
	if value >= 10000:
		return "%dk" % int(value / 1000)
	return str(value)


func _apply_item_tooltip(button: Button, item_id: String, quantity: int = 1) -> void:
	button.tooltip_text = _item_tooltip(item_id, quantity)
	button.set_meta("tooltip_accent", _item_color(item_id))


func _item_tooltip(item_id: String, quantity: int = 1) -> String:
	var definition = items_data.get(item_id, {})
	var lines: Array[String] = [_item_name(item_id)]
	var details: Array[String] = []
	var bonuses: Array[String] = []
	var effects: Array[String] = []
	var requirements: Array[String] = []
	if quantity > 1:
		details.append("Quantity: %d" % quantity)
	if definition is Dictionary:
		var category := str(definition.get("category", "misc"))
		details.append("Category: %s" % category)
		var sell_price := int(definition.get("sell_price", 0))
		if sell_price > 0:
			details.append("Sell: %d coins" % sell_price)
		if _definition_is_equipment(definition):
			details.append("Equip: %s" % _display_label(str(definition.get("equip_slot", ""))))
			bonuses.append_array(_equipment_bonus_lines(definition))
		if int(definition.get("heal_amount", 0)) > 0:
			effects.append("Heals %d HP" % int(definition["heal_amount"]))
		if bool(definition.get("cleanses_poison", false)):
			effects.append("Clears poison")
		effects.append_array(_usable_bonus_lines(definition))
		var requirement_text := _requirement_text(definition)
		if not requirement_text.is_empty():
			requirements.append("Requires: %s" % requirement_text)
	_add_tooltip_section(lines, "Details", details)
	_add_tooltip_section(lines, "Bonuses", bonuses)
	_add_tooltip_section(lines, "Effects", effects)
	_add_tooltip_section(lines, "Requirements", requirements)
	return "\n".join(lines)


func _add_tooltip_section(lines: Array[String], title: String, entries: Array[String]) -> void:
	if entries.is_empty():
		return
	lines.append("")
	lines.append(title)
	lines.append_array(entries)


func _equipment_item_summary(item_id: String) -> String:
	var definition = items_data.get(item_id, {})
	if not (definition is Dictionary):
		return ""
	var parts: Array[String] = _equipment_bonus_lines(definition)
	var requirement_text := _requirement_text(definition)
	if not requirement_text.is_empty():
		parts.append("Requires: %s" % requirement_text)
	return " | ".join(parts)


func _equipment_bonus_lines(definition: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in EQUIPMENT_BONUS_KEYS:
		var bonus := int(definition.get(key, 0))
		if bonus > 0:
			lines.append("%s +%d" % [_display_label(key.replace("_bonus", "")), bonus])
	return lines


func _usable_bonus_lines(definition: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in USABLE_BONUS_KEYS:
		var bonus := float(definition.get(key, 0.0))
		if bonus <= 0.0:
			continue
		if key == "action_speed_bonus":
			lines.append("Actions %d%% faster" % int(round(bonus * 100.0)))
		else:
			lines.append("%s +%d" % [_display_label(key.replace("_bonus", "")), int(bonus)])
	var duration := int(definition.get("effect_duration_seconds", 0))
	if not lines.is_empty() and duration > 0:
		lines.append("Lasts %ds" % duration)
	return lines


func _requirement_text(definition: Dictionary) -> String:
	var requirements = definition.get("required_skills", {})
	if not (requirements is Dictionary) or requirements.is_empty():
		return ""
	var texts: Array[String] = []
	for skill_id in requirements.keys():
		texts.append("%s %d" % [_skill_name(str(skill_id)), int(requirements[skill_id])])
	return ", ".join(texts)


func _definition_is_equipment(definition: Dictionary) -> bool:
	return not str(definition.get("equip_slot", "")).is_empty()


func _definition_is_usable(definition: Dictionary) -> bool:
	if int(definition.get("heal_amount", 0)) > 0 or bool(definition.get("cleanses_poison", false)):
		return true
	return not _usable_bonus_lines(definition).is_empty()


func _sorted_item_ids(items: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for item_id in items.keys():
		if int(items[item_id]) > 0:
			ids.append(str(item_id))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_definition = items_data.get(left, {})
		var right_definition = items_data.get(right, {})
		var left_category := str(left_definition.get("category", "") if left_definition is Dictionary else "")
		var right_category := str(right_definition.get("category", "") if right_definition is Dictionary else "")
		var left_rank := int(CATEGORY_ORDER.get(left_category, 99))
		var right_rank := int(CATEGORY_ORDER.get(right_category, 99))
		if left_rank == right_rank:
			return left < right
		return left_rank < right_rank
	)
	return ids


func _sorted_skill_ids(skills: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for skill_id in skills.keys():
		ids.append(str(skill_id))
	ids.sort_custom(func(left: String, right: String) -> bool:
		var left_rank := _skill_order_rank(left)
		var right_rank := _skill_order_rank(right)
		if left_rank == right_rank:
			return _skill_name(left) < _skill_name(right)
		return left_rank < right_rank
	)
	return ids


func _skill_order_rank(skill_id: String) -> int:
	var index := SKILL_DISPLAY_ORDER.find(skill_id)
	if index >= 0:
		return index
	return SKILL_DISPLAY_ORDER.size()


func _interaction_contains_button(text: String) -> bool:
	if interaction_body == null:
		return false
	for child in interaction_body.get_children():
		if child is Button and child.text == text:
			return true
	return false


func _panel_contains_button(text: String) -> bool:
	if panel_body == null:
		return false
	for child in panel_body.get_children():
		if _control_tree_contains_button_text(child, text):
			return true
	return false


func _panel_button_for_smoke(text: String) -> Button:
	if panel_body == null:
		return null
	for child in panel_body.get_children():
		var button := _control_tree_find_button_text(child, text)
		if button != null:
			return button
	return null


func _panel_contains_text(text: String) -> bool:
	if panel_body == null:
		return false
	for child in panel_body.get_children():
		if _control_tree_contains_text(child, text):
			return true
	return false


func _panel_skill_ids_for_smoke() -> Array[String]:
	var ids: Array[String] = []
	if panel_body == null:
		return ids
	for child in panel_body.get_children():
		_collect_skill_ids_for_smoke(child, ids)
	return ids


func _collect_skill_ids_for_smoke(node: Node, ids: Array[String]) -> void:
	if node.has_meta("skill_id"):
		ids.append(str(node.get_meta("skill_id")))
	for child in node.get_children():
		_collect_skill_ids_for_smoke(child, ids)


func _panel_contains_skill_icon(skill_id: String) -> bool:
	if panel_body == null:
		return false
	return _control_tree_contains_skill_icon(panel_body, skill_id)


func _control_tree_contains_skill_icon(node: Node, skill_id: String) -> bool:
	if node.has_meta("skill_id") and str(node.get_meta("skill_id")) == skill_id:
		return bool(node.get_meta("skill_icon_loaded", false))
	for child in node.get_children():
		if _control_tree_contains_skill_icon(child, skill_id):
			return true
	return false


func _control_tree_contains_button_text(node: Node, text: String) -> bool:
	if node.is_queued_for_deletion():
		return false
	if node is Button:
		if node.text == text or node.tooltip_text == text:
			return true
		if node.has_meta("item_name") and str(node.get_meta("item_name")) == text:
			return true
	if node is Label and node.text == text:
		return true
	for child in node.get_children():
		if _control_tree_contains_button_text(child, text):
			return true
	return false


func _control_tree_find_button_text(node: Node, text: String) -> Button:
	if node.is_queued_for_deletion():
		return null
	if node is Button and (node.text == text or node.tooltip_text == text):
		return node
	for child in node.get_children():
		var button := _control_tree_find_button_text(child, text)
		if button != null:
			return button
	return null


func _control_tree_contains_text(node: Node, text: String) -> bool:
	if node.is_queued_for_deletion():
		return false
	if node is Label and str(node.text).contains(text):
		return true
	if node is Button and (str(node.text).contains(text) or str(node.tooltip_text).contains(text)):
		return true
	for child in node.get_children():
		if _control_tree_contains_text(child, text):
			return true
	return false


func _stack_mapping(raw_value) -> Dictionary:
	if not (raw_value is Dictionary):
		return {}
	var clean := {}
	for item_id in raw_value.keys():
		var quantity := int(raw_value[item_id])
		if quantity > 0:
			clean[str(item_id)] = quantity
	return clean


func _string_mapping(raw_value) -> Dictionary:
	if not (raw_value is Dictionary):
		return {}
	var clean := {}
	for key in raw_value.keys():
		clean[str(key)] = str(raw_value[key])
	return clean


func _new_skill_icon(skill_id: String, size: Vector2) -> TextureRect:
	return _new_asset_icon(_skill_icon_key(skill_id), size)


func _new_asset_icon(icon_key: String, size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _asset_icon_texture(icon_key)
	return icon


func _asset_icon_texture(icon_key: String):
	var path := _asset_icon_path(icon_key)
	if item_icon_cache.has(path):
		return item_icon_cache[path]
	var texture = ResourceLoader.load(path)
	if texture == null and path != FALLBACK_ICON_PATH:
		texture = ResourceLoader.load(FALLBACK_ICON_PATH)
	item_icon_cache[path] = texture
	return texture


func _asset_icon_path(icon_key: String) -> String:
	var path := "res://assets/icons/%s.png" % icon_key
	if ResourceLoader.exists(path):
		return path
	return FALLBACK_ICON_PATH


func _new_item_icon(item_id: String, size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _item_icon_texture(item_id)
	return icon


func _item_icon_texture(item_id: String):
	var path := _item_icon_path(item_id)
	if item_icon_cache.has(path):
		return item_icon_cache[path]
	var texture = ResourceLoader.load(path)
	if texture == null and path != FALLBACK_ICON_PATH:
		texture = ResourceLoader.load(FALLBACK_ICON_PATH)
	item_icon_cache[path] = texture
	return texture


func _item_icon_path(item_id: String) -> String:
	var key := _item_icon_key(item_id)
	var path := "res://assets/icons/%s.png" % key
	if ResourceLoader.exists(path):
		return path
	return FALLBACK_ICON_PATH


func _item_icon_key(item_id: String) -> String:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		var explicit_icon := str(definition.get("icon", ""))
		if not explicit_icon.is_empty():
			return explicit_icon
	return "items/%s" % item_id


func _item_color(item_id: String) -> Color:
	return CATEGORY_COLORS.get(_item_category(item_id), CATEGORY_COLORS["misc"])


func _item_category(item_id: String) -> String:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return str(definition.get("category", "misc"))
	return "misc"


func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return str(definition.get("name", _display_label(item_id)))
	return _display_label(item_id)


func _compact_item_name(item_id: String) -> String:
	var words := _item_name(item_id).split(" ")
	if words.size() <= 1:
		return _item_name(item_id)
	return "%s\n%s" % [words[0], words[1]]


func _skill_name(skill_id: String) -> String:
	var definition = skills_data.get(skill_id, {})
	if definition is Dictionary:
		return str(definition.get("display_name", _display_label(skill_id)))
	return _display_label(skill_id)


func _skill_icon_key(skill_id: String) -> String:
	var definition = skills_data.get(skill_id, {})
	if definition is Dictionary:
		var explicit_icon := str(definition.get("icon", ""))
		if not explicit_icon.is_empty():
			return explicit_icon
	return "skills/%s" % skill_id


func _skill_icon_path(skill_id: String) -> String:
	return _asset_icon_path(_skill_icon_key(skill_id))


func _is_stackable_item(item_id: String) -> bool:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary and definition.has("stackable"):
		return bool(definition["stackable"])
	return item_id == "coins"


func _sell_price(item_id: String) -> int:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return int(definition.get("sell_price", 0))
	return 0


func _array_to_tile(value, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


func _display_label(value: String) -> String:
	return value.replace("_", " ").capitalize()
