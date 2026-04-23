extends Label

const FLOAT_DURATION: float = 0.7
const FADE_DURATION: float = 0.3
const BASE_FONT_SIZE: int = 24
const CRITICAL_FONT_SIZE: int = 34

var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	top_level = true
	z_index = 200
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	_base_scale = scale


func setup(value: float, is_critical: bool, color: Color) -> void:
	text = str(int(round(value)))
	modulate = color

	var target_font_size: int = CRITICAL_FONT_SIZE if is_critical else BASE_FONT_SIZE
	add_theme_font_size_override("font_size", target_font_size)
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	add_theme_constant_override("outline_size", 6 if is_critical else 4)

	var size_multiplier: float = 1.5 if is_critical else 1.0
	_base_scale = Vector2.ONE * size_multiplier
	scale = Vector2.ZERO
	pivot_offset = size * 0.5

	var start_position: Vector2 = global_position
	var target_position: Vector2 = start_position + Vector2(
		randf_range(-18.0, 18.0),
		randf_range(-70.0, -52.0)
	)
	var mid_position: Vector2 = start_position.lerp(target_position, 0.55) + Vector2(
		randf_range(-10.0, 10.0),
		randf_range(-12.0, -4.0)
	)

	var move_tween: Tween = create_tween()
	move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(self, "global_position", mid_position, FLOAT_DURATION * 0.45)
	move_tween.tween_property(self, "global_position", target_position, FLOAT_DURATION * 0.55)

	var scale_tween: Tween = create_tween()
	scale_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self, "scale", _base_scale * 1.2, 0.14)
	scale_tween.tween_property(self, "scale", _base_scale, 0.18)

	var fade_tween: Tween = create_tween()
	fade_tween.tween_interval(maxf(0.0, FLOAT_DURATION - FADE_DURATION))
	fade_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	fade_tween.tween_callback(queue_free)
