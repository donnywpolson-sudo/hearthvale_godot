extends CanvasLayer

const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const QUESTS_PATH := "res://data/quests.json"
const INVENTORY_SLOT_LIMIT := 28
const EQUIPMENT_SLOTS := ["head", "cape", "amulet", "ammo", "weapon", "body", "shield", "legs", "hands", "feet", "ring"]
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
var panel: PanelContainer
var panel_title: Label
var panel_body: VBoxContainer


func _ready() -> void:
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	quests_data = _load_json(QUESTS_PATH)
	_build_state_panel()


func set_account(username: String) -> void:
	account_label.text = "Account: %s" % username


func set_player_tile(tile: Vector2i) -> void:
	tile_label.text = "Tile: %d, %d" % [tile.x, tile.y]


func set_selection(label: String) -> void:
	selection_label.text = "Selected: %s" % label


func set_feedback(message: String) -> void:
	feedback_label.text = message
	if message.strip_edges().is_empty():
		return
	chat_messages.append(message)
	while chat_messages.size() > 8:
		chat_messages.pop_front()
	if active_tab == "state":
		_refresh_state_panel()


func bind_state(state: Dictionary) -> void:
	current_state = state
	_refresh_top_bar_from_state()
	_refresh_state_panel()


func refresh_state() -> void:
	_refresh_top_bar_from_state()
	_refresh_state_panel()


func select_tab(tab_id: String) -> void:
	active_tab = tab_id
	for key in tab_buttons.keys():
		tab_buttons[key].disabled = key == active_tab
	_refresh_state_panel()


func run_ui_state_smoke() -> bool:
	if current_state.is_empty():
		return false
	for tab_id in ["inventory", "equipment", "skills", "quests", "state"]:
		select_tab(tab_id)
		if panel_body.get_child_count() == 0:
			return false
	select_tab("inventory")
	return account_label.text.contains(str(current_state.get("username", ""))) and panel_title.text == "Inventory"


func _build_state_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "StatePanel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -292.0
	panel.offset_top = 58.0
	panel.offset_right = -10.0
	panel.offset_bottom = -190.0
	root_control.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	panel_title = Label.new()
	panel_title.text = "Inventory"
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(panel_title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	stack.add_child(tabs)
	_add_tab_button(tabs, "inventory", "Inv")
	_add_tab_button(tabs, "equipment", "Gear")
	_add_tab_button(tabs, "skills", "Skills")
	_add_tab_button(tabs, "quests", "Quest")
	_add_tab_button(tabs, "state", "State")

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(246, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	panel_body = VBoxContainer.new()
	panel_body.add_theme_constant_override("separation", 6)
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_body)

	select_tab(active_tab)


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
	for child in panel_body.get_children():
		child.queue_free()

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
	_add_section_label("Inventory slots: %d / %d" % [_inventory_slot_count(inventory), INVENTORY_SLOT_LIMIT])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	panel_body.add_child(grid)
	var views := _inventory_slot_views(inventory)
	for index in range(INVENTORY_SLOT_LIMIT):
		var button := Button.new()
		button.custom_minimum_size = Vector2(58, 38)
		if index < views.size():
			var view: Dictionary = views[index]
			button.text = _slot_button_text(view)
			button.tooltip_text = _item_name(str(view["item_id"]))
			button.pressed.connect(func(item_id := str(view["item_id"])) -> void: set_feedback("Selected item: %s" % _item_name(item_id)))
		else:
			button.text = ""
			button.disabled = true
		grid.add_child(button)

	_add_section_label("Bank")
	if bank.is_empty():
		_add_muted_label("Bank is empty")
	else:
		for item_id in _sorted_item_ids(bank):
			_add_row("%s x%d" % [_item_name(item_id), int(bank[item_id])])


func _render_equipment_panel() -> void:
	var equipment := _string_mapping(current_state.get("equipment", {}))
	for slot in EQUIPMENT_SLOTS:
		var item_id := str(equipment.get(slot, ""))
		var text := "%s: " % _display_label(slot)
		text += _item_name(item_id) if not item_id.is_empty() else "-"
		_add_row(text)


func _render_skills_panel() -> void:
	var skills = current_state.get("skills", {})
	if not (skills is Dictionary):
		_add_muted_label("No skills available")
		return
	for skill_id in _sorted_skill_ids(skills):
		var values = skills[skill_id]
		if not (values is Dictionary):
			continue
		var label := _skill_name(skill_id)
		var level := int(values.get("level", 1))
		var xp := int(values.get("xp", 0))
		_add_row("%s  Lv %d  XP %d" % [label, level, xp])


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
	if definitions.has(active_quest_id):
		_add_section_label("Active")
		_add_quest_row(active_quest_id, definitions[active_quest_id], quest_states.get(active_quest_id, {}))
	_add_section_label("Started")
	var shown_count := 0
	for quest_id in quest_states.keys():
		if str(quest_id) == active_quest_id:
			continue
		var state = quest_states[quest_id]
		if state is Dictionary and (bool(state.get("started", false)) or bool(state.get("completed", false))) and definitions.has(str(quest_id)):
			_add_quest_row(str(quest_id), definitions[str(quest_id)], state)
			shown_count += 1
	if shown_count == 0 and not quest_states.has(active_quest_id):
		_add_muted_label("No started quests")
	_add_section_label("Available")
	var available_count := 0
	for quest_id in definitions.keys():
		if quest_states.has(str(quest_id)):
			continue
		available_count += 1
		if available_count <= 6:
			var definition: Dictionary = definitions[quest_id]
			_add_row("%s: %s" % [str(definition.get("display_name", quest_id)), str(definition.get("not_started_objective", "Talk to the quest giver."))])
	if available_count == 0:
		_add_muted_label("All quests have been started")


func _add_quest_row(quest_id: String, definition: Dictionary, quest_state) -> void:
	var state: Dictionary = quest_state if quest_state is Dictionary else {}
	var title := str(definition.get("display_name", _display_label(quest_id)))
	var status: String = "complete" if bool(state.get("completed", false)) else ("active" if bool(state.get("started", false)) else "not started")
	_add_row("%s (%s)" % [title, status])
	_add_muted_label(_quest_objective_text(definition, state))


func _render_state_summary_panel() -> void:
	var time_state = current_state.get("time", {})
	if time_state is Dictionary:
		_add_row("Day %d  Minute %d" % [int(time_state.get("day", 1)), int(time_state.get("minute", 0))])
	var combat = current_state.get("combat", {})
	if combat is Dictionary:
		_add_row("HP: %d" % int(combat.get("current_hitpoints", 0)))
	var quest_progress = current_state.get("quest_progress", current_state.get("quest_state", {}))
	_add_section_label("Quest progress")
	if quest_progress is Dictionary and not quest_progress.is_empty():
		for quest_id in quest_progress.keys():
			_add_row("%s: %s" % [_display_label(str(quest_id)), str(quest_progress[quest_id])])
	else:
		_add_muted_label("No active quest progress")
	var settings = current_state.get("settings", {})
	_add_section_label("Settings")
	if settings is Dictionary and not settings.is_empty():
		for setting_id in settings.keys():
			_add_row("%s: %s" % [_display_label(str(setting_id)), str(settings[setting_id])])
	else:
		_add_muted_label("No settings saved")
	_add_section_label("Feedback")
	if chat_messages.is_empty():
		_add_muted_label("No feedback yet")
	else:
		for message in chat_messages:
			_add_row(message)


func _quest_root() -> Dictionary:
	var root = current_state.get("quest_state", {})
	if root is Dictionary and root.has("quests"):
		return root
	var legacy = current_state.get("quest_progress", {})
	if legacy is Dictionary:
		return {"active_quest_id": "starter_path", "quests": legacy}
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


func _slot_button_text(view: Dictionary) -> String:
	var item_id := str(view["item_id"])
	if bool(view.get("stackable", false)):
		return "%s\n%d" % [_compact_item_name(item_id), int(view["quantity"])]
	return _compact_item_name(item_id)


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
	ids.sort_custom(func(left: String, right: String) -> bool: return _skill_name(left) < _skill_name(right))
	return ids


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


func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return ""
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return str(definition.get("name", _display_label(item_id)))
	return _display_label(item_id)


func _compact_item_name(item_id: String) -> String:
	var words := _item_name(item_id).split(" ")
	if words.size() <= 2:
		return _item_name(item_id)
	return "%s %s" % [words[0], words[1]]


func _skill_name(skill_id: String) -> String:
	var definition = skills_data.get(skill_id, {})
	if definition is Dictionary:
		return str(definition.get("display_name", _display_label(skill_id)))
	return _display_label(skill_id)


func _is_stackable_item(item_id: String) -> bool:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary and definition.has("stackable"):
		return bool(definition["stackable"])
	return item_id == "coins"


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
