extends Node

# Size of one grid tile in pixels. The single source of truth — use Modules.GRID_SIZE
# rather than redeclaring it.
const GRID_SIZE: int = 16

# Null-peer-safe authority check. Node.is_multiplayer_authority() calls get_unique_id()
# internally, which errors when there is no multiplayer peer — e.g. offline/solo, or a
# world loaded before a client has connected. Treat "no peer" as local authority.
func is_authority(node: Node) -> bool:
	if node.multiplayer.multiplayer_peer == null:
		return true
	return node.is_multiplayer_authority()

func convert_vector2_to_vector2i(vector: Vector2) -> Vector2i:
	# int() makes the float->int truncation explicit (world px -> grid cell), which
	# avoids the "narrowing conversion" warning from passing floats into Vector2i.
	return Vector2i(int(vector.x / GRID_SIZE), int(vector.y / GRID_SIZE))
	
func convert_vector2i_to_vector2(vector: Vector2i) -> Vector2:
	return Vector2(vector.x * GRID_SIZE, vector.y * GRID_SIZE)

func get_target_colliders(target_world_position: Vector2) -> Array:
	var space_state = get_viewport().get_world_2d().direct_space_state
	
	var adjusted_target_position = target_world_position
	adjusted_target_position.x += 8
	adjusted_target_position.y += 8
	
	var query := PhysicsPointQueryParameters2D.new()
	query.position = adjusted_target_position
	query.collision_mask = 1
	query.collide_with_areas = true
	
	return [adjusted_target_position, space_state.intersect_point(query)]
