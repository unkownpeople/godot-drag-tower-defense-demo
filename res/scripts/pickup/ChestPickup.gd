extends Area2D

@export var lifetime: float = 12.0

var _velocity: Vector2 = Vector2.ZERO

@onready var _label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if _label != null:
		_label.text = "箱子"


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_velocity = _velocity.move_toward(Vector2.ZERO, 360.0 * delta)

	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func setup(launch_velocity: Vector2) -> void:
	_velocity = launch_velocity


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return

	if is_instance_valid(InventoryManager) and InventoryManager.has_method("grant_random_chest_item"):
		InventoryManager.grant_random_chest_item()

	var tree := get_tree()
	var global_node: Node = null
	if tree != null and tree.root != null:
		global_node = tree.root.get_node_or_null("Global")
	if global_node != null and is_instance_valid(global_node) and global_node.has_signal("screen_shake_requested"):
		global_node.screen_shake_requested.emit(3.0, 0.06)

	queue_free()
