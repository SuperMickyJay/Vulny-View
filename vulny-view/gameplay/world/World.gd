extends Node2D
class_name World

@onready var players_container: Node2D = $Players
@onready var level_container: Node = $CurrentLevel

var active_level: Node2D

func _ready() -> void:
	add_to_group("world")

func spawn_player(player_scene: PackedScene, spawn_point: SpawnPoint, network_id: int) -> Player:
	var player: Player = player_scene.instantiate()
	# Name the node BEFORE it enters the tree so Player._enter_tree derives the
	# correct input authority from the name on the server too (clients receive
	# the already-named node from the MultiplayerSpawner).
	player.name = str(network_id)
	players_container.add_child(player)
	player.global_position = spawn_point.global_position
	return player
	
func remove_player(network_id: int) -> void:
	for player: Player in players_container.get_children():
		if player.name == str(network_id):
			player.queue_free()
			return

func load_level(level_scene: PackedScene) -> void:
	if active_level:
		active_level.queue_free()
		
	active_level = level_scene.instantiate()
	level_container.add_child(active_level)
	
	await get_tree().process_frame

func transition_to_area(player: Player, spawn_tag := "default") -> void:
	# Runs on the OWNING client (the fade is local — see SceneTrigger). The player
	# body is server-authoritative, so the actual teleport must happen on the server
	# and replicate back; only routing changes here, the fade stays on this screen.
	var peer_id := str(player.name).to_int()

	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		# Solo, or the host's own player: apply the move directly.
		request_move_to_spawn(peer_id, spawn_tag)
	else:
		# Remote client: ask the server to move its authoritative copy.
		request_move_to_spawn.rpc_id(1, peer_id, spawn_tag)

	# Wait for the authoritative teleport to actually replicate back rather than
	# guessing a fixed number of frames. The spawn exists in this peer's local level
	# copy, so we can read its target position here; a safety timer stops us blocking
	# the fade forever if the update never arrives.
	var spawn: Marker2D = active_level.get_spawn_point_by_tag("PlayerPoints", spawn_tag)
	if spawn != null:
		# The server snaps the teleported body to the 16px grid, so wait for the player
		# to reach that SNAPPED tile — not the raw marker. A marker placed even a few px
		# off-grid would never match the un-snapped position, blocking the fade for the
		# full safety timeout.
		var target := spawn.global_position.snapped(Vector2(Modules.GRID_SIZE, Modules.GRID_SIZE))
		var timeout := get_tree().create_timer(3.0)
		while player.global_position.distance_to(target) > 1.0 and timeout.time_left > 0.0:
			await get_tree().process_frame

		# Face the way the spawn dictates on THIS client, so the owning player's own
		# (event-driven) idle animation points the right way once the fade lifts.
		_apply_spawn_facing(player, spawn)

@rpc("any_peer", "reliable")
func request_move_to_spawn(peer_id: int, spawn_tag: String) -> void:
	# Executes on the server (or locally when offline / host-owned). Cleanly ends any
	# in-progress step first so the teleport can't leave a stale target or a leaked
	# tile reservation behind, then moves the body (which replicates to every peer).
	var player := players_container.get_node_or_null(str(peer_id)) as Player
	if player == null:
		return

	var spawn: Marker2D = active_level.get_spawn_point_by_tag("PlayerPoints", spawn_tag)
	if spawn == null:
		return

	var movement: CharacterMovement = player.get_node("Movement")
	if movement.is_walking:
		movement.stop_walking()

	player.global_transform = spawn.global_transform
	movement.snap_position_to_grid()
	# Authoritative facing: publishes via sync_facing so remote peers see the arriving
	# player face the right way (the owning client sets its own copy in transition_to_area).
	_apply_spawn_facing(player, spawn)

# Point the player the way a spawn dictates. Sets the live facing + input direction;
# on the server that publishes through sync_facing, and on the owning client it drives
# the local idle animation. No-op for spawns that leave facing at ZERO.
func _apply_spawn_facing(player: Player, spawn: Marker2D) -> void:
	var sp := spawn as SpawnPoint
	if sp == null or sp.facing == Vector2.ZERO:
		return
	(player.get_node("Input") as CharacterInput).direction = sp.facing
	(player.get_node("Movement") as CharacterMovement).facing_direction = sp.facing
