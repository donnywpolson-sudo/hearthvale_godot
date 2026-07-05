extends CanvasLayer

signal command_executed(command_line: String, success: bool, message: String)

const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const QUESTS_PATH := "res://data/quests.json"

var state := {}
var world: Node
var hud: CanvasLayer
var gameplay: Node
var items_data := {}
var skills_data := {}
var quests_data := {}
var panel: PanelContainer
var output_label: Label
var input_line: LineEdit
var output_lines: Array[String] = []


func _ready() -> void:
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	quests_data = _load_json(QUESTS_PATH)
	_build_ui()
	hide_console()


func setup(initial_state: Dictionary, world_node: Node, hud_node: CanvasLayer, gameplay_node: Node) -> void:
	state = initial_state
	world = world_node
	hud = hud_node
	gameplay = gameplay_node


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		toggle_console()
		get_viewport().set_input_as_handled()


func toggle_console() -> void:
	if panel == null:
		return
	panel.visible = not panel.visible
	if panel.visible and input_line != null:
		input_line.grab_focus()


func show_console() -> void:
	if panel != null:
		panel.visible = true
	if input_line != null:
		input_line.grab_focus()


func hide_console() -> void:
	if panel != null:
		panel.visible = false


func execute_command(command_line: String) -> Dictionary:
	var clean_line := command_line.strip_edges()
	if clean_line.is_empty():
		return _command_result(false, "No debug command entered.", clean_line)
	var parts := clean_line.split(" ", false)
	var command := str(parts[0]).to_lower()
	var args: Array[String] = []
	for index in range(1, parts.size()):
		args.append(str(parts[index]))

	var result := {}
	match command:
		"help":
			result = _command_result(true, "Commands: give_item, teleport, set_quest_state, set_skill, spawn_enemy, spawn_drop, heal, damage, force_weather.", clean_line)
		"give_item":
			result = _command_give_item(args, clean_line)
		"teleport":
			result = _command_teleport(args, clean_line)
		"set_quest_state":
			result = _command_set_quest_state(args, clean_line)
		"set_skill":
			result = _command_set_skill(args, clean_line)
		"spawn_enemy":
			result = _command_spawn_enemy(args, clean_line)
		"spawn_drop":
			result = _command_spawn_drop(args, clean_line)
		"heal":
			result = _command_adjust_hitpoints(args, clean_line, true)
		"damage":
			result = _command_adjust_hitpoints(args, clean_line, false)
		"force_weather":
			result = _command_force_weather(args, clean_line)
		_:
			result = _command_result(false, "Unknown debug command '%s'. Try help." % command, clean_line)
	_record_output(clean_line, bool(result.get("success", false)), str(result.get("message", "")))
	_refresh_targets()
	command_executed.emit(clean_line, bool(result.get("success", false)), str(result.get("message", "")))
	return result


func _command_give_item(args: Array[String], command_line: String) -> Dictionary:
	if args.is_empty():
		return _command_result(false, "Usage: give_item <item_id> [quantity]", command_line)
	var item_id := args[0]
	var quantity := _optional_positive_int(args, 1, 1)
	if quantity <= 0:
		return _command_result(false, "give_item quantity must be positive.", command_line)
	if not _item_exists(item_id):
		return _command_result(false, "Unknown item_id '%s'." % item_id, command_line)
	var inventory := _inventory()
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
	return _command_result(true, "Gave %d %s." % [quantity, item_id], command_line)


func _command_teleport(args: Array[String], command_line: String) -> Dictionary:
	if args.size() < 2:
		return _command_result(false, "Usage: teleport <x> <y>", command_line)
	if not args[0].is_valid_int() or not args[1].is_valid_int():
		return _command_result(false, "teleport coordinates must be integers.", command_line)
	var tile := Vector2i(int(args[0]), int(args[1]))
	if world != null and world.has_method("debug_teleport_to_tile"):
		if not bool(world.call("debug_teleport_to_tile", tile)):
			return _command_result(false, "Could not teleport to %d, %d." % [tile.x, tile.y], command_line)
	else:
		state["player"] = {"tile": [tile.x, tile.y], "position": [tile.x + 0.5, tile.y + 0.5]}
	return _command_result(true, "Teleported to %d, %d." % [tile.x, tile.y], command_line)


func _command_set_quest_state(args: Array[String], command_line: String) -> Dictionary:
	if args.size() < 2:
		return _command_result(false, "Usage: set_quest_state <quest_id> <not_started|started|complete>", command_line)
	var quest_id := args[0]
	var status := args[1].to_lower()
	if not _quest_exists(quest_id):
		return _command_result(false, "Unknown quest_id '%s'." % quest_id, command_line)
	if status not in ["not_started", "started", "complete", "completed"]:
		return _command_result(false, "Quest state must be not_started, started, or complete.", command_line)
	var root := _quest_root()
	root["active_quest_id"] = quest_id
	var quests: Dictionary = root["quests"]
	var quest_state: Dictionary = quests.get(quest_id, {"quest_id": quest_id, "flags": []})
	quest_state["quest_id"] = quest_id
	quest_state["started"] = status in ["started", "complete", "completed"]
	quest_state["completed"] = status in ["complete", "completed"]
	if not quest_state.has("flags") or not (quest_state["flags"] is Array):
		quest_state["flags"] = []
	quests[quest_id] = quest_state
	state["quest_progress"] = quests.duplicate(true)
	_world_state()["quest_state"] = root.duplicate(true)
	return _command_result(true, "Set %s to %s." % [quest_id, status], command_line)


func _command_set_skill(args: Array[String], command_line: String) -> Dictionary:
	if args.size() < 2:
		return _command_result(false, "Usage: set_skill <skill_id> <level> [xp]", command_line)
	var skill_id := args[0]
	if not _skill_exists(skill_id):
		return _command_result(false, "Unknown skill_id '%s'." % skill_id, command_line)
	if not args[1].is_valid_int():
		return _command_result(false, "set_skill level must be an integer.", command_line)
	var level := int(args[1])
	if level < 1 or level > 99:
		return _command_result(false, "set_skill level must be 1-99.", command_line)
	var xp := _optional_nonnegative_int(args, 2, int(_skills().get(skill_id, {}).get("xp", 0)) if _skills().get(skill_id, {}) is Dictionary else 0)
	if xp < 0:
		return _command_result(false, "set_skill xp must be non-negative.", command_line)
	_skills()[skill_id] = {"level": level, "xp": xp}
	return _command_result(true, "Set %s to level %d." % [skill_id, level], command_line)


func _command_spawn_enemy(args: Array[String], command_line: String) -> Dictionary:
	if args.is_empty():
		return _command_result(false, "Usage: spawn_enemy <mob_id> [level] [hitpoints]", command_line)
	var mob_id := args[0]
	var level := _optional_positive_int(args, 1, 1)
	var hitpoints := _optional_positive_int(args, 2, max(1, level + 1))
	if level <= 0 or hitpoints <= 0:
		return _command_result(false, "spawn_enemy level and hitpoints must be positive.", command_line)
	var mob_data := {
		"id": mob_id,
		"mob_id": mob_id,
		"label": mob_id.replace("_", " ").capitalize(),
		"display_name": mob_id.replace("_", " ").capitalize(),
		"level": level,
		"hitpoints": hitpoints,
		"visual_kind": "target_dummy",
		"drops": [],
	}
	if world != null and world.has_method("debug_spawn_mob"):
		mob_data = world.call("debug_spawn_mob", mob_data)
		if not (mob_data is Dictionary) or mob_data.is_empty():
			return _command_result(false, "Could not spawn enemy '%s'." % mob_id, command_line)
	_combat_state()["mobs"][mob_id] = {"hitpoints": hitpoints, "dead": false}
	return _command_result(true, "Spawned enemy %s." % mob_id, command_line)


func _command_spawn_drop(args: Array[String], command_line: String) -> Dictionary:
	if args.is_empty():
		return _command_result(false, "Usage: spawn_drop <item_id> [quantity]", command_line)
	var item_id := args[0]
	var quantity := _optional_positive_int(args, 1, 1)
	if quantity <= 0:
		return _command_result(false, "spawn_drop quantity must be positive.", command_line)
	if not _item_exists(item_id):
		return _command_result(false, "Unknown item_id '%s'." % item_id, command_line)
	var drop := {}
	if world != null and world.has_method("debug_spawn_ground_drop"):
		drop = world.call("debug_spawn_ground_drop", item_id, quantity)
	if not (drop is Dictionary) or drop.is_empty():
		drop = {
			"object_id": "debug_drop_%d" % Time.get_ticks_msec(),
			"item_id": item_id,
			"quantity": quantity,
			"type": "ground_item",
		}
	var ground_items = _combat_state().get("ground_items", [])
	if not (ground_items is Array):
		ground_items = []
	ground_items.append(drop)
	_combat_state()["ground_items"] = ground_items
	return _command_result(true, "Spawned drop %d %s." % [quantity, item_id], command_line)


func _command_adjust_hitpoints(args: Array[String], command_line: String, heal: bool) -> Dictionary:
	var amount := _optional_positive_int(args, 0, 9999 if heal else 1)
	if amount <= 0:
		return _command_result(false, "Hitpoint amount must be positive.", command_line)
	var combat := _combat_state()
	var skills := _skills()
	var hitpoints = skills.get("hitpoints", {"level": 10, "xp": 0})
	var max_hitpoints := int(hitpoints.get("level", 10)) if hitpoints is Dictionary else 10
	var current := int(combat.get("current_hitpoints", max_hitpoints))
	combat["current_hitpoints"] = min(max_hitpoints, current + amount) if heal else max(0, current - amount)
	return _command_result(true, "HP is now %d." % int(combat["current_hitpoints"]), command_line)


func _command_force_weather(args: Array[String], command_line: String) -> Dictionary:
	if args.is_empty() or args[0].strip_edges().is_empty():
		return _command_result(false, "Usage: force_weather <weather_id>", command_line)
	var weather_id := args[0].strip_edges().to_lower()
	_world_state()["weather"] = weather_id
	return _command_result(true, "Forced weather to %s." % weather_id, command_line)


func _build_ui() -> void:
	layer = 50
	panel = PanelContainer.new()
	panel.name = "DebugCommandConsole"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 12.0
	panel.offset_top = 56.0
	panel.offset_right = -12.0
	panel.offset_bottom = 196.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "Debug Console"
	stack.add_child(title)

	output_label = Label.new()
	output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_label.text = "F10 toggles console. Type help for commands."
	stack.add_child(output_label)

	input_line = LineEdit.new()
	input_line.placeholder_text = "give_item coins 100"
	input_line.text_submitted.connect(_on_command_submitted)
	stack.add_child(input_line)


func _on_command_submitted(command_line: String) -> void:
	var result := execute_command(command_line)
	input_line.clear()
	if bool(result.get("success", false)):
		input_line.grab_focus()


func _record_output(command_line: String, success: bool, message: String) -> void:
	var prefix := "ok" if success else "error"
	output_lines.append("[%s] %s -> %s" % [prefix, command_line, message])
	while output_lines.size() > 4:
		output_lines.pop_front()
	if output_label != null:
		output_label.text = "\n".join(output_lines)
	if hud != null and hud.has_method("set_feedback"):
		hud.set_feedback(message)


func _refresh_targets() -> void:
	if hud != null and hud.has_method("refresh_state"):
		hud.refresh_state()


func _command_result(success: bool, message: String, command_line: String) -> Dictionary:
	return {"success": success, "message": message, "command": command_line}


func _inventory() -> Dictionary:
	var inventory = state.get("inventory", {})
	if not (inventory is Dictionary):
		inventory = {}
		state["inventory"] = inventory
	return inventory


func _skills() -> Dictionary:
	var skills = state.get("skills", {})
	if not (skills is Dictionary):
		skills = {}
		state["skills"] = skills
	return skills


func _combat_state() -> Dictionary:
	var combat = state.get("combat", {})
	if not (combat is Dictionary):
		combat = {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "status_effects": {}}
		state["combat"] = combat
	if not combat.has("mobs") or not (combat["mobs"] is Dictionary):
		combat["mobs"] = {}
	if not combat.has("ground_items") or not (combat["ground_items"] is Array):
		combat["ground_items"] = []
	if not combat.has("status_effects") or not (combat["status_effects"] is Dictionary):
		combat["status_effects"] = {}
	if not combat.has("current_hitpoints"):
		combat["current_hitpoints"] = 10
	return combat


func _world_state() -> Dictionary:
	var world_state = state.get("world", {})
	if not (world_state is Dictionary):
		world_state = {}
		state["world"] = world_state
	return world_state


func _quest_root() -> Dictionary:
	var root = state.get("quest_state", {})
	if not (root is Dictionary) or not root.has("quests"):
		root = {"active_quest_id": "starter_path", "quests": {}}
		state["quest_state"] = root
	if not (root["quests"] is Dictionary):
		root["quests"] = {}
	return root


func _optional_positive_int(args: Array[String], index: int, fallback: int) -> int:
	if index >= args.size():
		return fallback
	if not args[index].is_valid_int():
		return -1
	var value := int(args[index])
	return value if value > 0 else -1


func _optional_nonnegative_int(args: Array[String], index: int, fallback: int) -> int:
	if index >= args.size():
		return fallback
	if not args[index].is_valid_int():
		return -1
	var value := int(args[index])
	return value if value >= 0 else -1


func _item_exists(item_id: String) -> bool:
	return items_data.has(item_id)


func _skill_exists(skill_id: String) -> bool:
	return skills_data.has(skill_id)


func _quest_exists(quest_id: String) -> bool:
	var quests = quests_data.get("quests", [])
	if not (quests is Array):
		return false
	for quest in quests:
		if quest is Dictionary and str(quest.get("quest_id", "")) == quest_id:
			return true
	return false


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}
