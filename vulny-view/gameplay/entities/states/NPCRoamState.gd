extends State

@export var npc_input: NPCInput
@export var character_movement: CharacterMovement

var timer: float = 2.0
var current_patrol_points: Array[Vector2] = []

func _process(delta: float) -> void:
	if GameManager._session.is_multiplayer:
		# NPCs are server-authoritative: only the server (or an offline host) decides
		# their movement, so the random wander/look-around choices are made in ONE place
		# and replicated. Clients just receive the sync_* mirror and interpolate/animate.
		if not Modules.is_authority(state_owner):
			return
		# A client is mid-dialogue with this NPC: hold still, facing the talker.
		if (state_owner as NPC).is_held_by_remote_talker():
			return

	if character_movement.is_moving():
		return

	match npc_input.npc_input_config.movement_type:
		NPCMovementTypes.npc_movement_type.WANDER:
			handle_wander(delta, npc_input.npc_input_config.wander_move_interval)
		NPCMovementTypes.npc_movement_type.LOOK_AROUND:
			handle_look_around(delta, npc_input.npc_input_config.look_around_interval)
		NPCMovementTypes.npc_movement_type.PATROL:
			handle_patrol(delta, npc_input.npc_input_config.patrol_move_interval)			
	
func handle_wander(delta: float, interval: float) -> void:
	timer = timer - delta
	
	if timer > 0:
		return
		
	var data: Array = get_new_directions()
	var direction: Vector2 = data[0]
	var target_position: Vector2 = data[1]
	
	npc_input.direction = direction
	npc_input.target_position = target_position
	
	npc_input.emit_signal("walk_event_handler")
	timer = interval
	
func handle_patrol(delta: float, interval: float) -> void:
	if npc_input.npc_input_config.patrol_points.size() == 0:
		return
	
	timer = timer - delta
	
	if timer > 0:
		return
		
	var current_position: Vector2 = (state_owner as NPC).position
	
	if current_patrol_points.size() == 0:
		var patrol_point: Vector2 = npc_input.npc_input_config.patrol_points[npc_input.npc_input_config.patrol_index]
		npc_input.npc_input_config.patrol_index = (npc_input.npc_input_config.patrol_index + 1) % npc_input.npc_input_config.patrol_points.size()
	
		var pathing = GameManager._world.active_level.get_grid().get_id_path(Modules.convert_vector2_to_vector2i(current_position), Modules.convert_vector2_to_vector2i(patrol_point))
		
		for i in range(1, pathing.size()):
			var point: Vector2i = pathing[i]
			current_patrol_points.append(Modules.convert_vector2i_to_vector2(point))
			
		GameManager._world.active_level.current_patrol_points = current_patrol_points
			
		if current_patrol_points.size() == 0:
			return
	
	if (state_owner as NPC).position.distance_to(current_patrol_points[0]) < 1.0:
		
		current_patrol_points.remove_at(0)
		return
		
	npc_input.target_position = current_patrol_points[0]
	GameManager._world.active_level.target_position = npc_input.target_position
	
	var difference: Vector2 = npc_input.target_position - current_position
	
	if abs(difference.x) > abs(difference.y):
		npc_input.direction = Vector2.RIGHT if difference.x > 0 else Vector2.LEFT
	else:
		npc_input.direction = Vector2.DOWN if difference.y > 0 else Vector2.UP
		
	npc_input.walk_event_handler.emit()
	timer = interval
	
func handle_look_around(delta: float, interval: float) -> void:
	timer = timer - delta
	
	if timer > 0:
		return
		
	var data: Array = get_new_directions()
	var direction: Vector2 = data[0]
	var target_position: Vector2 = data[1]
	
	if direction == npc_input.direction:
		timer = interval
		return
	
	npc_input.direction = direction
	npc_input.target_position = target_position
	
	npc_input.turn_event_handler.emit()
	timer = interval

func get_new_directions() -> Array[Vector2]:
	var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var chosen_direction: Vector2
	
	var tries: int = 0
	
	while tries < 10:
		chosen_direction = directions[randi_range(0, directions.size() - 1)]
		var next_position = character_movement.character.position + chosen_direction * Modules.GRID_SIZE
		
		if npc_input.npc_input_config.movement_type == NPCMovementTypes.npc_movement_type.WANDER:
			var distance_from_origin: float = next_position.distance_to(npc_input.npc_input_config.wander_origin)
			if distance_from_origin <= npc_input.npc_input_config.wander_radius:
				break
		else:
			break
			
		tries = tries + 1
		
	return [chosen_direction, chosen_direction * Modules.GRID_SIZE]
