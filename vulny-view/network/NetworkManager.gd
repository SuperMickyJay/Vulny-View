extends Node

const SERVER_PORT: int = 8080

# Most players a server ever holds, counting a playing host. Matches the five characters
# and the World MultiplayerSpawner's spawn_limit — change all three together.
const MAX_PLAYERS: int = 5
# How long a client turned away for a full server stays connected, so the "server is full"
# RPC reaches it before the disconnect.
const REJECT_DELAY := 0.5

# Where the "Play Online" address comes from. Kept out of the repo: server.cfg is
# gitignored (copy config/server.example.cfg to create it) and packed into the Android
# build by its export include_filter. Re-export the client after changing it.
const SERVER_CONFIG_PATH := "res://config/server.cfg"

# The dedicated server's public IP or hostname; "" when server.cfg is missing/blank.
var server_address: String = ""

var is_hosting_game: bool = false

# Server-side: how many CLIENTS may play (MAX_PLAYERS, minus one when the host plays too).
var _client_slots: int = MAX_PLAYERS
# Server-side: peers being turned away because the server is full (peer id -> true).
var _rejected_peers: Dictionary = {}

func _ready() -> void:
	server_address = _load_server_address()

func _load_server_address() -> String:
	var config := ConfigFile.new()
	if config.load(SERVER_CONFIG_PATH) != OK:
		return ""
	return str(config.get_value("server", "address", "")).strip_edges()

signal server_disconnected
signal peer_connected(network_id: int)
signal peer_disconnected(network_id: int)
signal server_created
signal client_connected
# Both carry a user-facing message and whether the popup should offer a close button.
signal connection_failed(text: String, show_close: bool)
signal cant_create_server(text: String, show_close: bool)

# Best-effort LAN IPv4 of this device, shown to the host so a client on the same Wi-Fi
# can type it into the join field. Heuristic: picks the first private-range address
# (192.168.x.x, 10.x.x.x, or 172.16-31.x.x).
func get_local_ip() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_private_172(address):
			return address
	return "127.0.0.1"

func _is_private_172(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var parts := address.split(".")
	return parts.size() == 4 and parts[1].is_valid_int() and parts[1].to_int() >= 16 and parts[1].to_int() <= 31

# host_is_player: true when this device also plays (Host button), false for a player-less
# dedicated server. A playing host takes one of the MAX_PLAYERS places.
func create_server(port: int = SERVER_PORT, host_is_player: bool = true) -> void:
	is_hosting_game = true
	_client_slots = MAX_PLAYERS - 1 if host_is_player else MAX_PLAYERS
	_rejected_peers.clear()
	var enet_network_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	# One connection beyond the player slots, so an extra client can connect just long
	# enough to be told the server is full (see _peer_connected). Any more are refused by
	# ENet itself and see a generic "Failed to join server".
	var error: Error = enet_network_peer.create_server(port, _client_slots + 1)
	
	if error != OK:
		print("Could not create server: ", error)
		is_hosting_game = false   # we never became the host; don't leave the flag stale
		cant_create_server.emit("Could not create server", true)
		return
	
	get_tree().get_multiplayer().multiplayer_peer = enet_network_peer
	_setup_peer_connection_signals()
	print("Server created!")
	server_created.emit()

func create_client(host_ip: String = "localhost", host_port: int = SERVER_PORT) -> void:
	is_hosting_game = false
	_setup_client_connection_signals()
	var enet_network_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = enet_network_peer.create_client(host_ip, host_port)
	
	if error != OK:
		# Fails immediately (e.g. an unresolvable address) rather than timing out, so
		# report it like any other failed join: Main unlocks the lobby buttons and tears
		# down the half-loaded world, and UIRoot swaps "Connecting..." for this error.
		print("Could not create client: ", error)
		connection_failed.emit("Could not connect to %s" % host_ip, true)
		return

	get_tree().get_multiplayer().multiplayer_peer = enet_network_peer
	
	print("Attempting to connect to server...")
	
func _setup_client_connection_signals() -> void:
	if not get_tree().get_multiplayer().server_disconnected.is_connected(_server_disconnected):
		get_tree().get_multiplayer().server_disconnected.connect(_server_disconnected)
		
	if not get_tree().get_multiplayer().connection_failed.is_connected(_connection_failed):
		get_tree().get_multiplayer().connection_failed.connect(_connection_failed)
		
	if not get_tree().get_multiplayer().connected_to_server.is_connected(_connected_to_server):
		get_tree().get_multiplayer().connected_to_server.connect(_connected_to_server)
		
func _setup_peer_connection_signals() -> void:
	if not get_tree().get_multiplayer().peer_connected.is_connected(_peer_connected):
		get_tree().get_multiplayer().peer_connected.connect(_peer_connected)
		
	if not get_tree().get_multiplayer().peer_disconnected.is_connected(_peer_disconnected):
		get_tree().get_multiplayer().peer_disconnected.connect(_peer_disconnected)
	
func _server_disconnected() -> void:
	print("Server disconnected")
	server_disconnected.emit()
	
func terminate_connection() -> void:
	print("Terminate connection")
	_terminate_connection()
	_disconnect_client_connection_signals()
	_disconnect_peer_connection_signals()

func _terminate_connection() -> void:
	get_tree().get_multiplayer().multiplayer_peer = null
	
# Check for OUR handler, not has_connections(): other nodes (e.g. NPCs) connect to the
# same signals, and a client never connects the peer handlers at all.
func _disconnect_client_connection_signals() -> void:
	if get_tree().get_multiplayer().server_disconnected.is_connected(_server_disconnected):
		get_tree().get_multiplayer().server_disconnected.disconnect(_server_disconnected)

func _disconnect_peer_connection_signals() -> void:
	if get_tree().get_multiplayer().peer_connected.is_connected(_peer_connected):
		get_tree().get_multiplayer().peer_connected.disconnect(_peer_connected)

	if get_tree().get_multiplayer().peer_disconnected.is_connected(_peer_disconnected):
		get_tree().get_multiplayer().peer_disconnected.disconnect(_peer_disconnected)
		
func _peer_connected(network_id: int) -> void:
	print("Peer connected: %s" % network_id)
	# Peers already being turned away still appear in get_peers() until they disconnect.
	if multiplayer.get_peers().size() - _rejected_peers.size() > _client_slots:
		_reject_full(network_id)
		return   # never announced: the rest of the game doesn't see this peer
	peer_connected.emit(network_id)

func _peer_disconnected(network_id: int) -> void:
	print("Peer disconnected: %s" % network_id)
	_rejected_peers.erase(network_id)
	peer_disconnected.emit(network_id)

# Server-side: true for a peer being turned away because the server is full. Server
# handlers of client requests (join, character pick, spawn) ignore these peers.
func is_peer_rejected(peer_id: int) -> bool:
	return _rejected_peers.has(peer_id)

func _reject_full(peer_id: int) -> void:
	print("Server full, rejecting peer %s" % peer_id)
	_rejected_peers[peer_id] = true
	_server_full.rpc_id(peer_id)
	await get_tree().create_timer(REJECT_DELAY).timeout
	var peer := get_tree().get_multiplayer().multiplayer_peer
	if peer != null and _rejected_peers.has(peer_id):
		peer.disconnect_peer(peer_id)

# Server -> a rejected client. Handled like any failed join: Main tears down the
# half-loaded world and UIRoot shows the message.
@rpc("authority", "reliable")
func _server_full() -> void:
	print("Server is full")
	get_tree().get_multiplayer().multiplayer_peer = null
	connection_failed.emit("Server is full (%d players max)" % MAX_PLAYERS, true)
	
func _connected_to_server() -> void:
	print("Connection successful")
	client_connected.emit()
	
func _connection_failed() -> void:
	print("Connection failed")
	get_tree().get_multiplayer().multiplayer_peer = null
	connection_failed.emit("Failed to join server", true)
