extends Node2D

# Debug overlay of the patrol pathfinding grid (red = solid, green = free, blue = the
# current patrol path, cyan = its next target). Off by default; tick it on the level
# root in the Inspector. Only draws once the grid exists (a PATROL NPC has pathed).
@export var debug_draw_grid: bool = false

@onready var spawn_points: Node2D = $SpawnPoints

var reserved_tiles: Dictionary = {}
# Pathfinding grid for PATROL NPCs. Built on first use via get_grid(), so levels with no
# patrollers (and every client — NPCs only path on the server) never pay for it.
var grid: AStarGrid2D
# Written by NPCRoamState's patrol for the debug overlay.
var target_position: Vector2 = Vector2.ZERO
var current_patrol_points: Array[Vector2] = []

# Drawn on its own high-z child: the level root draws BELOW its children, so drawing
# there would be hidden under the TileMapLayers.
var _debug_overlay: Node2D

func _process(_delta: float) -> void:
	if not debug_draw_grid or grid == null:
		return
	if _debug_overlay == null:
		_debug_overlay = Node2D.new()
		_debug_overlay.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		_debug_overlay.draw.connect(_draw_debug_grid)
		add_child(_debug_overlay)
	_debug_overlay.queue_redraw()

func get_grid() -> AStarGrid2D:
	if grid == null:
		setup_grid()
	return grid

func get_spawn_point_by_tag(entity: String, tag: String) -> SpawnPoint:
	for child in spawn_points.get_node(entity).get_children():
		if child.spawn_tag == tag:
			return child
			
	return null
	
func setup_grid() -> void:
	# The region is in CELLS and covers every painted tile in the level — the outside,
	# and each house floor laid out elsewhere on the canvas (some at negative x).
	var bounds := _tile_bounds()
	grid = AStarGrid2D.new()
	grid.region = bounds
	grid.cell_size = Vector2(Modules.GRID_SIZE, Modules.GRID_SIZE)
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()

	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell: Vector2i = Vector2i(x, y)
			var world_position: Vector2 = Vector2(x * Modules.GRID_SIZE, y * Modules.GRID_SIZE)
			
			var data: Array = Modules.get_target_colliders(world_position)
			
			for collision in data[1]:
				var collider = collision["collider"]
				
				if collider is Player:
					continue
				if collider is NPC:
					match collider.npc_input_config.movement_type:
						NPCMovementTypes.npc_movement_type.PATROL:
							continue
						NPCMovementTypes.npc_movement_type.WANDER:
							continue
			
				grid.set_point_solid(cell, true)

# Union of every TileMapLayer's painted area, as level-space grid cells. Read from the
# tiles themselves so it can't drift out of date as the map grows.
func _tile_bounds() -> Rect2i:
	var bounds := Rect2i()
	var first := true
	for layer in find_children("*", "TileMapLayer", true, false):
		var used: Rect2i = (layer as TileMapLayer).get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		# Top-left of the first and last used tiles in this level's space (map_to_local
		# gives a tile's centre), so layer/parent offsets like Tiles' (16, 32) count.
		var half := Vector2(Modules.GRID_SIZE, Modules.GRID_SIZE) / 2.0
		var top_left := to_local(layer.to_global(layer.map_to_local(used.position))) - half
		var bottom_right := to_local(layer.to_global(layer.map_to_local(used.end - Vector2i.ONE))) - half
		var cells := Rect2i(
			Vector2i(floori(top_left.x / Modules.GRID_SIZE), floori(top_left.y / Modules.GRID_SIZE)),
			Vector2i.ONE
		).expand(Vector2i(floori(bottom_right.x / Modules.GRID_SIZE) + 1, floori(bottom_right.y / Modules.GRID_SIZE) + 1))
		bounds = cells if first else bounds.merge(cells)
		first = false
	return bounds

func _draw_debug_grid() -> void:
	for y in range(grid.region.position.y, grid.region.end.y):
		for x in range(grid.region.position.x, grid.region.end.x):
			var cell := Vector2i(x, y)
			var color := Color(1, 0, 0, 0.35) if grid.is_point_solid(cell) else Color(0, 1, 0, 0.2)
			_debug_overlay.draw_rect(Rect2(Vector2(cell) * Modules.GRID_SIZE, grid.cell_size), color, true)

	for point in current_patrol_points:
		_debug_overlay.draw_rect(Rect2(point, grid.cell_size), Color(0, 0, 1, 0.5), true)

	if target_position != Vector2.ZERO:
		_debug_overlay.draw_rect(Rect2(target_position, grid.cell_size), Color(0, 1, 1, 0.6), true)

# reserved_tiles maps a tile position -> Array of the nodes currently reserving it.
# Multiple players may reserve the same tile (they can stack); an NPC reservation is
# exclusive, so a tile can never hold an NPC alongside anything else.
func reserve_tile(tile_position: Vector2, reserver: Node2D) -> bool:
	var reservers: Array = reserved_tiles.get(tile_position, [])

	if reserver is NPC:
		# NPCs need the tile to themselves — no players and no other NPCs.
		if not reservers.is_empty():
			return false
	else:
		# Players may share with other players, but never with an NPC.
		for other in reservers:
			if other is NPC:
				return false

	reservers.append(reserver)
	reserved_tiles[tile_position] = reservers
	return true

func release_tile(tile_position: Vector2, reserver: Node2D) -> void:
	if not reserved_tiles.has(tile_position):
		return

	var reservers: Array = reserved_tiles[tile_position]
	reservers.erase(reserver)

	if reservers.is_empty():
		reserved_tiles.erase(tile_position)
