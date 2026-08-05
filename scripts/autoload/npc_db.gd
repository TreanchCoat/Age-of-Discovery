extends Node
## Registry of all NPCDefs. Drop .tres files in data/npcs/. Cities spawn the
## NPCs whose home_city matches when you enter street mode.

var _defs := {}  # id -> NPCDef

func _ready() -> void:
	var dir := DirAccess.open("res://data/npcs")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var d := load("res://data/npcs/" + file) as NPCDef
			if d and d.id != &"":
				_defs[d.id] = d

func get_def(id: StringName) -> NPCDef:
	return _defs.get(id)

func all_defs() -> Array:
	return _defs.values()

func for_city(city_id: StringName) -> Array:
	return _defs.values().filter(func(d): return d.home_city == city_id)
