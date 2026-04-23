extends CanvasLayer

const MAIN_MENU_SCENE_PATH: String = "res://res/scenes/ui/MainMenu.tscn"
const TITLE_VICTORY: String = "任务达成"
const TITLE_DEFEAT: String = "战损结算"
const STATS_TEMPLATE: String = "本局存活时间：%s\n击杀数：%d"

@onready var _fade_overlay: ColorRect = %FadeOverlay
@onready var _grayscale_modulate: CanvasModulate = %GrayModulate
@onready var _panel: PanelContainer = %Panel
@onready var _title_label: Label = %TitleLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _restart_button: Button = %RestartButton
@onready var _quit_button: Button = %QuitButton

var _global: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel.visible = false
	_fade_overlay.visible = false
	_grayscale_modulate.visible = false

	var tree := get_tree()
	if tree != null and tree.root != null:
		_global = tree.root.get_node_or_null("Global")
	if _global != null and is_instance_valid(_global):
		if _global.has_signal("game_over") and not _global.game_over.is_connected(_on_game_over):
			_global.game_over.connect(_on_game_over)
		if _global.has_signal("game_victory") and not _global.game_victory.is_connected(_on_game_victory):
			_global.game_victory.connect(_on_game_victory)

	if _restart_button != null and not _restart_button.pressed.is_connected(_on_restart_pressed):
		_restart_button.pressed.connect(_on_restart_pressed)
	if _quit_button != null and not _quit_button.pressed.is_connected(_on_quit_pressed):
		_quit_button.pressed.connect(_on_quit_pressed)


func _on_game_over() -> void:
	_show_defeat_sequence()


func _on_game_victory() -> void:
	_show_victory_sequence()


func _show_defeat_sequence() -> void:
	visible = true
	_panel.visible = false
	_fade_overlay.visible = true
	_fade_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_grayscale_modulate.visible = true
	_grayscale_modulate.color = Color(0.62, 0.62, 0.62, 1.0)

	_title_label.text = TITLE_DEFEAT
	_stats_label.text = _build_stats_text()

	var tween: Tween = create_tween()
	tween.tween_property(_fade_overlay, "color", Color(0.0, 0.0, 0.0, 0.45), 0.35)
	tween.tween_callback(_show_panel_and_pause)


func _show_victory_sequence() -> void:
	visible = true
	_panel.visible = false
	_fade_overlay.visible = true
	_fade_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	_grayscale_modulate.visible = false

	_title_label.text = TITLE_VICTORY
	_stats_label.text = _build_stats_text()

	Engine.time_scale = 0.5
	var tween: Tween = create_tween()
	tween.tween_property(_fade_overlay, "color", Color(1.0, 1.0, 1.0, 0.28), 0.45)
	tween.tween_interval(0.35)
	tween.tween_callback(_show_panel_and_pause)


func _show_panel_and_pause() -> void:
	Engine.time_scale = 1.0
	_panel.visible = true
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = true


func _build_stats_text() -> String:
	var survival_time: float = 0.0
	var kill_count: int = 0
	if _global != null and is_instance_valid(_global):
		survival_time = float(_global.get("survival_time"))
		kill_count = int(_global.get("kill_count"))

	return STATS_TEMPLATE % [_format_time(survival_time), kill_count]


func _format_time(total_seconds: float) -> String:
	var seconds: int = maxi(0, int(floor(total_seconds)))
	var minutes: int = seconds / 60
	var remaining_seconds: int = seconds % 60
	return "%02d:%02d" % [minutes, remaining_seconds]


func _on_restart_pressed() -> void:
	if _global != null and is_instance_valid(_global) and _global.has_method("reset_game_state"):
		_global.reset_game_state()

	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
		tree.reload_current_scene()


func _on_quit_pressed() -> void:
	if _global != null and is_instance_valid(_global) and _global.has_method("reset_game_state"):
		_global.reset_game_state()

	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
		tree.change_scene_to_file(MAIN_MENU_SCENE_PATH)
