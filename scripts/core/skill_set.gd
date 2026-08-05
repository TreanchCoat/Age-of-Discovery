class_name SkillSet
extends RefCounted
## Per-actor skill state: levels + XP toward the next level. Works for the
## player and (later) NPCs — anything can own a SkillSet.
##
## Defs come from SkillDB (data/skills/*.tres). Growth is learn-by-doing:
## gameplay calls add_xp() when the matching activity happens (sail a day ->
## navigation XP, close a trade -> trade XP...). No XP sources are wired yet —
## this is the exoskeleton.

signal skill_leveled(skill_id: StringName, new_level: int)

var _levels := {}  # skill_id -> int
var _xp := {}      # skill_id -> float (progress toward next level)

func level(id: StringName) -> int:
	return int(_levels.get(id, 0))

func xp(id: StringName) -> float:
	return float(_xp.get(id, 0.0))

## XP needed to go from `lvl` to lvl+1, per the def's curve.
func xp_to_next(id: StringName, lvl: int) -> float:
	var def: SkillDef = SkillDB.get_def(id)
	if def == null:
		return INF
	return def.base_xp * pow(def.xp_growth, float(lvl))

func add_xp(id: StringName, amount: float) -> void:
	var def: SkillDef = SkillDB.get_def(id)
	if def == null or amount <= 0.0:
		return
	var lvl := level(id)
	if lvl >= def.max_level:
		return
	var pool := xp(id) + amount
	while lvl < def.max_level and pool >= xp_to_next(id, lvl):
		pool -= xp_to_next(id, lvl)
		lvl += 1
		skill_leveled.emit(id, lvl)
	_levels[id] = lvl
	_xp[id] = pool if lvl < def.max_level else 0.0

## Grant levels directly (rewards, character creation, debug).
func set_level(id: StringName, lvl: int) -> void:
	_levels[id] = maxi(lvl, 0)
	_xp[id] = 0.0

## Push this skill set's passive effects into a StatSheet. Idempotent:
## clears each skill's source before re-adding. Call after any level change
## or after load.
func apply_to(sheet: StatSheet) -> void:
	for id in SkillDB.all_ids():
		var source := StringName("skill:" + String(id))
		sheet.remove_source(source)
		var lvl := level(id)
		if lvl <= 0:
			continue
		var def: SkillDef = SkillDB.get_def(id)
		for mod in def.modifiers:
			sheet.add_modifier(source, mod.stat,
				mod.add_per_level * lvl,
				1.0 + mod.percent_per_level * lvl / 100.0)

func to_dict() -> Dictionary:
	return {"levels": _levels, "xp": _xp}

func from_dict(d: Dictionary) -> void:
	_levels = d.get("levels", {})
	_xp = d.get("xp", {})
