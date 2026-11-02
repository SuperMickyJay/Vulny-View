extends Control

## Touch controls are authored in the 320x180 base canvas, but with
## display/window/stretch/aspect = "expand" the canvas grows past that on phones
## whose aspect differs from 16:9 (the extra space is added at the right/bottom,
## the top-left origin stays fixed). The controls are Node2Ds (TouchScreenButtons
## and the D-pad arrow sprites) with no anchors, so the ones that should hug the
## right/bottom edges drift inward.
##
## This pins those controls to the LIVE viewport edges while preserving the margin
## each had from its edge in the 320x180 design. Left/top-measured axes (e.g. the
## D-pad's x) need no adjustment because that origin does not move.

const BASE := Vector2(320, 180)

# Per button, which edge each axis is measured from. "left"/"top" keep the design
# coordinate; "right"/"bottom" are re-measured from the current edge so the button
# tracks it. The emote buttons sit under the Menu button on the right edge.
const EDGES := {
	"Up":    {"x": "left",  "y": "bottom"},
	"Down":  {"x": "left",  "y": "bottom"},
	"Left":  {"x": "left",  "y": "bottom"},
	"Right": {"x": "left",  "y": "bottom"},
	"A":     {"x": "right", "y": "bottom"},
	"B":     {"x": "right", "y": "bottom"},
	"Menu":  {"x": "right", "y": "top"},
	"EmoteOne":   {"x": "right", "y": "top"},
	"EmoteTwo":   {"x": "right", "y": "top"},
	"EmoteThree": {"x": "right", "y": "top"},
	"EmoteFour":  {"x": "right", "y": "top"},
}

var _design: Dictionary = {}

func _ready() -> void:
	# Capture the authored (320x180) positions once, before we start moving things.
	for btn_name in EDGES:
		_design[btn_name] = (get_node(NodePath(btn_name)) as Node2D).position
	# resized fires on this full-rect Control whenever the canvas viewport changes.
	resized.connect(_apply_layout)
	_apply_layout()

func _apply_layout() -> void:
	# size is this full-rect Control's rect = the canvas viewport size, in the same
	# coordinate space as the child TouchScreenButton (Node2D) positions.
	for btn_name in EDGES:
		var button := get_node(NodePath(btn_name)) as Node2D
		var design: Vector2 = _design[btn_name]
		var edge: Dictionary = EDGES[btn_name]
		var pos := design

		if edge["x"] == "right":
			pos.x = size.x - (BASE.x - design.x)
		if edge["y"] == "bottom":
			pos.y = size.y - (BASE.y - design.y)

		button.position = pos

# --- Virtual D-pad ----------------------------------------------------------
# The arrows are visual-only Sprite2Ds; movement input is driven here so the pad
# behaves like a joystick. A touch that starts on the pad is captured and holds a
# cardinal direction chosen by the finger's angle from the pad centre (45-degree
# sectors). It keeps holding as the finger moves — even off the arrows — switching
# when it crosses a sector boundary, and only releases when the finger lifts.
# Keyboard bindings are unaffected.

# A touch must start within this radius of the pad centre to grab it.
const DPAD_CAPTURE_RADIUS := 48.0
# Inside this radius no direction change is made (avoids flicker at the centre).
const DPAD_DEADZONE := 6.0

var _dpad_touch: int = -1        # finger index currently driving the pad (-1 = none)
var _dpad_action: String = ""    # movement action currently held ("" = none)

# Pad centre in this Control's local space. The arrow layout is symmetric, so the
# centroid of the four arrow origins is the centre; recomputed live so it tracks
# the edge-anchoring done in _apply_layout.
func _dpad_centre() -> Vector2:
	return ($Up.position + $Down.position + $Left.position + $Right.position) * 0.25

# Uses _input (not _unhandled_input) so it runs before GUI consumption: this full-rect
# Control would otherwise swallow the pointer event in the GUI phase. Non-pad touches are
# left unhandled here, so the A/B/Menu/emote TouchScreenButtons still receive them.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# Grab a new touch only while the HUD is on-screen, so the pad never
			# swallows touches meant for a menu behind a hidden HUD.
			if _dpad_touch != -1 or not is_visible_in_tree():
				return
			var pos: Vector2 = (make_input_local(event) as InputEventScreenTouch).position
			if pos.distance_to(_dpad_centre()) <= DPAD_CAPTURE_RADIUS:
				_dpad_touch = event.index
				_update_dpad(pos)
				get_viewport().set_input_as_handled()
		elif event.index == _dpad_touch:
			# Always release the tracked finger, even if the HUD hid mid-hold, so the
			# direction can't stick and the pad can be grabbed again afterwards.
			_dpad_touch = -1
			_release_dpad()
	elif event is InputEventScreenDrag and event.index == _dpad_touch:
		_update_dpad((make_input_local(event) as InputEventScreenDrag).position)

func _update_dpad(pos: Vector2) -> void:
	var offset := pos - _dpad_centre()
	if offset.length() < DPAD_DEADZONE:
		return   # near the centre: keep the current direction rather than flicker
	# Dominant axis => 45-degree sectors.
	var action: String
	if absf(offset.x) > absf(offset.y):
		action = "move_right" if offset.x > 0.0 else "move_left"
	else:
		action = "move_down" if offset.y > 0.0 else "move_up"
	if action == _dpad_action:
		return
	_release_dpad()
	_dpad_action = action
	Input.action_press(action)

func _release_dpad() -> void:
	if _dpad_action != "":
		Input.action_release(_dpad_action)
		_dpad_action = ""
