extends Button

const DEFAULT_ACCENT := Color(0.78, 0.72, 0.46, 1.0)
const PANEL_BACKGROUND := Color(0.07, 0.085, 0.06, 0.97)
const TITLE_COLOR := Color(0.96, 0.93, 0.82, 1.0)
const TEXT_COLOR := Color(0.86, 0.88, 0.80, 1.0)
const MUTED_COLOR := Color(0.62, 0.66, 0.57, 1.0)
const SECTION_COLOR := Color(0.78, 0.82, 0.64, 1.0)
const VALUE_COLOR := Color(0.91, 0.92, 0.84, 1.0)
const BONUS_COLOR := Color(0.72, 0.88, 0.62, 1.0)
const SECTION_HEADINGS := ["Details", "Bonuses", "Effects", "Requirements"]


func _make_custom_tooltip(for_text: String) -> Object:
	var accent := _tooltip_accent()
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 0)
	card.add_theme_stylebox_override("panel", _tooltip_panel_style(accent))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)

	var lines := for_text.split("\n", true)
	if lines.is_empty():
		return card

	var title := lines[0].strip_edges()
	if not title.is_empty():
		var title_label := Label.new()
		title_label.text = title
		title_label.modulate = TITLE_COLOR
		title_label.add_theme_font_size_override("font_size", 14)
		stack.add_child(title_label)
		_add_separator(stack, accent)

	var has_content := false
	for index in range(1, lines.size()):
		var line := lines[index].strip_edges()
		if line.is_empty():
			if has_content:
				_add_spacer(stack, 2)
			continue
		if _is_section_heading(line):
			if has_content:
				_add_spacer(stack, 2)
			_add_section_label(stack, line)
			has_content = true
			continue
		_add_detail_line(stack, line)
		has_content = true

	return card


func _tooltip_accent() -> Color:
	var value = get_meta("tooltip_accent", DEFAULT_ACCENT)
	if value is Color:
		return value
	return DEFAULT_ACCENT


func _tooltip_panel_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BACKGROUND
	style.border_color = Color(accent.r, accent.g, accent.b, 0.88)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	return style


func _add_separator(parent: VBoxContainer, accent: Color) -> void:
	var separator := ColorRect.new()
	separator.custom_minimum_size = Vector2(0, 1)
	separator.color = Color(accent.r, accent.g, accent.b, 0.55)
	parent.add_child(separator)


func _add_spacer(parent: VBoxContainer, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = SECTION_COLOR
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)


func _add_detail_line(parent: VBoxContainer, text: String) -> void:
	var separator_index := text.find(":")
	if separator_index > 0:
		_add_key_value_line(parent, text.substr(0, separator_index + 1), text.substr(separator_index + 1).strip_edges())
		return

	var label := Label.new()
	label.text = text
	label.modulate = BONUS_COLOR if _looks_like_bonus(text) else TEXT_COLOR
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)


func _add_key_value_line(parent: VBoxContainer, key_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.modulate = MUTED_COLOR
	key_label.custom_minimum_size = Vector2(76, 0)
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.modulate = VALUE_COLOR
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)


func _is_section_heading(text: String) -> bool:
	return SECTION_HEADINGS.has(text)


func _looks_like_bonus(text: String) -> bool:
	return text.find(" +") >= 0
