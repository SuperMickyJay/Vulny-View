extends Control

@onready var volume_slider: HSlider = $CenterContainer/VBoxContainer/HBoxContainer2/VolumeSlider
@onready var full_screen_check_button: CheckButton = $CenterContainer/VBoxContainer/HBoxContainer/FullScreenCheckButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

signal back_pressed

func _ready() -> void:
	var audio_settings := ConfigFileHandler.load_audio_settings()
	var display_settings := ConfigFileHandler.load_display_settings()

	# Apply the saved values before wiring signals so seeding them here
	# doesn't fire value_changed/toggled and re-save during setup.
	volume_slider.value = audio_settings.master_volume
	full_screen_check_button.button_pressed = bool(display_settings.fullscreen)

	back_button.pressed.connect(_on_back_button_pressed)
	volume_slider.value_changed.connect(_on_volume_slider_value_changed)
	full_screen_check_button.toggled.connect(_on_full_screen_check_button_toggled)

func open() -> void:
	show()
	back_button.grab_focus()

func _on_back_button_pressed() -> void:
	emit_signal("back_pressed")

func _on_volume_slider_value_changed(value: float) -> void:
	ConfigFileHandler.save_audio_setting("master_volume", volume_slider.value)
	var volume_db: float = linear_to_db(value)
	AudioServer.set_bus_volume_db(0, volume_db)

func _on_full_screen_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().size = Vector2(1280, 720)
		
	ConfigFileHandler.save_display_setting("fullscreen", full_screen_check_button.button_pressed)
