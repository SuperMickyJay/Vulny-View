extends Node

func _ready() -> void:	
	var audio_settings := ConfigFileHandler.load_audio_settings()
	var master_volume_db: float = linear_to_db(audio_settings.master_volume)
	AudioServer.set_bus_volume_db(0, master_volume_db)
	var music_volume_db: float = linear_to_db(audio_settings.music_volume)
	AudioServer.set_bus_volume_db(1, music_volume_db)
	var sfx_volume_db: float = linear_to_db(audio_settings.sfx_volume)
	AudioServer.set_bus_volume_db(2, sfx_volume_db)
	
	var display_settings := ConfigFileHandler.load_display_settings()
	
	# If being ran in browser then fullscreen is not applicable
	if OS.has_feature("web"):
		return
		
	
	if display_settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().size = Vector2(1280, 720)
