@tool

extends Resource
class_name NPCInputConfig

@export_group("Movement")
@export_subgroup("Common")
@export var movement_type: NPCMovementTypes.npc_movement_type = NPCMovementTypes.npc_movement_type.STATIC
@export var messages: Array[String]

@export_subgroup("Wander")
@export var wander_origin: Vector2 = Vector2.ZERO
@export var wander_radius: float = 64.0
@export var wander_move_interval: float = 2.0

@export_subgroup("Patrol")
@export var patrol_points: Array[Vector2]
@export var patrol_move_interval: float = 2.0
@export var patrol_index: int = 0

@export_subgroup("Look Around")
@export var look_around_interval: float = 2.0
