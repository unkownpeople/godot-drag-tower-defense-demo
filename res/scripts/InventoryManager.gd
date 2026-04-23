extends Node

signal inventory_changed(items: Array)

const DAMAGE_PER_STACK := 20.0
const RANGE_PER_STACK := 50.0
const SPEED_PER_STACK := 0.15
const FIRE_BASE_DAMAGE_PER_SECOND := 15.0
const FIRE_BASE_DURATION := 2.0
const ITEM_DIRS: PackedStringArray = ["res://Items", "res://res/Items"]
const CHEST_DROP_BASIC_WEIGHT := 0.5
const CHEST_DROP_SPECIAL_WEIGHT := 0.5
const OWNED_ITEM_WEIGHT_BONUS := 1.5
const ITEM_PICKUP_SCENE_PATH := "res://res/scenes/ItemPickup.tscn"
const CHEST_PICKUP_SCENE_PATH := "res://res/scenes/ChestPickup.tscn"

var _item_counts: Dictionary = {}
var _item_resources: Dictionary = {}
var _tag_counts: Dictionary = {}
var _computed_stats: Dictionary = {}
var _active_combos: Dictionary = {}
var _active_combo_names: Array[String] = []
var _item_pickup_scene: PackedScene = null
var _chest_pickup_scene: PackedScene = null


func _ready() -> void:
	_connect_global_signals()
	var tree := get_tree()
	if tree and not tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.connect(_on_tree_node_added)


func _connect_global_signals() -> void:
	var global_node: Node = get_node_or_null("/root/Global")
	if global_node == null or not is_instance_valid(global_node):
		push_warning("InventoryManager: Global not found.")
		return

	if global_node.has_signal("item_applied") and not global_node.item_applied.is_connected(_on_item_applied):
		global_node.item_applied.connect(_on_item_applied)


func _on_item_applied(item: Resource) -> void:
	if item == null:
		return

	add_item(item)


func add_item(item: Resource) -> void:
	if item == null:
		return
	if _is_heal_item(item):
		_apply_heal_item(item)
		return

	var item_id := _get_item_id(item)
	_item_counts[item_id] = int(_item_counts.get(item_id, 0)) + 1
	_item_resources[item_id] = item

	_rebuild_tag_counts()
	recalculate_stats()
	_emit_inventory_snapshot()


func drop_random_item(drop_position: Vector2) -> Resource:
	var available_item_ids: Array[String] = []
	for item_id_variant in _item_counts.keys():
		var item_id: String = str(item_id_variant)
		if int(_item_counts.get(item_id, 0)) > 0:
			available_item_ids.append(item_id)

	if available_item_ids.is_empty():
		return null

	var selected_item_id: String = available_item_ids[randi() % available_item_ids.size()]
	var item_resource: Resource = _item_resources.get(selected_item_id) as Resource
	if item_resource == null:
		return null

	var next_count: int = int(_item_counts.get(selected_item_id, 0)) - 1
	if next_count <= 0:
		_item_counts.erase(selected_item_id)
		_item_resources.erase(selected_item_id)
	else:
		_item_counts[selected_item_id] = next_count

	_rebuild_tag_counts()
	recalculate_stats()
	_emit_inventory_snapshot()
	_spawn_dropped_pickup(item_resource, drop_position)
	return item_resource


func _get_item_id(item: Resource) -> String:
	var item_name := str(item.get("item_name"))
	if not item_name.is_empty():
		return item_name

	var path := item.resource_path.get_file().get_basename()
	if not path.is_empty():
		return path

	return str(item.get_instance_id())


func _rebuild_tag_counts() -> void:
	_tag_counts.clear()

	for item_id in _item_resources.keys():
		var item: Resource = _item_resources[item_id]
		var item_count := int(_item_counts.get(item_id, 0))
		var tags: Array[String] = _get_item_tags(item)

		for tag_variant in tags:
			var tag := str(tag_variant)
			_tag_counts[tag] = int(_tag_counts.get(tag, 0)) + item_count


func recalculate_stats() -> void:
	var tower: Node = _get_tower()
	if tower == null or not is_instance_valid(tower):
		_computed_stats.clear()
		_active_combos.clear()
		_active_combo_names.clear()
		return

	var base_damage: float = 80.0
	var base_attack_speed: float = 0.75
	var base_range: float = 0.0

	if tower:
		if tower.has_method("get_base_damage"):
			base_damage = float(tower.get_base_damage())
		if tower.has_method("get_base_attack_speed"):
			base_attack_speed = float(tower.get_base_attack_speed())
		if tower.has_method("get_base_attack_range"):
			base_range = float(tower.get_base_attack_range())

	var damage_bonus := float(_get_tag_count("Damage")) * DAMAGE_PER_STACK
	var attack_speed_bonus := float(_get_tag_count("Speed")) * SPEED_PER_STACK
	var range_bonus := float(_get_tag_count("Range")) * RANGE_PER_STACK
	var fire_damage_per_second := _get_total_damage_per_second_for_tag("Burn")
	var fire_duration := _get_max_duration_for_tag("Burn")
	var poison_damage_per_second := _get_total_damage_per_second_for_tag("PoisonPool")
	var poison_duration := _get_max_duration_for_tag("PoisonPool")
	var poison_radius := _get_max_radius_for_tag("PoisonPool")
	var ice_slow_ratio := _get_total_slow_ratio_for_tag("Slow")
	var ice_duration := _get_max_duration_for_tag("Slow")
	var explosion_damage := _get_total_effect_value_for_tag("Explosion")
	var explosion_radius := _get_max_radius_for_tag("Explosion")
	var crystal_damage := _get_total_effect_value_for_tag("Crystal")
	var crystal_duration := _get_max_duration_for_tag("Crystal")
	var mist_damage_per_second := _get_total_damage_per_second_for_tag("Mist")
	var mist_radius := _get_max_radius_for_tag("Mist")

	_computed_stats = {
		"base_damage": base_damage,
		"base_attack_speed": base_attack_speed,
		"base_range": base_range,
		"damage_bonus": damage_bonus,
		"attack_speed_bonus": attack_speed_bonus,
		"range_bonus": range_bonus,
		"final_damage": base_damage + damage_bonus,
		"final_attack_speed": base_attack_speed + attack_speed_bonus,
		"final_range": base_range + range_bonus,
		"fire_damage_per_second": fire_damage_per_second,
		"fire_duration": fire_duration,
		"poison_damage_per_second": poison_damage_per_second,
		"poison_duration": poison_duration,
		"poison_radius": poison_radius,
		"ice_slow_ratio": ice_slow_ratio,
		"ice_duration": ice_duration,
		"explosion_damage": explosion_damage,
		"explosion_radius": explosion_radius,
		"crystal_damage": crystal_damage,
		"crystal_duration": crystal_duration,
		"mist_damage_per_second": mist_damage_per_second,
		"mist_radius": mist_radius
	}

	_active_combos = _build_combo_state()
	_active_combo_names = _build_active_combo_names()

	if tower and tower.has_method("apply_inventory_state"):
		tower.apply_inventory_state(_computed_stats, _active_combos)

	_debug_print_combat_state()


func _build_combo_state() -> Dictionary:
	var has_burn := _get_tag_count("Burn") > 0
	var has_poison_pool := _get_tag_count("PoisonPool") > 0
	var has_slow := _get_tag_count("Slow") > 0
	var has_explosion := _get_tag_count("Explosion") > 0
	var has_crystal := _get_tag_count("Crystal") > 0
	var has_mist := _get_tag_count("Mist") > 0

	var fire_damage := _get_total_damage_per_second_for_tag("Burn")
	var ice_slow := _get_total_slow_ratio_for_tag("Slow")
	var explosion_damage := _get_total_effect_value_for_tag("Explosion")
	var explosion_radius := _get_max_radius_for_tag("Explosion")

	return {
		"poison_fire_active": has_burn and has_poison_pool,
		"poison_fire_bonus_damage_per_second": fire_damage * 0.5 if has_burn and has_poison_pool else 0.0,
		"explosion_crystal_active": has_explosion and has_crystal,
		"explosion_crystal_damage": explosion_damage if has_explosion and has_crystal else 0.0,
		"explosion_crystal_radius": explosion_radius if has_explosion and has_crystal else 0.0,
		"mist_slow_active": has_slow and has_mist,
		"mist_slow_ratio": ice_slow if has_slow and has_mist else 0.0
	}


func _build_active_combo_names() -> Array[String]:
	var names: Array[String] = []
	if bool(_active_combos.get("poison_fire_active", false)):
		names.append("PoisonFire")
	if bool(_active_combos.get("explosion_crystal_active", false)):
		names.append("ExplosionCrystal")
	if bool(_active_combos.get("mist_slow_active", false)):
		names.append("MistSlow")
	return names


func _get_total_damage_per_second_for_tag(tag: String) -> float:
	var total := 0.0
	for item_id in _item_resources.keys():
		var item: Resource = _item_resources[item_id]
		var tags: Array[String] = _get_item_tags(item)
		if tags.has(tag):
			total += _get_item_float(item, "damage_per_second") * int(_item_counts.get(item_id, 0))
	return total


func _get_total_slow_ratio_for_tag(tag: String) -> float:
	var total := 0.0
	for item_id in _item_resources.keys():
		var item: Resource = _item_resources[item_id]
		var tags: Array[String] = _get_item_tags(item)
		if tags.has(tag):
			total += _get_item_float(item, "slow_ratio") * int(_item_counts.get(item_id, 0))
	return total


func _get_max_duration_for_tag(tag: String) -> float:
	var max_duration := 0.0
	for item_id in _item_resources.keys():
		var item: Resource = _item_resources[item_id]
		var tags: Array[String] = _get_item_tags(item)
		if tags.has(tag):
			max_duration = maxf(max_duration, _get_item_float(item, "duration_seconds"))
	return max_duration


func _get_max_radius_for_tag(tag: String) -> float:
	var max_radius := 0.0
	for item_id in _item_resources.keys():
		var item: Resource = _item_resources[item_id]
		var tags: Array[String] = _get_item_tags(item)
		if tags.has(tag):
			max_radius = maxf(max_radius, _get_item_float(item, "radius"))
	return max_radius


func _emit_inventory_snapshot() -> void:
	var snapshot: Array = []

	for item_id in _item_counts.keys():
		var item: Resource = _item_resources[item_id]
		snapshot.append({
			"id": item_id,
			"name": str(item.get("item_name")),
			"count": int(_item_counts[item_id]),
			"item": item
		})

	snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]) < str(b["name"])
	)

	inventory_changed.emit(snapshot)
	_push_ui_inventory(snapshot)


func _get_tag_count(tag: String) -> int:
	return int(_tag_counts.get(tag, 0))


func _get_tower() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("tower")


func get_item_count(item_id: String) -> int:
	return int(_item_counts.get(item_id, 0))


func get_inventory_counts() -> Dictionary:
	return _item_counts.duplicate(true)


func get_inventory_snapshot() -> Array:
	var snapshot: Array = []
	for item_id in _item_counts.keys():
		var item: Resource = _item_resources[item_id]
		snapshot.append({
			"id": item_id,
			"name": str(item.get("item_name")),
			"count": int(_item_counts[item_id]),
			"item": item
		})
	snapshot.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]) < str(b["name"])
	)
	return snapshot


func get_computed_stats() -> Dictionary:
	return _computed_stats.duplicate(true)


func get_active_combos() -> Dictionary:
	return _active_combos.duplicate(true)


func get_active_combo_names() -> Array[String]:
	return _active_combo_names.duplicate()


func get_final_stats() -> Dictionary:
	if _computed_stats.is_empty():
		recalculate_stats()
	return _computed_stats.duplicate(true)


func get_final_damage() -> float:
	if _computed_stats.is_empty():
		recalculate_stats()
	return float(_computed_stats.get("final_damage", 80.0))


func get_final_attack_speed() -> float:
	if _computed_stats.is_empty():
		recalculate_stats()
	return float(_computed_stats.get("final_attack_speed", 0.75))


func grant_random_chest_item() -> Resource:
	var item_pool := _load_all_item_resources()
	if item_pool.is_empty():
		return null

	var basic_items: Array[ItemData] = []
	var special_items: Array[ItemData] = []
	for item: ItemData in item_pool:
		if item == null:
			continue
		if not _can_receive_item(item):
			continue
		if item.item_type == ItemData.ItemType.SPECIAL:
			special_items.append(item)
		else:
			basic_items.append(item)

	var selected_item := _draw_random_item_from_pools(basic_items, special_items, CHEST_DROP_BASIC_WEIGHT, CHEST_DROP_SPECIAL_WEIGHT)
	if selected_item == null:
		return null

	add_item(selected_item)
	return selected_item


func apply_effects(target: Node2D, hit_position: Vector2 = Vector2.ZERO) -> void:
	apply_on_hit_effects(target, hit_position)


func apply_on_hit_effects(target: Node2D, hit_position: Vector2 = Vector2.ZERO) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not is_instance_valid(CombatEffectManager):
		return
	if _computed_stats.is_empty():
		recalculate_stats()

	var has_fire := _get_tag_count("Burn") > 0
	var has_poison := _get_tag_count("PoisonPool") > 0
	var has_ice := _get_tag_count("Slow") > 0
	var has_explosion := _get_tag_count("Explosion") > 0
	var has_mist := _get_tag_count("Mist") > 0
	var fire_damage := float(_computed_stats.get("fire_damage_per_second", 0.0))
	var fire_duration := float(_computed_stats.get("fire_duration", 0.0))
	var poison_damage := float(_computed_stats.get("poison_damage_per_second", 0.0))
	var poison_duration := float(_computed_stats.get("poison_duration", 0.0))
	var poison_radius := float(_computed_stats.get("poison_radius", 0.0))
	var ice_slow_ratio := float(_computed_stats.get("ice_slow_ratio", 0.0))
	var ice_duration := float(_computed_stats.get("ice_duration", 0.0))
	var explosion_damage := float(_computed_stats.get("explosion_damage", 0.0))
	var explosion_radius := float(_computed_stats.get("explosion_radius", 0.0))
	var mist_damage := float(_computed_stats.get("mist_damage_per_second", 0.0))
	var mist_radius := float(_computed_stats.get("mist_radius", 0.0))

	var effect_payload: Dictionary = {
		"fire_damage_per_second": 0.0,
		"fire_duration": 0.0,
		"poison_damage_per_second": 0.0,
		"poison_duration": 0.0,
		"poison_radius": 0.0,
		"ice_slow_ratio": 0.0,
		"ice_duration": 0.0,
		"explosion_damage": 0.0,
		"explosion_radius": 0.0,
		"poison_pool_bonus_damage_per_second": 0.0,
		"mist_damage_per_second": 0.0,
		"mist_radius": 0.0,
		"mist_slow_ratio": 0.0
	}

	if has_fire:
		effect_payload["fire_damage_per_second"] = maxf(FIRE_BASE_DAMAGE_PER_SECOND, fire_damage)
		effect_payload["fire_duration"] = maxf(FIRE_BASE_DURATION, fire_duration)

	if has_poison:
		effect_payload["poison_damage_per_second"] = poison_damage
		effect_payload["poison_duration"] = poison_duration
		effect_payload["poison_radius"] = poison_radius

	if has_ice:
		effect_payload["ice_slow_ratio"] = ice_slow_ratio
		effect_payload["ice_duration"] = ice_duration

	if has_explosion:
		effect_payload["explosion_damage"] = explosion_damage
		effect_payload["explosion_radius"] = maxf(20.0, explosion_radius)

	if bool(_active_combos.get("poison_fire_active", false)):
		effect_payload["poison_pool_bonus_damage_per_second"] = float(_active_combos.get("poison_fire_bonus_damage_per_second", 0.0))

	if has_mist:
		effect_payload["mist_damage_per_second"] = mist_damage
		effect_payload["mist_radius"] = mist_radius
		if bool(_active_combos.get("mist_slow_active", false)):
			effect_payload["mist_slow_ratio"] = float(_active_combos.get("mist_slow_ratio", 0.0))

	var final_hit_position := target.global_position
	if hit_position != Vector2.ZERO:
		final_hit_position = hit_position

	if is_instance_valid(CombatEffectManager) and CombatEffectManager.has_method("apply_effect"):
		CombatEffectManager.apply_effect(target, final_hit_position, effect_payload)


func _debug_print_combat_state() -> void:
	print("当前伤害: %.2f, 当前攻速: %.2f, 激活组合: %s" % [
		get_final_damage(),
		get_final_attack_speed(),
		get_active_combo_names()
	])
	return
	print("当前伤害: %.2f, 当前攻速: %.2f, 激活组合: %s" % [
		get_final_damage(),
		get_final_attack_speed(),
		get_active_combo_names()
	])


func _on_tree_node_added(node: Node) -> void:
	if node == null or not node.is_in_group("tower"):
		return
	if _computed_stats.is_empty():
		call_deferred("recalculate_stats")
		return
	if not _has_runtime_stat_changes():
		return
	if node.has_method("apply_inventory_state"):
		node.apply_inventory_state(_computed_stats, _active_combos)


func _push_ui_inventory(snapshot: Array) -> void:
	var tree := get_tree()
	if tree == null:
		return

	var game_ui := tree.get_first_node_in_group("game_ui")
	if game_ui and game_ui.has_method("sync_inventory"):
		game_ui.sync_inventory(snapshot)


func _get_item_tags(item: Resource) -> Array[String]:
	var tags: Array[String] = []
	if item == null:
		return tags

	var raw_tags: Variant = item.get("tags")
	if raw_tags is PackedStringArray:
		for tag: String in raw_tags:
			tags.append(tag)
	elif raw_tags is Array:
		for tag_value: Variant in raw_tags:
			var tag := str(tag_value)
			if not tag.is_empty():
				tags.append(tag)

	return tags


func _get_item_float(item: Resource, property_name: String) -> float:
	if item == null:
		return 0.0
	return float(item.get(property_name))


func _get_total_effect_value_for_tag(tag: String) -> float:
	var total := 0.0
	for item_id in _item_resources.keys():
		var item: Resource = _item_resources[item_id]
		var tags: Array[String] = _get_item_tags(item)
		if tags.has(tag):
			total += _get_item_float(item, "effect_value") * int(_item_counts.get(item_id, 0))
	return total


func _spawn_dropped_pickup(item_resource: Resource, drop_position: Vector2) -> void:
	if item_resource == null:
		return
	if _item_pickup_scene == null:
		_item_pickup_scene = load(ITEM_PICKUP_SCENE_PATH) as PackedScene
	if _item_pickup_scene == null:
		push_warning("InventoryManager: ItemPickup scene not found.")
		return

	var pickup: Node2D = _item_pickup_scene.instantiate() as Node2D
	if pickup == null:
		return

	pickup.global_position = drop_position
	var launch_velocity := Vector2(
		randf_range(-180.0, 180.0),
		randf_range(-260.0, -120.0)
	)
	if pickup.has_method("setup"):
		pickup.setup(item_resource, launch_velocity)

	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		tree.current_scene.add_child(pickup)


func spawn_chest_pickup(drop_position: Vector2) -> void:
	if _chest_pickup_scene == null:
		_chest_pickup_scene = load(CHEST_PICKUP_SCENE_PATH) as PackedScene
	if _chest_pickup_scene == null:
		push_warning("InventoryManager: ChestPickup scene not found.")
		return

	var pickup: Node2D = _chest_pickup_scene.instantiate() as Node2D
	if pickup == null:
		return

	pickup.global_position = drop_position
	var launch_velocity := Vector2(
		randf_range(-120.0, 120.0),
		randf_range(-220.0, -90.0)
	)
	if pickup.has_method("setup"):
		pickup.setup(launch_velocity)

	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		tree.current_scene.add_child(pickup)


func _load_all_item_resources() -> Array[ItemData]:
	var all_items: Array[ItemData] = []
	var used_items: Dictionary = {}

	for item_dir: String in ITEM_DIRS:
		var dir := DirAccess.open(item_dir)
		if dir == null:
			continue

		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var item_path := "%s/%s" % [item_dir, file_name]
				if ResourceLoader.exists(item_path):
					var item_resource := load(item_path) as ItemData
					if item_resource != null:
						var item_key := _get_item_id(item_resource)
						if not used_items.has(item_key):
							used_items[item_key] = true
							all_items.append(item_resource)
			file_name = dir.get_next()
		dir.list_dir_end()

	return all_items


func _draw_random_item_from_pools(basic_pool: Array[ItemData], special_pool: Array[ItemData], basic_weight: float, special_weight: float) -> ItemData:
	var choose_basic := true
	if basic_pool.is_empty():
		choose_basic = false
	elif special_pool.is_empty():
		choose_basic = true
	else:
		choose_basic = randf() < basic_weight / (basic_weight + special_weight)

	var pool := basic_pool if choose_basic else special_pool
	if pool.is_empty():
		pool = special_pool if choose_basic else basic_pool
	if pool.is_empty():
		return null

	var total_weight := 0.0
	var weighted_items: Array[Dictionary] = []
	for item: ItemData in pool:
		if item == null:
			continue
		var item_weight := OWNED_ITEM_WEIGHT_BONUS if get_item_count(_get_item_id(item)) > 0 else 1.0
		total_weight += item_weight
		weighted_items.append({
			"item": item,
			"weight": item_weight
		})

	if total_weight <= 0.0:
		return null

	var cursor := randf() * total_weight
	for weighted_item: Dictionary in weighted_items:
		cursor -= float(weighted_item.get("weight", 0.0))
		if cursor <= 0.0:
			return weighted_item.get("item") as ItemData

	return weighted_items.back().get("item") as ItemData


func _is_heal_item(item: Resource) -> bool:
	return _get_item_tags(item).has("Heal")


func _apply_heal_item(item: Resource) -> void:
	var global_node := get_node_or_null("/root/Global")
	if global_node != null and is_instance_valid(global_node) and global_node.has_method("heal"):
		var heal_amount := maxi(1, int(round(_get_item_float(item, "effect_value"))))
		global_node.heal(heal_amount)
		_push_player_health_to_ui(global_node)


func _push_player_health_to_ui(global_node: Node) -> void:
	if global_node == null or not is_instance_valid(global_node):
		return

	var tree := get_tree()
	if tree == null:
		return

	var game_ui := tree.get_first_node_in_group("game_ui")
	if game_ui == null or not game_ui.has_method("update_health"):
		return

	var current_hp := int(global_node.get("player_hp"))
	game_ui.update_health(current_hp, 4)


func _can_receive_item(item: Resource) -> bool:
	if not _is_heal_item(item):
		return true

	var global_node := get_node_or_null("/root/Global")
	if global_node == null or not is_instance_valid(global_node):
		return true
	return int(global_node.get("player_hp")) < 4


func _has_runtime_stat_changes() -> bool:
	if not _item_counts.is_empty():
		return true
	if not _active_combos.is_empty():
		return true
	if not _computed_stats.is_empty():
		if not is_zero_approx(float(_computed_stats.get("damage_bonus", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("attack_speed_bonus", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("range_bonus", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("fire_damage_per_second", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("poison_damage_per_second", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("ice_slow_ratio", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("explosion_damage", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("crystal_damage", 0.0))):
			return true
		if not is_zero_approx(float(_computed_stats.get("mist_damage_per_second", 0.0))):
			return true
	return false


func reset_inventory() -> void:
	_item_counts.clear()
	_item_resources.clear()
	_tag_counts.clear()
	_computed_stats.clear()
	_active_combos.clear()
	_active_combo_names.clear()

	_emit_inventory_snapshot()
