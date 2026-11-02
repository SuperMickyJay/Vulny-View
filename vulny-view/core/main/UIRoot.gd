extends CanvasLayer
class_name UIRoot

@onready var main_menu: Control = $MenuLayer/MainMenu
@onready var pause_menu: Control = $MenuLayer/PauseMenu
@onready var options_menu: Control = $MenuLayer/OptionsMenu
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var message_layer: CanvasLayer = $MessageLayer
@onready var popup_box_layer: CanvasLayer = $PopupBoxLayer
@onready var character_select_layer: CanvasLayer = $CharacterSelectLayer
@onready var transition_layer: CanvasLayer = $"../SceneRouter/TransitionLayer"

var session: Session

signal quit_to_menu_requested

func _ready() -> void:
	NetworkManager.cant_create_server.connect(show_popup_box)
	NetworkManager.connection_failed.connect(show_popup_box)

func hide_all() -> void:
	main_menu.hide()
	hud_layer.hide()
	options_menu.hide()
	pause_menu.hide()
	message_layer.hide()
	popup_box_layer.hide()
	character_select_layer.hide()

func show_main_menu() -> void:
	hide_all()
	main_menu.open()
	
func show_character_select() -> void:
	hide_all()
	character_select_layer.show()
		
func show_popup_box(text: String, show_close_button: bool, animate_ellipsis := false) -> void:
	popup_box_layer.show_message(text, show_close_button, animate_ellipsis)

func hide_popup() -> void:
	popup_box_layer.close()
	
func show_options_menu() -> void:
	hide_all()
	options_menu.open()

func show_game_hud() -> void:
	hide_all()
	hud_layer.show()
	
func show_message_layer() -> void:
	message_layer.show()

func show_pause_menu() -> void:
	pause_menu.open()
	hud_layer.hide()
	message_layer.hide()
	
func hide_pause_menu() -> void:
	pause_menu.hide()
	hud_layer.show()
	message_layer.show()
	
func connect_session(session_ref: Session) -> void:
	session = session_ref
	session.paused_changed.connect(_on_paused_changed)
	pause_menu.resume_requested.connect(_on_resume_requested)
	pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu_requested)

func _on_paused_changed(is_paused: bool) -> void:
	if is_paused:
		show_pause_menu()
	else:
		hide_pause_menu()
		
func _on_resume_requested() -> void:
	session.set_paused(false)
	
func _on_quit_to_menu_requested() -> void:
	emit_signal("quit_to_menu_requested")
	
func fade_out() -> void:
	await transition_layer.fade_out()
	
func fade_in() -> void:
	await transition_layer.fade_in()
