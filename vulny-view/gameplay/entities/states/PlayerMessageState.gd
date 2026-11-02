extends State

func _ready() -> void:
	# Only the player actually in Message (the local one) returns to Roam.
	Events.message_box_open.connect(
		func(value: bool):
			if !value and state_machine.current_state == self:
				state_machine.change_state("Roam")
	)

func _process(_delta: float) -> void:
	# In multiplayer the game runs behind the pause menu; don't let Enter/Space on its
	# buttons also advance the dialogue.
	if GameManager._session.is_paused:
		return
	if !MessageManager.scrolling() and (Input.is_action_just_released("interact") or Input.is_action_just_released("cancel")):
		MessageManager.scroll_text()
