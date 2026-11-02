extends TextureButton
class_name CharacterButton

# Network-safe id for this character (index into CharacterRegistry.CHARACTERS).
@export var character_id: int = 0

# Selection is driven by CharacterSelect (single-select across all buttons); hover is
# local. Both are drawn as a border in _draw(), so they never affect layout.
var _selected: bool = false
var _hovered: bool = false
var _taken: bool = false            # claimed by ANOTHER peer (lobby)

const HOVER_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.7)
const SELECTED_BORDER_COLOR := Color(1.0, 0.85, 0.2)  # gold
const HOVER_BORDER_WIDTH := 1.0
const SELECTED_BORDER_WIDTH := 2.0
const TAKEN_MODULATE := Color(0.35, 0.35, 0.35)       # greyed out

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	queue_redraw()

# Greys the button out and blocks clicks when another player owns this character.
func set_taken(value: bool) -> void:
	if _taken == value:
		return
	_taken = value
	disabled = value
	modulate = TAKEN_MODULATE if value else Color.WHITE
	queue_redraw()

func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()

func _draw() -> void:
	if _taken:
		return   # greyed out via modulate; no hover/selected border
	# Selection takes precedence over hover.
	if _selected:
		_draw_border(SELECTED_BORDER_COLOR, SELECTED_BORDER_WIDTH)
	elif _hovered:
		_draw_border(HOVER_BORDER_COLOR, HOVER_BORDER_WIDTH)

func _draw_border(color: Color, width: float) -> void:
	# Inset by half the width so the whole border stays inside the button's rect.
	var inset := width / 2.0
	draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), color, false, width)
