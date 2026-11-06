extends AnimatedSprite2D
class_name CharacterAnimation

const YIPPIE_ANIMATION := &"yippie"

@export var character_input: CharacterInput
@export var character_movement: CharacterMovement

@onready var sprite: AnimatedSprite2D = $"."
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $"../AudioStreamPlayer2D"

var character_animation: CharacterAnimations.character_animations

# Remote copies only: when non-zero, idle animation uses this facing instead of
# sync_facing. A client sets it while talking to a server-owned NPC so the NPC faces
# it at once, without flicking back before the server's turn replicates.
var facing_override: Vector2 = Vector2.ZERO

# Seconds of yippie left to play, and the sprite's resting height to bounce from.
var _yippie_time_left: float = 0.0
var _rest_y: float

func _ready() -> void:
	character_movement.animation_event_handler.connect(play_animation)
	_rest_y = position.y
	frame_changed.connect(_update_yippie_bounce)
	animation_changed.connect(_update_yippie_bounce)

func _process(delta: float) -> void:
	_tick_yippie(delta)

	if GameManager._session.is_multiplayer:
		# Pure remote copies never receive the local movement events, so derive their
		# animation from the replicated sync mirror. Simulating peers (server, owning
		# client, solo) run the movement and keep using the event-driven path above.
		if character_movement.simulate_only_on_authority and not character_movement.is_simulating():
			_apply_state_animation()

# Plays the yippie dance for this many seconds. Skipped for a character without the
# animation, and mid-step (the walk cycle keeps playing). Any new walk or turn animation
# replaces it, because both animation paths only call play() when their animation changes.
func play_yippie(duration: float) -> void:
	if not sprite_frames.has_animation(YIPPIE_ANIMATION):
		return
	if character_movement.is_moving() or character_movement.sync_walking:
		return
	_yippie_time_left = duration
	play(YIPPIE_ANIMATION)

func _tick_yippie(delta: float) -> void:
	if _yippie_time_left <= 0.0:
		return
	_yippie_time_left -= delta
	if _yippie_time_left <= 0.0 and animation == YIPPIE_ANIMATION:
		play(get_enum_name(character_animation, CharacterAnimations.character_animations))

# Hops the sprite up one pixel on every second yippie frame and back down on the next.
# Only the sprite moves: the character's position stays on the grid.
func _update_yippie_bounce() -> void:
	var hopping := animation == YIPPIE_ANIMATION and frame % 2 == 1
	if hopping:
		position.y = _rest_y - 1.0 
		if audio_stream_player_2d:
			audio_stream_player_2d.play()
	else:
		position.y = _rest_y

func _apply_state_animation() -> void:
	var direction: Vector2 = character_movement.sync_facing
	if facing_override != Vector2.ZERO and not character_movement.sync_walking:
		direction = facing_override
	var previous_animation := character_animation

	if character_movement.sync_walking:
		if direction == Vector2.UP:
			character_animation = CharacterAnimations.character_animations.walk_up
		elif direction == Vector2.DOWN:
			character_animation = CharacterAnimations.character_animations.walk_down
		elif direction == Vector2.LEFT:
			character_animation = CharacterAnimations.character_animations.walk_left
		elif direction == Vector2.RIGHT:
			character_animation = CharacterAnimations.character_animations.walk_right
	else:
		if direction == Vector2.UP:
			character_animation = CharacterAnimations.character_animations.idle_up
		elif direction == Vector2.DOWN:
			character_animation = CharacterAnimations.character_animations.idle_down
		elif direction == Vector2.LEFT:
			character_animation = CharacterAnimations.character_animations.idle_left
		elif direction == Vector2.RIGHT:
			character_animation = CharacterAnimations.character_animations.idle_right

	if previous_animation != character_animation:
		sprite.play(get_enum_name(character_animation, CharacterAnimations.character_animations))

func get_enum_name(enum_value: int, enum_type: Variant) -> String:
	return enum_type.keys()[enum_type.values().find(enum_value)]

func play_animation(animation_type: String) -> void:
	var previous_animation := character_animation
	
	if character_movement.is_moving():
		return
	
	match animation_type:
		"walk":
			if character_input.direction == Vector2.UP:
				character_animation = CharacterAnimations.character_animations.walk_up
			elif character_input.direction == Vector2.DOWN:
				character_animation = CharacterAnimations.character_animations.walk_down
			elif character_input.direction == Vector2.LEFT:
				character_animation = CharacterAnimations.character_animations.walk_left
			elif character_input.direction == Vector2.RIGHT:
				character_animation = CharacterAnimations.character_animations.walk_right
		"turn":
			if character_input.direction == Vector2.UP:
				character_animation = CharacterAnimations.character_animations.turn_up
			elif character_input.direction == Vector2.DOWN:
				character_animation = CharacterAnimations.character_animations.turn_down
			elif character_input.direction == Vector2.LEFT:
				character_animation = CharacterAnimations.character_animations.turn_left
			elif character_input.direction == Vector2.RIGHT:
				character_animation = CharacterAnimations.character_animations.turn_right
		"idle":
			if character_input.direction == Vector2.UP:
				character_animation = CharacterAnimations.character_animations.idle_up
			elif character_input.direction == Vector2.DOWN:
				character_animation = CharacterAnimations.character_animations.idle_down
			elif character_input.direction == Vector2.LEFT:
				character_animation = CharacterAnimations.character_animations.idle_left
			elif character_input.direction == Vector2.RIGHT:
				character_animation = CharacterAnimations.character_animations.idle_right
				
	if previous_animation != character_animation:
		sprite.play(get_enum_name(character_animation, CharacterAnimations.character_animations))
