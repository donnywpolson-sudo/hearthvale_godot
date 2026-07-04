extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = preload("res://autoload/state_store.gd").new()
	var state: Dictionary = store.create_default_state("codex_economy_quest_smoke")
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
	var passed: bool = gameplay.run_economy_quest_smoke()
	store.free()
	if passed:
		print("Hearthvale economy and quest smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale economy and quest smoke failed.")
		quit(1)
