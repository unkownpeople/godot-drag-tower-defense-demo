extends Node

const BOSS_PREPRESSURE_WAVE_INDEX: int = 5
const BOSS_WAVE_INDEX: int = 6
const SPAWN_RING_MIN_DISTANCE: float = 420.0
const SPAWN_RING_MAX_DISTANCE: float = 560.0
const FORWARD_BIAS_CHANCE: float = 0.7
const FRONT_HALF_RING_SPREAD: float = PI * 0.5
const SIDE_PRESSURE_SPREAD: float = PI * 0.22
const SPAWN_HINT_TEXTURE: Texture2D = preload("res://res/meis/敌人出现位置.png")

@export var spawn_interval: float = 12.0
@export var min_enemies_per_wave: int = 3
@export var max_enemies_per_wave: int = 5
@export var spawn_margin: float = 100.0
@export var melee_enemy_scene_path: String = "res://res/scenes/EnemyMelee.tscn"
@export var ranged_enemy_scene_path: String = "res://res/scenes/EnemyRanged.tscn"
@export var boss_enemy_scene_path: String = "res://res/scenes/EnemyBoss.tscn"
@export var wave_duration: float = 40.0
@export var cleanup_duration: float = 4.0

var current_wave: int = 0
var game_time: float = 0.0

var _spawn_timer: Timer = null
var _melee_enemy_scene: PackedScene = null
var _ranged_enemy_scene: PackedScene = null
var _boss_enemy_scene: PackedScene = null
var _player: Node2D = null
var _tower: Node2D = null
var _screen_size: Vector2 = Vector2(1280, 720)
var _initialized: bool = false
var _wave_elapsed: float = 0.0
var _cleanup_elapsed: float = 0.0
var _wave_active: bool = false
var _boss_wave_started: bool = false
var _wave_spawn_target: int = 0
var _wave_spawned_count: int = 0
var _wave_spawn_events_total: int = 0
var _wave_spawn_events_used: int = 0
var _current_wave_duration: float = 40.0


func _ready() -> void:
	_initialize_spawner()


func _process(delta: float) -> void:
	if not _initialized:
		return

	game_time += delta

	if _wave_active:
		_wave_elapsed += delta
		if current_wave == BOSS_WAVE_INDEX and not _boss_wave_started:
			_boss_wave_started = true
			_spawn_boss_wave()
			_stop_spawn_timer()

		if _wave_elapsed >= _current_wave_duration:
			_end_current_wave()
	else:
		_cleanup_elapsed += delta
		if _cleanup_elapsed >= cleanup_duration:
			_start_next_wave()


func _initialize_spawner() -> void:
	await get_tree().process_frame

	_screen_size = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	_cache_anchor_targets()

	_melee_enemy_scene = load(melee_enemy_scene_path) as PackedScene
	_ranged_enemy_scene = load(ranged_enemy_scene_path) as PackedScene
	_boss_enemy_scene = load(boss_enemy_scene_path) as PackedScene
	if _melee_enemy_scene == null:
		push_error("Spawner: Failed to load melee enemy scene: " + melee_enemy_scene_path)
		return
	if _ranged_enemy_scene == null:
		push_error("Spawner: Failed to load ranged enemy scene: " + ranged_enemy_scene_path)
		return
	if _boss_enemy_scene == null:
		push_error("Spawner: Failed to load boss enemy scene: " + boss_enemy_scene_path)
		return

	_spawn_timer = Timer.new()
	_spawn_timer.name = "SpawnTimer"
	_spawn_timer.wait_time = spawn_interval
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	_initialized = true
	_start_next_wave()


func _on_spawn_timer_timeout() -> void:
	if not _initialized or not _wave_active:
		return
	if current_wave == BOSS_WAVE_INDEX:
		return
	if _wave_spawn_events_used >= _wave_spawn_events_total:
		_stop_spawn_timer()
		return
	_spawn_wave_batch()


func _start_next_wave() -> void:
	current_wave += 1
	_wave_elapsed = 0.0
	_cleanup_elapsed = 0.0
	_wave_active = true
	_boss_wave_started = false
	_current_wave_duration = _get_wave_duration_for_current_wave()
	_wave_spawned_count = 0
	_wave_spawn_target = _get_enemy_count_for_current_wave()
	_wave_spawn_events_total = _get_spawn_events_for_current_wave()
	_wave_spawn_events_used = 0

	if current_wave == BOSS_WAVE_INDEX:
		_spawn_boss_wave()
		_boss_wave_started = true
		_stop_spawn_timer()
		return

	_spawn_wave_batch()
	if _spawn_timer != null:
		_spawn_timer.wait_time = _get_spawn_interval_for_current_wave()
		if _wave_spawn_events_total > 1:
			_spawn_timer.start()
		else:
			_stop_spawn_timer()


func _end_current_wave() -> void:
	_wave_active = false
	_cleanup_elapsed = 0.0
	_stop_spawn_timer()


func _spawn_wave_batch() -> void:
	if _melee_enemy_scene == null and _ranged_enemy_scene == null and _boss_enemy_scene == null:
		return
	if _wave_spawned_count >= _wave_spawn_target:
		_stop_spawn_timer()
		return

	_cache_anchor_targets()
	var enemy_count: int = _get_spawn_count_for_next_batch()
	if enemy_count <= 0:
		_stop_spawn_timer()
		return
	_wave_spawn_events_used += 1

	if current_wave == BOSS_PREPRESSURE_WAVE_INDEX:
		_spawn_boss_prep_pressure_batch(enemy_count)
	else:
		for i in range(enemy_count):
			var spawn_pos: Vector2 = _get_spawn_position()
			var enemy_role: int = _pick_enemy_role_for_wave()
			_show_spawn_hint(spawn_pos)
			_spawn_enemy(spawn_pos, enemy_role)
			_wave_spawned_count += 1

	if _wave_spawned_count >= _wave_spawn_target or _wave_spawn_events_used >= _wave_spawn_events_total:
		_stop_spawn_timer()


func _spawn_boss_wave() -> void:
	_cache_anchor_targets()
	var spawn_pos: Vector2 = _get_spawn_position()
	_show_spawn_hint(spawn_pos, 0.75)
	_spawn_enemy(spawn_pos, 2)


func _spawn_boss_prep_pressure_batch(enemy_count: int) -> void:
	var left_count: int = int(ceil(float(enemy_count) * 0.5))
	var right_count: int = enemy_count - left_count

	for i in range(left_count):
		var left_spawn := _get_side_pressure_spawn_position(Vector2.LEFT)
		_show_spawn_hint(left_spawn)
		_spawn_enemy(left_spawn, 0)
		_wave_spawned_count += 1

	for i in range(right_count):
		var right_spawn := _get_side_pressure_spawn_position(Vector2.RIGHT)
		_show_spawn_hint(right_spawn)
		_spawn_enemy(right_spawn, 1)
		_wave_spawned_count += 1


func _cache_anchor_targets() -> void:
	var tree := get_tree()
	if tree == null:
		return

	_player = tree.get_first_node_in_group("player") as Node2D
	_tower = tree.get_first_node_in_group("tower") as Node2D


func _get_spawn_position() -> Vector2:
	_cache_anchor_targets()
	if _player == null and _tower == null:
		return _get_random_screen_edge()

	var forward_direction := _get_forward_bias_direction()
	var use_front_half: bool = randf() < FORWARD_BIAS_CHANCE
	var base_direction := forward_direction if use_front_half else -forward_direction
	return _get_ring_spawn_position_from_direction(base_direction, FRONT_HALF_RING_SPREAD)


func _get_side_pressure_spawn_position(side_direction: Vector2) -> Vector2:
	return _get_ring_spawn_position_from_direction(side_direction.normalized(), SIDE_PRESSURE_SPREAD)


func _get_ring_spawn_position_from_direction(base_direction: Vector2, spread: float) -> Vector2:
	var center := _get_combat_center()
	if center == Vector2.ZERO and _player == null and _tower == null:
		return _get_random_screen_edge()

	var direction := base_direction
	if direction.length_squared() <= 0.001:
		direction = Vector2.RIGHT.rotated(randf() * TAU)
	var final_direction := direction.rotated(randf_range(-spread, spread)).normalized()
	var distance := randf_range(SPAWN_RING_MIN_DISTANCE, SPAWN_RING_MAX_DISTANCE)
	return center + final_direction * distance


func _get_combat_center() -> Vector2:
	if is_instance_valid(_player) and is_instance_valid(_tower):
		return (_player.global_position + _tower.global_position) * 0.5
	if is_instance_valid(_player):
		return _player.global_position
	if is_instance_valid(_tower):
		return _tower.global_position
	return Vector2.ZERO


func _get_forward_bias_direction() -> Vector2:
	if is_instance_valid(_player) and is_instance_valid(_tower):
		var tower_to_player := _tower.global_position.direction_to(_player.global_position)
		if tower_to_player.length_squared() > 0.001:
			return tower_to_player
	if is_instance_valid(_player):
		return Vector2.UP
	return Vector2.RIGHT


func _get_random_screen_edge() -> Vector2:
	var center: Vector2 = _screen_size / 2.0
	var margin: float = spawn_margin

	var edge: int = randi() % 4
	if edge == 0:
		return Vector2(-center.x - margin, randf_range(-center.y, center.y))
	if edge == 1:
		return Vector2(center.x + margin, randf_range(-center.y, center.y))
	if edge == 2:
		return Vector2(randf_range(-center.x, center.x), -center.y - margin)
	return Vector2(randf_range(-center.x, center.x), center.y + margin)


func _spawn_enemy(pos: Vector2, enemy_role: int = 0) -> void:
	var enemy_scene := _get_scene_for_role(enemy_role)
	if enemy_scene == null:
		return

	var enemy: Node2D = enemy_scene.instantiate() as Node2D
	if enemy == null:
		return

	enemy.global_position = pos
	if get_parent():
		get_parent().add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)


func _get_scene_for_role(enemy_role: int) -> PackedScene:
	match enemy_role:
		1:
			return _ranged_enemy_scene if _ranged_enemy_scene != null else _melee_enemy_scene
		2:
			return _boss_enemy_scene if _boss_enemy_scene != null else _melee_enemy_scene
		_:
			return _melee_enemy_scene


func _pick_enemy_role_for_wave() -> int:
	if current_wave <= 2:
		return 0
	if current_wave == 3 and randf() < 0.22:
		return 1
	if current_wave == 4 and randf() < 0.35:
		return 1
	if current_wave == BOSS_PREPRESSURE_WAVE_INDEX and randf() < 0.45:
		return 1
	return 0


func _get_enemy_count_for_current_wave() -> int:
	match current_wave:
		1:
			return randi_range(6, 8)
		2:
			return randi_range(8, 10)
		3:
			return randi_range(10, 12)
		4:
			return randi_range(12, 16)
		5:
			return randi_range(6, 8)
		_:
			return randi_range(min_enemies_per_wave, max_enemies_per_wave)


func _get_spawn_events_for_current_wave() -> int:
	match current_wave:
		1:
			return 3
		2:
			return 4
		3:
			return 4
		4:
			return 5
		5:
			return 3
		_:
			return 1


func _get_spawn_interval_for_current_wave() -> float:
	match current_wave:
		1:
			return 4.5
		2:
			return 4.0
		3:
			return 4.0
		4:
			return 3.5
		5:
			return 3.0
		_:
			return spawn_interval


func _get_spawn_count_for_next_batch() -> int:
	var remaining_enemies: int = _wave_spawn_target - _wave_spawned_count
	var remaining_events: int = _wave_spawn_events_total - _wave_spawn_events_used
	if remaining_enemies <= 0 or remaining_events <= 0:
		return 0
	return int(ceil(float(remaining_enemies) / float(remaining_events)))


func _get_wave_duration_for_current_wave() -> float:
	match current_wave:
		1:
			return 20.0
		2:
			return 24.0
		3:
			return 34.0
		4:
			return 50.0
		5:
			return 22.0
		_:
			return wave_duration


func _stop_spawn_timer() -> void:
	if _spawn_timer != null:
		_spawn_timer.stop()


func _show_spawn_hint(pos: Vector2, duration: float = 0.4) -> void:
	if SPAWN_HINT_TEXTURE == null:
		return

	var parent_node := get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene
	if parent_node == null:
		return

	var hint := Sprite2D.new()
	hint.texture = SPAWN_HINT_TEXTURE
	hint.global_position = pos
	hint.scale = Vector2(0.18, 0.18)
	hint.z_index = -5
	parent_node.add_child(hint)

	var tween := hint.create_tween()
	tween.tween_property(hint, "scale", Vector2(0.28, 0.28), duration)
	tween.parallel().tween_property(hint, "modulate:a", 0.0, duration)
	tween.tween_callback(hint.queue_free)
