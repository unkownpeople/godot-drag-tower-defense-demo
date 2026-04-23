extends CharacterBody2D

const MAX_DISTANCE: float = 800.0
const PRIMARY_TEXTURE: Texture2D = preload("res://res/meis/子弹.png")
const SECONDARY_TEXTURE: Texture2D = preload("res://res/meis/子弹2.png")
const IMPACT_TEXTURE: Texture2D = preload("res://res/meis/爆炸.png")

const GROUND_EFFECT_LAYER_NAME := "GroundEffectLayer"

var _target: Node2D
var _target_pos: Vector2
var _damage: int = 30
var _speed: float = 600.0
var _initialized: bool = false
var _distance_traveled: float = 0.0
var _texture_variant: int = 0

var _trail: Line2D
var _hit_effect: GPUParticles2D
var _sprite: Sprite2D


func _ready() -> void:
	_trail = %Trail
	_hit_effect = %HitEffect
	_sprite = $Sprite2D as Sprite2D

	if _trail:
		_trail.points = PackedVector2Array()
		_trail.width = 3.0
	if _sprite:
		_apply_texture_variant()


func initialize(target: Node2D, start_pos: Vector2, damage: int, speed: float, texture_variant: int = 0) -> void:
	_target = target
	_target_pos = target.global_position if target else start_pos
	global_position = start_pos
	_damage = damage
	_speed = speed
	_distance_traveled = 0.0
	_texture_variant = texture_variant
	_apply_texture_variant()

	var dir := Vector2.RIGHT
	if _target and is_instance_valid(_target):
		dir = global_position.direction_to(_target_pos)

	velocity = dir * _speed
	rotation = velocity.angle() if velocity.length() > 0 else 0.0
	_initialized = true


func _physics_process(delta: float) -> void:
	if not _initialized:
		return

	if _target and is_instance_valid(_target):
		_target_pos = _target.global_position
		var dir := global_position.direction_to(_target_pos)
		velocity = dir * _speed
		rotation = velocity.angle()

	move_and_slide()

	_distance_traveled += velocity.length() * delta
	if _distance_traveled > MAX_DISTANCE:
		queue_free()
		return

	for i in range(get_slide_collision_count()):
		var collider := get_slide_collision(i).get_collider()
		if collider and collider.has_method("take_damage"):
			collider.take_damage(_damage)
			_apply_on_hit_effects(collider)
		_spawn_hit_effect()
		queue_free()
		return

	_update_trail()


func _update_trail() -> void:
	if not _trail:
		return

	_trail.points = PackedVector2Array()
	var normalized_vel := velocity.normalized() if velocity.length() > 0 else Vector2.RIGHT
	_trail.add_point(Vector2.ZERO)
	_trail.add_point(-normalized_vel * 15.0)


func _spawn_hit_effect() -> void:
	if _hit_effect:
		_hit_effect.emitting = false
		_hit_effect.restart()
	_spawn_impact_sprite()


func _apply_on_hit_effects(collider: Object) -> void:
	if not is_instance_valid(InventoryManager):
		return
	if collider is Node2D and InventoryManager.has_method("apply_on_hit_effects"):
		InventoryManager.apply_on_hit_effects(collider, global_position)


func _apply_texture_variant() -> void:
	if _sprite == null:
		return

	if _texture_variant == 1:
		_sprite.texture = SECONDARY_TEXTURE
	else:
		_sprite.texture = PRIMARY_TEXTURE


func _spawn_impact_sprite() -> void:
	if IMPACT_TEXTURE == null:
		return

	var parent := _get_world_layer(GROUND_EFFECT_LAYER_NAME)
	if parent == null:
		return

	var sprite := Sprite2D.new()
	sprite.texture = IMPACT_TEXTURE
	sprite.global_position = global_position
	sprite.scale = Vector2(0.35, 0.35)
	sprite.z_index = 2
	parent.add_child(sprite)

	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.55, 0.55), 0.14)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.14)
	tween.tween_callback(sprite.queue_free)


func _get_world_layer(layer_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null

	var scene_root := tree.current_scene
	var layer := scene_root.get_node_or_null(layer_name)
	if layer != null:
		return layer
	return scene_root
