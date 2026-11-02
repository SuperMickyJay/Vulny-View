extends Control

@onready var play_button: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer/PlayButton
@onready var options_button: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer/OptionsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer/QuitButton

signal play_pressed
signal options_pressed
signal quit_pressed

func _ready() -> void:
	play_button.pressed.connect(_on_play_button_pressed)
	options_button.pressed.connect(_on_options_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)

func open() -> void:
	show()
	play_button.grab_focus()

func _on_play_button_pressed() -> void:
	emit_signal("play_pressed")

func _on_quit_button_pressed() -> void:
	emit_signal("quit_pressed")

func _on_options_button_pressed() -> void:
	emit_signal("options_pressed")
