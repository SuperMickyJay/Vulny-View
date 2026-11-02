extends Node
class_name Session

@export var scene_router: SceneRouter

@onready var mode_container: Node = $ModeContainer
@onready var world_container: Node = $WorldContainer

var active: bool = false

var current_world: Node
var current_mode: Node
var is_paused := false
var is_multiplayer: bool = false

signal paused_changed(is_paused: bool)

func _ready() -> void:
	# World loading and player spawning are decoupled (see start_session + the spawn
	# helpers below). A peer loads its world when it connects; spawning happens later,
	# on Start/Enter, driven by Main.
	NetworkManager.peer_disconnected.connect(remove_player_from_session)

func start_session(
	game_mode_scene: PackedScene,
	level_scene: PackedScene,
	is_multiplayer_session: bool
) -> void:
	if active:
		shutdown_session()
		
	active = true
	is_multiplayer = is_multiplayer_session
	
	current_world = preload("uid://b86bq2bmwo4rq").instantiate()
	world_container.add_child(current_world)
	GameManager.set_world(current_world)
	
	current_mode = game_mode_scene.instantiate()
	mode_container.add_child(current_mode)
	
	# Loads the world/level only — no players are spawned here. Spawning is a separate
	# step (below) so a peer can have its world ready (spawner + Players paths) before
	# the server replicates existing players to it.
	await scene_router.transition_to_level(current_world, current_mode, level_scene)

# --- Spawning (server-authoritative), decoupled from world loading -----------

# Server / single-player host: spawn our own player. Offline (solo) there is no peer,
# so we are peer 1.
func spawn_local_player(character_id: int) -> void:
	var local_id := 1
	if multiplayer.multiplayer_peer != null:
		local_id = multiplayer.get_unique_id()
	current_mode.add_player(local_id, character_id)

# Server-side: spawn the player for whichever peer requested it.
@rpc("any_peer", "reliable")
func request_spawn(character_id: int) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if NetworkManager.is_peer_rejected(peer_id):
		return   # server full
	current_mode.add_player(peer_id, character_id)

# Server-side: start replicating NPC state to a peer that has loaded its world. NPC
# synchronizers start hidden (public_visibility = false) until this runs, so the server
# never sends NPC sync to a peer that can't resolve the nodes yet.
func reveal_npcs_for(peer_id: int) -> void:
	for npc in get_tree().get_nodes_in_group("npc"):
		var npc_sync: MultiplayerSynchronizer = npc.get_node_or_null("MultiplayerSynchronizer")
		if npc_sync != null:
			npc_sync.set_visibility_for(peer_id, true)

func shutdown_session() -> void:
	print("Shutting down gameplay session")
	active = false

	# Quitting from the pause menu leaves is_paused set; clear it so the next session
	# doesn't start with input blocked. And drop any open dialogue — MessageManager is
	# static and outlives the session, so a box left open would stay up in the next game
	# and refuse all new dialogue.
	is_paused = false
	MessageManager.reset()

	# Detach before queue_free so the names "NormalMode"/"World" are free immediately. A
	# session restarted in the same frame (e.g. a retried join) would otherwise get an
	# auto-renamed "@World@N", whose MultiplayerSpawner path no longer matches the
	# server's — every replicated player spawn then silently fails on this peer.
	if current_mode:
		mode_container.remove_child(current_mode)
		current_mode.queue_free()
		current_mode = null

	if current_world:
		world_container.remove_child(current_world)
		current_world.queue_free()
		current_world = null
		GameManager.set_world(null)
		
	is_multiplayer = false
		
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and active:
		toggle_pause()

func toggle_pause() -> void:
	set_paused(!is_paused)
	
func set_paused(value: bool) -> void:
	if is_paused == value:
		return
		
	is_paused = value
	# Only freeze the game solo. In multiplayer the host IS the server, so pausing the
	# tree would freeze every player; there, pausing just opens the menu and
	# PlayerRoamState stops reading this peer's input while is_paused is set.
	if not is_multiplayer:
		get_tree().paused = is_paused
	paused_changed.emit(is_paused)
	
func remove_player_from_session(network_id: int) -> void:
	# A disconnect can arrive after the session has already been torn down.
	if current_mode == null:
		return
	current_mode.remove_player(network_id)
