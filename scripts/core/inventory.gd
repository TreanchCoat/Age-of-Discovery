class_name Inventory
extends RefCounted
## Personal items + equipment slots (distinct from the ship's CargoHold, which
## is bulk trade goods). Items are counted by id; equipping moves an item into
## a named slot and pushes its stat modifiers into a StatSheet.
##
## Slots are open-ended StringNames — an EquipmentDef declares which slot it
## fits (&"spyglass", &"weapon", &"coat", ship slots like &"cannon" later).

signal changed()

var _items := {}      # item_id -> count
var _equipped := {}   # slot (StringName) -> item_id

func count(id: StringName) -> int:
	return int(_items.get(id, 0))

func add(id: StringName, qty := 1) -> void:
	_items[id] = count(id) + qty
	changed.emit()

func remove(id: StringName, qty := 1) -> bool:
	if count(id) < qty:
		return false
	_items[id] -= qty
	if _items[id] <= 0:
		_items.erase(id)
	changed.emit()
	return true

func all_items() -> Dictionary:
	return _items.duplicate()

func equipped(slot: StringName) -> StringName:
	return _equipped.get(slot, &"")

func equipped_slots() -> Dictionary:
	return _equipped.duplicate()

## Equip an owned EquipmentDef item into its declared slot (swapping out any
## previous occupant back into the bag). `sheet` gets the item's modifiers
## under source "equip:<slot>".
func equip(id: StringName, sheet: StatSheet) -> bool:
	var def := ItemDB.get_def(id) as EquipmentDef
	if def == null or count(id) <= 0:
		return false
	unequip(def.slot, sheet)
	remove(id, 1)
	_equipped[def.slot] = id
	var source := StringName("equip:" + String(def.slot))
	for mod in def.modifiers:
		sheet.add_modifier(source, mod.stat, mod.add_per_level, 1.0 + mod.percent_per_level / 100.0)
	changed.emit()
	return true

func unequip(slot: StringName, sheet: StatSheet) -> void:
	var old: StringName = _equipped.get(slot, &"")
	if old == &"":
		return
	_equipped.erase(slot)
	sheet.remove_source(StringName("equip:" + String(slot)))
	add(old, 1)

## Re-apply every equipped item's modifiers (after load). Idempotent.
func apply_equipment(sheet: StatSheet) -> void:
	for slot in _equipped:
		var def := ItemDB.get_def(_equipped[slot]) as EquipmentDef
		if def == null:
			continue
		var source := StringName("equip:" + String(slot))
		sheet.remove_source(source)
		for mod in def.modifiers:
			sheet.add_modifier(source, mod.stat, mod.add_per_level, 1.0 + mod.percent_per_level / 100.0)

func to_dict() -> Dictionary:
	return {"items": _items, "equipped": _equipped}

func from_dict(d: Dictionary) -> void:
	_items = d.get("items", {})
	_equipped = d.get("equipped", {})
	changed.emit()
