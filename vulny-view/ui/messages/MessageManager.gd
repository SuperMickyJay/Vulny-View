extends CanvasLayer
class_name MessageManager

static var instance: MessageManager

@export var box: NinePatchRect
@export var label: RichTextLabel
@export var is_scrolling: bool = false
@export var delay: int = 15
@export var messages: Array[String] = []

# Bumped by reset() so a scroll_text() still typing a line (it awaits per letter) can
# tell it has been cancelled and stop, instead of touching the cleared queue.
var _generation: int = 0

func _ready() -> void:
	instance = self

# Closes the box and clears all pending text without emitting message_box_open — used
# when the session ends mid-dialogue (quit to menu / disconnect), when the players and
# NPCs listening for that signal are being freed anyway.
static func reset() -> void:
	if instance == null:
		return
	instance._generation += 1
	instance.messages.clear()
	instance.is_scrolling = false
	instance.label.text = ""
	instance.box.visible = false

static func play_text(payload: Array[String]) -> void:
	if is_reading():
		return
		
	if payload.is_empty():
		return
		
	Events.message_box_open.emit(true)
		
	for text in payload:
		instance.messages.append(text)
		
	scroll_text()
	
static func is_reading() -> bool:
	return instance.box.visible

static func scroll_text() -> void:
	if !is_reading():
		instance.box.visible = true
		
	if instance.messages.size() == 0:
		instance.box.visible = false
		Events.message_box_open.emit(false)
		return
		
	instance.is_scrolling = true
	instance.label.text = ""
	var generation := instance._generation

	for letter in instance.messages[0]:
		instance.label.text += letter
		await instance.get_tree().create_timer(instance.delay / 1000.0).timeout
		if generation != instance._generation:
			return   # reset() mid-line: the queue is gone, stop typing

	instance.messages.remove_at(0)
	instance.is_scrolling = false
	
static func scrolling() -> bool:
	return instance.is_scrolling
