extends Control
class_name Main

@onready var scene_router: Node = $SceneRouter
@onready var session: Session = $Session
@onready var ui: CanvasLayer = $UI
@onready var main_menu: Control = $UI/MenuLayer/MainMenu
@onready var options_menu: Control = $UI/MenuLayer/OptionsMenu
@onready var pause_menu: Control = $UI/MenuLayer/PauseMenu
@onready var character_select: CharacterSelect = $UI/CharacterSelectLayer/CharacterSelect

var _normal_mode_scene: PackedScene
var _overworld_scene: PackedScene

# Server-side: true once the host has started the match (players exist). A client that
# connects after this is a drop-in and loads straight into the running game.
var _match_started: bool = false

# True when launched as a headless, player-less dedicated server (command line --server).
var _dedicated_server: bool = false

# True from a Solo / Host / Join / Play Online press until that mode reaches its lobby
# or fails. While set, the mode buttons are disabled and repeat presses are ignored, so
# a double-tap (or tapping a second mode mid-load) can't start a second world load or
# network peer on top of the first.
var _busy: bool = false

func _ready() -> void:
	add_to_group("main")

	main_menu.play_pressed.connect(open_character_select)
	main_menu.options_pressed.connect(show_options_menu)
	options_menu.back_pressed.connect(return_to_menu)
	main_menu.quit_pressed.connect(quit_game)
	pause_menu.quit_to_menu_requested.connect(return_to_menu)
	character_select.back_pressed.connect(return_to_menu)
	character_select.solo_requested.connect(_on_solo_requested)
	character_select.host_requested.connect(_on_host_requested)
	character_select.join_requested.connect(_on_join_requested)
	character_select.start_pressed.connect(_on_start_pressed)
	character_select.enter_game_pressed.connect(_on_enter_game_pressed)
	NetworkManager.server_disconnected.connect(return_to_menu)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.client_connected.connect(_on_client_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.cant_create_server.connect(_on_cant_create_server)

	ui.connect_session(session)
	_preload_game_scenes()
	_boot_game()

# Load the gameplay scenes once at startup so the expensive TileSet build happens
# behind the main menu instead of stalling the main thread on the Start button press.
func _preload_game_scenes() -> void:
	_normal_mode_scene = load(scene_router.SCENES["normal_mode"])
	_overworld_scene = load(scene_router.SCENES["overworld"])

func _boot_game() -> void:
	print("Booting game...")
	if _dedicated_server_requested():
		_start_dedicated_server()
	else:
		show_main_menu()

# Launched with the `--server` flag, e.g.
#   godot --headless --path vulny-view -- --server
func _dedicated_server_requested() -> bool:
	return OS.get_cmdline_user_args().has("--server") or OS.get_cmdline_args().has("--server")

# Player-less server: hosts and simulates the world but never spawns a local player and
# shows no menus. _on_server_created finishes the setup once the server peer is up.
func _start_dedicated_server() -> void:
	print("Starting dedicated server...")
	_dedicated_server = true
	ui.hide_all()
	NetworkManager.create_server(NetworkManager.SERVER_PORT, false)

func show_main_menu() -> void:
	if session.active:
		session.shutdown_session()

	# Returning to the menu also tears down any lobby state so the screen reopens fresh.
	_match_started = false
	_set_busy(false)
	character_select.exit_lobby()
	CharacterLobby.reset()

	ui.show_main_menu()

func show_options_menu() -> void:
	ui.show_options_menu()

func open_character_select() -> void:
	ui.show_character_select()
	if not character_select.multiplayer_available:
		_on_solo_requested()

# Loads THIS peer's world/level. Every peer does this before any player is spawned, so
# the MultiplayerSpawner/Players paths exist when the server replicates players to it —
# which is what makes drop-in joins work. Spawning is a separate, later step.
func _load_world(is_multiplayer_session: bool) -> void:
	GameManager.set_session(session)
	await session.start_session(_normal_mode_scene, _overworld_scene, is_multiplayer_session)

# Switches from the menu/lobby UI to the in-game HUD.
func _begin_play() -> void:
	await ui.fade_out()
	ui.hide_all()
	ui.show_game_hud()
	ui.show_message_layer()
	await ui.fade_in()

# --- Single-player -----------------------------------------------------------

# Solo: load our world, then open a solo lobby to pick a character.
func _on_solo_requested() -> void:
	if _busy:
		return
	_set_busy(true)
	await _load_world(false)
	if not _busy:
		return  # cancelled (Back) while the world was loading
	character_select.enter_lobby(true, false, false)
	_set_busy(false)

# --- Hosting -----------------------------------------------------------------

# Host button: start the server; _on_server_created continues once it's up.
func _on_host_requested() -> void:
	if _busy:
		return
	_set_busy(true)
	NetworkManager.create_server()

# Port in use / no permission: UIRoot shows the error, so just unlock the buttons.
func _on_cant_create_server(_text: String = "", _show_close: bool = true) -> void:
	_set_busy(false)

# Host: load our world, then open the character screen as a lobby.
func _on_server_created() -> void:
	await _load_world(true)
	if _dedicated_server:
		# Player-less server: the world is live immediately, so there is no host player
		# and no lobby. Marking the match started means every client that joins is a
		# drop-in — it picks a character and enters on its own (no host Start needed).
		_match_started = true
	else:
		if not _busy:
			return  # cancelled (Back) while the world was loading
		# Player host (e.g. a phone): pick a character in the lobby, then press Start.
		character_select.enter_lobby(false, true, false)
		_set_busy(false)

# Solo/host press Start: spawn our own player and switch to the HUD. When networked
# (host), also mark the match started and tell every connected client to spawn.
func _on_start_pressed() -> void:
	session.spawn_local_player(GameManager.selected_character_id)
	_begin_play()
	if multiplayer.multiplayer_peer != null:
		_match_started = true
		_begin_match_remote.rpc()

@rpc("authority", "reliable")
func _begin_match_remote() -> void:
	session.request_spawn.rpc_id(1, GameManager.selected_character_id)
	_begin_play()

# --- Joining -----------------------------------------------------------------

# Join: load our world FIRST, then connect — so the spawner exists when the server
# replicates existing players (drop-in) or the host's players (on Start) to us.
func _on_join_requested(host_ip: String) -> void:
	if _busy:
		return
	_set_busy(true)
	# Clear a stale flag from an earlier host session BEFORE the world loads:
	# NormalMode._ready reads it to decide whether this peer owns a SpawnManager.
	NetworkManager.is_hosting_game = false
	# Blank falls back to localhost (same-machine testing); otherwise connect to the
	# host's address typed on the join screen (e.g. its LAN IP on the same Wi-Fi).
	var address := host_ip.strip_edges()
	if address.is_empty():
		address = "localhost"
	ui.show_popup_box("Connecting to server", false, true)
	await _load_world(true)
	if not _busy:
		return  # cancelled (Back) while the world was loading
	NetworkManager.create_client(address)

func _on_client_connected() -> void:
	_request_join.rpc_id(1)

# The join attempt failed (NetworkManager already cleared the peer and UIRoot shows the
# error popup). Tear down the half-loaded world so a retry starts from a clean session.
func _on_connection_failed(_text: String = "", _show_close: bool = true) -> void:
	_set_busy(false)
	if session.active:
		session.shutdown_session()

func _set_busy(value: bool) -> void:
	_busy = value
	character_select.set_mode_buttons_disabled(value)

@rpc("any_peer", "reliable")
func _request_join() -> void:
	# Server-side routing. The client has already loaded its world, so reveal NPCs to it
	# and send it into the lobby — in drop-in mode if the match is already running.
	var peer_id := multiplayer.get_remote_sender_id()
	if NetworkManager.is_peer_rejected(peer_id):
		return   # server full: NetworkManager is turning this peer away
	session.reveal_npcs_for(peer_id)
	_enter_lobby_remote.rpc_id(peer_id, _match_started)

@rpc("authority", "reliable")
func _enter_lobby_remote(drop_in: bool) -> void:
	_set_busy(false)
	character_select.enter_lobby(false, false, drop_in)

# Drop-in client presses Enter Game: spawn our picked character and switch to the HUD.
func _on_enter_game_pressed() -> void:
	session.request_spawn.rpc_id(1, GameManager.selected_character_id)
	_begin_play()

# --- Leaving -----------------------------------------------------------------

func return_to_menu() -> void:
	if GameManager._session and options_menu.visible:
		ui.hide_options_menu()
		return
		
	print("Returning to menu")
	get_tree().paused = false

	# Disconnect BEFORE tearing down the world so replication stops first, otherwise the
	# server's in-flight sync lands on freed nodes.
	if GameManager._session and GameManager._session.is_multiplayer:
		NetworkManager.terminate_connection()

	show_main_menu()

func quit_game() -> void:
	get_tree().quit()
