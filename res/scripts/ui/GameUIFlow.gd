extends CanvasLayer

const HEART_ICON_PATH := "res://res/heart.svg"
const RANGE_ICON_PATH := "res://res/灯塔.svg"
const DAMAGE_ICON_PATH := "res://res/经验值.svg"
const SPEED_ICON_PATH := "res://res/玩家.svg"
const DEFAULT_ICON_PATH := "res://res/圆形.svg"

const MAX_HEALTH: int = 4
const EXP_THRESHOLD: int = 20
const LEVEL_UP_TEXT_LIFETIME: float = 1.0
const LEVEL_UP_TEXT_RISE_SPEED: float = 28.0
const STATUS_HINT_PULSE_SPEED: float = 5.0
const HUD_PRIMARY_Z: int = 20
const HUD_ALERT_Z: int = 30
const HUD_FLASH_Z: int = 40

@onready var _hearts_container: HBoxContainer = %HeartsContainer
@onready var _exp_label: Label = %Label
@onready var _exp_bar: ProgressBar = %ProgressBar
@onready var _items_list: VBoxContainer = %ItemsList
@onready var _wave_label: Label = $WaveLabel
@onready var _boss_bar: ProgressBar = $BossBar
@onready var _boss_alert: TextureRect = $BossAlert

class ItemSlot:
	var item_id: String
	var item_name: String
	var icon: Texture2D
	var count: int
	var node: Control

var _item_queue: Array[ItemSlot] = []
var _item_dict: Dictionary = {}
var _warning_tween: Tween
var _flash_tween: Tween
var _level_up_label: Label
var _level_up_label_time_left: float = 0.0
var _level_up_label_rise: float = 0.0
var _wave_tween: Tween
var _last_wave_number: int = -1
var _boss_alert_tween: Tween
var _wave_label_base_position: Vector2 = Vector2.ZERO
var _tower_status_label: Label
var _global: Node = null
var _inventory_manager: Node = null
var _cached_player: Node2D = null
var _cached_tower: Node = null
var _cached_spawner: Node = null
var _cached_boss: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_ui")
	_configure_ui_stack()
	if _wave_label != null:
		_wave_label_base_position = _wave_label.position
	_create_level_up_label()
	_create_tower_status_label()
	_connect_damage_signals()
	_connect_progress_signals()
	_connect_inventory_signals()
	_refresh_hearts()
	_refresh_exp_bar()


func _configure_ui_stack() -> void:
	layer = 10
	if _wave_label != null:
		_wave_label.z_index = HUD_PRIMARY_Z
	if _boss_bar != null:
		_boss_bar.z_index = HUD_PRIMARY_Z
	if _boss_alert != null:
		_boss_alert.z_index = HUD_ALERT_Z


func _process(delta: float) -> void:
	_update_level_up_label(delta)
	_update_tower_status_ui()
	_update_wave_ui()
	_update_boss_ui()


func _get_global() -> Node:
	if _global != null and is_instance_valid(_global):
		return _global

	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	_global = tree.root.get_node_or_null("Global")
	if _global == null or not is_instance_valid(_global):
		_global = null
	return _global


func _get_inventory_manager() -> Node:
	if _inventory_manager != null and is_instance_valid(_inventory_manager):
		return _inventory_manager

	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	_inventory_manager = tree.root.get_node_or_null("InventoryManager")
	if _inventory_manager == null or not is_instance_valid(_inventory_manager):
		_inventory_manager = null
	return _inventory_manager


func _get_player() -> Node2D:
	if _cached_player != null and is_instance_valid(_cached_player):
		return _cached_player

	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	_cached_player = tree.get_first_node_in_group("player") as Node2D
	if _cached_player == null or not is_instance_valid(_cached_player):
		_cached_player = null
	return _cached_player


func _connect_damage_signals() -> void:
	var g := _get_global()
	if g and g.has_signal("player_damaged") and not g.player_damaged.is_connected(_on_player_damaged):
		g.player_damaged.connect(_on_player_damaged)
	if g and g.has_signal("player_health_changed") and not g.player_health_changed.is_connected(_on_player_health_changed):
		g.player_health_changed.connect(_on_player_health_changed)


func _connect_progress_signals() -> void:
	var g := _get_global()
	if not g:
		return

	if g.has_signal("exp_changed") and not g.exp_changed.is_connected(_on_global_exp_changed):
		g.exp_changed.connect(_on_global_exp_changed)

	if g.has_signal("level_up") and not g.level_up.is_connected(_on_global_level_up):
		g.level_up.connect(_on_global_level_up)


func _connect_inventory_signals() -> void:
	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager and inventory_manager.has_signal("inventory_changed"):
		if not inventory_manager.inventory_changed.is_connected(_on_inventory_changed):
			inventory_manager.inventory_changed.connect(_on_inventory_changed)
		if inventory_manager.has_method("get_inventory_snapshot"):
			_on_inventory_changed(inventory_manager.get_inventory_snapshot())


func update_health(current_hp: int, max_hp: int = MAX_HEALTH) -> void:
	if not _hearts_container:
		return

	var hearts: Array = _hearts_container.get_children()
	for i: int in range(hearts.size()):
		if i < current_hp:
			_set_heart_full(hearts[i])
		else:
			_set_heart_empty(hearts[i])

	if current_hp == 1:
		_start_warning_glow()
	elif _warning_tween:
		_warning_tween.kill()
		_update_warning_glow_visible(false)


func _set_heart_full(heart: TextureRect) -> void:
	if heart:
		heart.self_modulate = Color.WHITE


func _set_heart_empty(heart: TextureRect) -> void:
	if heart:
		heart.self_modulate = Color(0.4, 0.4, 0.4, 0.6)


func _start_warning_glow() -> void:
	if not _hearts_container:
		return

	var hearts: Array = _hearts_container.get_children()
	if hearts.size() > 0:
		_update_warning_glow_visible(true)
		_warning_tween = create_tween()
		_warning_tween.set_loops()
		_warning_tween.tween_method(_pulse_warning, 0.2, 0.7, 0.5)


func _pulse_warning(value: float) -> void:
	if _hearts_container:
		var hearts: Array = _hearts_container.get_children()
		if hearts.size() > 0:
			hearts[0].self_modulate = Color(1, value, value, 1)


func _on_player_damaged(_amount: int) -> void:
	var current_hp := MAX_HEALTH
	var g := _get_global()
	if g and "player_hp" in g:
		current_hp = g.get("player_hp")
	update_health(current_hp)
	_play_damage_flash()


func _on_player_health_changed(current_hp: int, max_hp: int) -> void:
	update_health(current_hp, max_hp)


func _update_warning_glow_visible(visible: bool) -> void:
	if _hearts_container:
		var hearts: Array = _hearts_container.get_children()
		if hearts.size() > 0:
			hearts[0].self_modulate = Color.WHITE if not visible else Color(1, 0.5, 0.5, 1)


func update_exp(current_exp: int, max_exp: int = EXP_THRESHOLD) -> void:
	if not _exp_bar or not _exp_label:
		return

	_exp_bar.max_value = max_exp
	_exp_bar.value = current_exp
	_exp_label.text = "%d / %d" % [current_exp, max_exp]


func flash_exp_bar() -> void:
	if not _exp_bar:
		return

	if _flash_tween:
		_flash_tween.kill()

	_flash_tween = create_tween()
	_flash_tween.tween_property(_exp_bar, "modulate", Color(1, 1, 0.5, 1), 0.1)
	_flash_tween.tween_property(_exp_bar, "modulate", Color.WHITE, 0.2)


func _on_global_exp_changed(current_exp: int, threshold: int) -> void:
	update_exp(current_exp, threshold)
	if current_exp >= threshold:
		flash_exp_bar()


func _on_global_level_up() -> void:
	flash_exp_bar()
	_show_level_up_text()


func _on_inventory_changed(items: Array) -> void:
	sync_inventory(items)
	call_deferred("_refresh_exp_bar")


func sync_inventory(items: Array) -> void:
	_rebuild_item_list(items)


func _get_item_icon(item: Resource) -> Texture2D:
	if item == null:
		return _load_icon_or_placeholder(HEART_ICON_PATH, Color(0.85, 0.85, 0.85, 1.0))

	if _item_has_tag(item, "Heal"):
		return _load_icon_or_placeholder(HEART_ICON_PATH, Color(0.95, 0.65, 0.75, 1.0))

	var tags: Variant = item.get("tags")
	if tags is PackedStringArray or tags is Array:
		if tags.has("Range"):
			return _load_icon_or_placeholder(RANGE_ICON_PATH, Color(0.75, 0.85, 1.0, 1.0))
		if tags.has("Damage"):
			return _load_icon_or_placeholder(DAMAGE_ICON_PATH, Color(1.0, 0.78, 0.45, 1.0))
		if tags.has("Speed"):
			return _load_icon_or_placeholder(SPEED_ICON_PATH, Color(0.65, 1.0, 0.75, 1.0))
	return _load_icon_or_placeholder(DEFAULT_ICON_PATH, Color(0.82, 0.82, 0.82, 1.0))


func _item_has_tag(item: Resource, tag_name: String) -> bool:
	if item == null:
		return false

	var tags: Variant = item.get("tags")
	if tags is PackedStringArray or tags is Array:
		return tags.has(tag_name)
	return false


func _rebuild_item_list(items: Array) -> void:
	_clear_item_list()

	for entry_variant: Variant in items:
		var entry: Dictionary = entry_variant
		var item_id := str(entry.get("id", ""))
		var item_name := str(entry.get("name", item_id))
		var count := int(entry.get("count", 0))
		var item_resource: Resource = entry.get("item", null)
		_add_inventory_entry(item_id, item_name, count, _get_item_icon(item_resource))


func _clear_item_list() -> void:
	for child: Node in _items_list.get_children():
		child.queue_free()
	_item_queue.clear()
	_item_dict.clear()


func _add_inventory_entry(item_id: String, item_name: String, count: int, icon: Texture2D) -> void:
	var slot := ItemSlot.new()
	slot.item_id = item_id
	slot.item_name = item_name
	slot.icon = icon
	slot.count = count
	slot.node = null

	var item_node := HBoxContainer.new()
	item_node.name = "Item_%s" % item_id
	item_node.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = Vector2(32, 32)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = icon if icon else _load_icon_or_placeholder(HEART_ICON_PATH, Color(0.85, 0.85, 0.85, 1.0))
	item_node.add_child(icon_rect)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_node.add_child(name_label)

	var count_label := Label.new()
	count_label.name = "Count"
	count_label.text = "x%d" % count
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	item_node.add_child(count_label)

	_items_list.add_child(item_node)
	slot.node = item_node
	_item_dict[item_id] = slot
	_item_queue.push_back(slot)


func _refresh_hearts() -> void:
	var current_hp := MAX_HEALTH
	var g := _get_global()
	if g and "player_hp" in g:
		current_hp = g.get("player_hp")
	update_health(current_hp)


func _refresh_exp_bar() -> void:
	var g := _get_global()
	if g:
		var current_exp: int = int(g.get("current_exp")) if "current_exp" in g else 0
		var max_exp: int = int(g.get("_exp_threshold")) if "_exp_threshold" in g else EXP_THRESHOLD
		update_exp(current_exp, max_exp)


func _play_damage_flash() -> void:
	var screen_flash := ColorRect.new()
	screen_flash.name = "DamageFlash"
	screen_flash.color = Color(1, 0, 0, 0.3)
	screen_flash.z_index = HUD_FLASH_Z
	screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen_flash)

	var tween := create_tween()
	tween.tween_property(screen_flash, "color:a", 0.0, 0.3)
	tween.tween_callback(screen_flash.queue_free)


func _create_level_up_label() -> void:
	_level_up_label = Label.new()
	_level_up_label.text = "Level Up!"
	_level_up_label.visible = false
	_level_up_label.z_index = HUD_ALERT_Z
	_level_up_label.add_theme_font_size_override("font_size", 28)
	_level_up_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1.0))
	_level_up_label.add_theme_constant_override("outline_size", 6)
	_level_up_label.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.1, 0.9))
	add_child(_level_up_label)


func _create_tower_status_label() -> void:
	_tower_status_label = _create_overlay_label(22, Color(1.0, 1.0, 1.0, 1.0), Color(0.08, 0.08, 0.08, 0.85))
	_tower_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tower_status_label.size = Vector2(520.0, 40.0)
	_tower_status_label.position = Vector2(380.0, 620.0)
	_tower_status_label.visible = false
	add_child(_tower_status_label)


func _create_overlay_label(font_size: int, font_color: Color, outline_color: Color) -> Label:
	var label := Label.new()
	label.visible = true
	label.z_index = HUD_ALERT_Z
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", outline_color)
	return label


func _show_level_up_text() -> void:
	_level_up_label_time_left = LEVEL_UP_TEXT_LIFETIME
	_level_up_label_rise = 0.0
	_level_up_label.modulate = Color(1, 1, 1, 1)
	_level_up_label.visible = true
	_update_level_up_label_position()


func _update_tower_status_ui() -> void:
	if _tower_status_label == null:
		return

	var tower := _get_tower()
	if tower == null:
		_tower_status_label.visible = false
		return

	if tower.has_method("is_drop_warning_active") and bool(tower.is_drop_warning_active()):
		var hits_left := int(tower.get_hits_until_drop()) if tower.has_method("get_hits_until_drop") else 0
		_tower_status_label.text = "塔即将掉落物品，再受击 %d 次" % hits_left
		_tower_status_label.modulate = Color(1.0, 0.4 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * STATUS_HINT_PULSE_SPEED), 0.4, 1.0)
		_tower_status_label.visible = true
		return

	_tower_status_label.visible = false


func _update_level_up_label(delta: float) -> void:
	if _level_up_label == null or not _level_up_label.visible:
		return

	_level_up_label_time_left -= delta
	_level_up_label_rise += LEVEL_UP_TEXT_RISE_SPEED * delta
	_update_level_up_label_position()

	var alpha := clampf(_level_up_label_time_left / LEVEL_UP_TEXT_LIFETIME, 0.0, 1.0)
	_level_up_label.modulate.a = alpha
	if _level_up_label_time_left <= 0.0:
		_level_up_label.visible = false


func _update_level_up_label_position() -> void:
	var player: Node2D = _get_player()
	if player == null or _level_up_label == null:
		return

	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * player.global_position
	_level_up_label.position = screen_pos + Vector2(-48.0, -80.0 - _level_up_label_rise)


func _get_tower() -> Node:
	if _cached_tower != null and is_instance_valid(_cached_tower):
		return _cached_tower

	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	_cached_tower = tree.get_first_node_in_group("tower")
	if _cached_tower == null or not is_instance_valid(_cached_tower):
		_cached_tower = null
	return _cached_tower


func _load_icon_or_placeholder(path: String, placeholder_color: Color) -> Texture2D:
	if FileAccess.file_exists(path):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			return texture
	return _create_placeholder_texture(placeholder_color)


func _create_placeholder_texture(color: Color) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _get_spawner() -> Node:
	if _cached_spawner != null and is_instance_valid(_cached_spawner):
		return _cached_spawner

	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_cached_spawner = tree.current_scene.get_node_or_null("Spawner")
	if _cached_spawner == null or not is_instance_valid(_cached_spawner):
		_cached_spawner = null
	return _cached_spawner


func _update_wave_ui() -> void:
	var spawner := _get_spawner()
	if spawner == null:
		return

	var current_wave := int(spawner.get("current_wave"))
	if current_wave <= 0 or current_wave == _last_wave_number:
		return

	_last_wave_number = current_wave
	_show_wave_label("Wave %d" % current_wave)


func _show_wave_label(text: String) -> void:
	if _wave_label == null:
		return

	if _wave_tween:
		_wave_tween.kill()

	_wave_label.text = text
	_wave_label.visible = true
	_wave_label.modulate = Color(1, 1, 1, 1)
	_wave_label.scale = Vector2(0.85, 0.85)
	_wave_label.position = _wave_label_base_position

	_wave_tween = create_tween()
	_wave_tween.tween_property(_wave_label, "scale", Vector2.ONE, 0.18)
	_wave_tween.parallel().tween_property(_wave_label, "position:y", _wave_label.position.y - 12.0, 0.18)
	_wave_tween.tween_interval(0.6)
	_wave_tween.tween_property(_wave_label, "modulate:a", 0.0, 0.25)
	_wave_tween.tween_callback(func() -> void:
		_wave_label.visible = false
		_wave_label.modulate.a = 1.0
		_wave_label.position = _wave_label_base_position
	)


func _update_boss_ui() -> void:
	if _boss_bar == null or _boss_alert == null:
		return

	var boss_enemy := _find_active_boss()
	if boss_enemy == null:
		_boss_bar.visible = false
		_boss_alert.visible = false
		if _boss_alert_tween:
			_boss_alert_tween.kill()
			_boss_alert_tween = null
		return

	_boss_bar.visible = true
	if boss_enemy.has_method("get_health_ratio"):
		_boss_bar.value = float(boss_enemy.get_health_ratio()) * 100.0

	var charging := boss_enemy.has_method("is_boss_charging") and bool(boss_enemy.is_boss_charging())
	_boss_alert.visible = charging
	if charging:
		_start_boss_alert_pulse()
	elif _boss_alert_tween:
		_boss_alert_tween.kill()
		_boss_alert_tween = null
		_boss_alert.scale = Vector2.ONE
		_boss_alert.modulate = Color(1, 1, 1, 1)


func _find_active_boss() -> Node:
	if _cached_boss != null and is_instance_valid(_cached_boss):
		if _cached_boss.has_method("is_boss_enemy") and bool(_cached_boss.is_boss_enemy()):
			return _cached_boss
		_cached_boss = null

	var tree: SceneTree = get_tree()
	if tree == null:
		return null

	for enemy: Node in tree.get_nodes_in_group("enemy"):
		if enemy != null and is_instance_valid(enemy) and enemy.has_method("is_boss_enemy") and bool(enemy.is_boss_enemy()):
			_cached_boss = enemy
			return enemy
	_cached_boss = null
	return null


func _start_boss_alert_pulse() -> void:
	if _boss_alert_tween != null or _boss_alert == null:
		return

	_boss_alert.scale = Vector2.ONE
	_boss_alert.modulate = Color(1, 1, 1, 1)
	_boss_alert_tween = create_tween()
	_boss_alert_tween.set_loops()
	_boss_alert_tween.tween_property(_boss_alert, "scale", Vector2(1.12, 1.12), 0.28)
	_boss_alert_tween.parallel().tween_property(_boss_alert, "modulate:a", 0.5, 0.28)
	_boss_alert_tween.tween_property(_boss_alert, "scale", Vector2.ONE, 0.28)
	_boss_alert_tween.parallel().tween_property(_boss_alert, "modulate:a", 1.0, 0.28)
