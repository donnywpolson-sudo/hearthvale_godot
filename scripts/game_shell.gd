extends Node

const START_SCENE := preload("res://scenes/start.tscn")
const WORLD_SCENE := preload("res://scenes/world.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const GAMEPLAY_CORE := preload("res://scripts/gameplay_core.gd")
const DEBUG_COMMAND_CONSOLE := preload("res://scripts/debug_command_console.gd")
const DEBUG_OVERLAY := preload("res://scripts/debug_overlay.gd")
const STATE_STORE_SCRIPT := preload("res://autoload/state_store.gd")

var start_screen: Control
var world: Node
var hud: CanvasLayer
var gameplay: Node
var debug_console: CanvasLayer
var debug_overlay: CanvasLayer
var state_store: Node
var username := "local_player"


func _ready() -> void:
	_resolve_state_store()
	_show_start_screen()


func _resolve_state_store() -> void:
	state_store = get_node_or_null("/root/StateStore")
	if state_store == null:
		state_store = STATE_STORE_SCRIPT.new()
		add_child(state_store)


func _show_start_screen() -> void:
	start_screen = START_SCENE.instantiate()
	add_child(start_screen)
	start_screen.start_requested.connect(_start_world)


func _start_world(requested_username: String) -> void:
	username = requested_username.strip_edges()
	if username.is_empty():
		username = "local_player"
	state_store.load_or_create_state(username)

	if is_instance_valid(start_screen):
		start_screen.queue_free()

	world = WORLD_SCENE.instantiate()
	hud = HUD_SCENE.instantiate()
	gameplay = GAMEPLAY_CORE.new()
	add_child(world)
	add_child(hud)
	add_child(gameplay)

	world.selection_changed.connect(hud.set_selection)
	world.hover_changed.connect(hud.set_hover_target)
	world.feedback_changed.connect(hud.set_feedback)
	world.player_tile_changed.connect(hud.set_player_tile)
	world.player_tile_changed.connect(hud.set_minimap_player_tile)
	world.camera_heading_changed.connect(hud.set_minimap_heading)
	hud.compass_reset_requested.connect(world.reset_camera_north)
	hud.configure_minimap(world.get_minimap_data())
	hud.set_account(username)
	hud.set_feedback("Logged in")
	hud.bind_state(state_store.current_state)
	gameplay.setup(state_store.current_state, world, hud)
	world.object_activated.connect(gameplay.activate_object)
	world.initialize_from_state(state_store.current_state)
	_attach_debug_overlay()
	_attach_debug_console()


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
