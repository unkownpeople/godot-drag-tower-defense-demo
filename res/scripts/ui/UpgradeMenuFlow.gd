extends CanvasLayer

const BASIC_CARD_COLOR := Color("7f7f7f")
const RECOVERY_CARD_COLOR := Color("f7c9de")
const SPECIAL_CARD_COLOR := Color("c44f7e")
const HEART_ICON_PATH := "res://res/heart.svg"
const RANGE_ICON_PATH := "res://res/灯塔.svg"
const DAMAGE_ICON_PATH := "res://res/经验值.svg"
const SPEED_ICON_PATH := "res://res/玩家.svg"
const DEFAULT_ICON_PATH := "res://res/圆形.svg"
const UPGRADE_MANAGER_SCRIPT := preload("res://res/scripts/ui/UpgradeManager.gd")

@onready var _cards_container: HBoxContainer = $Overlay/CenterWrap/Panel/VBox/CardsContainer

var _upgrade_manager: RefCounted = UPGRADE_MANAGER_SCRIPT.new()
var _inventory_manager: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	randomize()
	_upgrade_manager.reload_items()
	_connect_global_signals()


func _get_global_node() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	var global_node: Node = tree.root.get_node_or_null("Global")
	if global_node == null or not is_instance_valid(global_node):
		return null
	return global_node


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


func _connect_global_signals() -> void:
	var global_node: Node = _get_global_node()
	if global_node == null:
		push_warning("UpgradeMenu: Global not found.")
		return

	if global_node.has_signal("level_up") and not global_node.level_up.is_connected(_on_global_level_up):
		global_node.level_up.connect(_on_global_level_up)


func display_upgrades() -> void:
	_upgrade_manager.reload_items()

	var inventory_counts: Dictionary = {}
	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager != null and inventory_manager.has_method("get_inventory_counts"):
		inventory_counts = inventory_manager.get_inventory_counts()

	var selected_items: Array[ItemData] = _upgrade_manager.draw_upgrades(inventory_counts, 3)
	selected_items = selected_items.filter(func(item: ItemData) -> bool:
		return item != null and not item.item_name.is_empty()
	)

	if selected_items.is_empty():
		push_warning("UpgradeMenu: no valid upgrades available.")
		var global_node: Node = _get_global_node()
		if global_node and global_node.has_method("complete_level_up"):
			global_node.complete_level_up()
		return

	_rebuild_cards(selected_items)
	visible = true
	var tree := get_tree()
	if tree:
		tree.paused = true


func _rebuild_cards(items: Array[ItemData]) -> void:
	for child: Node in _cards_container.get_children():
		child.queue_free()

	for item: ItemData in items:
		_cards_container.add_child(_create_card(item))


func _create_card(item: ItemData) -> Button:
	if item == null:
		return Button.new()

	var card := Button.new()
	card.custom_minimum_size = Vector2(240, 320)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	card.flat = true
	card.button_down.connect(_on_card_button_down.bind(card))
	card.button_up.connect(_on_card_button_up.bind(card))
	card.pressed.connect(_on_card_selected.bind(item))

	var style := StyleBoxFlat.new()
	style.bg_color = _get_card_color(item)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_right = 24
	style.corner_radius_bottom_left = 24
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(1, 1, 1, 0.15)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style.duplicate())
	card.add_theme_stylebox_override("pressed", style.duplicate())
	card.add_theme_stylebox_override("focus", style.duplicate())

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 14)
	card.add_child(content)

	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(88, 88)
	icon_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(1, 1, 1, 0.18)
	icon_style.corner_radius_top_left = 18
	icon_style.corner_radius_top_right = 18
	icon_style.corner_radius_bottom_right = 18
	icon_style.corner_radius_bottom_left = 18
	icon_panel.add_theme_stylebox_override("panel", icon_style)
	content.add_child(icon_panel)

	var icon := TextureRect.new()
	icon.texture = _get_icon_for_item(item)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(56, 56)
	icon.modulate = _get_icon_modulate(item)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon_panel.add_child(icon)

	var name_label := Label.new()
	name_label.text = item.item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = item.description_text
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(desc_label)

	return card


func _get_card_color(item: ItemData) -> Color:
	if item.tags.has("Heal"):
		return RECOVERY_CARD_COLOR
	if item.item_type == ItemData.ItemType.SPECIAL:
		return SPECIAL_CARD_COLOR
	return BASIC_CARD_COLOR


func _get_icon_for_item(item: ItemData) -> Texture2D:
	if item.tags.has("Heal"):
		return _load_icon_or_placeholder(HEART_ICON_PATH, Color(0.95, 0.65, 0.75, 1.0))

	if item.tags.has("Range"):
		return _load_icon_or_placeholder(RANGE_ICON_PATH, Color(0.75, 0.85, 1.0, 1.0))
	if item.tags.has("Damage"):
		return _load_icon_or_placeholder(DAMAGE_ICON_PATH, Color(1.0, 0.78, 0.45, 1.0))
	if item.tags.has("Speed"):
		return _load_icon_or_placeholder(SPEED_ICON_PATH, Color(0.65, 1.0, 0.75, 1.0))
	return _load_icon_or_placeholder(DEFAULT_ICON_PATH, Color(0.82, 0.82, 0.82, 1.0))


func _get_icon_modulate(item: ItemData) -> Color:
	match item.category:
		ItemData.SpecialCategory.FIRE:
			return Color("ffb26a")
		ItemData.SpecialCategory.ICE:
			return Color("a8f1ff")
		ItemData.SpecialCategory.POISON:
			return Color("a6ff8d")
		_:
			return Color.WHITE


func _on_card_button_down(card: Button) -> void:
	card.scale = Vector2(0.97, 0.97)


func _on_card_button_up(card: Button) -> void:
	card.scale = Vector2.ONE


func _on_card_selected(selected_item: ItemData) -> void:
	var inventory_manager: Node = _get_inventory_manager()
	if inventory_manager != null and inventory_manager.has_method("add_item"):
		inventory_manager.add_item(selected_item)

	var tree := get_tree()
	var global_node: Node = _get_global_node()
	if global_node and global_node.has_method("complete_level_up"):
		global_node.complete_level_up()
	else:
		if tree:
			tree.paused = false

	visible = false


func _on_global_level_up() -> void:
	display_upgrades()


func _load_icon_or_placeholder(path: String, placeholder_color: Color) -> Texture2D:
	if FileAccess.file_exists(path):
		var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
		if texture != null:
			return texture
	return _create_placeholder_texture(placeholder_color)


func _create_placeholder_texture(color: Color) -> Texture2D:
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
