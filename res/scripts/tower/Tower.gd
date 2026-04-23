extends CharacterBody2D


enum State { IDLE, DRAGGING, BUFF }

const DEFAULT_ATTACK_RANGE_FALLBACK: float = 266.67

@export var stats: TowerData
@export var bullet_scene_path: String = "res://res/scenes/Bullet.tscn"

const MAX_ROPE_LENGTH: int = 80
const DRAG_SPEED: float = 110.0
const DRAG_DECAY_RATE: float = 0.2
const BUFF_DURATION: float = 3.5
const DRAG_BUFF_RECOVERY_MULTIPLIER: float = 1.8
const MAX_DRAG_BUFF_BONUS: float = 0.45
const DEFAULT_ATTACK_SPEED: float = 0.75
const LONG_PRESS_THRESHOLD: float = 0.4
const MAX_HITS: int = 10
const WARNING_HITS: int = 7
const WARNING_SHAKE_STRENGTH: float = 2.5
const DROP_HITSTOP_SCALE: float = 0.5
const DROP_HITSTOP_DURATION: float = 0.1

const COLOR_IDLE: Color = Color(0.7, 0.7, 0.7, 1.0)
const COLOR_DRAGGING: Color = Color(1.0, 0.4, 0.2, 1.0)
const COLOR_BUFF: Color = Color(0.2, 1.0, 0.4, 1.0)
const COLOR_WARNING: Color = Color(1.0, 0.3, 0.3, 1.0)
const RANGE_IDLE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)
const RANGE_DRAGGING_COLOR: Color = Color(1.0, 0.62, 0.22, 0.7)
const RANGE_BUFF_COLOR: Color = Color(0.35, 1.0, 0.5, 0.58)

var _state: State = State.IDLE
var _base_attack_speed: float = DEFAULT_ATTACK_SPEED
var _current_attack_speed: float = DEFAULT_ATTACK_SPEED
var _drag_time: float = 0.0
var _last_drag_duration: float = 0.0
var _buff_time: float = 0.0
var _needs_singleton_sync: bool = true
var _combat_snapshot_dirty: bool = true

var _target: Node2D = null
var _bullet_scene: PackedScene = null

var _attack_range_area: Area2D = null
var _attack_shape: CollisionShape2D = null
var _shoot_timer: Timer = null
var _buff_timer: Timer = null
var _muzzle: Marker2D = null
var _sprite: Sprite2D = null
var _rope: Line2D = null
var _range_indicator: Sprite2D = null

var _base_damage: int = 0
var _base_attack_range: float = 0.0
var attack_range: float = 0.0
var _inventory_damage_bonus: float = 0.0
var _inventory_attack_speed_bonus: float = 0.0
var _inventory_range_bonus: float = 0.0
var _combo_state: Dictionary = {}
var hit_counter: int = 0

var _is_player_in_range: bool = false
var _is_player_connected: bool = false
var _mouse_press_time: float = 0.0
var _is_mouse_pressed: bool = false
var _long_press_triggered: bool = false
var _is_hovered: bool = false
var _base_sprite_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	if stats == null:
		push_error("TowerData 资源未挂载！")
		return

	_find_nodes()
	_initialize_tower_data()
	_setup_signals()
	_apply_state_color()
	_start_shoot_timer()


func _physics_process(delta: float) -> void:
	if _needs_singleton_sync:
		_try_initialize_singletons()

	_update_hover_state()
	_process_long_press(delta)

	match _state:
		State.IDLE:
			_process_idle()
		State.DRAGGING:
			_process_dragging(delta)
		State.BUFF:
			_process_buff(delta)

	_update_rope()
	_update_range_indicator()
	_update_damage_warning_feedback()

	if _combat_snapshot_dirty:
		_print_combat_snapshot()
		_combat_snapshot_dirty = false


func _find_nodes() -> void:
	_attack_range_area = $AttackRange as Area2D
	_attack_shape = $AttackRange/AttackShape as CollisionShape2D
	_shoot_timer = $ShootTimer as Timer
	_buff_timer = $BuffTimer as Timer
	_muzzle = $Muzzle as Marker2D
	_sprite = $Sprite2D as Sprite2D
	_rope = $Line2D as Line2D
	_range_indicator = $RangeIndicator as Sprite2D

	if _attack_range_area == null:
		push_error("Tower: AttackRange not found")
	if _attack_shape == null:
		push_error("Tower: AttackShape not found")
	if _shoot_timer == null:
		push_error("Tower: ShootTimer not found")
	if _buff_timer == null:
		push_error("Tower: BuffTimer not found")
	if _muzzle == null:
		push_error("Tower: Muzzle not found")
	if _sprite == null:
		push_error("Tower: Sprite2D not found")
	if _rope == null:
		push_error("Tower: Line2D not found")
	if _range_indicator == null:
		push_error("Tower: RangeIndicator not found")

	if _sprite != null:
		_base_sprite_position = _sprite.position

func _initialize_tower_data() -> void:
	_base_damage = stats.base_damage
	_base_attack_speed = stats.base_attack_speed
	_base_attack_range = _get_scene_attack_range()
	attack_range = _base_attack_range
	_current_attack_speed = _base_attack_speed
	_sync_range_indicator_to_scene_shape()


func _setup_signals() -> void:
	if _attack_range_area != null:
		if not _attack_range_area.body_entered.is_connected(_on_attack_range_body_entered):
			_attack_range_area.body_entered.connect(_on_attack_range_body_entered)
		if not _attack_range_area.body_exited.is_connected(_on_attack_range_body_exited):
			_attack_range_area.body_exited.connect(_on_attack_range_body_exited)

	if _buff_timer != null and not _buff_timer.timeout.is_connected(_on_buff_timeout):
		_buff_timer.timeout.connect(_on_buff_timeout)

	if _shoot_timer != null and not _shoot_timer.timeout.is_connected(_on_shoot_timer_timeout):
		_shoot_timer.timeout.connect(_on_shoot_timer_timeout)


func _start_shoot_timer() -> void:
	if _shoot_timer == null:
		return
	_shoot_timer.one_shot = true
	_schedule_next_shot()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				if _is_pointer_over_tower(mouse_event.position):
					_on_mouse_pressed()
			else:
				if _is_mouse_pressed or _state == State.DRAGGING:
					_on_mouse_released()


func _process_long_press(delta: float) -> void:
	if _state != State.IDLE:
		return
	if not _is_mouse_pressed or _long_press_triggered:
		return
	if not _is_player_in_range:
		return

	_mouse_press_time += delta
	if _mouse_press_time >= LONG_PRESS_THRESHOLD:
		_long_press_triggered = true
		_establish_connection()


func _process_idle() -> void:
	var current_stats: Dictionary = _get_inventory_stats()
	var next_attack_speed: float = float(current_stats.get("final_attack_speed", _get_effective_base_attack_speed()))
	_set_current_attack_speed(next_attack_speed)
	if _attack_range_area != null:
		_attack_range_area.monitoring = true


func _process_dragging(delta: float) -> void:
	if not _is_player_connected:
		_set_state(State.IDLE)
		return

	var player: Node2D = _get_connected_player()
	if player == null:
		_is_player_connected = false
		_set_state(State.IDLE)
		return

	var distance_to_player: float = global_position.distance_to(player.global_position)
	var direction_to_player: Vector2 = global_position.direction_to(player.global_position)

	if distance_to_player > MAX_ROPE_LENGTH:
		velocity = direction_to_player * DRAG_SPEED
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	_drag_time += delta
	var drag_attack_speed: float = maxf(_get_effective_base_attack_speed() - _drag_time * DRAG_DECAY_RATE, 0.1)
	_set_current_attack_speed(drag_attack_speed)


func _process_buff(delta: float) -> void:
	_buff_time += delta
	if _attack_range_area != null:
		_attack_range_area.monitoring = true


func _on_mouse_pressed() -> void:
	if _state != State.IDLE:
		return
	_is_mouse_pressed = true
	_mouse_press_time = 0.0
	_long_press_triggered = false


func _on_mouse_released() -> void:
	_is_mouse_pressed = false

	if _state == State.DRAGGING:
		_is_player_connected = false
		_enter_buff_state()
		return

	if not _long_press_triggered:
		_mouse_press_time = 0.0


func _establish_connection() -> void:
	_is_player_connected = true
	_drag_time = 0.0
	_last_drag_duration = 0.0
	_set_state(State.DRAGGING)


func _enter_buff_state() -> void:
	_set_state(State.BUFF)
	_buff_time = 0.0
	_last_drag_duration = _drag_time

	var recovered_speed: float = _get_drag_buff_bonus(_last_drag_duration)
	_set_current_attack_speed(_get_effective_base_attack_speed() + recovered_speed)
	_schedule_next_shot()

	if _buff_timer != null:
		_buff_timer.start(BUFF_DURATION)


func _update_shoot_timer() -> void:
	if _shoot_timer == null:
		return

	_combat_snapshot_dirty = true


func _set_current_attack_speed(new_speed: float) -> void:
	var clamped_speed: float = maxf(new_speed, 0.1)
	if is_equal_approx(_current_attack_speed, clamped_speed):
		return
	_current_attack_speed = clamped_speed
	_update_shoot_timer()


func _get_shoot_interval() -> float:
	if _current_attack_speed <= 0.0:
		return 999.0
	return 1.0 / _current_attack_speed


func _schedule_next_shot() -> void:
	if _shoot_timer == null:
		return

	var interval: float = _get_shoot_interval()
	_shoot_timer.wait_time = interval
	_shoot_timer.start(interval)


func _update_rope() -> void:
	if _rope == null:
		return

	match _state:
		State.IDLE:
			_rope.visible = false
			_rope.points = PackedVector2Array()
		State.DRAGGING:
			_rope.visible = true
			_rope.points = PackedVector2Array()
			_rope.add_point(Vector2.ZERO)
			var player: Node2D = _get_connected_player()
			if player != null:
				_rope.add_point(to_local(player.global_position))
			var drag_ratio := get_drag_bonus_ratio()
			_rope.width = lerpf(3.0, 6.0, drag_ratio)
			_rope.default_color = COLOR_DRAGGING.lerp(Color(1.0, 0.9, 0.3, 1.0), drag_ratio)
		State.BUFF:
			_rope.visible = false
			_rope.width = 3.0
			_rope.points = PackedVector2Array()


func _update_range_indicator() -> void:
	if _range_indicator == null:
		return

	_range_indicator.visible = _state == State.DRAGGING or _is_hovered or _is_mouse_pressed
	if not _range_indicator.visible:
		return

	match _state:
		State.DRAGGING:
			var drag_ratio := get_drag_bonus_ratio()
			_range_indicator.modulate = RANGE_DRAGGING_COLOR.lerp(Color(1.0, 0.92, 0.45, 0.82), drag_ratio)
		State.BUFF:
			_range_indicator.modulate = RANGE_BUFF_COLOR
		_:
			_range_indicator.modulate = RANGE_IDLE_COLOR


func _update_hover_state() -> void:
	var viewport := get_viewport()
	if viewport == null:
		_is_hovered = false
		return

	_is_hovered = _is_pointer_over_tower(viewport.get_mouse_position())


func _is_pointer_over_tower(screen_position: Vector2) -> bool:
	if _sprite == null or _sprite.texture == null:
		return false

	var local_position := to_local(screen_position)
	var texture_size := _sprite.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return false

	var half_size := texture_size * _sprite.scale * 0.5
	var sprite_center := _sprite.position
	var rect := Rect2(sprite_center - half_size, half_size * 2.0)
	return rect.has_point(local_position)


func _get_connected_player() -> Node2D:
	if not _is_player_connected:
		return null

	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	return tree.get_first_node_in_group("player") as Node2D


func _on_shoot_timer_timeout() -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_nearest_enemy()
	elif global_position.distance_to(_target.global_position) > attack_range:
		_target = get_nearest_enemy()

	if _target == null or not is_instance_valid(_target):
		_schedule_next_shot()
		return

	if _bullet_scene == null:
		_bullet_scene = load(bullet_scene_path) as PackedScene

	if _bullet_scene == null:
		push_error("Tower: Bullet scene not loaded")
		_schedule_next_shot()
		return

	_fire_bullet(_target)
	_schedule_next_shot()


func get_nearest_enemy() -> Node2D:
	if _attack_range_area == null:
		return null

	var bodies: Array[Node2D] = []
	for body_variant: Node in _attack_range_area.get_overlapping_bodies():
		var body: Node2D = body_variant as Node2D
		if body != null:
			bodies.append(body)

	if bodies.is_empty():
		return null

	var nearest_enemy: Node2D = null
	var nearest_distance: float = INF
	for body: Node2D in bodies:
		if not is_instance_valid(body):
			continue
		if not body.is_in_group("enemy"):
			continue

		var distance_to_body: float = global_position.distance_to(body.global_position)
		if distance_to_body < nearest_distance and distance_to_body <= attack_range:
			nearest_distance = distance_to_body
			nearest_enemy = body

	return nearest_enemy


func _fire_bullet(target: Node2D) -> void:
	if _bullet_scene == null:
		return

	var muzzle_position: Vector2 = global_position
	if _muzzle != null:
		muzzle_position = _muzzle.global_position

	var current_stats: Dictionary = _get_inventory_stats()
	var final_damage: int = int(round(float(current_stats.get("final_damage", _get_final_damage()))))
	var bullet_speed: float = stats.bullet_speed

	var bullet: Node = _bullet_scene.instantiate()
	if bullet == null:
		return

	if bullet.has_method("initialize"):
		var bullet_variant := 0
		if _state == State.BUFF or bool(_combo_state.get("poison_fire_active", false)) or bool(_combo_state.get("poison_ice_active", false)):
			bullet_variant = 1
		bullet.initialize(target, muzzle_position, final_damage, bullet_speed, bullet_variant)

	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		tree.current_scene.add_child(bullet)


func _on_attack_range_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_is_player_in_range = true


func _on_attack_range_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_is_player_in_range = false
		if _is_player_connected and _state == State.DRAGGING:
			_is_player_connected = false
			_enter_buff_state()

	if body.is_in_group("enemy") and _target == body:
		_target = null


func on_attempt_connection(is_connecting: bool) -> void:
	if is_connecting:
		_establish_connection()
	elif _state == State.DRAGGING:
		_is_player_connected = false
		_enter_buff_state()


func _on_buff_timeout() -> void:
	_is_player_connected = false
	_drag_time = 0.0
	_last_drag_duration = 0.0
	_current_attack_speed = _get_effective_base_attack_speed()
	_update_shoot_timer()
	_schedule_next_shot()
	_set_state(State.IDLE)


func _set_state(new_state: State) -> void:
	_state = new_state
	_apply_state_color()


func _apply_state_color() -> void:
	if _sprite == null:
		return

	if hit_counter >= WARNING_HITS:
		_sprite.modulate = COLOR_WARNING
		return

	match _state:
		State.IDLE:
			_sprite.modulate = COLOR_IDLE
		State.DRAGGING:
			_sprite.modulate = COLOR_DRAGGING
		State.BUFF:
			_sprite.modulate = COLOR_BUFF


func get_state() -> State:
	return _state


func get_base_damage() -> int:
	return _base_damage


func get_base_attack_speed() -> float:
	return _base_attack_speed


func get_base_attack_range() -> float:
	return _base_attack_range


func get_drag_bonus_preview() -> float:
	if _state == State.DRAGGING:
		return _get_drag_buff_bonus(_drag_time)
	if _state == State.BUFF:
		return _get_drag_buff_bonus(_last_drag_duration)
	return 0.0


func get_drag_bonus_ratio() -> float:
	if MAX_DRAG_BUFF_BONUS <= 0.0:
		return 0.0
	return clampf(get_drag_bonus_preview() / MAX_DRAG_BUFF_BONUS, 0.0, 1.0)


func get_hit_counter() -> int:
	return hit_counter


func get_hits_until_drop() -> int:
	return maxi(0, MAX_HITS - hit_counter)


func is_drop_warning_active() -> bool:
	return hit_counter >= WARNING_HITS


func apply_inventory_state(item_stats: Dictionary, combos: Dictionary) -> void:
	_inventory_damage_bonus = float(item_stats.get("damage_bonus", 0.0))
	_inventory_attack_speed_bonus = float(item_stats.get("attack_speed_bonus", 0.0))
	_inventory_range_bonus = float(item_stats.get("range_bonus", 0.0))
	_combo_state = combos.duplicate(true)

	attack_range = _get_effective_attack_range()
	_update_attack_range_shape()

	match _state:
		State.IDLE:
			_current_attack_speed = _get_effective_base_attack_speed()
		State.DRAGGING:
			_current_attack_speed = maxf(_get_effective_base_attack_speed() - _drag_time * DRAG_DECAY_RATE, 0.1)
		State.BUFF:
			var recovered_speed: float = _get_drag_buff_bonus(_last_drag_duration)
			_current_attack_speed = _get_effective_base_attack_speed() + recovered_speed

	_update_shoot_timer()


func _get_drag_buff_bonus(drag_duration: float) -> float:
	return minf(drag_duration * DRAG_DECAY_RATE * DRAG_BUFF_RECOVERY_MULTIPLIER, MAX_DRAG_BUFF_BONUS)


func get_combo_state() -> Dictionary:
	return _combo_state.duplicate(true)


func _get_final_damage() -> float:
	var current_stats: Dictionary = _get_inventory_stats()
	return float(current_stats.get("final_damage", float(_base_damage) + _inventory_damage_bonus))


func _get_effective_base_attack_speed() -> float:
	var current_stats: Dictionary = _get_inventory_stats()
	return float(current_stats.get("final_attack_speed", _base_attack_speed + _inventory_attack_speed_bonus))


func _get_effective_attack_range() -> float:
	var current_stats: Dictionary = _get_inventory_stats()
	return float(current_stats.get("final_range", _base_attack_range + _inventory_range_bonus))


func _update_attack_range_shape() -> void:
	if _attack_shape == null:
		return

	var shape: Shape2D = _attack_shape.shape
	if shape is CircleShape2D:
		var circle_shape: CircleShape2D = shape as CircleShape2D
		circle_shape.radius = _get_effective_attack_range()
		_update_range_indicator_scale(circle_shape.radius)


func _sync_range_indicator_to_scene_shape() -> void:
	if _attack_shape == null or not (_attack_shape.shape is CircleShape2D):
		return

	var circle_shape: CircleShape2D = _attack_shape.shape as CircleShape2D
	if circle_shape == null:
		return

	_update_range_indicator_scale(circle_shape.radius)


func _get_scene_attack_range() -> float:
	if _attack_shape != null and _attack_shape.shape is CircleShape2D:
		var circle_shape: CircleShape2D = _attack_shape.shape as CircleShape2D
		if circle_shape != null and circle_shape.radius > 0.0:
			return circle_shape.radius

	if attack_range > 0.0:
		return attack_range

	return DEFAULT_ATTACK_RANGE_FALLBACK


func _update_range_indicator_scale(radius: float) -> void:
	if _range_indicator == null or _range_indicator.texture == null:
		return

	var texture_size := _range_indicator.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var diameter := radius * 2.0
	_range_indicator.scale = Vector2(diameter / texture_size.x, diameter / texture_size.y)


func _get_inventory_manager() -> Node:
	var tree := get_tree()
	var manager: Node = null
	if tree != null and tree.root != null:
		manager = tree.root.get_node_or_null("InventoryManager")
	if manager == null or not is_instance_valid(manager):
		return null
	return manager


func _get_inventory_stats() -> Dictionary:
	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager != null and inventory_manager.has_method("get_computed_stats"):
		var computed_stats: Dictionary = inventory_manager.get_computed_stats()
		if not computed_stats.is_empty():
			return computed_stats
	return {
		"final_damage": float(_base_damage) + _inventory_damage_bonus,
		"final_attack_speed": _base_attack_speed + _inventory_attack_speed_bonus,
		"final_range": _base_attack_range + _inventory_range_bonus
	}


func _get_global_singleton() -> Node:
	var tree := get_tree()
	var global_singleton: Node = null
	if tree != null and tree.root != null:
		global_singleton = tree.root.get_node_or_null("Global")
	if global_singleton == null or not is_instance_valid(global_singleton):
		return null
	return global_singleton


func _try_initialize_singletons() -> void:
	var inventory_manager: Node = _get_inventory_manager()
	var global_singleton: Node = _get_global_singleton()
	if inventory_manager == null or global_singleton == null:
		return

	_needs_singleton_sync = false
	_sync_inventory_state()
	_combat_snapshot_dirty = true


func _sync_inventory_state() -> void:
	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager == null:
		return
	if not inventory_manager.has_method("get_computed_stats"):
		return

	var item_stats: Dictionary = inventory_manager.get_computed_stats()
	if item_stats.is_empty():
		return

	var combos: Dictionary = {}
	if inventory_manager.has_method("get_active_combos"):
		combos = inventory_manager.get_active_combos()

	apply_inventory_state(item_stats, combos)


func _print_combat_snapshot() -> void:
	var combo_names: Array[String] = []
	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager != null and inventory_manager.has_method("get_active_combo_names"):
		combo_names = inventory_manager.get_active_combo_names()

	print("当前伤害: %.2f, 当前攻速: %.2f, 激活组合: %s" % [_get_final_damage(), _current_attack_speed, combo_names])


func take_damage(amount: int) -> void:
	if amount <= 0:
		return

	hit_counter = mini(MAX_HITS, hit_counter + 1)
	print("Tower hit: +%d, hit_counter=%d/%d" % [amount, hit_counter, MAX_HITS])

	if hit_counter >= MAX_HITS:
		_trigger_item_drop_penalty()
	else:
		_apply_state_color()


func _trigger_item_drop_penalty() -> void:
	hit_counter = 0

	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager != null and inventory_manager.has_method("drop_random_item"):
		var dropped_item: Resource = inventory_manager.drop_random_item(global_position)
		if dropped_item != null:
			print("Tower: drop item penalty triggered -> %s" % str(dropped_item.get("item_name")))
		else:
			print("Tower: drop item penalty triggered, but inventory was empty.")
	else:
		print("Tower: drop item penalty triggered, InventoryManager missing drop_random_item().")

	var tree: SceneTree = get_tree()
	if tree != null:
		Engine.time_scale = DROP_HITSTOP_SCALE
		var restore_timer: SceneTreeTimer = tree.create_timer(DROP_HITSTOP_DURATION, true, false, true)
		restore_timer.timeout.connect(_restore_time_scale)

	_apply_state_color()


func _restore_time_scale() -> void:
	Engine.time_scale = 1.0


func _update_damage_warning_feedback() -> void:
	if _sprite == null:
		return

	if hit_counter >= WARNING_HITS:
		var shake_offset := Vector2(
			randf_range(-WARNING_SHAKE_STRENGTH, WARNING_SHAKE_STRENGTH),
			randf_range(-WARNING_SHAKE_STRENGTH, WARNING_SHAKE_STRENGTH)
		)
		_sprite.position = _base_sprite_position + shake_offset
		_sprite.modulate = COLOR_WARNING
	else:
		_sprite.position = _base_sprite_position
