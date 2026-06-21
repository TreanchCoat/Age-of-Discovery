class_name GoodDef
extends Resource
## Immutable catalog entry for a trade good.

@export var id: StringName
@export var display_name: String
@export_enum("food", "raw_material", "textile", "spice", "luxury", "craft", "weapon") var category: String = "raw_material"
@export var base_price: int = 100
@export var weight_per_unit: float = 1.0
@export var perishable: bool = false        # spoils over long voyages (later system)
@export_multiline var description: String
