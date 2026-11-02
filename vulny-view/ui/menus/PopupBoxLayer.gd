extends CanvasLayer

@onready var label: Label = $Control/Label
@onready var button: Button = $Control/Button

const ELLIPSIS_INTERVAL := 0.4   # seconds between added dots
const MAX_DOTS := 3

# The message without any trailing dots; dots are appended by the animation.
var _base_text: String = ""
var _animate_ellipsis: bool = false
var _dot_count: int = 0
var _elapsed: float = 0.0

func _ready() -> void:
	button.pressed.connect(close)
	set_process(false)

# text is the message WITHOUT trailing dots. When animate_ellipsis is true, a cycling
# "" -> "." -> ".." -> "..." suffix is appended to hint that work is happening.
func show_message(text: String, show_close_button: bool, animate_ellipsis := false) -> void:
	_base_text = text
	_animate_ellipsis = animate_ellipsis
	_dot_count = 0
	_elapsed = 0.0
	button.visible = show_close_button
	_update_label()
	show()
	set_process(animate_ellipsis)

func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < ELLIPSIS_INTERVAL:
		return
	_elapsed -= ELLIPSIS_INTERVAL
	_dot_count = (_dot_count + 1) % (MAX_DOTS + 1)
	_update_label()

func _update_label() -> void:
	if _animate_ellipsis:
		label.text = _base_text + ".".repeat(_dot_count)
	else:
		label.text = _base_text

func close() -> void:
	set_process(false)
	hide()
