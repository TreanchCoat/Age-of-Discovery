class_name CargoHold
extends RefCounted
## Weight-limited cargo container. Pure data, easily serialized.

var capacity: float = 100.0
var items := {}  # good_id (StringName) -> qty (int)

var _weights := {}  # cached good_id -> weight_per_unit

func _init(p_capacity: float = 100.0) -> void:
	capacity = p_capacity

func used_weight() -> float:
	var total := 0.0
	for good_id in items:
		total += items[good_id] * _weights.get(good_id, 1.0)
	return total

func can_add(good_id: StringName, qty: int, good: GoodDef = null) -> bool:
	var w: float = good.weight_per_unit if good else _weights.get(good_id, 1.0)
	return used_weight() + qty * w <= capacity

func add(good_id: StringName, qty: int, good: GoodDef = null) -> void:
	if good:
		_weights[good_id] = good.weight_per_unit
	items[good_id] = items.get(good_id, 0) + qty

func remove(good_id: StringName, qty: int) -> bool:
	if items.get(good_id, 0) < qty:
		return false
	items[good_id] -= qty
	if items[good_id] == 0:
		items.erase(good_id)
	return true

func to_dict() -> Dictionary:
	return {"capacity": capacity, "items": items, "weights": _weights}

static func from_dict_static(d: Dictionary) -> CargoHold:
	var c := CargoHold.new(d.get("capacity", 100.0))
	c.items = d.get("items", {})
	c._weights = d.get("weights", {})
	return c
