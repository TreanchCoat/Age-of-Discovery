extends Node
## Owns the player's mutable state and save/load.
## Co-op note: in multiplayer this lives on the host; clients get replicated copies.

const SAVE_PATH := "user://save.json"

var player_name := "Captain"
var gold: int = 1000:
	set(v):
		gold = maxi(v, 0)
		EventBus.gold_changed.emit(gold)

var stats: CharacterStats = CharacterStats.new()
var ship: ShipState = null            # active ship
var fleet: Array[ShipState] = []      # all owned ships, incl. active
var current_port: StringName = &""    # empty = at sea
var flags := {}                       # misc story/world flags

func _ready() -> void:
	if ship == null:
		_new_game_defaults()

func _new_game_defaults() -> void:
	var def := load("res://data/ships/balsa.tres") as ShipDef
	if def:
		ship = ShipState.new_from_def(def)
		fleet = [ship]

func save_game() -> void:
	var data := {
		"player_name": player_name,
		"gold": gold,
		"stats": stats.to_dict(),
		"fleet": fleet.map(func(s): return s.to_dict()),
		"active_ship": fleet.find(ship),
		"current_port": String(current_port),
		"flags": flags,
		"clock": WorldClock.to_dict(),
		"discoveries": DiscoveryDB.to_dict(),
		"economy": EconomySim.to_dict(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	player_name = data.get("player_name", "Captain")
	gold = int(data.get("gold", 1000))
	stats.from_dict(data.get("stats", {}))
	fleet.clear()
	for sd in data.get("fleet", []):
		fleet.append(ShipState.from_dict_static(sd))
	var idx := int(data.get("active_ship", 0))
	ship = fleet[idx] if idx >= 0 and idx < fleet.size() else null
	current_port = StringName(data.get("current_port", ""))
	flags = data.get("flags", {})
	WorldClock.from_dict(data.get("clock", {}))
	DiscoveryDB.from_dict(data.get("discoveries", {}))
	EconomySim.from_dict(data.get("economy", {}))
	return true
