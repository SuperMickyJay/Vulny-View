extends State

@export var player_input: PlayerInput
@export var character_movement: CharacterMovement
@export var emote_container: EmoteContainer

# Server-side memory of the last synced wish_direction, used to reconstruct
# press/release edges from the continuously-replicated held-direction state.
var prev_wish_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	if player_input.direction == Vector2.ZERO:
		player_input.direction = Vector2.DOWN

	# Dialogue is local to this peer, so only the LOCAL player enters Message. Every
	# player node hears this global signal — on the host that includes every client's
	# server-simulated body, and switching those out of Roam would stop the server
	# moving everyone while the host reads a sign.
	Events.message_box_open.connect(
		func(value: bool):
			if value and state_owner == GameManager._player:
				state_machine.change_state("Message")
	)

# Leaving Roam (e.g. into dialogue) stops capture_input, which would otherwise leave
# the last held direction in the replicated wish_direction — the server would keep
# walking this player for the whole conversation. Drop it to "nothing held", and run
# one simulate tick locally so this client handles that release exactly as the server
# will (same release edge, same prev_wish_direction), keeping its prediction in step.
func exit_state() -> void:
	var owns_input := not GameManager._session.is_multiplayer or Modules.is_authority(player_input)
	if owns_input and player_input.wish_direction != Vector2.ZERO:
		player_input.wish_direction = Vector2.ZERO
		simulate(0.0)

func _process(_delta: float) -> void:
	# Edge-triggered actions (interact / emote) are polled on the idle frame so they
	# stay responsive; they run only for the owning client (local-only in scope).
	# Skipped while typing in chat or paused: these actions are polled, so keys fire.
	if _input_blocked():
		return
	if GameManager._session.is_multiplayer:
		if Modules.is_authority(player_input):
			get_interact_input()
			get_emote_input()
	else:
		get_interact_input()
		get_emote_input()

func _physics_process(delta: float) -> void:
	# Movement runs on the fixed timestep. Two independently-gated halves:
	#  - the owning client CAPTURES its intent into the synced wish_direction AND
	#    simulates locally (client-side prediction) so its own player responds with
	#    no round-trip lag,
	#  - the server (body authority) SIMULATES the authoritative copy from that
	#    synced intent and replicates it back for reconciliation.
	# On the host both halves are the same peer (id 1 == server), so it simulates
	# once. CharacterMovement reconciles the client's prediction against the server.
	if GameManager._session.is_multiplayer:
		if Modules.is_authority(player_input):
			capture_input()
		if Modules.is_authority(player_input) or Modules.is_authority(state_owner):
			simulate(delta)
	else:
		capture_input()
		simulate(delta)

# --- Client side: pure intent, replicated to the server ---------------------

func capture_input() -> void:
	# While this player is mid area-transition, publish no intent so the server stops
	# stepping it behind the faded-out screen. changing_area is per-player and set on
	# the owning client for the fade's duration by SceneRouter.transition_to_area.
	# Likewise while typing in chat or paused, so WASD / arrow keys don't walk the player.
	if (state_owner as Player).changing_area or _input_blocked():
		player_input.wish_direction = Vector2.ZERO
		return

	# Continuously-held direction (ZERO = nothing held). The server reconstructs
	# taps, holds and turns from changes to this value, so no events/timers here.
	var held := Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		held = Vector2.UP
	elif Input.is_action_pressed("move_down"):
		held = Vector2.DOWN
	elif Input.is_action_pressed("move_left"):
		held = Vector2.LEFT
	elif Input.is_action_pressed("move_right"):
		held = Vector2.RIGHT

	player_input.wish_direction = held

# The local player's input is ignored while typing in chat, or while the pause menu
# is open (in multiplayer the game keeps running behind it — see Session.set_paused).
func _input_blocked() -> bool:
	return GameManager.chat_open or GameManager._session.is_paused

# --- Simulation from synced intent (server: authoritative; owning client: prediction) ---

func simulate(delta: float) -> void:
	var wish := player_input.wish_direction

	var direction_changed := wish != Vector2.ZERO and wish != prev_wish_direction
	var released := wish == Vector2.ZERO and prev_wish_direction != Vector2.ZERO
	var held := wish != Vector2.ZERO

	# A new/changed held direction updates facing, and if we were already facing that
	# way we step immediately.
	if direction_changed:
		var already_facing := player_input.direction == wish

		player_input.direction = wish
		character_movement.facing_direction = wish
		player_input.target_position = wish * Modules.GRID_SIZE

		if already_facing and not character_movement.is_moving():
			# Already facing this way: move immediately, even for a tap below the
			# hold threshold. Prime hold_time to the threshold so a sustained hold
			# keeps walking smoothly into the next tile instead of pausing.
			player_input.hold_time = player_input.hold_threshold
			player_input.emit_signal("walk_event_handler")

	# Tap-vs-hold decides turn vs walk.
	if not character_movement.is_moving():
		if released:
			if player_input.hold_time > player_input.hold_threshold:
				player_input.emit_signal("walk_event_handler")
			else:
				player_input.emit_signal("turn_event_handler")

		if held:
			player_input.hold_time += delta

			if player_input.hold_time > player_input.hold_threshold:
				player_input.emit_signal("walk_event_handler")

	# Reset the hold timer whenever no direction is held, regardless of movement
	# state, so a release swallowed during a walk can't leave hold_time stranded
	# above the threshold and turn later taps into walks.
	if not held:
		player_input.hold_time = 0.0

	prev_wish_direction = wish

# --- Local interact (dialogue text is local to this peer) -------------------

func get_interact_input() -> void:
	if Input.is_action_just_released("interact"):
		var facing := character_movement.facing_direction
		var data = Modules.get_target_colliders((facing * Modules.GRID_SIZE) + state_owner.position)

		for collision in data[1]:
			var collider = collision["collider"]

			if collider is Interactable:
				collider.play_message()
				break
			elif collider is NPC:
				collider.play_message(facing)
				break

func get_emote_input() -> void:
	# Every character scene wires an emote_container, but this shared state guards
	# against a future one added without it (null export) rather than crashing.
	if emote_container == null:
		return

	if Input.is_action_just_pressed("emote_one"):
		_request_emote("heart")
	if Input.is_action_just_pressed("emote_two"):
		_request_emote("smile")
	if Input.is_action_just_pressed("emote_three"):
		_request_emote("sad")
	if Input.is_action_just_pressed("emote_four"):
		_request_emote("yippie")

# The emote is cosmetic but still server-authoritative like the rest of the game:
# the owning client asks the server, which rebroadcasts it to everyone. Solo has no
# peer to RPC to, so it just plays locally.
func _request_emote(emote: String) -> void:
	if GameManager._session.is_multiplayer:
		emote_container.request_emote.rpc_id(1, emote)
	else:
		emote_container.play_emote(emote)
