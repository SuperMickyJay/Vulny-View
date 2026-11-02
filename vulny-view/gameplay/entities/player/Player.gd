extends CharacterBody2D
class_name Player

@onready var camera: Camera2D = $Camera

@export var state_machine: StateMachine

# True while THIS player is mid area-transition (door/fade). Per-player and local to
# the owning client, so one player's transition never freezes anyone else. Set by
# SceneRouter.transition_to_area; read by PlayerRoamState (freeze intent) and
# SceneTrigger (block re-entry).
var changing_area: bool = false

func _ready() -> void:
	state_machine.change_state(state_machine.get_node("Roam"))
	add_to_group("player")

	if GameManager._session.is_multiplayer:
		# Only the peer that owns this player drives its camera and is treated as the
		# local player (GameManager._player drives dialogue and chat). Every other
		# player's camera is disabled on this peer.
		if str(name).to_int() == multiplayer.get_unique_id():
			camera.make_current()
			GameManager.set_player(self)
		else:
			camera.enabled = false
	else:
		camera.make_current()
		GameManager.set_player(self)

func _enter_tree() -> void:
	# The Input node — and, via recursion, its child input MultiplayerSynchronizer —
	# is owned by the peer whose id equals this player's name, so that peer's input
	# intent replicates to the server. The body/root stays server-owned (peer 1) by
	# default so the server simulates movement. $Input is used instead of the
	# @onready `input` var because @onready assignments haven't run yet in _enter_tree.
	$Input.set_multiplayer_authority(str(name).to_int())
