class_name CannonDef
extends EquipmentDef
## A cannon model — bought equipment, per the ship-customization pillar.
## Lives in data/items/ (ItemDB auto-loads it like any equipment). A ship's
## battery is ShipState.cannon_id + cannon_count; the Broadside component
## reads this def for ballistics. slot is always &"cannon".

@export var damage := 8               # hull damage per ball that connects
@export var fire_range := 90.0        # meaningful reach in world units
@export var reload_time := 6.0        # seconds per broadside
@export var ball_speed := 60.0        # world units/sec
@export var scatter_deg := 4.0        # aim wobble per ball; skill = get close
@export var weight_each := 2.0        # cargo-competition, enforced by the shipyard later
