extends Marker2D
class_name SpawnPoint

@export var spawn_tag := "default"
# Direction the player faces on arrival at this spawn (ZERO = keep current facing).
@export var facing: Vector2 = Vector2.ZERO
