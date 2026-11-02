extends Node
class_name StateMachine

@export var customer: Node
@export var current_state: State

func _ready() -> void:
	for child in get_children():
		if child is State:
			var state: State = child
			state.state_owner = customer
			state.set_process(false)
			state.set_physics_process(false)

func change_state(new_state: Variant) -> void:
	var _state
	
	if new_state is String:
		_state = get_node(new_state)
	else:
		_state = new_state
		
	if current_state:
		current_state.exit_state()
		
	current_state = _state
	current_state.enter_state()
	
	for child in get_children():
		if child is State:
			var state: State = child
			state.set_process(child == current_state)
			state.set_physics_process(child == current_state)
