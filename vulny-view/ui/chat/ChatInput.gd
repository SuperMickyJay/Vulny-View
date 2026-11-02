extends Control

# HUD chat entry. A Chat button (or the "chat" key, T) opens a text bar at the TOP of
# the screen — the phone keyboard rises from the bottom, so it can never cover it.
# Send / Enter / the keyboard's Done says the text over the local player's head;
# X / Escape cancels.
#
# While open, GameManager.chat_open stops PlayerRoamState reading movement, interact
# and emotes (those actions are polled, so they'd otherwise fire while typing — e.g.
# WASD would walk). After closing, it stays set until interact/cancel are released,
# because Enter is bound to interact and Backspace to cancel.

@onready var chat_button: Button = $ChatButton
@onready var bar: PanelContainer = $Bar
@onready var line_edit: LineEdit = $Bar/HBox/LineEdit
@onready var send_button: Button = $Bar/HBox/SendButton
@onready var close_button: Button = $Bar/HBox/CloseButton

var _open: bool = false
var _waiting_for_release: bool = false

func _ready() -> void:
	bar.hide()
	line_edit.max_length = ChatBubble.MAX_LENGTH
	chat_button.pressed.connect(open_chat)
	send_button.pressed.connect(_send)
	close_button.pressed.connect(close_chat)
	line_edit.text_submitted.connect(func(_text: String) -> void: _send())

func open_chat() -> void:
	if _open or _local_bubble() == null:
		return
	_open = true
	_waiting_for_release = false
	GameManager.chat_open = true
	chat_button.hide()
	bar.show()
	line_edit.clear()
	line_edit.grab_focus()

func close_chat() -> void:
	if not _open:
		return
	_open = false
	line_edit.release_focus()
	bar.hide()
	chat_button.show()
	_waiting_for_release = true

func _send() -> void:
	var bubble := _local_bubble()
	if bubble != null:
		bubble.say(line_edit.text)
	close_chat()

func _local_bubble() -> ChatBubble:
	var player := GameManager._player
	if player == null or not is_instance_valid(player):
		return null
	return player.get_node_or_null("EmoteAnchor/ChatBubble") as ChatBubble

func _unhandled_input(event: InputEvent) -> void:
	# Reaches here only when no GUI control (e.g. the focused LineEdit) took the key.
	if not _open and is_visible_in_tree() and event.is_action_pressed("chat"):
		open_chat()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Escape closes the chat instead of opening the pause menu behind it.
	if _open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close_chat()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# The HUD hid (pause menu, back to the main menu): drop the half-typed message.
	if _open and not is_visible_in_tree():
		close_chat()
	if _waiting_for_release and not Input.is_action_pressed("interact") \
			and not Input.is_action_pressed("cancel"):
		_waiting_for_release = false
		GameManager.chat_open = false
