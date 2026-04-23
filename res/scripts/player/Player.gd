extends CharacterBody2D

signal attempt_connection(is_connecting: bool)

const CONNECTION_DISTANCE: float = 150.0

@export var player_speed: float = 120.0

var _is_holding: bool = false
var _is_connected: bool = false
var _hurt_tween: Tween = null
var _has_connected_once: bool = false
var _base_sprite_position: Vector2 = Vector2.ZERO
var _base_sprite_scale: Vector2 = Vector2.ONE
var _tower: CharacterBody2D = null

@onready var _hold_timer: Timer = %HoldTimer
@onready var _hint_label: Label = %HintLabel
@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if _hold_timer and not _hold_timer.timeout.is_connected(_on_hold_timeout):
		_hold_timer.timeout.connect(_on_hold_timeout)
	if _sprite != null:
		_base_sprite_position = _sprite.position
		_base_sprite_scale = _sprite.scale
	var tree := get_tree()
	var global_node: Node = null
	if tree != null and tree.root != null:
		global_node = tree.root.get_node_or_null("Global")
	if global_node != null and is_instance_valid(global_node) and global_node.has_signal("player_damaged") and not global_node.player_damaged.is_connected(_on_player_damaged):
		global_node.player_damaged.connect(_on_player_damaged)
	_hide_hint()


func _physics_process(_delta: float) -> void:
	var dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = dir * player_speed
	move_and_slide()
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_start_hold()
			else:
				_end_hold()
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event as InputEventScreenTouch
		if st.pressed:
			_try_start_hold()
		else:
			_end_hold()


func _update_hint() -> void:
	if _has_connected_once or _is_connected:
		_hide_hint()
		return

	var nearby_tower: CharacterBody2D = _get_nearby_tower()
	if nearby_tower:
		_show_hint("长按连接", Color(0.55, 0.95, 1.0, 1.0))
	else:
		_hide_hint()


func _get_nearby_tower() -> CharacterBody2D:
	if _tower == null or not is_instance_valid(_tower):
		var tree: SceneTree = get_tree()
		if tree != null:
			_tower = tree.get_first_node_in_group("tower") as CharacterBody2D

	if _tower == null or not is_instance_valid(_tower):
		return null

	var dist: float = global_position.distance_to(_tower.global_position)
	if dist >= CONNECTION_DISTANCE:
		return null
	return _tower


func _try_start_hold() -> void:
	var nearby: CharacterBody2D = _get_nearby_tower()
	if nearby:
		_is_holding = true
		_hold_timer.start()


func _end_hold() -> void:
	var should_disconnect: bool = _is_holding or _is_connected
	_is_holding = false
	_hold_timer.stop()

	if should_disconnect:
		_is_connected = false
		attempt_connection.emit(false)
		_hide_hint()


func _on_hold_timeout() -> void:
	if _is_holding and _get_nearby_tower():
		_is_connected = true
		_has_connected_once = true
		attempt_connection.emit(true)
		_hide_hint()


func _show_hint(text: String, color: Color) -> void:
	if _hint_label:
		_hint_label.text = text
		_hint_label.add_theme_color_override("font_color", color)
		_hint_label.visible = true


func _hide_hint() -> void:
	if _hint_label:
		_hint_label.visible = false


func _on_player_damaged(_amount: int) -> void:
	if _sprite == null:
		return

	if _hurt_tween:
		_hurt_tween.kill()

	_sprite.position = _base_sprite_position
	_sprite.scale = _base_sprite_scale
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_sprite, "scale", Vector2(_base_sprite_scale.x * 0.86, _base_sprite_scale.y * 1.12), 0.07)
	_hurt_tween.tween_property(_sprite, "position", _base_sprite_position + Vector2(-6.0, 2.0), 0.05)
	_hurt_tween.tween_property(_sprite, "position", _base_sprite_position, 0.08)
	_hurt_tween.parallel().tween_property(_sprite, "scale", _base_sprite_scale, 0.13)
