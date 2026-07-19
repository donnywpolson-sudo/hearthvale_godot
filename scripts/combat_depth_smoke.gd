extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale combat depth smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "res://.godot_smoke_saves"
	var username := "codex_combat_depth_smoke"
	var state: Dictionary = store.create_default_state(username)
	var world = preload("res://scenes/world.tscn").instantiate()
	var hud = preload("res://scenes/hud.tscn").instantiate()
	var gameplay = preload("res://scripts/test_support/gameplay_smoke_harness.gd").new()
	root.add_child(world)
	root.add_child(hud)
	root.add_child(gameplay)
	await process_frame
	hud.bind_state(state)
	world.initialize_from_state(state)
	gameplay.setup(state, world, hud, "manual")
	var passed: bool = gameplay.run_combat_depth_smoke()
	passed = passed and _assert_combat_status_round_trip(store, username, state)
	store.free()
	if passed:
		print("Hearthvale combat depth smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale combat depth smoke failed.")
		quit(1)


func _assert_combat_status_round_trip(store: Node, username: String, state: Dictionary) -> bool:
	state["combat"]["status_effects"] = {"poison": {"damage": 2, "rounds_remaining": 3}}
	if not store.save_state(username, state):
		push_error("Combat depth smoke failed: save_state returned false")
		return false
	var loaded: Dictionary = store.load_state(username)
	var loaded_combat = loaded.get("combat", {})
	if not (loaded_combat is Dictionary):
		push_error("Combat depth smoke failed: combat missing after load")
		return false
	return _normalize_for_compare(loaded_combat.get("status_effects", {})) == _normalize_for_compare(state["combat"]["status_effects"])


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
