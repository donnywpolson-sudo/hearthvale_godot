extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale golden scenarios smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "res://.godot_smoke_saves"
	var username := "codex_golden_scenarios_smoke"
	var state: Dictionary = store.create_default_state(username)
	var world = preload("res://scenes/world.tscn").instantiate()
	var hud = preload("res://scenes/hud.tscn").instantiate()
	var gameplay = preload("res://scripts/gameplay_core.gd").new()
	root.add_child(world)
	root.add_child(hud)
	root.add_child(gameplay)
	await process_frame
	hud.bind_state(state)
	world.initialize_from_state(state)
	gameplay.setup(state, world, hud)
	var passed: bool = gameplay.run_golden_scenarios_smoke()
	passed = passed and _assert_save_round_trip(store, username, state)
	store.free()
	if passed:
		print("Hearthvale golden scenarios smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale golden scenarios smoke failed.")
		quit(1)


func _assert_save_round_trip(store: Node, username: String, state: Dictionary) -> bool:
	var expected := state.duplicate(true)
	if not store.save_state(username, state):
		push_error("Golden scenarios smoke save round-trip failed: save_state returned false")
		return false
	var loaded: Dictionary = store.load_state(username)
	if loaded.is_empty():
		push_error("Golden scenarios smoke save round-trip failed: load_state returned empty")
		return false
	for key in ["inventory", "bank", "equipment", "skills", "combat", "world", "quest_state", "quest_progress"]:
		if _normalize_for_compare(loaded.get(key, {})) != _normalize_for_compare(expected.get(key, {})):
			push_error("Golden scenarios smoke save round-trip failed: %s mismatch" % key)
			return false
	if str(loaded.get("username", "")) != username:
		push_error("Golden scenarios smoke save round-trip failed: username mismatch")
		return false
	return true


func _normalize_for_compare(value):
	if value is Dictionary:
		var clean := {}
		for key in value.keys():
			clean[str(key)] = _normalize_for_compare(value[key])
		return clean
	if value is Array:
		var clean_array := []
		for item in value:
			clean_array.append(_normalize_for_compare(item))
		return clean_array
	if value is float and is_equal_approx(value, round(value)):
		return int(round(value))
	return value
