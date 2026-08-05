extends Node
## Registry of all ItemDefs/EquipmentDefs. Drop .tres files in data/items/.
## Player inventory STATE lives in GameState.inventory.

var _defs := {}  # id -> ItemDef

func _ready() -> void:
	var dir := DirAccess.open("res://data/items")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var d := load("res://data/items/" + file) as ItemDef
			if d and d.id != &"":
				_defs[d.id] = d

func get_def(id: StringName) -> ItemDef:
	return _defs.get(id)

func all_defs() -> Array:
	return _defs.values()

func equipment_for_slot(slot: StringName) -> Array:
	return _defs.values().filter(func(d): return d is EquipmentDef and d.slot == slot)
