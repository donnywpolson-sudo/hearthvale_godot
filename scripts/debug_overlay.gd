extends CanvasLayer

const MAP_SIZE := Vector2(220.0, 160.0)

var state := {}
var world: Node
var panel: PanelContainer
var summary_label: Label
var map_view: Control
var latest_data := {}


func _ready() -> void:
	layer = 45
	_build_ui()
	hide_overlay()


func setup(initial_state: Dictionary, world_node: Node) -> void:
	state = initial_state
	world = world_node
	refresh_now()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		toggle_overlay()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if panel != null and panel.visible:
		refresh_now()


func toggle_overlay() -> void:
	if panel == null:
		return
	panel.visible = not panel.visible
	if panel.visible:
		refresh_now()


func show_overlay() -> void:
	if panel != null:
		panel.visible = true
	refresh_now()


func hide_overlay() -> void:
	if panel != null:
		panel.visible = false


func refresh_now() -> void:
	latest_data = _read_world_data()
	if summary_label != null:
		summary_label.text = _summary_text(latest_data)
	if map_view != null:
		map_view.queue_redraw()


func overlay_visible_for_smoke() -> bool:
	return panel != null and panel.visible


func summary_text_for_smoke() -> String:
	return summary_label.text if summary_label != null else ""


func map_has_data_for_smoke() -> bool:
	return not latest_data.is_empty() and int(latest_data.get("width", 0)) > 0 and int(latest_data.get("height", 0)) > 0


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "DebugOverlay"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -272.0
	panel.offset_top = 56.0
	panel.offset_right = -12.0
	panel.offset_bottom = 300.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "Debug Overlay"
	stack.add_child(title)

	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(summary_label)

	map_view = Control.new()
	map_view.custom_minimum_size = MAP_SIZE
	map_view.draw.connect(_draw_map)
	stack.add_child(map_view)


func _summary_text(data: Dictionary) -> String:
	var player_tile := _tile_array(data.get("player_tile", [0, 0]))
	var destination_tile := _tile_array(data.get("destination_tile", [0, 0]))
	var combat := _combat_state()
	var quest_counts := _quest_counts()
	var status_count := _status_count(combat.get("status_effects", {}))
	var objects = data.get("objects", [])
	var path_tiles = data.get("path_tiles", [])
	return "F9 overlay | player %d,%d | dest %d,%d | objects %d | blocked %d | path %d | hp %d | statuses %d | quests %d/%d | heading %.0f" % [
		player_tile.x,
		player_tile.y,
		destination_tile.x,
		destination_tile.y,
		objects.size() if objects is Array else 0,
		data.get("blocked_tiles", []).size() if data.get("blocked_tiles", []) is Array else 0,
		path_tiles.size() if path_tiles is Array else 0,
		int(combat.get("current_hitpoints", 0)),
		status_count,
		int(quest_counts.get("completed", 0)),
		int(quest_counts.get("started", 0)),
		float(data.get("camera_heading", 0.0)),
	]


func _draw_map() -> void:
	if map_view == null or latest_data.is_empty():
		return
	var width: int = max(1, int(latest_data.get("width", 1)))
	var height: int = max(1, int(latest_data.get("height", 1)))
	var tile_size: float = min(map_view.size.x / float(width), map_view.size.y / float(height))
	var origin := Vector2(
		(map_view.size.x - float(width) * tile_size) * 0.5,
		(map_view.size.y - float(height) * tile_size) * 0.5
	)
	map_view.draw_rect(Rect2(origin, Vector2(width, height) * tile_size), Color(0.06, 0.08, 0.07, 0.86), true)
	_draw_tile_list("dirt_tiles", origin, tile_size, Color(0.48, 0.34, 0.16, 0.70))
	_draw_tile_list("water_tiles", origin, tile_size, Color(0.10, 0.32, 0.58, 0.82))
	_draw_tile_list("blocked_tiles", origin, tile_size, Color(0.90, 0.18, 0.12, 0.72))
	_draw_path(origin, tile_size)
	_draw_objects(origin, tile_size)
	_draw_tile(_tile_array(latest_data.get("destination_tile", [0, 0])), origin, tile_size, Color(0.95, 0.78, 0.22, 0.90))
	_draw_tile(_tile_array(latest_data.get("player_tile", [0, 0])), origin, tile_size, Color(0.20, 0.95, 0.95, 1.0))


func _draw_tile_list(key: String, origin: Vector2, tile_size: float, color: Color) -> void:
	var tiles = latest_data.get(key, [])
	if not (tiles is Array):
		return
	for value in tiles:
		_draw_tile(_tile_array(value), origin, tile_size, color)


func _draw_path(origin: Vector2, tile_size: float) -> void:
	var path_tiles = latest_data.get("path_tiles", [])
	if not (path_tiles is Array):
		return
	for value in path_tiles:
		_draw_tile(_tile_array(value), origin, tile_size, Color(0.92, 0.86, 0.20, 0.70))


func _draw_objects(origin: Vector2, tile_size: float) -> void:
	var objects = latest_data.get("objects", [])
	if not (objects is Array):
		return
	for object_data in objects:
		if not (object_data is Dictionary):
			continue
		var color := Color(0.90, 0.90, 0.90, 0.85)
		match str(object_data.get("type", "")):
			"resource":
				color = Color(0.18, 0.80, 0.28, 0.85)
			"mob":
				color = Color(0.92, 0.16, 0.20, 0.90)
			"npc":
				color = Color(0.95, 0.66, 0.22, 0.90)
			"station":
				color = Color(0.38, 0.52, 0.95, 0.90)
			"ground_item":
				color = Color(0.96, 0.88, 0.30, 0.90)
		_draw_tile(_tile_array(object_data.get("tile", [0, 0])), origin, tile_size, color)


func _draw_tile(tile: Vector2i, origin: Vector2, tile_size: float, color: Color) -> void:
	var rect := Rect2(origin + Vector2(tile.x * tile_size, tile.y * tile_size), Vector2(max(1.0, tile_size - 1.0), max(1.0, tile_size - 1.0)))
	map_view.draw_rect(rect, color, true)


func _read_world_data() -> Dictionary:
	if world != null and world.has_method("debug_overlay_data"):
		var data = world.call("debug_overlay_data")
		if data is Dictionary:
			return data
	return {}


func _combat_state() -> Dictionary:
	var combat = state.get("combat", {})
	if combat is Dictionary:
		return combat
	return {}


func _quest_counts() -> Dictionary:
	var counts := {
		"started": 0,
		"completed": 0,
	}
	var quest_root = state.get("quest_state", {})
	if quest_root is Dictionary:
		var quests = quest_root.get("quests", {})
		if quests is Dictionary:
			for quest_state in quests.values():
				if quest_state is Dictionary:
					if bool(quest_state.get("started", false)):
						counts["started"] = int(counts["started"]) + 1
					if bool(quest_state.get("completed", false)):
						counts["completed"] = int(counts["completed"]) + 1
	return counts


func _status_count(status_effects) -> int:
	if status_effects is Dictionary:
		return status_effects.size()
	if status_effects is Array:
		return status_effects.size()
	return 0


func _tile_array(value) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Vector2i:
		return value
	return Vector2i.ZERO
