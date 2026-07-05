extends Control

signal start_requested(username: String)

@onready var name_edit: LineEdit = $Panel/Margin/Stack/NameEdit
@onready var start_button: Button = $Panel/Margin/Stack/StartButton

var _time := 0.0


func _ready() -> void:
	start_button.pressed.connect(_request_start)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.grab_focus()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return

	_draw_sky()
	_draw_moon()
	_draw_fireflies()
	_draw_horizon()
	_draw_path()


func _request_start() -> void:
	start_requested.emit(name_edit.text)


func _on_name_submitted(_text: String) -> void:
	_request_start()


func _draw_sky() -> void:
	var bands := 30
	var top := Color(0.015, 0.026, 0.03, 1.0)
	var middle := Color(0.045, 0.095, 0.08, 1.0)
	var bottom := Color(0.09, 0.12, 0.08, 1.0)
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var color: Color = top.lerp(middle, min(t * 1.35, 1.0))
		if t > 0.55:
			color = middle.lerp(bottom, (t - 0.55) / 0.45)
		draw_rect(Rect2(0.0, size.y * t, size.x, size.y / float(bands) + 1.0), color)

	_draw_glow(Vector2(size.x * 0.24, size.y * 0.25), size.x * 0.28, Color(0.12, 0.29, 0.22, 0.16), 9)
	_draw_glow(Vector2(size.x * 0.73, size.y * 0.16), size.x * 0.22, Color(0.95, 0.67, 0.31, 0.10), 8)


func _draw_moon() -> void:
	var center := Vector2(size.x * 0.73, size.y * 0.18)
	var radius: float = clamp(size.y * 0.055, 22.0, 46.0)
	_draw_glow(center, radius * 3.2, Color(0.95, 0.74, 0.41, 0.08), 6)
	draw_circle(center, radius, Color(0.94, 0.80, 0.52, 0.92))
	draw_circle(center + Vector2(radius * 0.28, -radius * 0.12), radius * 0.82, Color(0.046, 0.078, 0.064, 0.95))


func _draw_fireflies() -> void:
	for i in range(36):
		var seed := float(i)
		var x := fmod(73.0 * seed + 41.0, max(size.x, 1.0))
		var y := fmod(47.0 * seed + 29.0, max(size.y * 0.68, 1.0)) + size.y * 0.08
		var drift := Vector2(sin(_time * 0.55 + seed) * 8.0, cos(_time * 0.38 + seed * 1.7) * 5.0)
		var pulse := 0.45 + sin(_time * 1.8 + seed * 2.3) * 0.25
		draw_circle(Vector2(x, y) + drift, 1.5 + pulse, Color(0.96, 0.72, 0.28, 0.18 + pulse * 0.28))


func _draw_horizon() -> void:
	var ridge_y := size.y * 0.66
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, ridge_y),
		Vector2(size.x * 0.12, ridge_y - size.y * 0.08),
		Vector2(size.x * 0.23, ridge_y - size.y * 0.03),
		Vector2(size.x * 0.36, ridge_y - size.y * 0.12),
		Vector2(size.x * 0.48, ridge_y - size.y * 0.04),
		Vector2(size.x * 0.64, ridge_y - size.y * 0.15),
		Vector2(size.x * 0.82, ridge_y - size.y * 0.05),
		Vector2(size.x, ridge_y - size.y * 0.1),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y),
	]), Color(0.018, 0.045, 0.036, 1.0))

	var tree_base := size.y * 0.71
	for i in range(25):
		var x := size.x * float(i) / 24.0
		var height := size.y * (0.10 + fmod(float(i * 7), 9.0) * 0.008)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - 32.0, tree_base),
			Vector2(x, tree_base - height),
			Vector2(x + 32.0, tree_base),
		]), Color(0.011, 0.03, 0.025, 1.0))
	draw_rect(Rect2(0.0, tree_base, size.x, size.y - tree_base), Color(0.012, 0.028, 0.022, 1.0))


func _draw_path() -> void:
	var bottom := size.y
	var center_x := size.x * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(center_x - size.x * 0.05, size.y * 0.71),
		Vector2(center_x + size.x * 0.05, size.y * 0.71),
		Vector2(center_x + size.x * 0.18, bottom),
		Vector2(center_x - size.x * 0.18, bottom),
	]), Color(0.205, 0.155, 0.085, 0.8))
	draw_line(Vector2(center_x - size.x * 0.05, size.y * 0.72), Vector2(center_x - size.x * 0.17, bottom), Color(0.64, 0.42, 0.18, 0.28), 2.0)
	draw_line(Vector2(center_x + size.x * 0.05, size.y * 0.72), Vector2(center_x + size.x * 0.17, bottom), Color(0.64, 0.42, 0.18, 0.28), 2.0)
	draw_rect(Rect2(0.0, 0.0, size.x, size.y), Color(0.0, 0.0, 0.0, 0.16), false, 28.0)


func _draw_glow(center: Vector2, radius: float, color: Color, steps: int) -> void:
	for i in range(steps, 0, -1):
		var t := float(i) / float(steps)
		var glow_color := color
		glow_color.a *= (1.0 - t) * 0.7
		draw_circle(center, radius * t, glow_color)
