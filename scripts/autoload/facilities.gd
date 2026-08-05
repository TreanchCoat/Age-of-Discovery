extends Node
## Facility registry + dispatcher: maps a building_type to a Facility UI and
## opens it when the player interacts with that building in a city.
##
## Adding a facility = write one script extending Facility, register it below
## (or from anywhere) with register(). Unregistered building types keep the
## "not yet open" toast. See DOCUMENTATION.md §11.

var _facilities := {}  # building_type (StringName) -> GDScript (extends Facility)
var _open_facility: Facility = null

func _ready() -> void:
	EventBus.city_building_interacted.connect(_on_building_interacted)
	# --- Registrations (the example tavern proves the pipeline) -------------
	register(&"tavern", preload("res://scripts/ui/facilities/tavern_facility.gd"))

func register(building_type: StringName, facility_script: GDScript) -> void:
	_facilities[building_type] = facility_script

func has_facility(building_type: StringName) -> bool:
	return _facilities.has(building_type)

func _on_building_interacted(city_id: StringName, building_type: String) -> void:
	open(city_id, StringName(building_type))

func open(city_id: StringName, building_type: StringName) -> void:
	if _open_facility != null or not has_facility(building_type):
		return
	var f: Facility = (_facilities[building_type] as GDScript).new()
	f.city_id = city_id
	f.closed.connect(func(): _open_facility = null)
	_open_facility = f
	get_tree().root.add_child(f)
