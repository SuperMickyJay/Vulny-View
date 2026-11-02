extends AnimatedSprite2D

# Banner plane that flies right -> left across the screen (the plane is on the sprite's
# left end, towing the banner), bobbing gently, then wraps back off the right edge once
# it has fully left the screen. Drop it into any menu.
#
# Every BannerPlane shares ONE flight (the static vars below), so switching between
# menus that each have a plane carries on from the same spot instead of restarting.
# The first visible plane to process each frame advances the shared state; any other
# visible plane just mirrors it. The flight starts from the first plane's placed x.

@export var banner_speed: float = 30.0   # pixels per second
@export var bob_height: float = 2.0      # pixels above/below its resting height
@export var bob_speed: float = 0.5       # full up-down cycles per second

static var _x: float = NAN
static var _bob_time: float = 0.0
static var _anim_frame: int = 0
static var _anim_progress: float = 0.0
static var _last_tick: int = -1
static var _driver_id: int = 0

var _base_y: float

func _ready() -> void:
	_base_y = position.y

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	var tick := Engine.get_process_frames()
	if _last_tick != tick:
		# This plane drives the shared flight this frame.
		_last_tick = tick
		if is_nan(_x):
			_x = position.x
		if _driver_id != get_instance_id():
			# Just became the visible plane: pick up the propeller where the last one was.
			_driver_id = get_instance_id()
			set_frame_and_progress(_anim_frame, _anim_progress)
		_advance(delta)
		_anim_frame = frame
		_anim_progress = frame_progress
	else:
		set_frame_and_progress(_anim_frame, _anim_progress)

	position.x = _x
	# Gentle sine bob around this plane's authored height, rounded to whole pixels so
	# the pixel art stays crisp under integer scaling.
	position.y = _base_y + roundf(sin(_bob_time * TAU * bob_speed) * bob_height)

func _advance(delta: float) -> void:
	_x -= banner_speed * delta
	_bob_time += delta

	# Sprite is centred, so its right edge is x + half its width. Once that is past the
	# left edge, restart just beyond the right edge. Uses the live viewport width because
	# stretch aspect "expand" can make the screen wider than 320.
	var half_width := _width() / 2.0
	if _x + half_width < 0.0:
		_x = get_viewport_rect().size.x + half_width

func _width() -> float:
	return sprite_frames.get_frame_texture(animation, frame).get_width() * absf(scale.x)
