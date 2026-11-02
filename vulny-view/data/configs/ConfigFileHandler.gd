extends Node

const SETTINGS_FILE_PATH = "user://settings.ini"

# Every setting the game reads, with its default. Initializer / OptionsMenu access these
# keys directly, so each one must always exist — add new settings here.
const DEFAULTS := {
	"audio": {"master_volume": 1.0},
	"display": {"fullscreen": true},
}

var config := ConfigFile.new()

func _ready() -> void:
	if FileAccess.file_exists(SETTINGS_FILE_PATH) and config.load(SETTINGS_FILE_PATH) != OK:
		# Corrupt / unreadable: start from defaults rather than half-loaded data.
		config = ConfigFile.new()

	# Fill in any key missing from an older or partial settings file (or a new install),
	# then save so the file on disk is complete.
	var filled := false
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if not config.has_section_key(section, key):
				config.set_value(section, key, DEFAULTS[section][key])
				filled = true
	if filled:
		config.save(SETTINGS_FILE_PATH)

func save_audio_setting(key: String, value: Variant) -> void:
	config.set_value("audio", key, value)
	config.save(SETTINGS_FILE_PATH)
	
func load_audio_settings() -> Dictionary:
	var audio_settings := {}
	for key in config.get_section_keys("audio"):
		audio_settings[key] = config.get_value("audio", key)
		
	return audio_settings
	
func save_display_setting(key: String, value: Variant) -> void:
	config.set_value("display", key, value)
	config.save(SETTINGS_FILE_PATH)
	
func load_display_settings() -> Dictionary:
	var display_settings := {}
	for key in config.get_section_keys("display"):
		display_settings[key] = config.get_value("display", key)
		
	return display_settings
