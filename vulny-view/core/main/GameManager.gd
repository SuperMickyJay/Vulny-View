extends Node2D

var _player : Player
var _world: World
var _session: Session

# The character this peer picked in CharacterSelect, as a CharacterRegistry index.
# Defaults to 0 (Mimi). The client sends this to the server, which resolves it to a
# scene (and may reassign it to avoid duplicates).
var selected_character_id: int = 0

# True while the local player is typing in the chat bar (ui/chat/ChatInput.gd).
# PlayerRoamState ignores movement / interact / emote input while it's set.
var chat_open: bool = false

func set_selected_character(character_id: int) -> void:
	selected_character_id = character_id

func set_player(player: Player) -> void:
	_player = player
	
func set_world(world: World) -> void:
	_world = world
	
func set_session(session: Session) -> void:
	_session = session
