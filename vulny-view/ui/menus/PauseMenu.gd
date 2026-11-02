extends Control

@onready var resume_button: Button = $MarginContainer/VBoxContainer/ResumeButton
@onready var quit_button: Button = $MarginContainer/VBoxContainer/QuitButton

signal resume_requested
signal quit_to_menu_requested

func _ready() -> void:
	resume_button.pressed.connect(_on_resume_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	
func open() -> void:
	show()
	resume_button.grab_focus()

func _on_resume_button_pressed() -> void:
	emit_signal("resume_requested")

func _on_quit_button_pressed() -> void:
	emit_signal("quit_to_menu_requested")
