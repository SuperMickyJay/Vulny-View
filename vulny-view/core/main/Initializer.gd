extends Node

func _ready() -> void:	
	var audio_settings := ConfigFileHandler.load_audio_settings()
	var volume_db: float = linear_to_db(audio_settings.master_volume)
	AudioServer.set_bus_volume_db(0, volume_db)
	
	var display_settings := ConfigFileHandler.load_display_settings()
	
	if display_settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().size = Vector2(1280, 720)
