extends RefCounted

const SNAPSHOT_SCHEMA := "hearthvale_state_snapshot_v1"


static func capture(state: Dictionary, label: String = "", metadata: Dictionary = {}) -> Dictionary:
	return {
		"schema": SNAPSHOT_SCHEMA,
		"created_at": Time.get_datetime_string_from_system(true),
		"label": label,
		"metadata": _json_safe(metadata),
		"summary": summarize_state(state),
		"state": _json_safe(state),
	}


static func restore_into(target_state: Dictionary, snapshot_or_state: Dictionary) -> Dictionary:
	var source_state = snapshot_or_state.get("state", snapshot_or_state)
	if not (source_state is Dictionary):
		return _result(false, "Snapshot does not contain a state dictionary.")
	target_state.clear()
	var clean_state: Dictionary = _json_safe(source_state)
	for key in clean_state.keys():
		target_state[str(key)] = clean_state[key]
	return _result(true, "State restored from snapshot.")


static func export_to_file(path: String, snapshot: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty():
		return _result(false, "Snapshot export path is empty.")
	var directory := path.get_base_dir()
	if not directory.is_empty():
		var make_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		if make_error != OK:
			return _result(false, "Could not create snapshot directory: %s" % str(make_error))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _result(false, "Could not open snapshot export path: %s" % path)
	file.store_string(JSON.stringify(_json_safe(snapshot), "\t", true))
	file.close()
	var result := _result(true, "Snapshot exported.")
	result["path"] = path
	return result


static func import_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _result(false, "Snapshot file does not exist: %s" % path)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return _result(false, "Snapshot file did not contain a JSON object.")
	if str(parsed.get("schema", "")) != SNAPSHOT_SCHEMA:
		return _result(false, "Snapshot schema mismatch: %s" % str(parsed.get("schema", "")))
	if not (parsed.get("state", null) is Dictionary):
		return _result(false, "Snapshot file is missing state.")
	var result := _result(true, "Snapshot imported.")
	result["snapshot"] = parsed
	return result


static func summarize_state(state: Dictionary) -> Dictionary:
	return {
		"username": str(state.get("username", "")),
		"player_tile": _player_tile_summary(state),
		"inventory": _stack_summary(state.get("inventory", {})),
		"bank": _stack_summary(state.get("bank", {})),
		"skills": _skills_summary(state.get("skills", {})),
		"quests": _quests_summary(state),
		"combat": _combat_summary(state.get("combat", {})),
		"world": _world_summary(state.get("world", {})),
	}


static func _stack_summary(raw_value) -> Dictionary:
	var total_quantity := 0
	var unique_items := 0
	if raw_value is Dictionary:
		for item_id in raw_value.keys():
			var quantity := int(raw_value[item_id])
			if quantity <= 0:
				continue
			unique_items += 1
			total_quantity += quantity
	return {"unique_items": unique_items, "total_quantity": total_quantity}


static func _skills_summary(raw_value) -> Dictionary:
	var total_xp := 0
	var highest_level := 0
	var highest_skill := ""
	if raw_value is Dictionary:
		for skill_id in raw_value.keys():
			var values = raw_value[skill_id]
			if not (values is Dictionary):
				continue
			total_xp += int(values.get("xp", 0))
			var level := int(values.get("level", 0))
			if level > highest_level:
				highest_level = level
				highest_skill = str(skill_id)
	return {"total_xp": total_xp, "highest_level": highest_level, "highest_skill": highest_skill}


static func _quests_summary(state: Dictionary) -> Dictionary:
	var started := 0
	var completed := 0
	var quest_root = state.get("quest_state", {})
	var quest_states = {}
	if quest_root is Dictionary:
		quest_states = quest_root.get("quests", {})
	if not (quest_states is Dictionary) or quest_states.is_empty():
		quest_states = state.get("quest_progress", {})
	if quest_states is Dictionary:
		for quest_id in quest_states.keys():
			var quest_state = quest_states[quest_id]
			if not (quest_state is Dictionary):
				continue
			if bool(quest_state.get("started", false)):
				started += 1
			if bool(quest_state.get("completed", false)):
				completed += 1
	return {"started": started, "completed": completed}


static func _combat_summary(raw_value) -> Dictionary:
	if not (raw_value is Dictionary):
		return {"current_hitpoints": 0, "alive_mobs": 0, "ground_items": 0, "status_effects": 0}
	var alive_mobs := 0
	var mobs = raw_value.get("mobs", {})
	if mobs is Dictionary:
		for mob_id in mobs.keys():
			var mob_state = mobs[mob_id]
			if mob_state is Dictionary and not bool(mob_state.get("dead", false)):
				alive_mobs += 1
	var ground_items = raw_value.get("ground_items", [])
	var status_effects = raw_value.get("status_effects", {})
	return {
		"current_hitpoints": int(raw_value.get("current_hitpoints", 0)),
		"alive_mobs": alive_mobs,
		"ground_items": ground_items.size() if ground_items is Array else 0,
		"status_effects": status_effects.size() if status_effects is Dictionary else 0,
	}


static func _world_summary(raw_value) -> Dictionary:
	if not (raw_value is Dictionary):
		return {"depleted_resources": 0, "action_clock_seconds": 0.0, "weather": ""}
	var resource_nodes = raw_value.get("resource_nodes", {})
	var depleted := 0
	if resource_nodes is Dictionary:
		for node_id in resource_nodes.keys():
			var node_state = resource_nodes[node_id]
			if node_state is Dictionary and bool(node_state.get("depleted", false)):
				depleted += 1
	return {
		"depleted_resources": depleted,
		"action_clock_seconds": float(raw_value.get("action_clock_seconds", 0.0)),
		"weather": str(raw_value.get("weather", "")),
	}


static func _player_tile_summary(state: Dictionary) -> Array:
	var player = state.get("player", {})
	if player is Dictionary:
		var tile = player.get("tile", [])
		if tile is Array and tile.size() >= 2:
			return [int(tile[0]), int(tile[1])]
		if tile is Vector2i:
			return [tile.x, tile.y]
		if tile is Vector2:
			return [int(tile.x), int(tile.y)]
	return []


static func _json_safe(value):
	if value is Dictionary:
		var clean := {}
		for key in value.keys():
			clean[str(key)] = _json_safe(value[key])
		return clean
	if value is Array:
		var clean_array := []
		for item in value:
			clean_array.append(_json_safe(item))
		return clean_array
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Vector3:
		return [value.x, value.y, value.z]
	return value


static func _result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message}
