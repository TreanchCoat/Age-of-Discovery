extends Node
## Port markets. Each port stocks goods with supply-driven prices that drift
## back to baseline daily and react to player trades.
## Design goal vs UWO: prices respond to YOUR actions, visibly and quickly.

# market[port_id][good_id] = { "supply": float, "baseline": float, "fluct": float }
# fluct is a per-visit 0.8-1.2 random price multiplier (re-rolled when you dock).
var market: Dictionary = {}

var _good_defs: Dictionary = {}  # good_id -> GoodDef
var _port_defs: Dictionary = {}  # port_id -> PortDef

func _ready() -> void:
	randomize()
	_load_defs("res://data/goods", _good_defs)
	_load_defs("res://data/ports", _port_defs)
	for port_id in _port_defs:
		_init_port(port_id)
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.port_entered.connect(_on_port_entered)

func _load_defs(dir_path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres") or file.ends_with(".res"):
			var res := load(dir_path + "/" + file)
			if res and "id" in res:
				into[res.id] = res

func _init_port(port_id: StringName) -> void:
	var port: PortDef = _port_defs[port_id]
	market[port_id] = {}
	# Every port trades every good, so you can always buy or offload anything.
	# Producers sit on a surplus (cheap); ports that crave a good are scarce (pricey);
	# everything else is neutral. This is what gives the same good a different value
	# at port A vs port B. A random 80-120% "fluct" rides on top, re-rolled per visit.
	for good_id in _good_defs:
		var base := 1.0
		if good_id in port.produces:
			base = 1.5
		elif good_id in port.demands:
			base = 0.5
		market[port_id][good_id] = {"supply": base, "baseline": base, "fluct": randf_range(0.8, 1.2)}

## Price = base_price * fluct / supply (clamped). supply 1.0 + fluct 1.0 == base price.
func get_price(port_id: StringName, good_id: StringName) -> int:
	var good: GoodDef = _good_defs.get(good_id)
	if good == null:
		return 0
	var entry: Dictionary = market.get(port_id, {}).get(good_id, {"supply": 1.0, "fluct": 1.0})
	var supply: float = clampf(entry["supply"], 0.2, 4.0)
	var fluct: float = entry.get("fluct", 1.0)
	return maxi(1, roundi(good.base_price * fluct / supply))

func buy(port_id: StringName, good_id: StringName, qty: int) -> bool:
	var price := get_price(port_id, good_id) * qty
	if GameState.gold < price or not GameState.ship.cargo.can_add(good_id, qty, _good_defs.get(good_id)):
		return false
	GameState.gold -= price
	GameState.ship.cargo.add(good_id, qty)
	_shift_supply(port_id, good_id, -qty * 0.01)  # buying drains supply -> price rises
	EventBus.trade_executed.emit(port_id, good_id, qty, price)
	return true

func sell(port_id: StringName, good_id: StringName, qty: int) -> bool:
	if not GameState.ship.cargo.remove(good_id, qty):
		return false
	var price := get_price(port_id, good_id) * qty
	GameState.gold += price
	_shift_supply(port_id, good_id, qty * 0.01)  # selling floods supply -> price falls
	EventBus.trade_executed.emit(port_id, good_id, -qty, price)
	return true

func _shift_supply(port_id: StringName, good_id: StringName, delta: float) -> void:
	if not market.has(port_id):
		return
	if not market[port_id].has(good_id):
		market[port_id][good_id] = {"supply": 1.0, "baseline": 1.0, "fluct": 1.0}
	market[port_id][good_id]["supply"] = clampf(market[port_id][good_id]["supply"] + delta, 0.2, 4.0)
	EventBus.prices_updated.emit(port_id)

func _on_day_passed(_day: int) -> void:
	# Drift each market 10% back toward baseline daily.
	for port_id in market:
		for good_id in market[port_id]:
			var e: Dictionary = market[port_id][good_id]
			e["supply"] = lerpf(e["supply"], e["baseline"], 0.1)
		EventBus.prices_updated.emit(port_id)

func _on_port_entered(port_id: StringName) -> void:
	# Fresh prices each time you make port: re-roll the 80-120% fluctuation.
	if not market.has(port_id):
		return
	for good_id in market[port_id]:
		market[port_id][good_id]["fluct"] = randf_range(0.8, 1.2)
	EventBus.prices_updated.emit(port_id)

func to_dict() -> Dictionary:
	return {"market": market}

func from_dict(d: Dictionary) -> void:
	if d.has("market"):
		market = d["market"]
