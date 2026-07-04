extends Node
## Catalog of all DiscoveryDefs + record of what the player has found.
## Flow: ship enters a DiscoveryArea -> "spotted" -> player uses observation
## (spyglass) -> confirm() -> rewards + world effects.

var _defs: Dictionary = {}            # id -> DiscoveryDef
var found: Dictionary = {}            # id -> { "day": int }
var spotted: Dictionary = {}          # id -> true (in range but unconfirmed)

func _ready() -> void:
	var dir := DirAccess.open("res://data/discoveries")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var d := load("res://data/discoveries/" + file) as DiscoveryDef
				if d:
					_defs[d.id] = d

func get_def(id: StringName) -> DiscoveryDef:
	return _defs.get(id)

func all_defs() -> Array:
	return _defs.values()

func is_found(id: StringName) -> bool:
	return found.has(id)

func spot(id: StringName) -> void:
	if is_found(id) or spotted.has(id):
		return
	spotted[id] = true
	EventBus.discovery_spotted.emit(id)

func confirm(id: StringName, roll_bonus: int = 0) -> bool:
	if is_found(id) or not _defs.has(id):
		return false
	var def: DiscoveryDef = _defs[id]
	# Skill check: observation stat vs difficulty (with luck factor).
	# roll_bonus comes from a good spyglass minigame hit.
	var roll := GameState.stats.observation + roll_bonus + randi_range(0, 20)
	if roll < def.difficulty:
		return false  # try again — encourages skill investment, not grinding
	spotted.erase(id)
	found[id] = {"day": WorldClock.day}
	GameState.stats.add_fame(def.fame_category, def.fame_reward)
	GameState.gold += def.gold_reward
	GameState.stats.grow(&"observation", 1)  # learn by doing
	EventBus.discovery_made.emit(id)
	return true

func reset() -> void:
	found.clear()
	spotted.clear()

func to_dict() -> Dictionary:
	return {"found": found}

func from_dict(d: Dictionary) -> void:
	found = d.get("found", {})
	spotted.clear()
