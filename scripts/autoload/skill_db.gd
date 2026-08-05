extends Node
## Registry of all SkillDefs. Drop .tres files in data/skills/ and they're
## live — no code. Player skill STATE lives in GameState.skills (a SkillSet).

var _defs := {}  # id -> SkillDef

func _ready() -> void:
	var dir := DirAccess.open("res://data/skills")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var d := load("res://data/skills/" + file) as SkillDef
			if d and d.id != &"":
				_defs[d.id] = d

func get_def(id: StringName) -> SkillDef:
	return _defs.get(id)

func all_ids() -> Array:
	return _defs.keys()

func all_defs() -> Array:
	return _defs.values()

func by_category(category: String) -> Array:
	return _defs.values().filter(func(d): return d.category == category)

## Convenience for gameplay code: grant XP to the player and refresh the
## stat sheet if a level-up changed passive effects.
func grant_player_xp(id: StringName, amount: float) -> void:
	var before := GameState.skills.level(id)
	GameState.skills.add_xp(id, amount)
	if GameState.skills.level(id) != before:
		GameState.skills.apply_to(GameState.sheet)
