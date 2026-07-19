extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(5.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale camera minimap smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	store.current_state = store.create_default_state("codex_camera_minimap_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	world.set_script(preload("res://scripts/test_support/world_smoke_harness.gd"))
	var hud = preload("res://scenes/hud.tscn").instantiate()
	root.add_child(world)
	root.add_child(hud)
	await process_frame

	world.player_tile_changed.connect(hud.set_minimap_player_tile)
	world.camera_heading_changed.connect(hud.set_minimap_heading)
	hud.compass_reset_requested.connect(world.reset_camera_north)
	hud.configure_minimap(world.get_minimap_data())
	world.initialize_from_state(store.current_state)

	var passed: bool = world.run_camera_minimap_smoke()
	var expected_tile := _state_player_tile(store.current_state)
	if hud.minimap_player_tile_for_smoke() != expected_tile:
		passed = false
	if not hud.minimap_has_data_for_smoke() or not hud.minimap_player_is_centered_for_smoke():
		passed = false

	world.call("_set_camera_heading_degrees", 83.0)
	hud.emit_compass_reset_for_smoke()
	await process_frame
	if absf(world.camera_heading_for_smoke()) > 0.1:
		passed = false
	if absf(hud.minimap_heading_for_smoke()) > 0.1:
		passed = false

	store.free()
	if passed:
		print("Hearthvale camera minimap smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale camera minimap smoke failed.")
		quit(1)


func _state_player_tile(state: Dictionary) -> Vector2i:
	var player_state = state.get("player", {})
	if player_state is Dictionary:
		var tile = player_state.get("tile", [0, 0])
		if tile is Array and tile.size() >= 2:
			return Vector2i(int(tile[0]), int(tile[1]))
	return Vector2i.ZERO
