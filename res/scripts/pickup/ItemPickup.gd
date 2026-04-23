extends Area2D

@export var item_data: Resource
@export var lifetime: float = 12.0

var _velocity: Vector2 = Vector2.ZERO

@onready var _label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_label()


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_velocity = _velocity.move_toward(Vector2.ZERO, 420.0 * delta)

	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func setup(resource: Resource, launch_velocity: Vector2) -> void:
	item_data = resource
	_velocity = launch_velocity
	_update_label()


func _on_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if item_data == null:
		queue_free()
		return

	var tree := get_tree()
	var global_node: Node = null
	if tree != null and tree.root != null:
		global_node = tree.root.get_node_or_null("Global")
	if global_node != null and is_instance_valid(global_node) and global_node.has_signal("item_applied"):
		global_node.item_applied.emit(item_data)
	queue_free()


func _update_label() -> void:
	if _label == null:
		return
	if item_data == null:
		_label.text = "?"
		return
	_label.text = str(item_data.get("item_name"))
