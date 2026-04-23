extends CharacterBody2D

enum AIState { UNLOCKED, CHASE }
enum EnemyRole { MELEE, RANGED, BOSS }

const DEFAULT_ATTACK_DISTANCE: float = 30.0
const LOCK_CHECK_INTERVAL: float = 0.2
const LOCK_MARK_TEXT: String = "!"
const LOCK_MARK_DURATION: float = 0.45
const COLOR_MELEE: Color = Color(0.8367441, 0.0, 0.33054394, 1.0)
const COLOR_RANGED: Color = Color(0.55, 0.35, 1.0, 1.0)
const COLOR_BOSS: Color = Color(1.0, 0.15, 0.15, 1.0)
const BOSS_SPRITE_SCALE_MULTIPLIER: float = 2.5
const BOSS_SHADOW_SCALE_MULTIPLIER: float = 1.8
const PATROL_RADIUS: float = 100.0
const PATROL_MOVE_SPEED_RATIO: float = 0.5
const PATROL_REACHED_DISTANCE: float = 8.0
const PATROL_IDLE_MIN: float = 1.0
const PATROL_IDLE_MAX: float = 2.0
const UNLOCKED_ALPHA: float = 0.65
const CHASE_ALPHA: float = 1.0
const HIGH_DAMAGE_KNOCKBACK_THRESHOLD: int = 50
const HIGH_DAMAGE_KNOCKBACK_DISTANCE: float = 18.0
const DAMAGE_LABEL_SCENE: PackedScene = preload("res://res/scenes/DamageLabel.tscn")
const DAMAGE_POPUP_NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const DAMAGE_POPUP_SPECIAL_COLOR: Color = Color(1.0, 0.85, 0.2, 1.0)
const MELEE_IDLE_TEXTURE: Texture2D = preload("res://res/charactor/近战常态.png")
const MELEE_ATTACK_TEXTURE: Texture2D = preload("res://res/charactor/近战攻击.png")
const RANGED_IDLE_TEXTURE: Texture2D = preload("res://res/charactor/远程常态.png")
const RANGED_ATTACK_TEXTURE: Texture2D = preload("res://res/charactor/远程攻击.png")
const BOSS_IDLE_TEXTURE: Texture2D = preload("res://res/charactor/boss常态.png")
const BOSS_CHARGE_TEXTURE: Texture2D = preload("res://res/charactor/boss蓄力.png")
const SLASH_LEFT_TEXTURE: Texture2D = preload("res://res/meis/斩击左.png")
const SLASH_RIGHT_TEXTURE: Texture2D = preload("res://res/meis/斩击右.png")
const ENEMY_EXPLOSION_1_TEXTURE: Texture2D = preload("res://res/meis/敌人爆炸1.png")
const ENEMY_EXPLOSION_2_TEXTURE: Texture2D = preload("res://res/meis/敌人爆炸2.png")
const BOSS_EXPLOSION_TEXTURE: Texture2D = preload("res://res/meis/boss爆炸.png")
const LOCK_ICON_TEXTURE: Texture2D = preload("res://res/meis/UI/锁定.png")
const MELEE_ATTACK_VISUAL_DURATION: float = 0.3
const SLASH_EFFECT_DURATION: float = 0.12
const SLASH_EFFECT_SCALE: float = 0.24
const NORMAL_EXPLOSION_SCALE: float = 0.3
const BOSS_EXPLOSION_SCALE: float = 0.45
const CHEST_DROP_CHANCE: float = 0.1
const GROUND_EFFECT_LAYER_NAME: String = "GroundEffectLayer"
const WORLD_OVERLAY_LAYER_NAME: String = "WorldOverlayLayer"
const BOSS_WARNING_FILL_COLOR: Color = Color(1.0, 0.1, 0.1, 0.18)
const BOSS_WARNING_RING_COLOR: Color = Color(1.0, 0.2, 0.2, 0.9)
const BOSS_WARNING_RING_WIDTH: float = 6.0
const BOSS_WARNING_POINT_COUNT: int = 64

@export var enemy_role: EnemyRole = EnemyRole.MELEE
@export var move_speed: float = 100.0
@export var max_health: int = 150
@export var attack_damage: int = 1
@export var exp_value: int = 10
@export var lock_range: float = 70.0
@export var attack_distance: float = 14.0
@export var attack_cooldown: float = 1.0
@export var ranged_charge_duration: float = 2.0
@export var ranged_interrupted_charge_duration: float = 1.5
@export var ranged_max_attack_range: float = 200.0
@export var boss_warning_radius: float = 300.0
@export var boss_charge_duration: float = 3.0
@export var boss_aoe_damage: int = 3

var _health: int = 0
var _player: CharacterBody2D = null
var _tower_target: Node2D = null
var _current_target: Node2D = null
var _state: AIState = AIState.UNLOCKED
var _flash_tween: Tween = null
var _lock_mark_tween: Tween = null
var _dying: bool = false
var _base_move_speed: float = 100.0
var _status_slow_ratio: float = 0.0
var _lock_check_elapsed: float = 0.0
var _lock_mark: Sprite2D = null
var _boss_is_charging: bool = false
var _boss_charge_elapsed: float = 0.0
var _boss_cooldown_remaining: float = 0.0
var _ranged_is_charging: bool = false
var _ranged_charge_elapsed: float = 0.0
var _ranged_next_charge_duration: float = 2.0
var _spawn_origin: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _patrol_wait_remaining: float = 0.0
var _is_melee_attack_visual: bool = false
var _pending_melee_target: Node2D = null
var _base_sprite_scale: Vector2 = Vector2.ONE
var _base_shadow_scale: Vector2 = Vector2.ONE
var _base_boss_warning_scale: Vector2 = Vector2.ONE
var _melee_attack_visual_timer: Timer = null
var _boss_ground_warning: Node2D = null

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _hit_flash: ColorRect = $HitFlash
@onready var _attack_timer: Timer = $AttackTimer
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _attack_shape: CollisionShape2D = $AttackRange/AttackShape
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shadow: Sprite2D = $Shadow
@onready var _boss_warning_sprite: Sprite2D = $BossWarningSprite


func _ready() -> void:
	_apply_role_stats()
	_base_move_speed = move_speed
	_health = max_health
	_spawn_origin = global_position
	_patrol_target = global_position
	if _sprite != null:
		_base_sprite_scale = _sprite.scale
	if _shadow != null:
		_base_shadow_scale = _shadow.scale
	if _boss_warning_sprite != null:
		_base_boss_warning_scale = _boss_warning_sprite.scale
	_update_health_bar()
	_cache_targets()
	_create_lock_mark()
	_create_attack_visual_timer()
	_apply_role_visuals()
	_apply_unlocked_visuals()

	if enemy_role == EnemyRole.MELEE:
		_pick_new_patrol_target()

	if _attack_timer and not _attack_timer.timeout.is_connected(_on_attack_timer_timeout):
		_attack_timer.timeout.connect(_on_attack_timer_timeout)

	if enemy_role == EnemyRole.BOSS and is_instance_valid(_player):
		_lock_target(_player)
	_update_boss_ground_warning()


func _exit_tree() -> void:
	_free_boss_ground_warning()


func _apply_role_stats() -> void:
	_ranged_next_charge_duration = ranged_charge_duration
	if _attack_timer != null:
		_attack_timer.wait_time = attack_cooldown


func _create_attack_visual_timer() -> void:
	_melee_attack_visual_timer = Timer.new()
	_melee_attack_visual_timer.one_shot = true
	_melee_attack_visual_timer.wait_time = MELEE_ATTACK_VISUAL_DURATION
	add_child(_melee_attack_visual_timer)
	if not _melee_attack_visual_timer.timeout.is_connected(_on_melee_attack_visual_timeout):
		_melee_attack_visual_timer.timeout.connect(_on_melee_attack_visual_timeout)


func _physics_process(delta: float) -> void:
	if _dying or _health <= 0:
		_update_boss_ground_warning()
		return

	_cache_targets()
	_update_ranged_charge(delta)
	_update_boss_charge(delta)
	_update_boss_cooldown(delta)
	_update_boss_ground_warning()
	_update_lock_detection(delta)
	_resolve_state_transition()
	_execute_movement()
	_try_attack_current_target()


func _cache_targets() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	_tower_target = _get_nearest_tower()


func _update_lock_detection(delta: float) -> void:
	if enemy_role == EnemyRole.BOSS:
		if is_instance_valid(_player):
			_lock_target(_player)
		return

	if enemy_role == EnemyRole.MELEE and _is_melee_attack_visual:
		return

	if enemy_role == EnemyRole.RANGED and _ranged_is_charging:
		return

	_lock_check_elapsed += delta
	if _lock_check_elapsed < LOCK_CHECK_INTERVAL:
		return

	_lock_check_elapsed = 0.0

	if _state == AIState.UNLOCKED:
		var candidate: Node2D = _pick_lock_candidate()
		if candidate != null:
			_lock_target(candidate)
		return

	if _state == AIState.CHASE:
		_refresh_chase_target()


func _resolve_state_transition() -> void:
	if enemy_role == EnemyRole.BOSS:
		if is_instance_valid(_player):
			_state = AIState.CHASE
			_current_target = _player
		return

	if enemy_role == EnemyRole.MELEE and _is_melee_attack_visual:
		_state = AIState.CHASE
		return

	if _state == AIState.UNLOCKED:
		if _current_target != null and is_instance_valid(_current_target):
			_state = AIState.CHASE
		return

	if _current_target == null or not is_instance_valid(_current_target):
		_current_target = _pick_lock_candidate()
		if _current_target == null:
			_state = AIState.UNLOCKED
		else:
			_state = AIState.CHASE


func _execute_movement() -> void:
	if _boss_is_charging:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if enemy_role == EnemyRole.MELEE and _is_melee_attack_visual:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _ranged_is_charging:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _state == AIState.UNLOCKED:
		_process_unlocked_state(get_physics_process_delta_time())
		return

	_chase_current_target()


func _chase_current_target() -> void:
	_apply_chase_visuals()

	if _current_target == null or not is_instance_valid(_current_target):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _is_target_in_attack_distance(_current_target):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_move_toward_target(_current_target)


func _move_toward_target(target: Node2D) -> void:
	var direction: Vector2 = global_position.direction_to(target.global_position)
	velocity = direction * move_speed
	move_and_slide()


func _pick_lock_candidate() -> Node2D:
	var player_in_range: bool = _is_target_in_lock_range(_player)
	var tower_in_range: bool = _is_target_in_lock_range(_tower_target)

	match enemy_role:
		EnemyRole.MELEE:
			if player_in_range:
				return _player
			if tower_in_range:
				return _tower_target
		EnemyRole.RANGED:
			if tower_in_range:
				return _tower_target
			if player_in_range:
				return _player
		EnemyRole.BOSS:
			if is_instance_valid(_player):
				return _player

	return null


func _refresh_chase_target() -> void:
	if enemy_role == EnemyRole.MELEE:
		if _current_target == _tower_target and _is_target_in_lock_range(_player):
			_lock_target(_player)
			return

		if _current_target == null or not is_instance_valid(_current_target):
			var melee_candidate: Node2D = _pick_lock_candidate()
			if melee_candidate != null:
				_lock_target(melee_candidate)
		return

	if enemy_role == EnemyRole.RANGED:
		if _current_target == _tower_target and not _is_target_in_lock_range(_tower_target):
			if is_instance_valid(_player):
				_interrupt_ranged_charge(false)
				_lock_target(_player)
			else:
				_current_target = null
				_state = AIState.UNLOCKED
			return

		if _current_target == _player and _is_target_in_lock_range(_tower_target):
			_interrupt_ranged_charge(false)
			_lock_target(_tower_target)
			return

		if _current_target == null or not is_instance_valid(_current_target):
			var ranged_candidate: Node2D = _pick_lock_candidate()
			if ranged_candidate != null:
				_lock_target(ranged_candidate)


func _lock_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return

	var target_changed: bool = _current_target != target or _state != AIState.CHASE
	_current_target = target
	_state = AIState.CHASE
	_apply_chase_visuals()

	if target_changed:
		_show_lock_mark()


func _try_attack_current_target() -> void:
	if _dying or _health <= 0:
		return
	if enemy_role == EnemyRole.MELEE and _is_melee_attack_visual:
		return
	if _ranged_is_charging:
		return
	if _boss_is_charging:
		return
	if enemy_role == EnemyRole.BOSS and _boss_cooldown_remaining > 0.0:
		return
	_ensure_immediate_attack_target()

	_apply_attack_target_priority()
	if _current_target == null or not is_instance_valid(_current_target):
		return
	if not _is_target_in_attack_distance(_current_target):
		return
	if _attack_timer and not _attack_timer.is_stopped():
		return

	_perform_attack()


func _on_attack_timer_timeout() -> void:
	if _dying or _health <= 0:
		return
	if enemy_role == EnemyRole.BOSS:
		return
	if enemy_role == EnemyRole.MELEE and _is_melee_attack_visual:
		return
	if _ranged_is_charging:
		return
	if _boss_is_charging:
		return
	_ensure_immediate_attack_target()

	_apply_attack_target_priority()
	if _current_target == null or not is_instance_valid(_current_target):
		return
	if not _is_target_in_attack_distance(_current_target):
		return

	_perform_attack()


func _perform_attack() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		return

	if enemy_role == EnemyRole.RANGED:
		_start_ranged_charge()
		return

	if enemy_role == EnemyRole.BOSS:
		_start_boss_charge()
		return

	_start_melee_attack_visual(_current_target)

	if _attack_timer:
		_attack_timer.start()


func _apply_attack_target_priority() -> void:
	if enemy_role == EnemyRole.MELEE:
		if is_instance_valid(_player) and _is_target_in_lock_range(_player):
			_current_target = _player
		elif is_instance_valid(_tower_target) and _is_target_in_lock_range(_tower_target):
			_current_target = _tower_target
		return

	if enemy_role == EnemyRole.RANGED:
		if is_instance_valid(_tower_target) and _is_target_in_lock_range(_tower_target):
			_current_target = _tower_target
		elif is_instance_valid(_player) and _is_target_in_lock_range(_player):
			_current_target = _player


func _ensure_immediate_attack_target() -> void:
	if _current_target != null and is_instance_valid(_current_target):
		return

	var fallback_target: Node2D = _pick_lock_candidate()
	if fallback_target != null:
		_lock_target(fallback_target)
		return

	if enemy_role == EnemyRole.MELEE:
		if is_instance_valid(_player) and _is_target_in_attack_distance(_player):
			_lock_target(_player)
			return
		if is_instance_valid(_tower_target) and _is_target_in_attack_distance(_tower_target):
			_lock_target(_tower_target)
			return

	if enemy_role == EnemyRole.RANGED:
		if is_instance_valid(_tower_target) and _is_target_in_attack_distance(_tower_target):
			_lock_target(_tower_target)
			return
		if is_instance_valid(_player) and _is_target_in_attack_distance(_player):
			_lock_target(_player)


func take_damage(amount: int) -> void:
	if _health <= 0 or _dying:
		return

	_health -= amount
	_show_damage_popup(float(amount), false, DAMAGE_POPUP_NORMAL_COLOR)
	if enemy_role == EnemyRole.MELEE and amount >= HIGH_DAMAGE_KNOCKBACK_THRESHOLD:
		_apply_knockback()
	_update_health_bar()
	_play_hit_feedback()

	if _health <= 0:
		_die()


func apply_effect_damage(amount: float) -> void:
	if _health <= 0 or _dying:
		return

	var final_amount: int = maxi(1, int(round(amount)))
	_health -= final_amount
	_show_damage_popup(float(final_amount), true, DAMAGE_POPUP_SPECIAL_COLOR)
	_update_health_bar()

	if _health <= 0:
		_die()


func _update_health_bar() -> void:
	if _health_bar:
		_health_bar.max_value = max_health
		_health_bar.value = _health
		_health_bar.visible = _health < max_health


func _play_hit_feedback() -> void:
	if _hit_flash:
		_hit_flash.visible = true
		_hit_flash.modulate.a = 0.8

	if _flash_tween:
		_flash_tween.kill()

	_flash_tween = create_tween()
	_flash_tween.tween_property(_hit_flash, "modulate:a", 0.0, 0.15)
	_flash_tween.tween_callback(_hide_hit_flash)

	var sprite: Sprite2D = $Sprite2D as Sprite2D
	if sprite:
		var sprite_tween: Tween = create_tween()
		sprite_tween.tween_property(sprite, "modulate", Color(2, 2, 2, 1), 0.08)
		sprite_tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)
		sprite_tween.tween_callback(_refresh_visual_state)


func _hide_hit_flash() -> void:
	if _hit_flash:
		_hit_flash.visible = false


func _die() -> void:
	_dying = true
	velocity = Vector2.ZERO

	if is_instance_valid(CombatEffectManager) and CombatEffectManager.has_method("handle_enemy_defeated"):
		CombatEffectManager.handle_enemy_defeated(global_position)

	if enemy_role != EnemyRole.BOSS and is_instance_valid(InventoryManager) and InventoryManager.has_method("spawn_chest_pickup"):
		if randf() < CHEST_DROP_CHANCE:
			InventoryManager.spawn_chest_pickup(global_position)

	_play_death_effect()

	var tree := get_tree()
	var global_node: Node = null
	if tree != null and tree.root != null:
		global_node = tree.root.get_node_or_null("Global")
	if global_node != null and is_instance_valid(global_node) and global_node.has_signal("enemy_died"):
		if global_node.has_signal("screen_shake_requested"):
			if enemy_role == EnemyRole.BOSS:
				global_node.screen_shake_requested.emit(28.0, 0.45)
			else:
				global_node.screen_shake_requested.emit(4.5, 0.08)
		global_node.enemy_died.emit(exp_value)
		if enemy_role == EnemyRole.BOSS and global_node.has_signal("boss_defeated"):
			global_node.boss_defeated.emit(int(global_node.get("kill_count")), float(global_node.get("elapsed_time")))

	var death_timer: SceneTreeTimer = get_tree().create_timer(0.3)
	death_timer.timeout.connect(_on_death_timer_timeout)


func _on_death_timer_timeout() -> void:
	queue_free()


func _play_death_effect() -> void:
	if enemy_role == EnemyRole.BOSS:
		_spawn_temporary_effect(BOSS_EXPLOSION_TEXTURE, global_position, BOSS_EXPLOSION_SCALE, 0.35)
	else:
		var death_texture := ENEMY_EXPLOSION_1_TEXTURE if randf() < 0.5 else ENEMY_EXPLOSION_2_TEXTURE
		_spawn_temporary_effect(death_texture, global_position, NORMAL_EXPLOSION_SCALE, 0.25)

	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.2)


func set_status_slow(slow_ratio: float) -> void:
	_status_slow_ratio = clampf(slow_ratio, 0.0, 0.9)
	move_speed = _base_move_speed * maxf(0.1, 1.0 - _status_slow_ratio)


func _get_default_path_target() -> Node2D:
	if is_instance_valid(_tower_target):
		return _tower_target
	if is_instance_valid(_player):
		return _player
	return null


func _get_nearest_tower() -> Node2D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	var nearest_tower: Node2D = null
	var nearest_distance: float = INF
	for node: Node in tree.get_nodes_in_group("tower"):
		var tower: Node2D = node as Node2D
		if tower == null or not is_instance_valid(tower):
			continue

		var distance_to_tower: float = global_position.distance_to(tower.global_position)
		if distance_to_tower < nearest_distance:
			nearest_distance = distance_to_tower
			nearest_tower = tower

	return nearest_tower


func _get_lock_range() -> float:
	if enemy_role == EnemyRole.BOSS:
		return INF
	return lock_range


func _is_target_in_lock_range(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= _get_lock_range() + _get_target_interaction_radius(target)


func _is_target_in_attack_distance(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false

	var extra_self_radius: float = 0.0
	if enemy_role == EnemyRole.MELEE:
		extra_self_radius = _get_self_interaction_radius()

	return global_position.distance_to(target.global_position) <= _get_attack_distance() + extra_self_radius + _get_target_interaction_radius(target)


func _get_attack_distance() -> float:
	if attack_distance > 0.0:
		return attack_distance

	if _attack_shape != null and _attack_shape.shape is CircleShape2D:
		var circle: CircleShape2D = _attack_shape.shape as CircleShape2D
		return circle.radius
	return DEFAULT_ATTACK_DISTANCE


func _get_target_interaction_radius(target: Node2D) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0

	for child: Node in target.get_children():
		var collision := child as CollisionShape2D
		if collision == null or collision.shape == null:
			continue
		if collision.shape is CircleShape2D:
			return float((collision.shape as CircleShape2D).radius)
		if collision.shape is RectangleShape2D:
			var size := (collision.shape as RectangleShape2D).size
			return maxf(size.x, size.y) * 0.5

	return 0.0


func _get_self_interaction_radius() -> float:
	if _body_shape == null or _body_shape.shape == null:
		return 0.0

	if _body_shape.shape is CircleShape2D:
		return float((_body_shape.shape as CircleShape2D).radius)
	if _body_shape.shape is RectangleShape2D:
		var size := (_body_shape.shape as RectangleShape2D).size
		return maxf(size.x, size.y) * 0.5

	return 0.0


func _create_lock_mark() -> void:
	_lock_mark = Sprite2D.new()
	_lock_mark.name = "LockMark"
	_lock_mark.texture = LOCK_ICON_TEXTURE
	_lock_mark.position = Vector2(-12.0, -52.0)
	_lock_mark.scale = Vector2(0.15, 0.15)
	_lock_mark.visible = false
	add_child(_lock_mark)


func _show_lock_mark() -> void:
	if _lock_mark == null:
		return

	if _lock_mark_tween:
		_lock_mark_tween.kill()

	_lock_mark.visible = true
	_lock_mark.modulate = Color(1.0, 0.95, 0.2, 1.0)
	_lock_mark.position = Vector2(-12.0, -52.0)

	_lock_mark_tween = create_tween()
	_lock_mark_tween.tween_property(_lock_mark, "position:y", -64.0, LOCK_MARK_DURATION)
	_lock_mark_tween.parallel().tween_property(_lock_mark, "modulate:a", 0.0, LOCK_MARK_DURATION)
	_lock_mark_tween.tween_callback(_hide_lock_mark)


func _hide_lock_mark() -> void:
	if _lock_mark == null:
		return
	_lock_mark.visible = false
	_lock_mark.modulate.a = 1.0
	_lock_mark.position = Vector2(-12.0, -52.0)


func _start_melee_attack_visual(target: Node2D) -> void:
	_is_melee_attack_visual = true
	_pending_melee_target = target
	_refresh_visual_state()
	if _melee_attack_visual_timer != null:
		_melee_attack_visual_timer.start()


func _on_melee_attack_visual_timeout() -> void:
	_resolve_melee_attack()
	_is_melee_attack_visual = false
	_pending_melee_target = null
	_refresh_visual_state()


func _resolve_melee_attack() -> void:
	if _pending_melee_target == null or not is_instance_valid(_pending_melee_target):
		return
	if not _is_target_in_attack_distance(_pending_melee_target):
		return

	_spawn_slash_effect()
	if _pending_melee_target.is_in_group("player"):
		var tree := get_tree()
		var global_node: Node = null
		if tree != null and tree.root != null:
			global_node = tree.root.get_node_or_null("Global")
		if global_node != null and is_instance_valid(global_node) and global_node.has_method("take_damage"):
			global_node.take_damage(attack_damage)
	elif _pending_melee_target.has_method("take_damage"):
		_pending_melee_target.take_damage(attack_damage)


func _spawn_slash_effect() -> void:
	if _pending_melee_target == null or not is_instance_valid(_pending_melee_target):
		return

	var slash_texture := SLASH_RIGHT_TEXTURE if _pending_melee_target.global_position.x >= global_position.x else SLASH_LEFT_TEXTURE
	var offset_direction := global_position.direction_to(_pending_melee_target.global_position)
	var effect_position := global_position + offset_direction * 26.0
	_spawn_temporary_effect(slash_texture, effect_position, SLASH_EFFECT_SCALE, SLASH_EFFECT_DURATION)


func _spawn_temporary_effect(texture: Texture2D, world_position: Vector2, scale_value: float, duration: float) -> void:
	if texture == null:
		return

	var parent := _get_world_layer(WORLD_OVERLAY_LAYER_NAME)
	if parent == null:
		return

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.global_position = world_position
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.z_index = 0
	parent.add_child(sprite)

	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector2(scale_value * 1.2, scale_value * 1.2), duration)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, duration)
	tween.tween_callback(sprite.queue_free)


func _process_unlocked_state(delta: float) -> void:
	_apply_unlocked_visuals()

	match enemy_role:
		EnemyRole.MELEE:
			if _patrol_wait_remaining > 0.0:
				_patrol_wait_remaining = maxf(0.0, _patrol_wait_remaining - delta)
				velocity = Vector2.ZERO
				move_and_slide()
				if _patrol_wait_remaining <= 0.0:
					_pick_new_patrol_target()
				return

			if global_position.distance_to(_patrol_target) <= PATROL_REACHED_DISTANCE:
				velocity = Vector2.ZERO
				move_and_slide()
				_patrol_wait_remaining = randf_range(PATROL_IDLE_MIN, PATROL_IDLE_MAX)
				return

			var patrol_direction: Vector2 = global_position.direction_to(_patrol_target)
			velocity = patrol_direction * (_base_move_speed * PATROL_MOVE_SPEED_RATIO)
			move_and_slide()
		EnemyRole.RANGED:
			velocity = Vector2.ZERO
			move_and_slide()
		EnemyRole.BOSS:
			velocity = Vector2.ZERO
			move_and_slide()


func _pick_new_patrol_target() -> void:
	var random_offset: Vector2 = Vector2(
		randf_range(-PATROL_RADIUS, PATROL_RADIUS),
		randf_range(-PATROL_RADIUS, PATROL_RADIUS)
	)
	_patrol_target = _spawn_origin + random_offset


func _apply_unlocked_visuals() -> void:
	_set_sprite_alpha(UNLOCKED_ALPHA)


func _apply_chase_visuals() -> void:
	_set_sprite_alpha(CHASE_ALPHA)


func _update_ranged_charge(delta: float) -> void:
	if enemy_role != EnemyRole.RANGED or not _ranged_is_charging:
		return

	if _current_target == null or not is_instance_valid(_current_target):
		_interrupt_ranged_charge(true)
		return

	var distance_to_target: float = global_position.distance_to(_current_target.global_position)
	if distance_to_target > ranged_max_attack_range:
		_interrupt_ranged_charge(true)
		return

	_ranged_charge_elapsed += delta
	if _ranged_charge_elapsed >= _ranged_next_charge_duration:
		_resolve_ranged_charge()


func _start_ranged_charge() -> void:
	if enemy_role != EnemyRole.RANGED or _ranged_is_charging:
		return
	if _current_target == null or not is_instance_valid(_current_target):
		return
	if not _is_target_in_attack_distance(_current_target):
		return

	_ranged_is_charging = true
	_ranged_charge_elapsed = 0.0
	velocity = Vector2.ZERO
	_refresh_visual_state()


func _interrupt_ranged_charge(use_interrupt_penalty: bool) -> void:
	if not _ranged_is_charging:
		return

	_ranged_is_charging = false
	_ranged_charge_elapsed = 0.0
	if use_interrupt_penalty:
		_ranged_next_charge_duration = ranged_interrupted_charge_duration
	else:
		_ranged_next_charge_duration = ranged_charge_duration
	_refresh_visual_state()


func _resolve_ranged_charge() -> void:
	_ranged_is_charging = false
	_ranged_charge_elapsed = 0.0

	if _current_target != null and is_instance_valid(_current_target):
		if global_position.distance_to(_current_target.global_position) <= ranged_max_attack_range:
			if _current_target.is_in_group("player"):
				var tree := get_tree()
				var global_node: Node = null
				if tree != null and tree.root != null:
					global_node = tree.root.get_node_or_null("Global")
				if global_node != null and is_instance_valid(global_node) and global_node.has_method("take_damage"):
					global_node.take_damage(attack_damage)
			elif _current_target.has_method("take_damage"):
				_current_target.take_damage(attack_damage)

	_ranged_next_charge_duration = ranged_charge_duration
	if _attack_timer:
		_attack_timer.start(attack_cooldown)
	_refresh_visual_state()


func _apply_role_visuals() -> void:
	if _sprite == null:
		return

	match enemy_role:
		EnemyRole.MELEE:
			_sprite.scale = _base_sprite_scale
			if _shadow != null:
				_shadow.scale = _base_shadow_scale
		EnemyRole.RANGED:
			_sprite.scale = _base_sprite_scale
			if _shadow != null:
				_shadow.scale = _base_shadow_scale
		EnemyRole.BOSS:
			_sprite.scale = _base_sprite_scale * BOSS_SPRITE_SCALE_MULTIPLIER
			if _shadow != null:
				_shadow.scale = _base_shadow_scale * BOSS_SHADOW_SCALE_MULTIPLIER

	_refresh_visual_state()


func _refresh_visual_state() -> void:
	if _sprite == null:
		return

	_sprite.texture = _get_texture_for_current_state()
	if _state == AIState.CHASE:
		_set_sprite_alpha(CHASE_ALPHA)
	else:
		_set_sprite_alpha(UNLOCKED_ALPHA)

	_update_boss_warning_sprite()


func _get_texture_for_current_state() -> Texture2D:
	match enemy_role:
		EnemyRole.MELEE:
			return MELEE_ATTACK_TEXTURE if _is_melee_attack_visual else MELEE_IDLE_TEXTURE
		EnemyRole.RANGED:
			return RANGED_ATTACK_TEXTURE if _ranged_is_charging else RANGED_IDLE_TEXTURE
		EnemyRole.BOSS:
			return BOSS_CHARGE_TEXTURE if _boss_is_charging else BOSS_IDLE_TEXTURE
	return MELEE_IDLE_TEXTURE


func _set_sprite_alpha(alpha: float) -> void:
	if _sprite == null:
		return

	var next_color := _sprite.modulate
	next_color.r = 1.0
	next_color.g = 1.0
	next_color.b = 1.0
	next_color.a = alpha
	_sprite.modulate = next_color


func is_boss_enemy() -> bool:
	return enemy_role == EnemyRole.BOSS


func is_boss_charging() -> bool:
	return enemy_role == EnemyRole.BOSS and _boss_is_charging


func get_health_ratio() -> float:
	if max_health <= 0:
		return 0.0
	return clampf(float(_health) / float(max_health), 0.0, 1.0)


func _update_boss_warning_sprite() -> void:
	if _boss_warning_sprite == null:
		return

	_boss_warning_sprite.visible = false


func _update_boss_charge(delta: float) -> void:
	if enemy_role != EnemyRole.BOSS or not _boss_is_charging:
		return

	_boss_charge_elapsed += delta
	queue_redraw()

	if _boss_charge_elapsed >= boss_charge_duration:
		_resolve_boss_charge()


func _start_boss_charge() -> void:
	if enemy_role != EnemyRole.BOSS or _boss_is_charging:
		return
	if _boss_cooldown_remaining > 0.0:
		return

	_boss_is_charging = true
	_boss_charge_elapsed = 0.0
	velocity = Vector2.ZERO
	_refresh_visual_state()
	_update_boss_ground_warning()
	queue_redraw()


func _resolve_boss_charge() -> void:
	_boss_is_charging = false
	_boss_charge_elapsed = 0.0
	_boss_cooldown_remaining = attack_cooldown
	_refresh_visual_state()
	_update_boss_ground_warning()
	queue_redraw()

	var tree := get_tree()
	var global_node: Node = null
	if tree != null and tree.root != null:
		global_node = tree.root.get_node_or_null("Global")
	if global_node != null and is_instance_valid(global_node) and global_node.has_signal("screen_shake_requested"):
		global_node.screen_shake_requested.emit(20.0, 0.3)
	for target: Node2D in _get_targets_in_boss_warning_radius():
		if target.is_in_group("player"):
			if global_node != null and is_instance_valid(global_node) and global_node.has_method("take_damage"):
				global_node.take_damage(boss_aoe_damage)
		elif target.has_method("take_damage"):
			target.take_damage(boss_aoe_damage)



func _update_boss_cooldown(delta: float) -> void:
	if enemy_role != EnemyRole.BOSS or _boss_cooldown_remaining <= 0.0:
		return
	_boss_cooldown_remaining = maxf(0.0, _boss_cooldown_remaining - delta)


func _get_targets_in_boss_warning_radius() -> Array[Node2D]:
	var results: Array[Node2D] = []
	var tree: SceneTree = get_tree()
	if tree == null:
		return results

	for node: Node in tree.get_nodes_in_group("player"):
		var player_target: Node2D = node as Node2D
		if player_target != null and is_instance_valid(player_target):
			if global_position.distance_to(player_target.global_position) <= boss_warning_radius:
				results.append(player_target)

	for node: Node in tree.get_nodes_in_group("tower"):
		var tower_target: Node2D = node as Node2D
		if tower_target != null and is_instance_valid(tower_target):
			if global_position.distance_to(tower_target.global_position) <= boss_warning_radius:
				results.append(tower_target)

	return results


func _draw() -> void:
	return


func _apply_knockback() -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		return

	var away_direction: Vector2 = _current_target.global_position.direction_to(global_position)
	global_position += away_direction * HIGH_DAMAGE_KNOCKBACK_DISTANCE


func _show_damage_popup(value: float, is_special: bool, color: Color) -> void:
	if DAMAGE_LABEL_SCENE == null:
		return

	var popup: Label = DAMAGE_LABEL_SCENE.instantiate() as Label
	if popup == null:
		return

	var parent := _get_world_layer(WORLD_OVERLAY_LAYER_NAME)
	if parent == null:
		popup.queue_free()
		return

	parent.add_child(popup)
	popup.global_position = global_position + Vector2(randf_range(-20.0, 20.0), -40.0)
	if popup.has_method("setup"):
		popup.setup(value, is_special, color)


func _update_boss_ground_warning() -> void:
	if enemy_role != EnemyRole.BOSS:
		_free_boss_ground_warning()
		return

	if not _boss_is_charging or _dying or _health <= 0:
		if _boss_ground_warning != null and is_instance_valid(_boss_ground_warning):
			_boss_ground_warning.visible = false
		return

	var warning := _ensure_boss_ground_warning()
	if warning == null:
		return

	warning.visible = true
	warning.global_position = global_position


func _ensure_boss_ground_warning() -> Node2D:
	if _boss_ground_warning != null and is_instance_valid(_boss_ground_warning):
		return _boss_ground_warning

	var parent := _get_world_layer(GROUND_EFFECT_LAYER_NAME)
	if parent == null:
		return null

	var root := Node2D.new()
	root.name = "BossGroundWarning"
	root.z_index = 8
	root.visible = false

	var fill := Polygon2D.new()
	fill.color = BOSS_WARNING_FILL_COLOR
	fill.polygon = _build_circle_polygon(boss_warning_radius, BOSS_WARNING_POINT_COUNT)
	root.add_child(fill)

	var ring := Line2D.new()
	ring.width = BOSS_WARNING_RING_WIDTH
	ring.default_color = BOSS_WARNING_RING_COLOR
	ring.closed = true
	ring.points = _build_circle_polygon(boss_warning_radius, BOSS_WARNING_POINT_COUNT)
	root.add_child(ring)

	parent.add_child(root)
	_boss_ground_warning = root
	return _boss_ground_warning


func _free_boss_ground_warning() -> void:
	if _boss_ground_warning != null and is_instance_valid(_boss_ground_warning):
		_boss_ground_warning.queue_free()
	_boss_ground_warning = null


func _get_world_layer(layer_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null

	var scene_root := tree.current_scene
	var layer := scene_root.get_node_or_null(layer_name)
	if layer != null:
		return layer
	return scene_root


func _build_circle_polygon(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(point_count):
		var angle := (TAU * float(i)) / float(point_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
