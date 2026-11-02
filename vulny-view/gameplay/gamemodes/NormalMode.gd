extends GameMode
class_name NormalMode

var world: World
var spawn_manager: SpawnManager

const SPAWN_MANAGER = preload("uid://md0le86iagyn")

signal setup_finished

func _ready() -> void:
	if not GameManager._session.is_multiplayer or NetworkManager.is_hosting_game:
		var spawn_manager_scene = SPAWN_MANAGER
		spawn_manager = spawn_manager_scene.instantiate()
		add_child(spawn_manager)

func setup_match(world_ref: World) -> void:
	world = world_ref
	await get_tree().create_timer(1.0).timeout
	emit_signal("setup_finished")

func add_player(network_id: int, character_id: int, spawn_tag := "default") -> void:
	spawn_manager.add_player(
		network_id,
		character_id,
		spawn_tag
	)

func remove_player(network_id: int) -> void:
	if spawn_manager:
		spawn_manager.release_character(network_id)
	world.remove_player(network_id)
