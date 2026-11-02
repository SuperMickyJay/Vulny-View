extends Control
class_name ChatBubble

# Overhead chat bubble. Lives under a player's EmoteAnchor (beside the EmoteContainer)
# and follows the same server-authoritative path as emotes: the owning client asks the
# server, which validates and rebroadcasts to every peer. Solo just shows it locally.
# Bubble and emote share the spot above the head, so showing one hides the other.

const MAX_LENGTH := 60           # characters per message
const MAX_TEXT_WIDTH := 140.0    # canvas px before the text wraps (~3 lines at max length)
const FONT_SIZE := 8
const MIN_INTERVAL := 1.0        # server-side rate limit per player, in seconds
const BASE_TIME := 3.0           # display time = base + per-char, capped
const PER_CHAR_TIME := 0.06
const MAX_TIME := 7.0

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Label
@onready var timer: Timer = $Timer

# Server-side: when this player last had a message accepted.
var _last_message_time: float = -INF

func _ready() -> void:
	hide()
	timer.timeout.connect(hide)

# Owning client: send a message to be shown over this player's head.
func say(text: String) -> void:
	text = sanitize(text)
	if text.is_empty():
		return
	if GameManager._session.is_multiplayer:
		request_say.rpc_id(1, text)
	else:
		show_message(text)

# Strips control characters (new lines, tabs, etc.), trims, and caps the length. Used
# on the client for the preview and again on the server, which never trusts the client.
static func sanitize(text: String) -> String:
	var clean := ""
	for character in text:
		var code := character.unicode_at(0)
		clean += " " if code < 32 or code == 127 else character
	return clean.strip_edges().left(MAX_LENGTH)

# Owning client -> server. call_local so the host (peer 1) can send it to itself.
@rpc("any_peer", "call_local", "reliable")
func request_say(text: String) -> void:
	if not is_multiplayer_authority():
		return
	# Only the player's own peer may speak through this bubble.
	var player := _player()
	if player == null or str(player.name).to_int() != multiplayer.get_remote_sender_id():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_message_time < MIN_INTERVAL:
		return
	text = sanitize(text)
	if text.is_empty():
		return
	_last_message_time = now
	show_message.rpc(text)

# Server -> all peers (call_local so the host shows it too). A plain Label is used, not
# a RichTextLabel, so players can't inject BBCode formatting.
@rpc("authority", "call_local", "reliable")
func show_message(text: String) -> void:
	label.text = text
	# Size to the text, wrapping only past MAX_TEXT_WIDTH.
	var font := label.get_theme_font("font")
	var text_width := ceilf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	label.custom_minimum_size.x = minf(text_width, MAX_TEXT_WIDTH)
	# Collapse the panel to zero; its minimum size regrows it upward and out to both
	# sides from the anchor point (grow_vertical = begin, grow_horizontal = both), so
	# the bubble stays centred above the head and shrinks for shorter messages.
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0

	var emote := get_parent().get_node_or_null("EmoteContainer") as Control
	if emote != null:
		emote.hide()

	show()
	timer.start(clampf(BASE_TIME + PER_CHAR_TIME * text.length(), BASE_TIME, MAX_TIME))

func _player() -> Player:
	var node := get_parent()
	while node != null and not node is Player:
		node = node.get_parent()
	return node as Player
