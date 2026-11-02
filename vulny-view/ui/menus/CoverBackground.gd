extends AnimatedSprite2D

# Animated menu background that always fills its parent Control.
# A Node2D has no anchors, and stretch aspect "expand" makes the canvas wider/taller
# than 320x180 on non-16:9 phones, so this scales the sprite to COVER the parent and
# centres it — the same rule as a TextureRect's "keep aspect covered" stretch, so it
# lines up with a full-rect Foreground TextureRect using that mode.

func _ready() -> void:
	centered = true
	var parent := get_parent() as Control
	parent.resized.connect(_fit)
	_fit()

func _fit() -> void:
	var parent := get_parent() as Control
	var frame_size := Vector2(sprite_frames.get_frame_texture(animation, 0).get_size())
	var cover := maxf(parent.size.x / frame_size.x, parent.size.y / frame_size.y)
	scale = Vector2(cover, cover)
	position = parent.size / 2.0
