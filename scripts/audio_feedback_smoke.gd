extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale audio feedback smoke timed out.")
		quit(1)
	)
	var hud = preload("res://scenes/hud.tscn").instantiate()
	hud.set_script(preload("res://scripts/test_support/hud_smoke_harness.gd"))
	root.add_child(hud)
	await process_frame
	var store = preload("res://autoload/state_store.gd").new()
	hud.bind_state(store.create_default_state("codex_audio_smoke"))
	var passed := bool(hud.run_audio_feedback_smoke())
	store.free()
	if passed:
		print("Hearthvale audio feedback smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale audio feedback smoke failed.")
		quit(1)
