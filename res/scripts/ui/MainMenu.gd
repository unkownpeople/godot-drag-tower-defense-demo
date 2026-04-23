extends CanvasLayer

const GAME_SCENE_PATH: String = "res://Main.tscn"

@onready var _start_button: TextureButton = $Root/HouseBody/StartButton
@onready var _items_button: TextureButton = $Root/HouseBody/ItemsButton
@onready var _settings_button: TextureButton = $Root/HouseBody/SettingsButton
@onready var _quit_button: TextureButton = $Root/HouseBody/QuitButton
@onready var _popup_overlay: Control = $Root/PopupOverlay
@onready var _popup_title: Label = $Root/PopupOverlay/CenterWrap/Panel/VBox/PopupTitle
@onready var _popup_body: Label = $Root/PopupOverlay/CenterWrap/Panel/VBox/PopupBody
@onready var _popup_close_button: Button = $Root/PopupOverlay/CenterWrap/Panel/VBox/PopupCloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_popup_overlay.visible = false

	_connect_button(_start_button, _on_start_pressed)
	_connect_button(_items_button, _on_items_pressed)
	_connect_button(_settings_button, _on_settings_pressed)
	_connect_button(_quit_button, _on_quit_pressed)

	if _popup_close_button != null and not _popup_close_button.pressed.is_connected(_hide_popup):
		_popup_close_button.pressed.connect(_hide_popup)


func _unhandled_input(event: InputEvent) -> void:
	if not _popup_overlay.visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_hide_popup()
		get_viewport().set_input_as_handled()


func _connect_button(button: TextureButton, callable: Callable) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(callable):
		button.pressed.connect(callable)
	if not button.mouse_entered.is_connected(_on_button_hovered.bind(button, true)):
		button.mouse_entered.connect(_on_button_hovered.bind(button, true))
	if not button.mouse_exited.is_connected(_on_button_hovered.bind(button, false)):
		button.mouse_exited.connect(_on_button_hovered.bind(button, false))
	if not button.focus_entered.is_connected(_on_button_hovered.bind(button, true)):
		button.focus_entered.connect(_on_button_hovered.bind(button, true))
	if not button.focus_exited.is_connected(_on_button_hovered.bind(button, false)):
		button.focus_exited.connect(_on_button_hovered.bind(button, false))


func _on_button_hovered(button: TextureButton, is_hovered: bool) -> void:
	if button == null:
		return
	button.modulate = Color(1.08, 1.08, 1.08, 1.0) if is_hovered else Color(1.0, 1.0, 1.0, 1.0)


func _on_start_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	tree.paused = false
	Engine.time_scale = 1.0

	var global: Node = null
	if tree.root != null:
		global = tree.root.get_node_or_null("Global")
	if global != null and is_instance_valid(global) and global.has_method("reset_game_state"):
		global.reset_game_state()

	tree.change_scene_to_file(GAME_SCENE_PATH)


func _on_items_pressed() -> void:
	_show_popup("物品效果", "这里先作为查看物品效果的入口。\n后续可以继续补已解锁物品、组合说明和掉落图鉴。")


func _on_settings_pressed() -> void:
	_show_popup("设置", "这里先作为设置入口。\n后续建议补音量、操作说明和返回主菜单确认。")


func _on_quit_pressed() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.quit()


func _show_popup(title: String, body: String) -> void:
	_popup_title.text = title
	_popup_body.text = body
	_popup_overlay.visible = true


func _hide_popup() -> void:
	_popup_overlay.visible = false
