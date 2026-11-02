extends Control
class_name EmoteContainer

const HEART = preload("uid://ch72jjo4fhfv2")
const SMILE = preload("uid://bkrn38tfl2pv1")
const SAD = preload("uid://bndmxg677q4e2")
const YIPPIE = preload("uid://c7wcubp7x4xi0")

@onready var sprite_2d: Sprite2D = $Container/Sprite2D
@onready var timer: Timer = $Timer

const DISPLAY_TIME := 2.0

func _ready() -> void:
	timer.timeout.connect(hide)

# Owning client -> server. Everything outside the player's Input subtree stays owned
# by the server (peer 1), so the server is this node's authority: it validates the
# request and rebroadcasts it to every peer. call_local so the host (peer 1) can send
# this to itself — rpc_id(1) from the host targets its own id, which Godot only permits
# on a call_local RPC.
@rpc("any_peer", "call_local", "reliable")
func request_emote(emote: String) -> void:
	if not is_multiplayer_authority():
		return
	# Only the player's own peer may emote through it (players are named by peer id),
	# and only a known emote is relayed — this RPC is any_peer, so don't trust either.
	var player := get_parent().get_parent() as Player
	if player == null or str(player.name).to_int() != multiplayer.get_remote_sender_id():
		return
	if emote not in ["heart", "smile", "sad", "yippie"]:
		return
	play_emote.rpc(emote)

# Server -> all peers (call_local so the host shows it too). Displays the emote on
# this player's copy on every screen; each peer's own Timer hides it afterwards.
@rpc("authority", "call_local", "reliable")
func play_emote(emote: String) -> void:
	load_emote(emote)
	# Emote and chat bubble share the spot above the head: the newest one wins.
	var chat_bubble := get_parent().get_node_or_null("ChatBubble") as Control
	if chat_bubble != null:
		chat_bubble.hide()
	show()
	# Restart the full duration on every emote, so pressing a second emote while the
	# first is still up gives it the full time instead of inheriting the remainder.
	timer.start(DISPLAY_TIME)
	if emote == "yippie":
		var character_sprite = get_parent().get_parent().get_node_or_null("Sprite") as CharacterAnimation
		if character_sprite != null:
			character_sprite.play_yippie(DISPLAY_TIME)

func load_emote(emote: String) -> void:
	match emote:
		"heart":
			sprite_2d.texture = HEART
		"smile":
			sprite_2d.texture = SMILE
		"sad":
			sprite_2d.texture = SAD
		"yippie":
			sprite_2d.texture = YIPPIE
