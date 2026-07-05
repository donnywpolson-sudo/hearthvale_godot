extends Control

const TILE_PIXELS := 5.0
const PLAYER_RADIUS := 4.5
const MINIMAP_RADIUS_MARGIN := 5.0

var map_data := {}
var player_tile := Vector2i.ZERO
var heading_degrees := 0.0


func configure(data: Dictionary) -> void:
	map_data = data.duplicate(true)
	queue_redraw()


func set_player_tile(tile: Vector2i) -> void:
	player_tile = tile
	queue_redraw()


func set_heading(value: float) -> void:
	heading_degrees = fposmod(value, 360.0)
	queue_redraw()


func has_minimap_data() -> bool:
	return int(map_data.get("width", 0)) > 0 and int(map_data.get("height", 0)) > 0


func player_tile_for_smoke() -> Vector2i:
	return player_tile


func heading_for_smoke() -> float:
	return heading_degrees


func player_screen_position_for_smoke() -> Vector2:
	return size * 0.5


func _draw() -> void:
	var center := size * 0.5
	var radius: float = maxf(8.0, minf(size.x, size.y) * 0.5 - MINIMAP_RADIUS_MARGIN)
	draw_circle(center, radius + 3.0, Color(0.05, 0.06, 0.05, 0.92))
	draw_circle(center, radius, Color(0.11, 0.16, 0.13, 0.96))
	_draw_tile_list("water_tiles", Color(0.12, 0.38, 0.58, 1.0), radius, 5.5)
	_draw_tile_list("dirt_tiles", Color(0.58, 0.42, 0.22, 1.0), radius, 4.5)
	_draw_tile_list("blocked_tiles", Color(0.19, 0.19, 0.18, 1.0), radius, 4.0)
	_draw_objects(radius)
	draw_circle(center, PLAYER_RADIUS + 2.0, Color(0.02, 0.03, 0.03, 0.85))
	draw_circle(center, PLAYER_RADIUS, Color(0.35, 0.70, 1.0, 1.0))
	var north_tip := center + Vector2(0.0, -radius + 12.0).rotated(deg_to_rad(-heading_degrees))
	draw_line(center, north_tip, Color(0.94, 0.82, 0.34, 0.82), 2.0)
	draw_arc(center, radius, 0.0, TAU, 80, Color(0.68, 0.58, 0.34, 0.95), 2.0)


func _draw_tile_list(key: String, color: Color, radius: float, tile_size: float) -> void:
	var tiles = map_data.get(key, [])
	if not (tiles is Array):
		return
	for raw_tile in tiles:
		var tile := _array_to_tile(raw_tile, Vector2i(-1, -1))
		if tile == Vector2i(-1, -1):
			continue
		var point := _tile_to_screen(tile)
		if point.distance_to(size * 0.5) > radius:
			continue
		draw_rect(Rect2(point - Vector2(tile_size, tile_size) * 0.5, Vector2(tile_size, tile_size)), color)


func _draw_objects(radius: float) -> void:
	var objects = map_data.get("objects", [])
	if not (objects is Array):
		return
	for object_data in objects:
		if not (object_data is Dictionary):
			continue
		var tile := _array_to_tile(object_data.get("tile", []), Vector2i(-1, -1))
		if tile == Vector2i(-1, -1):
			continue
		var point := _tile_to_screen(tile)
		if point.distance_to(size * 0.5) > radius:
			continue
		draw_circle(point, 2.8, _object_color(str(object_data.get("type", ""))))


func _tile_to_screen(tile: Vector2i) -> Vector2:
	var relative := Vector2(float(tile.x - player_tile.x), float(tile.y - player_tile.y))
	var rotated := relative.rotated(deg_to_rad(-heading_degrees))
	return size * 0.5 + rotated * TILE_PIXELS


func _object_color(object_type: String) -> Color:
	match object_type:
		"resource":
			return Color(0.38, 0.76, 0.34, 1.0)
		"npc":
			return Color(0.95, 0.76, 0.34, 1.0)
		"mob":
			return Color(0.88, 0.30, 0.25, 1.0)
		"station":
			return Color(0.66, 0.64, 0.86, 1.0)
		"ground_item":
			return Color(0.96, 0.86, 0.36, 1.0)
		_:
			return Color(0.82, 0.82, 0.76, 1.0)


func _array_to_tile(value, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback
