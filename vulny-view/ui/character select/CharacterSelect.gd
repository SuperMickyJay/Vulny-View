extends Control
class_name CharacterSelect

@export var ui: UIRoot

@onready var character_row: HBoxContainer = $CenterContainer/VBoxContainer/HBoxContainer
@onready var back_button: Button = $CenterContainer/VBoxContainer/Button
@onready var mimi_button: CharacterButton = $CenterContainer/VBoxContainer/HBoxContainer/MimiContainer/MimiButton
@onready var sisi_button: CharacterButton = $CenterContainer/VBoxContainer/HBoxContainer/SisiContainer/SisiButton
@onready var riri_button: CharacterButton = $CenterContainer/VBoxContainer/HBoxContainer/RiriContainer/RiriButton
@onready var prannu_button: CharacterButton = $CenterContainer/VBoxContainer/HBoxContainer/PrannuContainer/PrannuButton
@onready var rara_button: CharacterButton = $CenterContainer/VBoxContainer/HBoxContainer/RaraContainer/RaraButton
@onready var solo_button: Button = $CenterContainer/VBoxContainer/HBoxContainer2/SoloButton
@onready var host_button: Button = $CenterContainer/VBoxContainer/HBoxContainer2/HostButton
@onready var online_button: Button = $CenterContainer/VBoxContainer/HBoxContainer2/OnlineButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/HBoxContainer3/JoinButton
@onready var ip_field: LineEdit = $CenterContainer/VBoxContainer/HBoxContainer3/IpField
@onready var start_button: Button = $CenterContainer/VBoxContainer/HBoxContainer2/StartButton
@onready var status_label: Label = $CenterContainer/VBoxContainer/VBoxContainer/StatusLabel
@onready var label: RichTextLabel = $CenterContainer/VBoxContainer/Label
@onready var center_container: CenterContainer = $CenterContainer

# Gap (canvas px) kept between the IP field's bottom and the top of the on-screen keyboard.
const KEYBOARD_MARGIN := 4.0
# How fast the menu slides up/down to clear the keyboard (higher = snappier).
const KEYBOARD_SLIDE_RATE := 20.0
# Current upward shift applied to the menu so the IP field stays above the keyboard.
var _keyboard_shift: float = 0.0

@onready var character_buttons: Array[CharacterButton] = [
	mimi_button, sisi_button, riri_button, prannu_button, rara_button
]

signal back_pressed
signal solo_requested       # Main loads the world, then opens a solo lobby
signal host_requested       # Main starts the server, loads the world, opens a host lobby
signal join_requested(host_ip: String)   # Main loads the world, then connects to host_ip
signal start_pressed        # solo / host: begin the match
signal enter_game_pressed   # drop-in client: load into an already-running match

# Character selection happens in the lobby. Before entering a lobby the screen shows only
# the mode buttons (Solo/Host/Join); the character row appears once in a lobby.
var _in_lobby: bool = false
var _is_solo: bool = false
var _is_host: bool = false
var _is_drop_in: bool = false   # client that joined while a match is already running

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	for button in character_buttons:
		button.pressed.connect(_on_character_button_pressed.bind(button))
	solo_button.pressed.connect(func() -> void: solo_requested.emit())
	host_button.pressed.connect(func() -> void: host_requested.emit())
	online_button.pressed.connect(_on_online_button_pressed)
	join_button.pressed.connect(func() -> void: join_requested.emit(ip_field.text))
	start_button.pressed.connect(_on_start_button_pressed)
	CharacterLobby.taken_changed.connect(_refresh_characters)
	# The keyboard's Done/Enter closes it, which slides the menu back down.
	ip_field.text_submitted.connect(func(_text: String) -> void: ip_field.release_focus())

	exit_lobby()   # start in the pre-lobby (mode-select) state

# --- On-screen keyboard avoidance ----------------------------------------------
# Godot runs fullscreen on mobile, so the OS doesn't pan the app when the virtual
# keyboard opens — it simply covers the bottom of the screen, hiding the IP field.
# While the field is focused, slide the menu up just far enough to keep it visible.

func _process(delta: float) -> void:
	var target := 0.0
	if is_visible_in_tree() and ip_field.is_visible_in_tree() and ip_field.has_focus():
		target = _shift_to_clear_keyboard()

	if is_equal_approx(_keyboard_shift, target):
		return
	_keyboard_shift = lerpf(_keyboard_shift, target, 1.0 - exp(-delta * KEYBOARD_SLIDE_RATE))
	if absf(_keyboard_shift - target) < 0.5:
		_keyboard_shift = target
	# Move the menu as a whole (background/foreground stay put) by offsetting both
	# edges of the full-rect container, so its size and anchoring are unchanged.
	center_container.offset_top = -_keyboard_shift
	center_container.offset_bottom = -_keyboard_shift

func _shift_to_clear_keyboard() -> float:
	var keyboard_px := DisplayServer.virtual_keyboard_get_height()
	if keyboard_px <= 0:
		return 0.0
	# Keyboard height is in window pixels; map the keyboard's top edge into canvas
	# coordinates through the stretch transform (integer scale + any letterbox offset).
	var to_window := get_viewport().get_final_transform()
	var keyboard_top_window := float(DisplayServer.window_get_size().y - keyboard_px)
	var keyboard_top := (keyboard_top_window - to_window.origin.y) / to_window.get_scale().y
	# Where the field's bottom would be with no shift applied.
	var field_bottom := ip_field.get_global_rect().end.y + _keyboard_shift
	return maxf(0.0, field_bottom + KEYBOARD_MARGIN - keyboard_top)

# --- Picking (only reachable while in a lobby; the row is hidden otherwise) ---

func _on_character_button_pressed(pressed_button: CharacterButton) -> void:
	# Authoritative: the server (or the local CharacterLobby when solo) confirms the
	# claim; the UI updates on taken_changed.
	CharacterLobby.pick(pressed_button.character_id)

# Rebuilds every button's state from the lobby's replicated claim map.
func _refresh_characters(taken: Dictionary) -> void:
	if not _in_lobby:
		return
	# Offline (solo) or mid-teardown there is no peer; treat ourselves as peer 1.
	var my_id := 1
	if multiplayer.multiplayer_peer != null:
		my_id = multiplayer.get_unique_id()
	var my_pick := -1
	for button in character_buttons:
		var owner_peer: int = taken.get(button.character_id, 0)
		button.set_selected(owner_peer == my_id)
		button.set_taken(owner_peer != 0 and owner_peer != my_id)
		if owner_peer == my_id:
			my_pick = button.character_id
	if my_pick != -1:
		GameManager.set_selected_character(my_pick)
	# The action button (solo/host Start, drop-in Enter) unlocks once we hold a pick.
	if _has_action_button():
		start_button.disabled = my_pick == -1

# --- Lobby state -------------------------------------------------------------

func enter_lobby(is_solo: bool, is_host: bool, is_drop_in: bool) -> void:
	_in_lobby = true
	_is_solo = is_solo
	_is_host = is_host
	_is_drop_in = is_drop_in

	character_row.show()
	solo_button.hide()
	host_button.hide()
	online_button.hide()
	join_button.hide()
	ip_field.hide()

	# Solo/host get a Start button, a drop-in client gets Enter Game; a normal client
	# just waits for the host. Action buttons stay disabled until a character is picked.
	var has_action := _has_action_button()
	start_button.visible = has_action
	label.text = "Character Select"
	start_button.disabled = true
	start_button.text = "Enter Game" if is_drop_in else "Start Game"

	# The host shows its LAN IP so a client on the same network can type it in to join;
	# a normal client shows a waiting message.
	if is_host:
		status_label.visible = true
		status_label.text = "Your IP: %s" % NetworkManager.get_local_ip()
	else:
		status_label.visible = not has_action
		status_label.text = "Waiting for host to start..."

	ui.hide_popup()

	# Solo/host own the claim state; a client receives it synced from the server.
	if is_solo or is_host:
		CharacterLobby.reset()
	_refresh_characters(CharacterLobby.taken)

func exit_lobby() -> void:
	_in_lobby = false
	_is_solo = false
	_is_host = false
	_is_drop_in = false

	character_row.hide()
	solo_button.show()
	host_button.show()
	online_button.show()
	join_button.show()
	ip_field.show()
	start_button.hide()
	status_label.hide()
	label.text = "Choose Game Option"

	for button in character_buttons:
		button.set_taken(false)
		button.set_selected(false)

# Locks the mode buttons while Solo / Host / Join is setting up, so a second tap can't
# start another world load / connection on top of the first.
func set_mode_buttons_disabled(disabled: bool) -> void:
	for button: Button in [solo_button, host_button, online_button, join_button]:
		button.disabled = disabled

func _has_action_button() -> bool:
	return _is_solo or _is_host or _is_drop_in

# --- Button handlers ---------------------------------------------------------

func _on_start_button_pressed() -> void:
	if _is_solo or _is_host:
		start_pressed.emit()
	elif _is_drop_in:
		enter_game_pressed.emit()

# Play Online joins the dedicated server from config/server.cfg. Without one, say so —
# passing "" on would fall back to localhost like a blank Join field.
func _on_online_button_pressed() -> void:
	if NetworkManager.server_address.is_empty():
		ui.show_popup_box("Online server not configured", true)
		return
	join_requested.emit(NetworkManager.server_address)

func _on_back_button_pressed() -> void:
	# back_pressed -> Main.return_to_menu, which disconnects (if connected) and then
	# tears down the lobby/world in the correct order (exit_lobby before reset).
	emit_signal("back_pressed")
