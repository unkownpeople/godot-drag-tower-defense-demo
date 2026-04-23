extends Node

signal enemy_died(exp: int)
signal exp_changed(current_exp: int, threshold: int)
signal level_up()
signal item_applied(item: Resource)
signal player_damaged(amount: int)
signal player_health_changed(current_hp: int, max_hp: int)
signal screen_shake_requested(intensity: float, duration: float)
signal boss_defeated(kill_count: int, elapsed_time: float)
signal game_over()
signal game_victory()

const BASE_EXP_THRESHOLD: int = 40
const EXP_THRESHOLD_STEP: int = 25
const MAX_PLAYER_HP: int = 4

var current_exp: int = 0
var current_level: int = 1
var player_hp: int = MAX_PLAYER_HP
var kill_count: int = 0
var survival_time: float = 0.0
var elapsed_time: float = 0.0
var _exp_threshold: int = BASE_EXP_THRESHOLD
var _pending_level_ups: int = 0
var _level_up_active: bool = false
var _session_finished: bool = false


func _ready() -> void:
	if not enemy_died.is_connected(_on_enemy_died):
		enemy_died.connect(_on_enemy_died)
	if not boss_defeated.is_connected(_on_boss_defeated):
		boss_defeated.connect(_on_boss_defeated)


func _process(delta: float) -> void:
	if _session_finished:
		return
	survival_time += delta
	elapsed_time += delta

func add_exp(amount: int) -> void:
	if amount <= 0:
		return

	current_exp += amount

	var leveled_up: bool = false
	while current_exp >= _exp_threshold:
		current_exp -= _exp_threshold
		current_level += 1
		_pending_level_ups += 1
		_exp_threshold = _get_threshold_for_level(current_level)
		leveled_up = true

	exp_changed.emit(current_exp, _exp_threshold)

	if leveled_up:
		_start_next_level_up()

func take_damage(hp_loss: int = 1) -> void:
	if _session_finished:
		return
	player_hp = maxi(0, player_hp - hp_loss)
	player_damaged.emit(hp_loss)
	player_health_changed.emit(player_hp, MAX_PLAYER_HP)
	screen_shake_requested.emit(10.0, 0.18)
	if player_hp <= 0:
		_trigger_game_over()

func heal(amount: int = 1) -> void:
	if _session_finished:
		return
	player_hp = mini(MAX_PLAYER_HP, player_hp + maxi(0, amount))
	player_health_changed.emit(player_hp, MAX_PLAYER_HP)

func reset_exp() -> void:
	complete_level_up()


func complete_level_up() -> void:
	if _pending_level_ups > 0:
		_pending_level_ups -= 1

	_level_up_active = false
	exp_changed.emit(current_exp, _exp_threshold)
	player_health_changed.emit(player_hp, MAX_PLAYER_HP)
	if _pending_level_ups > 0:
		call_deferred("_start_next_level_up")
		return

	var tree := get_tree()
	if tree:
		tree.paused = false


func _on_enemy_died(exp: int) -> void:
	if _session_finished:
		return
	kill_count += 1
	add_exp(exp)


func _on_boss_defeated(_final_kills: int, _final_time: float) -> void:
	if _session_finished:
		return
	_session_finished = true
	game_victory.emit()


func _trigger_game_over() -> void:
	if _session_finished:
		return
	_session_finished = true
	game_over.emit()


func reset_game_state() -> void:
	_session_finished = false
	current_exp = 0
	current_level = 1
	player_hp = MAX_PLAYER_HP
	kill_count = 0
	survival_time = 0.0
	elapsed_time = 0.0
	_exp_threshold = BASE_EXP_THRESHOLD
	_pending_level_ups = 0
	_level_up_active = false

	exp_changed.emit(current_exp, _exp_threshold)

	_cleanup_runtime_nodes()

	var inventory_manager: Node = get_node_or_null("/root/InventoryManager")
	if inventory_manager != null and is_instance_valid(inventory_manager) and inventory_manager.has_method("reset_inventory"):
		inventory_manager.reset_inventory()

	var combat_effect_manager: Node = get_node_or_null("/root/CombatEffectManager")
	if combat_effect_manager != null and is_instance_valid(combat_effect_manager) and combat_effect_manager.has_method("reset_effects"):
		combat_effect_manager.reset_effects()

	Engine.time_scale = 1.0
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false


func _cleanup_runtime_nodes() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return

	for enemy_node: Node in tree.get_nodes_in_group("enemy"):
		if enemy_node != null and is_instance_valid(enemy_node):
			enemy_node.queue_free()

	var cleanup_targets: Array[Node] = []
	_collect_cleanup_nodes(tree.current_scene, cleanup_targets)
	for node: Node in cleanup_targets:
		if node != null and is_instance_valid(node):
			node.queue_free()


func _collect_cleanup_nodes(node: Node, cleanup_targets: Array[Node]) -> void:
	for child: Node in node.get_children():
		_collect_cleanup_nodes(child, cleanup_targets)

	var script: Script = node.get_script() as Script
	if script == null:
		return

	var script_path: String = script.resource_path
	if script_path.ends_with("Bullet.gd"):
		cleanup_targets.append(node)


func _start_next_level_up() -> void:
	if _level_up_active or _pending_level_ups <= 0:
		return

	_level_up_active = true
	var tree := get_tree()
	if tree:
		tree.paused = true
	level_up.emit()


func _get_threshold_for_level(level: int) -> int:
	return BASE_EXP_THRESHOLD + maxi(0, level - 1) * EXP_THRESHOLD_STEP
