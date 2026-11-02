extends Area2D

@export var spawn_tag := "front_door_interior"

@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	# body_entered passes any physics body (walls/tilemaps included), so accept the
	# signal's real Node2D type and filter to players — a stricter param type makes
	# Godot fail to convert a non-CharacterBody2D body ("Cannot convert Object to Object").
	if not body.is_in_group("player"):
		return

	var player := body as Player

	if GameManager._session.is_multiplayer:
		# The trigger's Area2D and the replicated player body exist on EVERY peer, so
		# body_entered fires on all of them. Only act for the peer that actually controls
		# this player — its Input subtree's multiplayer authority is that client's id
		# (the body/root itself is server-owned). This keeps the fade on the walking
		# player's client alone, instead of playing on every connected peer.
		if not Modules.is_authority(player.get_node("Input")):
			return

	# Guard against re-entry while this player's transition is already running (e.g.
	# if the destination spawn happens to sit on top of another trigger).
	if player.changing_area:
		return

	var world := get_tree().get_first_node_in_group("world")
	var scene_router := get_tree().get_first_node_in_group("scene_router")

	scene_router.transition_to_area(player, world, spawn_tag)

	audio_stream_player.play()
