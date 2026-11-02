extends StaticBody2D
class_name Interactable

@export var messages: Array[String]
		
func play_message() -> void:
	MessageManager.play_text(messages)
