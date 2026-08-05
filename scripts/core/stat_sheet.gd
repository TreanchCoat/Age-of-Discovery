class_name StatSheet
extends RefCounted
## The keystone of the modifier architecture: every tunable number can live
## here as base value + stacked modifiers. Skills, equipment, morale, events,
## faction perks — anything that "changes a number" adds a modifier tagged
## with its source, and removes it by source when it no longer applies.
##
##   value(stat) = (base + Σ add) × Π mul
##
## Sources are StringNames like &"skill:navigation" or &"equip:spyglass" —
## remove_source() clears every modifier that source added, so re-applying a
## skill/equipment is always remove_source() + add again (idempotent).
##
## Bases persist via to_dict(); modifiers deliberately do NOT — their owners
## (SkillSet, Inventory, ...) re-apply them after a load. That keeps save data
## from ever double-stacking a bonus.

signal stat_changed(stat: StringName)

var _base := {}       # StringName -> float
var _mods: Array = [] # { "source": StringName, "stat": StringName, "add": float, "mul": float }

func set_base(stat: StringName, v: float) -> void:
	_base[stat] = v
	stat_changed.emit(stat)

func get_base(stat: StringName) -> float:
	return _base.get(stat, 0.0)

func has_stat(stat: StringName) -> bool:
	return _base.has(stat)

func stats() -> Array:
	return _base.keys()

## The final number systems should read.
func value(stat: StringName) -> float:
	var v: float = _base.get(stat, 0.0)
	var mul := 1.0
	for m in _mods:
		if m.stat == stat:
			v += m.add
			mul *= m.mul
	return v * mul

func add_modifier(source: StringName, stat: StringName, add := 0.0, mul := 1.0) -> void:
	_mods.append({"source": source, "stat": stat, "add": add, "mul": mul})
	stat_changed.emit(stat)

func remove_source(source: StringName) -> void:
	var touched: Array[StringName] = []
	for i in range(_mods.size() - 1, -1, -1):
		if _mods[i].source == source:
			touched.append(_mods[i].stat)
			_mods.remove_at(i)
	for stat in touched:
		stat_changed.emit(stat)

func has_source(source: StringName) -> bool:
	for m in _mods:
		if m.source == source:
			return true
	return false

## For UI: every modifier affecting `stat`, e.g. the character sheet's breakdown.
func modifiers_for(stat: StringName) -> Array:
	return _mods.filter(func(m): return m.stat == stat)

func to_dict() -> Dictionary:
	return {"base": _base}

func from_dict(d: Dictionary) -> void:
	_base = d.get("base", {})
	_mods.clear()
