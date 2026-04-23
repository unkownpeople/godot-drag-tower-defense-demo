extends Node2D

var _tower: CharacterBody2D
var _player: CharacterBody2D
var _rope: Line2D
var _camera: Camera2D
var _shake_timer: float = 0.0
var _shake_intensity: float = 0.0


func _ready() -> void:
	_rope = Line2D.new()
	_rope.name = "RopeLine"
	_rope.width = 3.0
	_rope.joint_mode = Line2D.LINE_JOINT_ROUND
	_rope.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_rope.end_cap_mode = Line2D.LINE_CAP_ROUND
	_rope.default_color = Color(0.7, 0.7, 0.7, 1.0)
	_rope.z_index = -1
	_rope.visible = false
	add_child(_rope)

	_connect_signals()


func _connect_signals() -> void:
	_player = get_node_or_null("Player") as CharacterBody2D
	_tower = get_node_or_null("Tower") as CharacterBody2D
	_camera = get_node_or_null("Player/FollowCamera") as Camera2D
	var global_node: Node = get_node_or_null("/root/Global")

	if not _player:
		push_error("Main: Player not found")
	if not _tower:
		push_error("Main: Tower not found")
		return
	if _camera == null:
		push_warning("Main: FollowCamera not found")

	if _player and _tower and _player.has_signal("attempt_connection"):
		if not _player.attempt_connection.is_connected(_on_player_attempt_connection):
			_player.attempt_connection.connect(_on_player_attempt_connection)
	if global_node != null and is_instance_valid(global_node) and global_node.has_signal("screen_shake_requested"):
		if not global_node.screen_shake_requested.is_connected(_on_screen_shake_requested):
			global_node.screen_shake_requested.connect(_on_screen_shake_requested)


func _physics_process(delta: float) -> void:
	_update_rope()
	_update_screen_shake(delta)


func _update_rope() -> void:
	if not _rope or _tower == null or not is_instance_valid(_tower):
		return

	if not _tower.has_method("get_state"):
		return

	var state: int = _tower.get_state()
	_rope.visible = (state == 1)

	if not _rope.visible:
		return

	var player_node: Node2D = _player
	if player_node == null or not is_instance_valid(player_node):
		player_node = get_node_or_null("Player") as Node2D
		_player = player_node as CharacterBody2D
	if not player_node:
		return

	_rope.points = PackedVector2Array()
	_rope.add_point(_tower.global_position)
	_rope.add_point(player_node.global_position)

	match state:
		1:
			_rope.default_color = Color(1.0, 0.4, 0.2, 1.0)


func _on_player_attempt_connection(is_connecting: bool) -> void:
	if _tower != null and is_instance_valid(_tower) and _tower.has_method("on_attempt_connection"):
		_tower.on_attempt_connection(is_connecting)


func _on_screen_shake_requested(intensity: float, duration: float) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_timer = maxf(_shake_timer, duration)


func _update_screen_shake(delta: float) -> void:
	if _camera == null:
		return

	if _shake_timer <= 0.0:
		_camera.offset = Vector2.ZERO
		return

	_shake_timer = maxf(0.0, _shake_timer - delta)
	var offset: Vector2 = Vector2(
		randf_range(-_shake_intensity, _shake_intensity),
		randf_range(-_shake_intensity, _shake_intensity)
	)
	_camera.offset = offset

	if _shake_timer <= 0.0:
		_camera.offset = Vector2.ZERO
