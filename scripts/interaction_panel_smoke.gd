extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale interaction panel smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	var state: Dictionary = store.create_default_state("codex_interaction_panel_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	var hud = preload("res://scenes/hud.tscn").instantiate()
	hud.set_script(preload("res://scripts/test_support/hud_smoke_harness.gd"))
	var gameplay = preload("res://scripts/test_support/gameplay_smoke_harness.gd").new()
	root.add_child(world)
	root.add_child(hud)
	root.add_child(gameplay)
	await process_frame
	hud.bind_state(state)
	world.initialize_from_state(state)
	gameplay.setup(state, world, hud, "manual")
	var passed: bool = hud.run_interaction_panel_smoke() and gameplay.run_interaction_panel_smoke()
	store.free()
	if passed:
		print("Hearthvale interaction panel smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale interaction panel smoke failed.")
		quit(1)
