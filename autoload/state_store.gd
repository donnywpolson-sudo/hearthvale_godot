extends Node

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves"
const MAX_SAVE_STEM_LENGTH := 64
const DEFAULT_COMBAT_TRAINING_STYLE := "attack"

const STARTER_ITEMS := {
	"bronze_axe": 1,
	"bronze_pickaxe": 1,
	"fishing_rod": 1,
	"bronze_sword": 1,
	"training_bow": 1,
	"training_staff": 1,
	"bronze_shield": 1,
}

const DEFAULT_SKILL_IDS := [
	"woodcutting",
	"mining",
	"fishing",
	"foraging",
	"herbalism",
	"cooking",
	"attack",
	"strength",
	"defence",
	"ranged",
	"magic",
	"hitpoints",
	"smithing",
	"carpentry",
]

const DEFAULT_SETTINGS := {
	"fullscreen": false,
	"master_volume": 1.0,
	"music_volume": 1.0,
	"sfx_volume": 1.0,
}

var current_state := {}
var save_dir := SAVE_DIR


func create_default_state(username: String) -> Dictionary:
	var clean_username := username.strip_edges()
	if clean_username.is_empty():
		clean_username = "player"

	var skills := {}
	for skill_id in DEFAULT_SKILL_IDS:
		var default_level := 1
		if skill_id == "hitpoints":
			default_level = 10
		skills[skill_id] = {"xp": 0, "level": default_level}

	var combat := {
		"current_hitpoints": 10,
		"mobs": {},
		"ground_items": [],
		"status_effects": {},
	}

	var now := Time.get_datetime_string_from_system(true)
	return {
		"schema": "hearthvale_godot_reset_v1",
		"version": SAVE_VERSION,
		"account": {
			"username": clean_username,
			"created_at": now,
			"last_login_at": null,
		},
		"username": clean_username,
		"player": {
			"tile": [15, 15],
			"position": [15.5, 15.5],
		},
		"camera": {
			"center_x": 15.0,
			"center_y": 15.0,
			"heading": 45.0,
			"zoom": 22.0,
		},
		"inventory": STARTER_ITEMS.duplicate(true),
		"bank": {},
		"equipment": {},
		"combat_training_style": DEFAULT_COMBAT_TRAINING_STYLE,
		"skills": skills,
		"combat": combat.duplicate(true),
		"active_effects": [],
		"quest_progress": {},
		"quest_state": {},
		"settings": DEFAULT_SETTINGS.duplicate(true),
		"world": {
			"depleted_resources": [],
			"chopped_trees": [],
			"resource_nodes": {},
			"combat": combat.duplicate(true),
			"active_effects": [],
			"quest_state": {},
			"day": 1,
			"minute": 720.0,
		},
		"time": {"day": 1, "minute": 720.0},
	}


func load_or_create_state(username: String) -> Dictionary:
	var loaded := load_state(username)
	if not loaded.is_empty():
		current_state = loaded.duplicate(true)
		return current_state

	current_state = create_default_state(username)
	save_state(username, current_state)
	return current_state


func save_state(username: String, state: Dictionary) -> bool:
	var save_path := get_save_path(username)
	_ensure_save_dir()

	var state_to_save := state.duplicate(true)
	state_to_save["username"] = username.strip_edges()
	if state_to_save.has("account") and (state_to_save["account"] is Dictionary):
		state_to_save["account"]["username"] = username.strip_edges()

	if FileAccess.file_exists(save_path):
		var backup_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path("%s.bak" % save_path)
		)
		if backup_error != OK:
			push_warning("Could not create save backup: %s" % backup_error)

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file for writing: %s" % save_path)
		return false

	file.store_string(JSON.stringify(state_to_save, "\t", true))
	file.close()
	current_state = state_to_save.duplicate(true)
	return true


func load_state(username: String) -> Dictionary:
	var save_path := get_save_path(username)
	if not FileAccess.file_exists(save_path):
		return {}

	var raw_json := FileAccess.get_file_as_string(save_path)
	var parsed = JSON.parse_string(raw_json)
	if parsed is Dictionary:
		return parsed

	push_warning("Save file did not contain a JSON object: %s" % save_path)
	return {}


func get_save_path(username: String) -> String:
	return "%s/%s.json" % [save_dir, sanitize_username_for_filename(username)]


func sanitize_username_for_filename(username: String) -> String:
	var raw_username := username.strip_edges()
	if raw_username.is_empty():
		raw_username = "player"

	var allowed := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
	var sanitized := ""
	for index in raw_username.length():
		var character := raw_username.substr(index, 1)
		if allowed.contains(character):
			sanitized += character
		else:
			sanitized += "_"

	sanitized = _strip_save_stem_edges(sanitized.strip_edges())
	if sanitized.length() > MAX_SAVE_STEM_LENGTH:
		sanitized = _strip_save_stem_edges(sanitized.substr(0, MAX_SAVE_STEM_LENGTH))
	if sanitized.is_empty():
		sanitized = "user"

	var reserved_names := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
	var changed := sanitized != raw_username
	var reserved := reserved_names.has(sanitized.to_upper())
	if changed or reserved:
		var digest := raw_username.sha256_text().substr(0, 12)
		var available_length := MAX_SAVE_STEM_LENGTH - digest.length() - 1
		sanitized = "%s_%s" % [_strip_save_stem_edges(sanitized.substr(0, available_length)), digest]

	return sanitized


func add_inventory_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	if current_state.is_empty():
		return false
	var inventory := _stack_mapping(current_state.get("inventory", {}))
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
	current_state["inventory"] = inventory
	return true


func remove_inventory_item(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0 or current_state.is_empty():
		return 0
	var inventory := _stack_mapping(current_state.get("inventory", {}))
	var removed: int = min(int(inventory.get(item_id, 0)), quantity)
	var remaining: int = int(inventory.get(item_id, 0)) - removed
	if remaining > 0:
		inventory[item_id] = remaining
	else:
		inventory.erase(item_id)
	current_state["inventory"] = inventory
	return removed


func deposit_to_bank(item_id: String, quantity: int = 1) -> int:
	if current_state.is_empty():
		return 0
	var removed := remove_inventory_item(item_id, quantity)
	if removed <= 0:
		return 0
	var bank := _stack_mapping(current_state.get("bank", {}))
	bank[item_id] = int(bank.get(item_id, 0)) + removed
	current_state["bank"] = bank
	return removed


func withdraw_from_bank(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0 or current_state.is_empty():
		return 0
	var bank := _stack_mapping(current_state.get("bank", {}))
	var removed: int = min(int(bank.get(item_id, 0)), quantity)
	if removed <= 0:
		return 0

	var remaining: int = int(bank.get(item_id, 0)) - removed
	if remaining > 0:
		bank[item_id] = remaining
	else:
		bank.erase(item_id)
	current_state["bank"] = bank
	add_inventory_item(item_id, removed)
	return removed


func set_quest_progress(quest_id: String, progress: Dictionary) -> void:
	if current_state.is_empty():
		return
	var quest_progress = current_state.get("quest_progress", {})
	if not (quest_progress is Dictionary):
		quest_progress = {}
	quest_progress[quest_id] = progress.duplicate(true)
	current_state["quest_progress"] = quest_progress
	current_state["quest_state"] = quest_progress.duplicate(true)
	if current_state.has("world") and current_state["world"] is Dictionary:
		current_state["world"]["quest_state"] = quest_progress.duplicate(true)


func update_setting(setting_id: String, value) -> void:
	if current_state.is_empty():
		return
	var settings = current_state.get("settings", DEFAULT_SETTINGS.duplicate(true))
	if not (settings is Dictionary):
		settings = DEFAULT_SETTINGS.duplicate(true)
	settings[setting_id] = value
	current_state["settings"] = settings


func run_save_roundtrip_smoke(username: String = "codex_smoke") -> bool:
	var state := create_default_state(username)
	current_state = state.duplicate(true)
	add_inventory_item("coins", 125)
	deposit_to_bank("bronze_axe", 1)
	set_quest_progress("starter_path", {"started": true, "completed": false, "flags": ["created_save"]})
	update_setting("sfx_volume", 0.75)

	if not save_state(username, current_state):
		return false

	var loaded := load_state(username)
	if loaded.is_empty():
		return false
	var inventory = loaded.get("inventory", {})
	var bank = loaded.get("bank", {})
	var quest_progress = loaded.get("quest_progress", {})
	var settings = loaded.get("settings", {})
	if not (inventory is Dictionary and bank is Dictionary and quest_progress is Dictionary and settings is Dictionary):
		return false
	return (
		str(loaded.get("schema", "")) == "hearthvale_godot_reset_v1"
		and int(loaded.get("version", 0)) == SAVE_VERSION
		and str(loaded.get("username", "")) == username
		and int(inventory.get("coins", 0)) == 125
		and int(bank.get("bronze_axe", 0)) == 1
		and quest_progress.has("starter_path")
		and float(settings.get("sfx_volume", 0.0)) == 0.75
	)


func _ensure_save_dir() -> void:
	var global_save_dir := ProjectSettings.globalize_path(save_dir)
	DirAccess.make_dir_recursive_absolute(global_save_dir)


func _stack_mapping(raw_value) -> Dictionary:
	if not (raw_value is Dictionary):
		return {}
	var clean := {}
	for item_id in raw_value.keys():
		var quantity := int(raw_value[item_id])
		if quantity > 0:
			clean[str(item_id)] = quantity
	return clean


func _strip_save_stem_edges(value: String) -> String:
	var start := 0
	var end := value.length()
	while start < end and _is_disallowed_save_edge(value.substr(start, 1)):
		start += 1
	while end > start and _is_disallowed_save_edge(value.substr(end - 1, 1)):
		end -= 1
	return value.substr(start, end - start)


func _is_disallowed_save_edge(character: String) -> bool:
	return character == " " or character == "." or character == "_"
