extends Node

# Maps a network-safe character id (the index) to its PackedScene. This is the single
# source of truth shared by every peer: the CharacterSelect buttons carry the id, the
# client sends the id to the server, and the server resolves it back to a scene here.
# Keep the ids in sync with the buttons' `character_id` in character_select.tscn.
const CHARACTERS: Array[PackedScene] = [
	preload("res://gameplay/entities/player/characters/Mimi.tscn"),  # 0: Mimi (default)
	preload("res://gameplay/entities/player/characters/Sisi.tscn"),  # 1: Sisi
	preload("res://gameplay/entities/player/characters/Riri.tscn"),  # 2: Riri
	preload("res://gameplay/entities/player/characters/Prannu.tscn"),  # 3: Prannu
	preload("res://gameplay/entities/player/characters/Rara.tscn"),  # 4: Rara
]

const DEFAULT_ID: int = 0  # Mimi

func count() -> int:
	return CHARACTERS.size()

func is_valid_id(character_id: int) -> bool:
	return character_id >= 0 and character_id < CHARACTERS.size()

func get_scene(character_id: int) -> PackedScene:
	if not is_valid_id(character_id):
		return CHARACTERS[DEFAULT_ID]
	return CHARACTERS[character_id]
