extends Control

signal start_requested(username: String)

@onready var name_edit: LineEdit = $Panel/Margin/Stack/NameEdit
@onready var start_button: Button = $Panel/Margin/Stack/StartButton


func _ready() -> void:
	start_button.pressed.connect(_request_start)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.grab_focus()


func _request_start() -> void:
	start_requested.emit(name_edit.text)


func _on_name_submitted(_text: String) -> void:
	_request_start()
