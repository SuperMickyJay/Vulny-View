extends Node
class_name CharacterInput

@export var direction: Vector2 = Vector2.ZERO
@export var target_position: Vector2 = Vector2.ZERO

# Currently-held movement direction (ZERO = nothing held). Written by the owning
# client and replicated client -> server via the input MultiplayerSynchronizer.
# The server reconstructs press/release/tap-vs-hold from changes to this value.
@export var wish_direction: Vector2 = Vector2.ZERO

signal walk_event_handler
signal turn_event_handler
