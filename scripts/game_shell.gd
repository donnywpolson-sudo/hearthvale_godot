extends Node

const START_SCENE := preload("res://scenes/start.tscn")
const WORLD_SCENE := preload("res://scenes/world.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const GAMEPLAY_CORE := preload("res://scripts/gameplay_core.gd")
const DEBUG_COMMAND_CONSOLE := preload("res://scripts/debug_command_console.gd")
const DEBUG_OVERLAY := preload("res://scripts/debug_overlay.gd")
const STATE_STORE_SCRIPT := preload("res://autoload/state_store.gd")
const AUTOSAVE_DELAY_SECONDS := 1.0

var start_screen: Control
var world: Node
var hud: CanvasLayer
var gameplay: Node
var debug_console: CanvasLayer
var debug_overlay: CanvasLayer
var state_store: Node
var username := "local_player"
var autosave_timer: Timer
var save_dirty := false


func _ready() -> void:
	_resolve_state_store()
	_configure_autosave()
	_show_start_screen()


func _exit_tree() -> void:
	_flush_pending_save(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_pending_save(false)


func _resolve_state_store() -> void:
	state_store = get_node_or_null("/root/StateStore")
	if state_store == null:
		state_store = STATE_STORE_SCRIPT.new()
		add_child(state_store)


func _configure_autosave() -> void:
	autosave_timer = Timer.new()
	autosave_timer.name = "AutosaveTimer"
	autosave_timer.one_shot = true
	autosave_timer.wait_time = AUTOSAVE_DELAY_SECONDS
	autosave_timer.timeout.connect(_flush_pending_save)
	add_child(autosave_timer)


func _show_start_screen() -> void:
	start_screen = START_SCENE.instantiate()
	add_child(start_screen)
	start_screen.start_requested.connect(_start_world)


func _start_world(requested_username: String) -> void:
	username = requested_username.strip_edges()
	if username.is_empty():
		username = "local_player"
	var loaded_state: Dictionary = state_store.load_or_create_state(username)
	if loaded_state.is_empty():
		var message := str(state_store.last_error).strip_edges()
		if message.is_empty():
			message = "The account could not be loaded safely."
		if is_instance_valid(start_screen) and start_screen.has_method("show_error"):
			start_screen.show_error(message)
		return

	if is_instance_valid(start_screen):
		start_screen.queue_free()

	world = WORLD_SCENE.instantiate()
	hud = HUD_SCENE.instantiate()
	gameplay = GAMEPLAY_CORE.new()
	add_child(world)
	add_child(hud)
	add_child(gameplay)
	_connect_persistence_signals()

	world.selection_changed.connect(hud.set_selection)
	world.hover_changed.connect(hud.set_hover_target)
	world.feedback_changed.connect(hud.set_feedback)
	world.player_tile_changed.connect(hud.set_player_tile)
	world.player_tile_changed.connect(hud.set_minimap_player_tile)
	world.camera_heading_changed.connect(hud.set_minimap_heading)
	hud.compass_reset_requested.connect(world.reset_camera_north)
	hud.configure_minimap(world.get_minimap_data())
	var account = state_store.current_state.get("account", {})
	var display_username := str(account.get("username", username)) if account is Dictionary else username
	hud.set_account(display_username)
	hud.set_feedback("Logged in")
	hud.bind_state(state_store.current_state)
	gameplay.setup(state_store.current_state, world, hud)
	world.object_activated.connect(gameplay.activate_object)
	world.initialize_from_state(state_store.current_state)
	_attach_debug_overlay()
	_attach_debug_console()


func _connect_persistence_signals() -> void:
	for source in [world, gameplay]:
		if source != null and source.has_signal("persistent_state_changed"):
			source.connect("persistent_state_changed", _mark_save_dirty)


func _mark_save_dirty() -> void:
	if state_store == null or state_store.current_state.is_empty():
		return
	save_dirty = true
	autosave_timer.start(AUTOSAVE_DELAY_SECONDS)


func _flush_pending_save(show_feedback: bool = true) -> bool:
	if not save_dirty or state_store == null or state_store.current_state.is_empty():
		return true
	if state_store.save_state(username, state_store.current_state):
		save_dirty = false
		if show_feedback and is_instance_valid(hud):
			hud.set_feedback("Progress saved")
		return true
	if show_feedback and is_instance_valid(hud):
		hud.set_feedback("Save failed: %s" % str(state_store.last_error))
	return false


func _attach_debug_overlay() -> void:
	if OS.has_feature("release"):
		return
	debug_overlay = DEBUG_OVERLAY.new()
	add_child(debug_overlay)
	debug_overlay.setup(state_store.current_state, world)


func _attach_debug_console() -> void:
	if OS.has_feature("release"):
		return
	debug_console = DEBUG_COMMAND_CONSOLE.new()
	add_child(debug_console)
	debug_console.setup(state_store.current_state, world, hud, gameplay)
