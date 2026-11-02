extends Node
class_name SceneRouter

@onready var transition_layer: CanvasLayer = $TransitionLayer

const SCENES := {
	"overworld": "uid://dgo440hq7nckx",
	"normal_mode": "uid://bl8nd1bhj3v7c",
}

func _ready() -> void:
	add_to_group("scene_router")
	
func transition_to_level(
	world: World,
	game_mode: GameMode,
	level_scene: PackedScene,
) -> void:
	await transition_layer.black_out()
	await world.load_level(level_scene)
	game_mode.setup_match(world)
	await game_mode.setup_finished
	transition_layer.fade_in()
	
func transition_to_area(
	player: Player,
	world: World,
	spawn_tag := "default"
) -> void:
	player.changing_area = true
	await transition_layer.fade_out()
	await world.transition_to_area(player, spawn_tag)
	await transition_layer.fade_in()
	player.changing_area = false
