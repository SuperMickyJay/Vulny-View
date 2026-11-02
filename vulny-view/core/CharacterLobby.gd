extends Node

# Pre-game character claims: character_id -> peer_id. Authoritative on the server and
# mirrored on every client, so the CharacterSelect screen can grey out characters that
# other players have already taken. Lives at the menu (before a session exists), so it
# is its own autoload rather than part of SpawnManager.
var taken: Dictionary = {}

signal taken_changed(taken: Dictionary)

func _ready() -> void:
	NetworkManager.peer_connected.connect(_on_peer_connected)
	NetworkManager.peer_disconnected.connect(_on_peer_disconnected)

func reset() -> void:
	taken.clear()
	taken_changed.emit(taken)

# Called by the local UI when this peer picks a character.
func pick(character_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		_server_pick(1, character_id)                             # offline (solo)
	elif multiplayer.is_server():
		_server_pick(multiplayer.get_unique_id(), character_id)   # host claims directly
	else:
		_request_pick.rpc_id(1, character_id)                     # client asks the server

@rpc("any_peer", "reliable")
func _request_pick(character_id: int) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if NetworkManager.is_peer_rejected(peer_id):
		return   # server full
	_server_pick(peer_id, character_id)

func _server_pick(peer_id: int, character_id: int) -> void:
	if not CharacterRegistry.is_valid_id(character_id):
		return
	if taken.has(character_id) and taken[character_id] != peer_id:
		return   # already claimed by someone else -> reject
	_release_peer(peer_id)              # drop this peer's previous pick
	taken[character_id] = peer_id
	_broadcast()

@rpc("authority", "call_local", "reliable")
func _sync_taken(new_taken: Dictionary) -> void:
	taken = new_taken
	taken_changed.emit(taken)

func _on_peer_connected(peer_id: int) -> void:
	# Bring a freshly connected peer up to date with the current claims.
	if multiplayer.is_server():
		_sync_taken.rpc_id(peer_id, taken)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_release_peer(peer_id)
	_broadcast()

func _release_peer(peer_id: int) -> void:
	for id in taken.keys():
		if taken[id] == peer_id:
			taken.erase(id)

func _broadcast() -> void:
	if multiplayer.multiplayer_peer != null:
		_sync_taken.rpc(taken)   # to all peers; call_local updates the host too
	else:
		taken_changed.emit(taken)
