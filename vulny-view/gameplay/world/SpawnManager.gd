extends Node
class_name SpawnManager

var world: World

# character_id -> network_id, so no two players end up with the same character.
var _taken_characters: Dictionary = {}

func _ready() -> void:
	world = GameManager._world
	# Spawning is triggered explicitly (Session.spawn_local_player / request_spawn) once
	# a peer starts/enters the match — not automatically on level load.

func add_player(network_id: int = 1, character_id: int = CharacterRegistry.DEFAULT_ID, spawn_tag := "default") -> Player:
	# One player per peer. A client drives spawning over an "any_peer" RPC, so an
	# untrusted/buggy client could call it repeatedly; ignore requests for a peer that
	# already has a body (players are named by their peer id under Players).
	if world.players_container.has_node(str(network_id)):
		return null
	# Hard cap, whatever the network layer let through: the MultiplayerSpawner's
	# spawn_limit is the same number, so a body past it would never reach clients.
	if world.players_container.get_child_count() >= NetworkManager.MAX_PLAYERS:
		return null

	var resolved_id := _claim_character(character_id, network_id)

	var spawn_point: SpawnPoint = world.active_level.get_spawn_point_by_tag(
		"PlayerPoints",
		spawn_tag
	)

	var player: Player = world.spawn_player(
		CharacterRegistry.get_scene(resolved_id),
		spawn_point,
		network_id
	)

	# Body authority intentionally left at the server (peer 1) default so the
	# server simulates all players. Input authority is assigned per-peer in
	# Player._enter_tree. Do NOT call set_multiplayer_authority here: it defaults
	# to recursive and would clobber the client-owned Input node back to the server.
	return player

# Reserves a character for this peer. If the requested one is invalid or already
# taken, falls back to the lowest free id so two players never share a character.
func _claim_character(requested_id: int, network_id: int) -> int:
	var character_id := requested_id

	if not CharacterRegistry.is_valid_id(character_id) or _taken_characters.has(character_id):
		character_id = _first_free_character()

	_taken_characters[character_id] = network_id
	return character_id

func _first_free_character() -> int:
	for id in range(CharacterRegistry.count()):
		if not _taken_characters.has(id):
			return id
	return CharacterRegistry.DEFAULT_ID  # only if MAX_PLAYERS ever exceeds the character count

func release_character(network_id: int) -> void:
	for id in _taken_characters.keys():
		if _taken_characters[id] == network_id:
			_taken_characters.erase(id)
			return
