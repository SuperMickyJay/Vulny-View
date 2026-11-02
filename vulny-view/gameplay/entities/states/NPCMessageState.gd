extends State

func _ready() -> void:
	# Only the NPC that was being talked to (the one in Message) returns to Roam;
	# the signal is global, so without this every NPC would be re-entered into Roam.
	Events.message_box_open.connect(
		func(value: bool):
			if !value and state_machine.current_state == self:
				state_machine.change_state("Roam")
	)
