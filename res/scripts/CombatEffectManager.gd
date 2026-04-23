extends Node

const DOT_TICK_INTERVAL := 0.25
const MIN_SLOW_MULTIPLIER := 0.1
const CRYSTAL_CONTACT_RADIUS := 24.0
const VISUAL_POINT_COUNT := 18
const GROUND_EFFECT_LAYER_NAME := "GroundEffectLayer"

var _burning_targets: Dictionary = {}
var _direct_slow_targets: Dictionary = {}
var _poison_pools: Array[Dictionary] = []
var _poison_mists: Dictionary = {}
var _ice_crystals: Array[Dictionary] = []
var _last_slow_targets: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func apply_effect(target: Node2D, hit_position: Vector2, effect_payload: Dictionary) -> void:
	apply_bullet_effects(target, hit_position, effect_payload)


func apply_bullet_effects(target: Node2D, hit_position: Vector2, effect_payload: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return

	var fire_dps := float(effect_payload.get("fire_damage_per_second", 0.0))
	var fire_duration := float(effect_payload.get("fire_duration", 0.0))
	if fire_dps > 0.0 and fire_duration > 0.0:
		_apply_burning(target, fire_dps, fire_duration)

	var ice_slow_ratio := float(effect_payload.get("ice_slow_ratio", 0.0))
	var ice_duration := float(effect_payload.get("ice_duration", 0.0))
	if ice_slow_ratio > 0.0 and ice_duration > 0.0:
		_apply_direct_slow(target, ice_slow_ratio, ice_duration)

	var poison_dps := float(effect_payload.get("poison_damage_per_second", 0.0))
	var poison_duration := float(effect_payload.get("poison_duration", 0.0))
	var poison_radius := float(effect_payload.get("poison_radius", 0.0))
	if poison_dps > 0.0 and poison_duration > 0.0 and poison_radius > 0.0:
		_add_poison_pool(
			hit_position,
			poison_radius,
			poison_duration,
			poison_dps,
			0.0,
			float(effect_payload.get("poison_pool_bonus_damage_per_second", 0.0))
		)

	var explosion_damage := float(effect_payload.get("explosion_damage", 0.0))
	var explosion_radius := float(effect_payload.get("explosion_radius", 0.0))
	if explosion_damage > 0.0 and explosion_radius > 0.0:
		_apply_area_damage(hit_position, explosion_radius, explosion_damage)

	var mist_damage := float(effect_payload.get("mist_damage_per_second", 0.0))
	var mist_radius := float(effect_payload.get("mist_radius", 0.0))
	if mist_damage > 0.0 and mist_radius > 0.0:
		_apply_poison_mist(target, mist_damage, mist_radius, float(effect_payload.get("mist_slow_ratio", 0.0)))


func _physics_process(delta: float) -> void:
	_process_burning(delta)
	_process_direct_slows(delta)
	_process_poison_pools(delta)
	_process_poison_mists(delta)
	_process_ice_crystals(delta)


func _apply_burning(target: Node2D, damage_per_second: float, duration: float) -> void:
	var key := str(target.get_instance_id())
	var state: Dictionary = _burning_targets.get(key, {
		"target_ref": weakref(target),
		"time_left": 0.0,
		"damage_per_second": 0.0,
		"tick_accumulator": 0.0
	})
	state["target_ref"] = weakref(target)
	state["time_left"] = duration
	state["damage_per_second"] = damage_per_second
	_burning_targets[key] = state


func _apply_direct_slow(target: Node2D, slow_ratio: float, duration: float) -> void:
	var key := str(target.get_instance_id())
	var state: Dictionary = _direct_slow_targets.get(key, {
		"target_ref": weakref(target),
		"time_left": 0.0,
		"slow_ratio": 0.0
	})
	state["target_ref"] = weakref(target)
	state["time_left"] = duration
	state["slow_ratio"] = maxf(float(state.get("slow_ratio", 0.0)), slow_ratio)
	_direct_slow_targets[key] = state


func _add_poison_pool(position: Vector2, radius: float, duration: float, damage_per_second: float, slow_ratio: float, bonus_damage_per_second: float) -> void:
	for pool in _poison_pools:
		if pool["position"].distance_to(position) <= maxf(radius, float(pool["radius"])) * 0.35:
			pool["position"] = (pool["position"] + position) * 0.5
			pool["radius"] = maxf(float(pool["radius"]), radius)
			pool["time_left"] = maxf(float(pool["time_left"]), duration)
			pool["damage_per_second"] = maxf(float(pool["damage_per_second"]), damage_per_second)
			pool["slow_ratio"] = maxf(float(pool["slow_ratio"]), slow_ratio)
			pool["bonus_damage_per_second"] = maxf(float(pool.get("bonus_damage_per_second", 0.0)), bonus_damage_per_second)
			var visual := pool.get("visual") as Node2D
			_update_visual_scale(visual, float(pool["radius"]))
			_update_visual_position(visual, pool["position"])
			return

	var visual := _create_circle_visual(Color(0.32, 0.95, 0.42, 0.22), radius, 3)
	_poison_pools.append({
		"position": position,
		"radius": radius,
		"time_left": duration,
		"damage_per_second": damage_per_second,
		"slow_ratio": slow_ratio,
		"bonus_damage_per_second": bonus_damage_per_second,
		"tick_accumulator": 0.0,
		"visual": visual
	})


func _process_burning(delta: float) -> void:
	var expired_keys: Array[String] = []

	for key in _burning_targets.keys():
		var state: Dictionary = _burning_targets[key]
		var target_ref: WeakRef = state.get("target_ref") as WeakRef
		if target_ref == null:
			expired_keys.append(key)
			continue
		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			expired_keys.append(key)
			continue
		var target: Node2D = target_object as Node2D
		if target == null:
			expired_keys.append(key)
			continue

		state["time_left"] = float(state["time_left"]) - delta
		state["tick_accumulator"] = float(state["tick_accumulator"]) + delta

		while float(state["tick_accumulator"]) >= DOT_TICK_INTERVAL and float(state["time_left"]) > 0.0:
			state["tick_accumulator"] = float(state["tick_accumulator"]) - DOT_TICK_INTERVAL
			_apply_damage_tick(target, float(state["damage_per_second"]) * DOT_TICK_INTERVAL)

		if float(state["time_left"]) <= 0.0:
			expired_keys.append(key)
		else:
			_burning_targets[key] = state

	for key in expired_keys:
		_burning_targets.erase(key)


func _process_direct_slows(delta: float) -> void:
	var active_slow_map: Dictionary = {}
	var expired_keys: Array[String] = []

	for key in _direct_slow_targets.keys():
		var state: Dictionary = _direct_slow_targets[key]
		var target_ref: WeakRef = state.get("target_ref") as WeakRef
		if target_ref == null:
			expired_keys.append(key)
			continue
		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			expired_keys.append(key)
			continue
		var target: Node2D = target_object as Node2D
		if target == null:
			expired_keys.append(key)
			continue

		state["time_left"] = float(state["time_left"]) - delta
		if float(state["time_left"]) <= 0.0:
			expired_keys.append(key)
			continue

		_direct_slow_targets[key] = state
		active_slow_map[key] = {
			"target_ref": weakref(target),
			"slow_ratio": maxf(float(active_slow_map.get(key, {}).get("slow_ratio", 0.0)), float(state["slow_ratio"]))
		}

	_process_slow_map_from_pools(active_slow_map)
	_process_slow_map_from_mists(active_slow_map)

	for key in expired_keys:
		_direct_slow_targets.erase(key)

	_apply_slow_map(active_slow_map)


func _process_poison_pools(delta: float) -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	var retained_pools: Array[Dictionary] = []

	for pool in _poison_pools:
		pool["time_left"] = float(pool["time_left"]) - delta
		if float(pool["time_left"]) <= 0.0:
			_free_visual(pool.get("visual") as Node)
			continue

		pool["tick_accumulator"] = float(pool["tick_accumulator"]) + delta
		_update_visual_position(pool.get("visual") as Node2D, pool["position"])
		if float(pool["tick_accumulator"]) >= DOT_TICK_INTERVAL:
			while float(pool["tick_accumulator"]) >= DOT_TICK_INTERVAL:
				pool["tick_accumulator"] = float(pool["tick_accumulator"]) - DOT_TICK_INTERVAL
				_apply_poison_pool_tick(pool, enemies)

		retained_pools.append(pool)

	_poison_pools = retained_pools


func _apply_poison_pool_tick(pool: Dictionary, enemies: Array) -> void:
	var origin: Vector2 = pool["position"]
	var radius := float(pool["radius"])
	var tick_damage := (float(pool["damage_per_second"]) + float(pool.get("bonus_damage_per_second", 0.0))) * DOT_TICK_INTERVAL

	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if not _is_enemy_affectable(enemy):
			continue
		if enemy.global_position.distance_to(origin) > radius:
			continue
		_apply_damage_tick(enemy, tick_damage)


func _process_slow_map_from_pools(active_slow_map: Dictionary) -> void:
	if _poison_pools.is_empty():
		return

	var enemies := get_tree().get_nodes_in_group("enemy")
	for pool in _poison_pools:
		var slow_ratio := float(pool["slow_ratio"])
		if slow_ratio <= 0.0:
			continue

		var origin: Vector2 = pool["position"]
		var radius := float(pool["radius"])
		for enemy_variant in enemies:
			var enemy := enemy_variant as Node2D
			if not _is_enemy_affectable(enemy):
				continue
			if enemy.global_position.distance_to(origin) > radius:
				continue

			var key := str(enemy.get_instance_id())
			var existing_ratio := 0.0
			if active_slow_map.has(key):
				existing_ratio = float(active_slow_map[key].get("slow_ratio", 0.0))
			active_slow_map[key] = {
				"target_ref": weakref(enemy),
				"slow_ratio": maxf(existing_ratio, slow_ratio)
			}


func _apply_poison_mist(target: Node2D, damage_per_second: float, radius: float, slow_ratio: float) -> void:
	var key := str(target.get_instance_id())
	if _poison_mists.has(key):
		return

	var visual := _create_poison_mist_visual(radius)
	_poison_mists[key] = {
		"target_ref": weakref(target),
		"damage_per_second": damage_per_second,
		"radius": radius,
		"slow_ratio": slow_ratio,
		"tick_accumulator": 0.0,
		"visual": visual
	}


func _process_poison_mists(delta: float) -> void:
	if _poison_mists.is_empty():
		return

	var enemies := get_tree().get_nodes_in_group("enemy")
	var expired_keys: Array[String] = []

	for key in _poison_mists.keys():
		var state: Dictionary = _poison_mists[key]
		var target_ref: WeakRef = state.get("target_ref") as WeakRef
		if target_ref == null:
			expired_keys.append(key)
			continue

		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			expired_keys.append(key)
			continue

		var target := target_object as Node2D
		if target == null:
			expired_keys.append(key)
			continue

		_update_visual_position(state.get("visual") as Node2D, target.global_position)
		state["tick_accumulator"] = float(state["tick_accumulator"]) + delta
		if float(state["tick_accumulator"]) >= DOT_TICK_INTERVAL:
			while float(state["tick_accumulator"]) >= DOT_TICK_INTERVAL:
				state["tick_accumulator"] = float(state["tick_accumulator"]) - DOT_TICK_INTERVAL
				_apply_poison_mist_tick(target.global_position, float(state["radius"]), float(state["damage_per_second"]), enemies)

		_poison_mists[key] = state

	for key in expired_keys:
		var state: Dictionary = _poison_mists.get(key, {})
		_free_visual(state.get("visual") as Node)
		_poison_mists.erase(key)


func _apply_poison_mist_tick(origin: Vector2, radius: float, damage_per_second: float, enemies: Array) -> void:
	var tick_damage := damage_per_second * DOT_TICK_INTERVAL
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if not _is_enemy_affectable(enemy):
			continue
		if not _is_position_affecting_enemy(origin, radius, enemy):
			continue
		_apply_damage_tick(enemy, tick_damage)


func _process_slow_map_from_mists(active_slow_map: Dictionary) -> void:
	if _poison_mists.is_empty():
		return

	var enemies := get_tree().get_nodes_in_group("enemy")
	for key in _poison_mists.keys():
		var state: Dictionary = _poison_mists[key]
		var mist_slow_ratio := float(state.get("slow_ratio", 0.0))
		if mist_slow_ratio <= 0.0:
			continue

		var target_ref: WeakRef = state.get("target_ref") as WeakRef
		if target_ref == null:
			continue
		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			continue

		var target := target_object as Node2D
		if target == null:
			continue

		for enemy_variant in enemies:
			var enemy := enemy_variant as Node2D
			if not _is_enemy_affectable(enemy):
				continue
			if not _is_position_affecting_enemy(target.global_position, float(state["radius"]), enemy):
				continue

			var enemy_key := str(enemy.get_instance_id())
			var existing_ratio := 0.0
			if active_slow_map.has(enemy_key):
				existing_ratio = float(active_slow_map[enemy_key].get("slow_ratio", 0.0))
			active_slow_map[enemy_key] = {
				"target_ref": weakref(enemy),
				"slow_ratio": maxf(existing_ratio, mist_slow_ratio)
			}


func handle_enemy_defeated(world_position: Vector2) -> void:
	if not is_instance_valid(InventoryManager):
		return
	if not InventoryManager.has_method("get_final_stats") or not InventoryManager.has_method("get_active_combos"):
		return

	var final_stats: Dictionary = InventoryManager.get_final_stats()
	var combo_state: Dictionary = InventoryManager.get_active_combos()
	var crystal_damage := float(final_stats.get("crystal_damage", 0.0))
	var crystal_duration := float(final_stats.get("crystal_duration", 0.0))
	if crystal_damage <= 0.0 or crystal_duration <= 0.0:
		return

	var combo_explosion_damage := float(combo_state.get("explosion_crystal_damage", 0.0))
	var combo_explosion_radius := maxf(50.0, float(combo_state.get("explosion_crystal_radius", 0.0)))
	_add_ice_crystal(world_position, crystal_damage, crystal_duration, combo_explosion_damage, combo_explosion_radius)


func _add_ice_crystal(world_position: Vector2, damage: float, duration: float, combo_explosion_damage: float, combo_explosion_radius: float) -> void:
	var visual := _create_diamond_visual(Color(0.6, 0.92, 1.0, 0.9), 24.0, 9)
	_update_visual_position(visual, world_position)
	_ice_crystals.append({
		"position": world_position,
		"damage": damage,
		"time_left": duration,
		"combo_explosion_damage": combo_explosion_damage,
		"combo_explosion_radius": combo_explosion_radius,
		"visual": visual
	})


func _process_ice_crystals(delta: float) -> void:
	if _ice_crystals.is_empty():
		return

	var enemies := get_tree().get_nodes_in_group("enemy")
	var retained_crystals: Array[Dictionary] = []

	for crystal in _ice_crystals:
		crystal["time_left"] = float(crystal["time_left"]) - delta
		var consumed := false

		for enemy_variant in enemies:
			var enemy := enemy_variant as Node2D
			if not _is_enemy_affectable(enemy):
				continue
			if not _is_position_affecting_enemy(crystal["position"], CRYSTAL_CONTACT_RADIUS, enemy):
				continue

			_apply_damage_tick(enemy, float(crystal["damage"]))
			_finish_ice_crystal(crystal)
			consumed = true
			break

		if consumed:
			continue

		if float(crystal["time_left"]) <= 0.0:
			_finish_ice_crystal(crystal)
			continue

		retained_crystals.append(crystal)

	_ice_crystals = retained_crystals


func _finish_ice_crystal(crystal: Dictionary) -> void:
	_free_visual(crystal.get("visual") as Node)
	var combo_damage := float(crystal.get("combo_explosion_damage", 0.0))
	var combo_radius := float(crystal.get("combo_explosion_radius", 0.0))
	if combo_damage > 0.0 and combo_radius > 0.0:
		_apply_area_damage(crystal["position"], combo_radius, combo_damage)


func _apply_slow_map(active_slow_map: Dictionary) -> void:
	for key in _last_slow_targets.keys():
		if active_slow_map.has(key):
			continue
		var target_ref: WeakRef = _last_slow_targets[key] as WeakRef
		if target_ref == null:
			continue
		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			continue
		var target: Node2D = target_object as Node2D
		if target and target.has_method("set_status_slow"):
			target.set_status_slow(0.0)

	var next_slow_targets: Dictionary = {}
	for key in active_slow_map.keys():
		var target_ref: WeakRef = active_slow_map[key].get("target_ref") as WeakRef
		if target_ref == null:
			continue
		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			continue
		var target: Node2D = target_object as Node2D
		var slow_ratio := clampf(float(active_slow_map[key].get("slow_ratio", 0.0)), 0.0, 1.0 - MIN_SLOW_MULTIPLIER)
		if target and target.has_method("set_status_slow"):
			target.set_status_slow(slow_ratio)
			next_slow_targets[key] = weakref(target)

	_last_slow_targets = next_slow_targets


func _apply_area_damage(origin: Vector2, radius: float, amount: float) -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy_variant in enemies:
		var enemy := enemy_variant as Node2D
		if not _is_enemy_affectable(enemy):
			continue
		if not _is_position_affecting_enemy(origin, radius, enemy):
			continue
		_apply_damage_tick(enemy, amount)


func _apply_damage_tick(target: Node2D, amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("apply_effect_damage"):
		target.apply_effect_damage(amount)
	elif target.has_method("take_damage"):
		target.take_damage(int(round(amount)))


func reset_effects() -> void:
	_burning_targets.clear()
	_direct_slow_targets.clear()
	for pool in _poison_pools:
		_free_visual(pool.get("visual") as Node)
	_poison_pools.clear()

	for mist_key in _poison_mists.keys():
		var mist_state: Dictionary = _poison_mists[mist_key]
		_free_visual(mist_state.get("visual") as Node)
	_poison_mists.clear()

	for crystal in _ice_crystals:
		_free_visual(crystal.get("visual") as Node)
	_ice_crystals.clear()

	for key in _last_slow_targets.keys():
		var target_ref: WeakRef = _last_slow_targets[key] as WeakRef
		if target_ref == null:
			continue
		var target_object: Object = target_ref.get_ref()
		if target_object == null or not is_instance_valid(target_object):
			continue
		var target: Node2D = target_object as Node2D
		if target != null and target.has_method("set_status_slow"):
			target.set_status_slow(0.0)

	_last_slow_targets.clear()


func _create_circle_visual(color: Color, radius: float, z_index: int) -> Node2D:
	var root := Node2D.new()
	root.z_index = z_index

	var polygon := Polygon2D.new()
	polygon.color = color
	polygon.polygon = _build_circle_polygon(radius)
	root.add_child(polygon)

	_add_visual_to_layer(root, GROUND_EFFECT_LAYER_NAME)
	return root


func _create_poison_mist_visual(radius: float) -> Node2D:
	var root := Node2D.new()
	root.z_index = 6

	var outer := Polygon2D.new()
	outer.color = Color(0.52, 0.92, 0.45, 0.14)
	outer.polygon = _build_circle_polygon(maxf(radius * 1.35, 22.0))
	root.add_child(outer)

	var inner := Polygon2D.new()
	inner.color = Color(0.78, 1.0, 0.62, 0.22)
	inner.polygon = _build_circle_polygon(maxf(radius, 16.0))
	root.add_child(inner)

	var core := Polygon2D.new()
	core.color = Color(0.88, 1.0, 0.82, 0.12)
	core.polygon = _build_circle_polygon(maxf(radius * 0.55, 10.0))
	root.add_child(core)

	_add_visual_to_layer(root, GROUND_EFFECT_LAYER_NAME)
	return root


func _create_diamond_visual(color: Color, radius: float, z_index: int) -> Node2D:
	var root := Node2D.new()
	root.z_index = z_index

	var polygon := Polygon2D.new()
	polygon.color = color
	polygon.polygon = PackedVector2Array([
		Vector2(0.0, -radius),
		Vector2(radius * 0.7, 0.0),
		Vector2(0.0, radius),
		Vector2(-radius * 0.7, 0.0)
	])
	root.add_child(polygon)

	_add_visual_to_layer(root, GROUND_EFFECT_LAYER_NAME)
	return root


func _add_visual_to_layer(visual: Node2D, layer_name: String) -> void:
	if visual == null:
		return

	var parent := _get_world_layer(layer_name)
	if parent == null:
		visual.queue_free()
		return

	parent.add_child(visual)


func _get_world_layer(layer_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null

	var scene_root := tree.current_scene
	var layer := scene_root.get_node_or_null(layer_name)
	if layer != null:
		return layer
	return scene_root


func _build_circle_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(VISUAL_POINT_COUNT):
		var angle := (TAU * float(i)) / float(VISUAL_POINT_COUNT)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _update_visual_position(visual: Node2D, world_position: Vector2) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	visual.global_position = world_position


func _update_visual_scale(visual: Node2D, radius: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var polygon := visual.get_child(0) as Polygon2D
	if polygon == null:
		return
	if polygon.polygon.is_empty():
		return

	var current_radius := polygon.polygon[0].length()
	if current_radius <= 0.0:
		return
	visual.scale = Vector2.ONE * (radius / current_radius)


func _free_visual(visual: Node) -> void:
	if visual != null and is_instance_valid(visual):
		visual.queue_free()


func _is_enemy_affectable(enemy: Node2D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if enemy.has_method("get_health_ratio") and float(enemy.get_health_ratio()) <= 0.0:
		return false
	return true


func _is_position_affecting_enemy(origin: Vector2, radius: float, enemy: Node2D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	return enemy.global_position.distance_to(origin) <= radius + _get_target_radius(enemy)


func _get_target_radius(target: Node2D) -> float:
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
