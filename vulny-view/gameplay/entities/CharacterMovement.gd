extends Node
class_name CharacterMovement

@export var character: Node2D
@export var character_input: CharacterInput
@export var target_position: Vector2 = Vector2.DOWN
@export var is_walking: bool = false
@export var facing_direction: Vector2 = Vector2.DOWN

# When true (set on the networked Player + NPC scenes), this movement is simulated
# on the body's multiplayer authority (the server) AND, for a player, predicted on
# its owning client (see is_simulating). Pure remote copies interpolate instead.
@export var simulate_only_on_authority: bool = false

# --- Networked authoritative mirror (server -> all) --------------------------
# The live fields above (position/is_walking/facing_direction) are simulated
# locally: on the server, on the owning client (client-side prediction) and in
# solo. Replicating them directly would clobber a predicting client, so the
# server's truth travels in these separate sync_* fields instead. Remote copies
# read them to interpolate + animate; the owning client reads them to reconcile.
@export var sync_position: Vector2 = Vector2.ZERO
@export var sync_walking: bool = false
@export var sync_facing: Vector2 = Vector2.DOWN

# Exponential rate at which a remote copy chases sync_position (higher = tighter).
const INTERP_RATE := 20.0
# Beyond this the copy hard-snaps instead of easing: spawn, area-transition
# teleport, first sync, or a hard client misprediction.
const SNAP_DISTANCE := 32.0   # 2 tile
const WALK_SPEED := 60.0

signal animation_event_handler(animation_type: String)

func _ready() -> void:
	character_input.walk_event_handler.connect(start_walking)
	character_input.turn_event_handler.connect(turn)
	# Seed the mirror to the current spot so a copy never eases toward (0,0) before
	# the first packet arrives (NPCs are placed pre-positioned on every peer).
	sync_position = character.position
	sync_facing = facing_direction

func _physics_process(delta: float) -> void:
	# Fixed timestep keeps stepping smooth and keeps the client's prediction and the
	# server's authoritative simulation in step.
	if not GameManager._session.is_multiplayer or not simulate_only_on_authority:
		walk(delta)
		return

	if is_simulating():
		walk(delta)
		if Modules.is_authority(character):
			_publish_state()   # server/host: mirror live state out to every peer
		else:
			_reconcile()       # owning client: correct its prediction against server
	else:
		_interpolate(delta)    # pure remote copy: ease toward the server's state

# Peers that actively run the movement simulation for this character: the server
# (body authority) authoritatively, the owning client (input authority) as a
# prediction, and solo. Everyone else is a passive remote copy that interpolates.
func is_simulating() -> bool:
	if not GameManager._session.is_multiplayer:
		return true
	return Modules.is_authority(character) or Modules.is_authority(character_input)

# Server-only: copy the live simulation into the replicated mirror.
func _publish_state() -> void:
	sync_position = character.position
	sync_walking = is_walking
	sync_facing = facing_direction

# Owning client: keep the predicted position honest against the server's.
func _reconcile() -> void:
	var drift := character.position.distance_to(sync_position)
	if drift > SNAP_DISTANCE:
		# Teleport / area change / hard misprediction — snap now, dropping any
		# in-flight predicted step (and its local tile reservation) cleanly.
		if is_walking:
			GameManager._world.active_level.release_tile(target_position, character)
		is_walking = false
		character.position = sync_position
		return
	# Otherwise only correct once both we and the server are at rest, so the normal
	# round-trip gap while a step is in flight doesn't rubber-band us.
	if not is_walking and not sync_walking and drift > 1.0:
		character.position = sync_position

# Pure remote copy: ease toward the replicated position (jitter-free), snapping
# only on big jumps (spawn / teleport / first sync).
func _interpolate(delta: float) -> void:
	if character.position.distance_to(sync_position) > SNAP_DISTANCE:
		character.position = sync_position
	else:
		character.position = character.position.lerp(sync_position, 1.0 - exp(-delta * INTERP_RATE))

func is_moving() -> bool:
	return is_walking

func is_target_occupied(target_world_position: Vector2) -> bool:
	var data = Modules.get_target_colliders(target_world_position)

	for collision in data[1]:
		var collider = collision["collider"]

		# Never block on our own body.
		if collider == character:
			continue

		if collider is NPC:
			# NPCs occupy a tile exclusively — they block players and other NPCs.
			return true
		elif collider is Player:
			# Players may share a tile with other players, but still block NPCs.
			if character is NPC:
				return true
			continue
		elif collider is TileMapLayer or collider is StaticBody2D:
			# Solid world geometry: walls, boundaries, signs.
			return true
		# Anything else (e.g. a SceneTrigger Area2D) is walkable.

	return false
	
func start_walking() -> void:
	# Never retarget mid-step: target_position is also the tile this step reserved, so
	# overwriting it would send the step off-grid and leak that reservation.
	if is_moving():
		return

	target_position = character.position + character_input.direction * Modules.GRID_SIZE

	if !is_target_occupied(target_position) and GameManager._world.active_level.reserve_tile(target_position, character):
		emit_signal("animation_event_handler", "walk")
		# Record facing so remote peers animate the correct walk direction (via sync_facing).
		facing_direction = character_input.direction
		is_walking = true
		
func walk(delta: float) -> void:
	if is_walking:
		character.position = character.position.move_toward(target_position, delta * WALK_SPEED)
		
		if character.position.is_equal_approx(target_position):
			stop_walking()
	else:
		emit_signal("animation_event_handler", "idle")
		
func stop_walking() -> void:
	GameManager._world.active_level.release_tile(target_position, character)
	is_walking = false
	snap_position_to_grid()
	
func turn() -> void:
	# Record facing so remote copies (players turning in place, look-around NPCs)
	# animate the new direction — the server mirrors it out via sync_facing.
	facing_direction = character_input.direction
	emit_signal("animation_event_handler", "turn")

func snap_position_to_grid() -> void:
	character.position = Vector2(
		roundf(character.position.x / Modules.GRID_SIZE) * Modules.GRID_SIZE,
		roundf(character.position.y / Modules.GRID_SIZE) * Modules.GRID_SIZE
	)
