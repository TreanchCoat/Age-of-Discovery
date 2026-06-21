class_name SupplySystem
extends Node
## Voyage pressure: every game day at sea, the crew consumes water and food.
## Running dry tanks morale (which slows the ship via ShipState.effective_speed)
## and eventually starts killing crew. Resupply cheaply in any port.
## Add one instance to the World scene.

const WATER_PER_CREW_PER_DAY := 0.5
const FOOD_PER_CREW_PER_DAY := 0.3
const PRICE_PER_SUPPLY_UNIT := 2

func _ready() -> void:
	EventBus.day_passed.connect(_on_day_passed)

func _on_day_passed(_day: int) -> void:
	if GameState.current_port != &"":
		return  # docked: no consumption
	for ship in GameState.fleet:
		_consume(ship)

func _consume(ship: ShipState) -> void:
	var water_need := int(ceil(ship.crew * WATER_PER_CREW_PER_DAY))
	var food_need := int(ceil(ship.crew * FOOD_PER_CREW_PER_DAY))

	var water_short: int = water_need - ship.supplies[&"water"]
	var food_short: int = food_need - ship.supplies[&"food"]
	ship.supplies[&"water"] = maxi(ship.supplies[&"water"] - water_need, 0)
	ship.supplies[&"food"] = maxi(ship.supplies[&"food"] - food_need, 0)

	if water_short > 0 or food_short > 0:
		# Shortage: morale collapses fast, then crew starts dying.
		ship.morale = maxf(ship.morale - 0.25, 0.0)
		if ship.morale <= 0.0:
			ship.crew = maxi(ship.crew - maxi(1, ship.crew / 10), 1)
		EventBus.supplies_short.emit(ship)
	else:
		# Well-fed crew slowly recovers morale.
		ship.morale = minf(ship.morale + 0.1, 1.0)

## --- Port resupply -------------------------------------------------------

static func max_supplies(ship: ShipState) -> Dictionary:
	# Simple cap: scale with crew so bigger crews need bigger stocks.
	return {&"water": ship.crew * 10, &"food": ship.crew * 8}

static func resupply_cost(ship: ShipState) -> int:
	var cap := max_supplies(ship)
	var missing: int = (cap[&"water"] - ship.supplies[&"water"]) + (cap[&"food"] - ship.supplies[&"food"])
	return maxi(missing, 0) * PRICE_PER_SUPPLY_UNIT

static func resupply(ship: ShipState) -> bool:
	var cost := resupply_cost(ship)
	if cost == 0 or GameState.gold < cost:
		return false
	GameState.gold -= cost
	var cap := max_supplies(ship)
	ship.supplies[&"water"] = cap[&"water"]
	ship.supplies[&"food"] = cap[&"food"]
	ship.morale = 1.0
	return true
