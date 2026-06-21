class_name VoyageEventSystem
extends Node
## Rolls data-driven VoyageEventDefs on hour/day ticks while at sea.
## Mitigating skills lower the chance and grow when an event is survived
## ("learn by doing"). Fired events emit EventBus.voyage_event_fired; the
## VoyageEventUI presents text + optional choice and applies effects.
## Add one instance to the World scene; assign `wind` for storm conditions.

@export var wind: WindSystem

var _defs: Array[VoyageEventDef] = []
var _days_at_sea: int = 0
var _pending: VoyageEventDef = null  # one event at a time

func _ready() -> void:
	var dir := DirAccess.open("res://data/events")
	if dir:
		for file in dir.get_files():
			if file.ends_with(".tres"):
				var d := load("res://data/events/" + file) as VoyageEventDef
				if d:
					_defs.append(d)
	EventBus.hour_passed.connect(_on_hour)
	EventBus.day_passed.connect(_on_day)
	EventBus.port_entered.connect(_on_port_entered)

func _on_port_entered(_p: StringName) -> void:
	_days_at_sea = 0

func _on_hour(_h: int) -> void:
	_roll("hourly")

func _on_day(_d: int) -> void:
	if GameState.current_port == &"":
		_days_at_sea += 1
	_roll("daily")

## Debug: fire a random loaded event right now (used by the debug panel).
func debug_force_event() -> void:
	if _pending != null or _defs.is_empty():
		return
	var def: VoyageEventDef = _defs[randi() % _defs.size()]
	_pending = def
	EventBus.voyage_event_fired.emit(def)

func _roll(tick: String) -> void:
	if _pending != null:
		return  # an event is already awaiting resolution
	var ship := GameState.ship
	if ship == null:
		return
	for def in _defs:
		if def.tick != tick:
			continue
		if def.requires_at_sea and GameState.current_port != &"":
			continue
		if _days_at_sea < def.min_days_at_sea:
			continue
		if def.requires_low_supplies and ship.supplies[&"water"] > 0 and ship.supplies[&"food"] > 0:
			continue
		if wind and wind.strength < def.min_wind_strength:
			continue
		var chance := def.base_chance * _skill_factor(def)
		if randf() < chance:
			_pending = def
			EventBus.voyage_event_fired.emit(def)
			return  # max one event per tick

## Each point of the mitigating skill above 5 cuts chance ~4%, floor at half.
func _skill_factor(def: VoyageEventDef) -> float:
	if def.mitigating_skill == &"":
		return 1.0
	var skill := int(GameState.stats.get(def.mitigating_skill))
	return clampf(1.0 - (skill - 5) * 0.04, 0.5, 1.2)

## Called by VoyageEventUI once the player has (or hasn't) taken the choice.
func resolve(accepted_choice: bool) -> void:
	if _pending == null:
		return
	var def := _pending
	_pending = null
	var ship := GameState.ship

	if accepted_choice and def.choice_text != "":
		ship.durability = clampi(ship.durability + def.choice_durability_delta, 0, ship.def.max_durability)
		ship.morale = clampf(ship.morale + def.choice_morale_delta, 0.0, 1.0)
		ship.crew = clampi(ship.crew + def.choice_crew_delta, 1, ship.def.max_crew)
		GameState.gold += def.choice_gold_delta
		WorldClock.total_minutes += def.choice_hours_lost * 60.0
	else:
		ship.durability = clampi(ship.durability + def.durability_delta, 0, ship.def.max_durability)
		ship.morale = clampf(ship.morale + def.morale_delta, 0.0, 1.0)
		ship.crew = clampi(ship.crew + def.crew_delta, 1, ship.def.max_crew)
		GameState.gold += def.gold_delta
		ship.supplies[&"water"] = maxi(ship.supplies[&"water"] + def.water_delta, 0)
		ship.supplies[&"food"] = maxi(ship.supplies[&"food"] + def.food_delta, 0)

	# Surviving an event teaches its mitigating skill.
	if def.mitigating_skill != &"":
		GameState.stats.grow(def.mitigating_skill, 1)

	EventBus.voyage_event_resolved.emit(def)
