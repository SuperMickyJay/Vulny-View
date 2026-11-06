@tool

extends CharacterBody2D
class_name NPC

@onready var animated_sprite: AnimatedSprite2D = $Sprite
@onready var npc_input: Node = $Input
@onready var character_movement: CharacterMovement = $Movement
@onready var state_machine: StateMachine = $StateMachine
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

@export var sprite_frames: SpriteFrames:
	set(value):
		sprite_frames = value
		
		if is_node_ready():
			update_appearance()
			
@export var npc_input_config: NPCInputConfig

func _ready() -> void:
	update_appearance()
	
	if Engine.is_editor_hint():
		return

	add_to_group("npc")
	Events.message_box_open.connect(_on_message_box_open)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	npc_input.npc_input_config = npc_input_config
	state_machine.change_state("Roam")
	animated_sprite.play("idle_down")
	
func update_appearance() -> void:
	var sprite := get_node_or_null("Sprite") as AnimatedSprite2D
	
	if sprite == null:
		return

	sprite.sprite_frames = sprite_frames

func play_message(direction: Vector2) -> void:
	if Engine.is_editor_hint():
		return

	if _is_remote_copy():
		# Client: this copy only mirrors the server, which keeps re-publishing its own
		# facing every frame — a local turn would be overwritten instantly. Ask the server
		# to turn + hold the NPC, and pin the talk facing locally until its update lands.
		if character_movement.sync_walking:
			return
		animated_sprite.set("facing_override", direction * -1)
		_start_talk.rpc_id(1, direction * -1)
	else:
		if character_movement.is_moving():
			return
		_face(direction * -1)

	_talking_locally = true
	state_machine.change_state("Message")
	MessageManager.play_text(npc_input_config.messages)
	
	if audio_stream_player_2d.stream:
		audio_stream_player_2d.play()

# --- Networked conversation hold ---------------------------------------------
# Dialogue itself is local, but the NPC is server-simulated, so a remote talker must
# tell the server to turn the NPC toward it and stop roaming until the talk ends.

# A client's hold lapses after this many seconds even without an _end_talk, so a phone
# backgrounded (or crashed) mid-dialogue while still connected can't freeze the NPC for
# everyone. Far longer than any NPC's dialogue; a fresh talk renews it.
const TALK_HOLD_TIMEOUT := 30.0
const CARDINALS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

# Server-side: peer id -> time (seconds) its hold on this NPC expires.
var _remote_talkers: Dictionary = {}
# Server-side: a turn requested by a talker, applied once any in-flight step finishes.
var _pending_face: Vector2 = Vector2.ZERO
# This peer is the one talking (its message box belongs to this NPC).
var _talking_locally: bool = false

func is_held_by_remote_talker() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for peer_id in _remote_talkers.keys():
		if now >= _remote_talkers[peer_id]:
			_remote_talkers.erase(peer_id)
	return not _remote_talkers.is_empty()

func _is_remote_copy() -> bool:
	return GameManager._session.is_multiplayer and not character_movement.is_simulating()

func _face(direction: Vector2) -> void:
	if npc_input.direction != direction:
		npc_input.direction = direction
		npc_input.emit_signal("turn_event_handler")

@rpc("any_peer", "reliable")
func _start_talk(direction: Vector2) -> void:
	# Untrusted input: only a cardinal facing makes sense (anything else has no animation).
	if direction not in CARDINALS:
		return
	_remote_talkers[multiplayer.get_remote_sender_id()] = Time.get_ticks_msec() / 1000.0 + TALK_HOLD_TIMEOUT
	# Roaming is paused from now on; a step already in flight finishes first, then the
	# NPC turns (see _physics_process). No await loop, so a freed NPC just never turns.
	_pending_face = direction

func _physics_process(_delta: float) -> void:
	if _pending_face == Vector2.ZERO or Engine.is_editor_hint():
		return
	if character_movement.is_moving():
		return
	if is_held_by_remote_talker():
		_face(_pending_face)
	_pending_face = Vector2.ZERO

@rpc("any_peer", "reliable")
func _end_talk() -> void:
	_remote_talkers.erase(multiplayer.get_remote_sender_id())

func _on_message_box_open(value: bool) -> void:
	if value or not _talking_locally:
		return
	_talking_locally = false
	if _is_remote_copy():
		animated_sprite.set("facing_override", Vector2.ZERO)
		if multiplayer.multiplayer_peer != null:
			_end_talk.rpc_id(1)

func _on_peer_disconnected(peer_id: int) -> void:
	_remote_talkers.erase(peer_id)
	if _remote_talkers.is_empty():
		_pending_face = Vector2.ZERO
