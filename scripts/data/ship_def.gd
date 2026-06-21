class_name ShipDef
extends Resource
## Immutable catalog entry for a ship class.

@export var id: StringName
@export var display_name: String
@export_enum("light", "standard", "heavy") var hull_class: String = "light"
@export var base_speed: float = 8.0            # reference top speed (kept for tuning/UI)
@export var horizontal_sail_power: float = 8.0 # square sail thrust; best with wind astern
@export var vertical_sail_power: float = 6.0   # fore-and-aft sail; best on the beam, some downwind
@export var vs_wind_penalty: float = 0.6       # legacy; unused by the two-sail model
@export var turn_rate: float = 1.2             # rad/s
@export var cargo_capacity: float = 100.0      # weight units
@export var max_crew: int = 20
@export var max_durability: int = 100
@export var scene: PackedScene                 # visual model (low-poly)
@export_multiline var description: String
