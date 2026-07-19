extends Node

const SAVE_VERSION := 2
const SAVE_SCHEMA := "hearthvale_godot_v2"
const LEGACY_SAVE_SCHEMA := "hearthvale_godot_reset_v1"
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
var last_error := ""
var _last_loaded_path := ""
var _last_load_needs_save := false
var _allow_invalid_primary_recovery := false


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
		"ground_drop_sequence": 0,
		"status_effects": {},
	}
	var account_key := canonical_account_key(clean_username)

	var now := Time.get_datetime_string_from_system(true)
	return {
		"schema": SAVE_SCHEMA,
		"version": SAVE_VERSION,
		"account": {
			"username": clean_username,
			"key": account_key,
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
		"carpentry_specialization": "",
		"skills": skills,
		"combat": combat,
		"active_effects": [],
		"quest_state": {"active_quest_id": "starter_path", "quests": {}},
		"settings": DEFAULT_SETTINGS.duplicate(true),
		"world": {
			"depleted_resources": [],
			"chopped_trees": [],
			"resource_nodes": {},
			"action_clock_seconds": 0.0,
			"action_cooldowns": {},
		},
		"time": {"day": 1, "minute": 720.0},
	}


func load_or_create_state(username: String) -> Dictionary:
	last_error = ""
	var loaded := load_state(username)
	if not loaded.is_empty():
		current_state = loaded.duplicate(true)
		if _last_load_needs_save:
			if not _preserve_loaded_source_as_backup(username):
				current_state = {}
				return {}
			_allow_invalid_primary_recovery = true
			var migrated := save_state(username, current_state)
			_allow_invalid_primary_recovery = false
			if not migrated:
				current_state = {}
				return {}
		return current_state
	if not last_error.is_empty():
		return {}

	current_state = create_default_state(username)
	if not save_state(username, current_state):
		current_state = {}
		return {}
	return current_state


func save_state(username: String, state: Dictionary) -> bool:
	last_error = ""
	var save_path := get_save_path(username)
	_ensure_save_dir()

	var state_to_save := _normalize_v2_state(state, username)
	var validation_error := _validate_v2_state(state_to_save)
	if not validation_error.is_empty():
		return _fail("Save state is invalid: %s" % validation_error)

	var temporary_path := "%s.tmp" % save_path
	var old_path := "%s.old" % save_path
	if FileAccess.file_exists(old_path):
		if FileAccess.file_exists(save_path):
			return _fail("A previous save transaction is ambiguous because both primary and staged files exist: %s" % old_path)
		var staged_result := _read_state_file(old_path, username)
		if not bool(staged_result.get("valid", false)):
			return _fail("A previous staged primary is invalid and cannot be recovered: %s" % str(staged_result.get("error", "unknown error")))
		var restore_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(old_path), ProjectSettings.globalize_path(save_path))
		if restore_error != OK:
			return _fail("Could not restore the validated staged primary: %s" % restore_error)
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not open temporary save file for writing: %s" % temporary_path)

	file.store_string(JSON.stringify(state_to_save, "\t", true))
	file.flush()
	file.close()
	var temporary_result := _read_state_file(temporary_path, username)
	if not bool(temporary_result.get("valid", false)) or bool(temporary_result.get("legacy", false)):
		return _fail("Temporary save validation failed: %s" % str(temporary_result.get("error", "unknown error")))

	var primary_exists := FileAccess.file_exists(save_path)
	if primary_exists:
		var primary_result := _read_state_file(save_path, username)
		if not bool(primary_result.get("valid", false)):
			if not _allow_invalid_primary_recovery:
				return _fail("Refusing to overwrite an invalid primary save: %s" % str(primary_result.get("error", "invalid save")))
			var corrupt_path := "%s.corrupt.%d" % [save_path, Time.get_ticks_msec()]
			var quarantine_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(corrupt_path))
			if quarantine_error != OK:
				return _fail("Could not preserve the invalid primary save before recovery: %s" % quarantine_error)
			if not _promote_temporary_save(temporary_path, save_path, username):
				DirAccess.rename_absolute(ProjectSettings.globalize_path(corrupt_path), ProjectSettings.globalize_path(save_path))
				return false
		else:
			var move_old_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(old_path))
			if move_old_error != OK:
				return _fail("Could not stage the existing primary save: %s" % move_old_error)
			if not _promote_temporary_save(temporary_path, save_path, username):
				DirAccess.rename_absolute(ProjectSettings.globalize_path(old_path), ProjectSettings.globalize_path(save_path))
				return false
			_rotate_validated_backup(old_path, "%s.bak" % save_path, username)
	else:
		if not _promote_temporary_save(temporary_path, save_path, username):
			return false

	state.clear()
	state.merge(state_to_save.duplicate(true), true)
	current_state = state
	return true


func load_state(username: String) -> Dictionary:
	last_error = ""
	_last_loaded_path = ""
	_last_load_needs_save = false
	_allow_invalid_primary_recovery = false
	var resolution := _resolve_account_files(username)
	if not str(resolution.get("error", "")).is_empty():
		_fail(str(resolution["error"]))
		return {}
	var primary_paths: Array = resolution.get("primary_paths", [])
	var recovery_paths: Array = resolution.get("recovery_paths", [])
	var backup_paths: Array = resolution.get("backup_paths", [])
	var errors: Array[String] = []
	for path_value in primary_paths:
		var path := str(path_value)
		var result := _read_state_file(path, username)
		if bool(result.get("valid", false)):
			_last_loaded_path = path
			_last_load_needs_save = bool(result.get("legacy", false)) or path != get_save_path(username)
			return _normalize_v2_state(result["state"], username)
		errors.append("%s: %s" % [path, str(result.get("error", "invalid save"))])
	for path_value in recovery_paths:
		var path := str(path_value)
		var result := _read_state_file(path, username)
		if bool(result.get("valid", false)):
			_last_loaded_path = path
			_last_load_needs_save = true
			_allow_invalid_primary_recovery = true
			return _normalize_v2_state(result["state"], username)
		errors.append("%s: %s" % [path, str(result.get("error", "invalid staged primary"))])
	for path_value in backup_paths:
		var path := str(path_value)
		var result := _read_state_file(path, username)
		if bool(result.get("valid", false)):
			_last_loaded_path = path
			_last_load_needs_save = true
			_allow_invalid_primary_recovery = true
			return _normalize_v2_state(result["state"], username)
		errors.append("%s: %s" % [path, str(result.get("error", "invalid backup"))])
	if not errors.is_empty():
		_fail("No safe save could be loaded. %s" % " | ".join(errors))
	elif bool(resolution.get("has_orphan_transaction", false)):
		_fail("An interrupted save transaction exists without a valid primary or backup.")
	return {}


func get_save_path(username: String) -> String:
	return "%s/%s.json" % [save_dir, sanitize_username_for_filename(username)]


func sanitize_username_for_filename(username: String) -> String:
	var raw_username := canonical_account_key(username)
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


func canonical_account_key(username: String) -> String:
	var clean := username.strip_edges().to_lower()
	return clean if not clean.is_empty() else "player"


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
	var quest_root = current_state.get("quest_state", {})
	if not (quest_root is Dictionary):
		quest_root = {}
	var quests = quest_root.get("quests", {})
	if not (quests is Dictionary):
		quests = {}
	quests[quest_id] = progress.duplicate(true)
	quest_root["quests"] = quests
	if not quest_root.has("active_quest_id"):
		quest_root["active_quest_id"] = "starter_path"
	current_state["quest_state"] = quest_root


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
	current_state["carpentry_specialization"] = "fieldwright"
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
	var quest_root = loaded.get("quest_state", {})
	var quest_progress = quest_root.get("quests", {}) if quest_root is Dictionary else {}
	var settings = loaded.get("settings", {})
	if not (inventory is Dictionary and bank is Dictionary and quest_progress is Dictionary and settings is Dictionary):
		return false
	return (
		str(loaded.get("schema", "")) == SAVE_SCHEMA
		and int(loaded.get("version", 0)) == SAVE_VERSION
		and str(loaded.get("username", "")) == username
		and int(inventory.get("coins", 0)) == 125
		and int(bank.get("bronze_axe", 0)) == 1
		and quest_progress.has("starter_path")
		and float(settings.get("sfx_volume", 0.0)) == 0.75
		and str(loaded.get("carpentry_specialization", "")) == "fieldwright"
	)


func _ensure_save_dir() -> void:
	var global_save_dir := ProjectSettings.globalize_path(save_dir)
	DirAccess.make_dir_recursive_absolute(global_save_dir)


func _normalize_v2_state(raw_state: Dictionary, requested_username: String) -> Dictionary:
	var normalized := raw_state.duplicate(true)
	var world_state = normalized.get("world", {})
	if not (world_state is Dictionary):
		world_state = {}

	var display_username := requested_username.strip_edges()
	var account = normalized.get("account", {})
	if account is Dictionary:
		display_username = str(account.get("username", normalized.get("username", display_username))).strip_edges()
	else:
		account = {}
	if display_username.is_empty():
		display_username = "player"
	account["username"] = display_username
	account["key"] = canonical_account_key(display_username)
	if not account.has("created_at"):
		account["created_at"] = Time.get_datetime_string_from_system(true)
	if not account.has("last_login_at"):
		account["last_login_at"] = null
	normalized["account"] = account
	normalized["username"] = display_username

	var quest_root = normalized.get("quest_state", {})
	var canonical_quests := {}
	var active_quest_id := "starter_path"
	if quest_root is Dictionary and quest_root.has("quests") and quest_root["quests"] is Dictionary:
		canonical_quests = quest_root["quests"].duplicate(true)
		active_quest_id = str(quest_root.get("active_quest_id", active_quest_id))
	elif normalized.get("quest_progress", {}) is Dictionary and not normalized.get("quest_progress", {}).is_empty():
		canonical_quests = normalized["quest_progress"].duplicate(true)
	elif quest_root is Dictionary:
		active_quest_id = str(quest_root.get("active_quest_id", active_quest_id))
		for key in quest_root.keys():
			if str(key) != "active_quest_id" and quest_root[key] is Dictionary:
				canonical_quests[str(key)] = quest_root[key].duplicate(true)
	normalized["quest_state"] = {"active_quest_id": active_quest_id, "quests": canonical_quests}
	normalized.erase("quest_progress")

	var combat = normalized.get("combat", {})
	if not normalized.has("combat") or not (combat is Dictionary):
		combat = world_state.get("combat", {})
	if not (combat is Dictionary):
		combat = {}
	if not combat.get("mobs", {}) is Dictionary:
		combat["mobs"] = {}
	if not combat.get("ground_items", []) is Array:
		combat["ground_items"] = []
	if not combat.get("status_effects", {}) is Dictionary:
		combat["status_effects"] = {}
	if not combat.has("current_hitpoints"):
		combat["current_hitpoints"] = 10
	combat["ground_drop_sequence"] = max(int(combat.get("ground_drop_sequence", 0)), _highest_ground_drop_sequence(combat["ground_items"]))
	normalized["combat"] = combat

	var active_effects = normalized.get("active_effects", world_state.get("active_effects", []))
	normalized["active_effects"] = active_effects if active_effects is Array else []
	var time_state = normalized.get("time", {})
	if not (time_state is Dictionary):
		time_state = {}
	time_state["day"] = max(1, int(time_state.get("day", world_state.get("day", 1))))
	time_state["minute"] = float(time_state.get("minute", world_state.get("minute", 720.0)))
	normalized["time"] = time_state

	for key in ["combat", "quest_state", "active_effects", "day", "minute"]:
		world_state.erase(key)
	if not world_state.get("resource_nodes", {}) is Dictionary:
		world_state["resource_nodes"] = {}
	if not world_state.get("action_cooldowns", {}) is Dictionary:
		world_state["action_cooldowns"] = {}
	world_state["action_clock_seconds"] = maxf(0.0, float(world_state.get("action_clock_seconds", 0.0)))
	normalized["world"] = world_state
	for key in ["inventory", "bank", "equipment", "skills", "settings"]:
		if not normalized.get(key, {}) is Dictionary:
			normalized[key] = {}
	normalized["schema"] = SAVE_SCHEMA
	normalized["version"] = SAVE_VERSION
	return normalized


func _validate_v2_state(state_value: Dictionary) -> String:
	if str(state_value.get("schema", "")) != SAVE_SCHEMA:
		return "unsupported schema"
	if int(state_value.get("version", 0)) != SAVE_VERSION:
		return "unsupported version"
	for key in ["account", "player", "camera", "inventory", "bank", "equipment", "skills", "combat", "quest_state", "settings", "world", "time"]:
		if not state_value.get(key, null) is Dictionary:
			return "%s must be a dictionary" % key
	if not state_value.get("active_effects", null) is Array:
		return "active_effects must be an array"
	var account: Dictionary = state_value["account"]
	if str(account.get("username", "")).strip_edges().is_empty() or str(account.get("key", "")).strip_edges().is_empty():
		return "account identity is incomplete"
	if str(account.get("key", "")) != canonical_account_key(str(account.get("username", ""))):
		return "account key does not match the display username"
	var quest_root: Dictionary = state_value["quest_state"]
	if not quest_root.get("quests", null) is Dictionary:
		return "quest_state.quests must be a dictionary"
	var combat: Dictionary = state_value["combat"]
	if not combat.get("mobs", null) is Dictionary or not combat.get("ground_items", null) is Array or not combat.get("status_effects", null) is Dictionary:
		return "combat state has an invalid shape"
	if int(combat.get("ground_drop_sequence", -1)) < 0:
		return "ground_drop_sequence must be non-negative"
	return ""


func _validate_legacy_state(state_value: Dictionary) -> String:
	if str(state_value.get("schema", "")) != LEGACY_SAVE_SCHEMA or int(state_value.get("version", 0)) != 1:
		return "unsupported schema or version"
	for key in ["player", "inventory", "bank", "equipment", "skills", "settings", "world"]:
		if not state_value.get(key, null) is Dictionary:
			return "legacy %s must be a dictionary" % key
	return ""


func _read_state_file(path: String, requested_username: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "error": "file is missing"}
	var parse_result := _parse_json(FileAccess.get_file_as_string(path))
	var parsed = parse_result.get("value")
	if not (parsed is Dictionary):
		return {"valid": false, "error": str(parse_result.get("error", "JSON root is not an object"))}
	var is_legacy := str(parsed.get("schema", "")) == LEGACY_SAVE_SCHEMA and int(parsed.get("version", 0)) == 1
	var error := _validate_legacy_state(parsed) if is_legacy else _validate_v2_state(parsed)
	if not error.is_empty():
		return {"valid": false, "error": error}
	var stored_username := _stored_username(parsed)
	if not stored_username.is_empty() and canonical_account_key(stored_username) != canonical_account_key(requested_username):
		return {"valid": false, "error": "account identity does not match the requested username"}
	return {"valid": true, "legacy": is_legacy, "state": parsed}


func _resolve_account_files(username: String) -> Dictionary:
	var canonical_path := get_save_path(username)
	var primary_paths: Array[String] = []
	var recovery_paths: Array[String] = []
	var backup_paths: Array[String] = []
	var requested_key := canonical_account_key(username)
	var directory := DirAccess.open(save_dir)
	if directory != null:
		for filename in directory.get_files():
			var is_backup := filename.ends_with(".json.bak")
			if not filename.ends_with(".json") and not is_backup:
				continue
			var path := "%s/%s" % [save_dir, filename]
			var parsed = _parse_json(FileAccess.get_file_as_string(path)).get("value")
			var matches := false
			if parsed is Dictionary:
				matches = canonical_account_key(_stored_username(parsed)) == requested_key
			else:
				var canonical_filename := get_save_path(username).get_file()
				matches = filename.to_lower() == canonical_filename.to_lower() or filename.to_lower() == ("%s.bak" % canonical_filename).to_lower()
			if not matches:
				continue
			if is_backup:
				backup_paths.append(path)
			else:
				primary_paths.append(path)
	if FileAccess.file_exists(canonical_path) and not _path_list_contains(primary_paths, canonical_path):
		primary_paths.append(canonical_path)
	if FileAccess.file_exists("%s.bak" % canonical_path) and not _path_list_contains(backup_paths, "%s.bak" % canonical_path):
		backup_paths.append("%s.bak" % canonical_path)
	if FileAccess.file_exists("%s.old" % canonical_path):
		recovery_paths.append("%s.old" % canonical_path)
	if primary_paths.size() > 1 or backup_paths.size() > 1:
		return {"error": "Conflicting case variants exist for this local account; refusing to merge them."}
	return {
		"primary_paths": primary_paths,
		"recovery_paths": recovery_paths,
		"backup_paths": backup_paths,
		"has_orphan_transaction": FileAccess.file_exists("%s.tmp" % canonical_path) or FileAccess.file_exists("%s.old" % canonical_path),
	}


func _stored_username(state_value: Dictionary) -> String:
	var account = state_value.get("account", {})
	if account is Dictionary:
		return str(account.get("username", state_value.get("username", ""))).strip_edges()
	return str(state_value.get("username", "")).strip_edges()


func _path_list_contains(paths: Array, candidate: String) -> bool:
	var candidate_global := ProjectSettings.globalize_path(candidate)
	for path_value in paths:
		var existing_global := ProjectSettings.globalize_path(str(path_value))
		if existing_global == candidate_global:
			return true
		if OS.get_name() == "Windows" and existing_global.to_lower() == candidate_global.to_lower():
			return true
	return false


func _promote_temporary_save(temporary_path: String, save_path: String, username: String) -> bool:
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path))
	if error != OK:
		return _fail("Could not promote the validated temporary save: %s" % error)
	var promoted := _read_state_file(save_path, username)
	if not bool(promoted.get("valid", false)):
		var failed_path := "%s.failed.%d" % [save_path, Time.get_ticks_msec()]
		DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(failed_path))
		return _fail("Promoted save did not validate: %s" % str(promoted.get("error", "invalid save")))
	return true


func _rotate_validated_backup(old_path: String, backup_path: String, username: String) -> void:
	var old_result := _read_state_file(old_path, username)
	if not bool(old_result.get("valid", false)):
		push_warning("Validated primary staging file became unreadable; leaving it at %s" % old_path)
		return
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(old_path), ProjectSettings.globalize_path(backup_path))
	if error != OK:
		var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(old_path), ProjectSettings.globalize_path(backup_path))
		if copy_error == OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
		else:
			push_warning("Could not rotate validated save backup: %s (copy fallback: %s)" % [error, copy_error])


func _preserve_loaded_source_as_backup(username: String) -> bool:
	if _last_loaded_path.is_empty() or not FileAccess.file_exists(_last_loaded_path):
		return _fail("The validated migration source disappeared before it could be preserved.")
	var canonical_path := get_save_path(username)
	if _last_loaded_path == canonical_path or _last_loaded_path == "%s.bak" % canonical_path:
		return true
	var backup_path := "%s.bak" % canonical_path
	if FileAccess.file_exists(backup_path):
		return true
	var error := DirAccess.copy_absolute(ProjectSettings.globalize_path(_last_loaded_path), ProjectSettings.globalize_path(backup_path))
	if error != OK:
		return _fail("Could not preserve the validated v1 save before migration: %s" % error)
	return true


func _highest_ground_drop_sequence(ground_items: Array) -> int:
	var highest := 0
	for item in ground_items:
		if not (item is Dictionary):
			continue
		var object_id := str(item.get("object_id", ""))
		if object_id.begins_with("ground_item_"):
			highest = max(highest, int(object_id.trim_prefix("ground_item_")))
	return highest


func _parse_json(raw_json: String) -> Dictionary:
	var parser := JSON.new()
	var error := parser.parse(raw_json)
	if error != OK:
		return {"value": null, "error": "invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	if not (parser.data is Dictionary):
		return {"value": parser.data, "error": "JSON root is not an object"}
	return {"value": parser.data, "error": ""}


func _fail(message: String) -> bool:
	last_error = message
	push_warning(message)
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
