extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(5.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale debug overlay smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	var state: Dictionary = store.create_default_state("codex_debug_overlay_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	var overlay = preload("res://scripts/debug_overlay.gd").new()
	root.add_child(world)
	root.add_child(overlay)
	await process_frame

	world.initialize_from_state(state)
	overlay.setup(state, world)
	overlay.show_overlay()
	overlay.refresh_now()
	await process_frame

	var data: Dictionary = world.debug_overlay_data()
	var summary := overlay.summary_text_for_smoke()
	var passed := true
	passed = passed and overlay.overlay_visible_for_smoke()
	passed = passed and overlay.map_has_data_for_smoke()
	passed = passed and int(data.get("width", 0)) > 0
	passed = passed and int(data.get("height", 0)) > 0
	passed = passed and data.get("objects", []) is Array and not data.get("objects", []).is_empty()
	passed = passed and data.get("blocked_tiles", []) is Array and not data.get("blocked_tiles", []).is_empty()
	passed = passed and summary.find("F9 overlay") != -1
	passed = passed and summary.find("player") != -1
	passed = passed and summary.find("objects") != -1

	store.free()
	if passed:
		print("Hearthvale debug overlay smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale debug overlay smoke failed.")
		quit(1)
