extends RefCounted
class_name UpgradeManager

const ITEM_DIRS: PackedStringArray = ["res://Items", "res://res/Items"]
const BASIC_WEIGHT: float = 0.7
const SPECIAL_WEIGHT: float = 0.3
const OWNED_BONUS_MULTIPLIER: float = 1.5

var _all_items: Array[ItemData] = []
var _basic_items: Array[ItemData] = []
var _special_items: Array[ItemData] = []


func reload_items() -> void:
	_all_items.clear()
	_basic_items.clear()
	_special_items.clear()

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
				if not ResourceLoader.exists(item_path):
					file_name = dir.get_next()
					continue

				var item_resource: ItemData = load(item_path) as ItemData
				if item_resource != null:
					var item_key := _get_item_id(item_resource)
					if not used_items.has(item_key):
						used_items[item_key] = true
						_all_items.append(item_resource)
			file_name = dir.get_next()
		dir.list_dir_end()

	for item: ItemData in _all_items:
		if not _can_offer_item(item):
			continue
		if item.item_type == ItemData.ItemType.SPECIAL:
			_special_items.append(item)
		else:
			_basic_items.append(item)


func draw_upgrades(inventory_counts: Dictionary, count: int = 3) -> Array[ItemData]:
	if _all_items.is_empty():
		reload_items()

	var selected_items: Array[ItemData] = []
	var basic_pool: Array[ItemData] = _basic_items.duplicate()
	var special_pool: Array[ItemData] = _special_items.duplicate()

	while selected_items.size() < count and (not basic_pool.is_empty() or not special_pool.is_empty()):
		var choose_basic: bool = _choose_basic_pool(basic_pool, special_pool)
		var chosen_pool: Array[ItemData] = basic_pool if choose_basic else special_pool
		if chosen_pool.is_empty():
			chosen_pool = special_pool if choose_basic else basic_pool
		if chosen_pool.is_empty():
			break

		var selected_item: ItemData = _pick_weighted_item(chosen_pool, inventory_counts)
		if selected_item == null:
			break

		selected_items.append(selected_item)
		if choose_basic:
			basic_pool.erase(selected_item)
		else:
			special_pool.erase(selected_item)
		if basic_pool.has(selected_item):
			basic_pool.erase(selected_item)
		if special_pool.has(selected_item):
			special_pool.erase(selected_item)

	return selected_items


func _choose_basic_pool(basic_pool: Array[ItemData], special_pool: Array[ItemData]) -> bool:
	if basic_pool.is_empty():
		return false
	if special_pool.is_empty():
		return true
	return randf() < BASIC_WEIGHT / (BASIC_WEIGHT + SPECIAL_WEIGHT)


func _pick_weighted_item(pool: Array[ItemData], inventory_counts: Dictionary) -> ItemData:
	var total_weight: float = 0.0
	var weighted_items: Array[Dictionary] = []

	for item: ItemData in pool:
		if item == null:
			continue
		var weight: float = 1.0
		var item_id := _get_item_id(item)
		if int(inventory_counts.get(item_id, 0)) > 0:
			weight *= OWNED_BONUS_MULTIPLIER
		total_weight += weight
		weighted_items.append({
			"item": item,
			"weight": weight
		})

	if total_weight <= 0.0:
		return null

	var cursor: float = randf() * total_weight
	for weighted_item: Dictionary in weighted_items:
		cursor -= float(weighted_item["weight"])
		if cursor <= 0.0:
			return weighted_item["item"] as ItemData

	return weighted_items.back().get("item") as ItemData


func _get_item_id(item: ItemData) -> String:
	if item == null:
		return ""
	if not item.item_name.is_empty():
		return item.item_name
	if not item.resource_path.is_empty():
		return item.resource_path.get_file().get_basename()
	return str(item.get_instance_id())


func _can_offer_item(item: ItemData) -> bool:
	if item == null:
		return false
	if not item.tags.has("Heal"):
		return true

	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var global_node: Node = tree.root.get_node_or_null("Global")
	if global_node == null or not is_instance_valid(global_node):
		return true
	return int(global_node.get("player_hp")) < 4
