extends Control

@onready var master_volume_slider: HSlider = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/MasterVolumeRow/MasterVolumeSlider
@onready var music_volume_slider: HSlider = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/MusicVolumeRow/MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/SFXVolumeRow/SFXVolumeSlider
@onready var full_screen_check_button: CheckButton = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/FullScreenRow/FullScreenCheckButton
@onready var back_button: Button = $MarginContainer/VBoxContainer/BackButton
@onready var full_screen_row: HBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/FullScreenRow

signal back_pressed

func _ready() -> void:
	var audio_settings := ConfigFileHandler.load_audio_settings()
	var display_settings := ConfigFileHandler.load_display_settings()

	# Apply the saved values before wiring signals so seeding them here
	# doesn't fire value_changed/toggled and re-save during setup.
	master_volume_slider.value = audio_settings.master_volume
	music_volume_slider.value = audio_settings.music_volume
	sfx_volume_slider.value = audio_settings.sfx_volume
	full_screen_check_button.button_pressed = bool(display_settings.fullscreen)

	back_button.pressed.connect(_on_back_button_pressed)
	master_volume_slider.value_changed.connect(_on_master_volume_slider_value_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_slider_value_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_slider_value_changed)
	full_screen_check_button.toggled.connect(_on_full_screen_check_button_toggled)
	full_screen_row.visible = not OS.has_feature("web")

func open() -> void:
	show()
	back_button.grab_focus()

func _on_back_button_pressed() -> void:
	emit_signal("back_pressed")

func _on_master_volume_slider_value_changed(value: float) -> void:
	ConfigFileHandler.save_audio_setting("master_volume", master_volume_slider.value)
	var volume_db: float = linear_to_db(value)
	AudioServer.set_bus_volume_db(0, volume_db)
	
func _on_music_volume_slider_value_changed(value: float) -> void:
	ConfigFileHandler.save_audio_setting("music_volume", music_volume_slider.value)
	var volume_db: float = linear_to_db(value)
	AudioServer.set_bus_volume_db(1, volume_db)
	
func _on_sfx_volume_slider_value_changed(value: float) -> void:
	ConfigFileHandler.save_audio_setting("sfx_volume", sfx_volume_slider.value)
	var volume_db: float = linear_to_db(value)
	AudioServer.set_bus_volume_db(2, volume_db)

func _on_full_screen_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().size = Vector2(1280, 720)
		
	ConfigFileHandler.save_display_setting("fullscreen", full_screen_check_button.button_pressed)
