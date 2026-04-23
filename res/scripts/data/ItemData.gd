extends Resource
class_name ItemData

enum ItemType {
	BASIC,
	SPECIAL
}

enum SpecialCategory {
	NONE,
	FIRE,
	POISON,
	ICE
}

@export var item_name: String
@export var item_type: ItemType = ItemType.BASIC
@export var effect_value: float
@export var description_text: String = ""
@export var category: SpecialCategory = SpecialCategory.NONE
@export var tags: PackedStringArray = PackedStringArray()
@export var duration_seconds: float = 0.0
@export var radius: float = 0.0
@export var damage_per_second: float = 0.0
@export var slow_ratio: float = 0.0
