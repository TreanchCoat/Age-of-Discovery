class_name ShipState
extends Resource
## Mutable state of one owned ship. References an immutable ShipDef.

@export var def: ShipDef
var custom_name := ""
var durability: int = 100
var crew: int = 10
var supplies := {&"water": 50, &"food": 50}  # consumed per day at sea (later system)
var morale: float = 1.0                      # 0..1, affects speed & events
var cargo: CargoHold = CargoHold.new()

static func new_from_def(p_def: ShipDef) -> ShipState:
	var s := ShipState.new()
	s.def = p_def
	s.custom_name = p_def.display_name
	s.durability = p_def.max_durability
	s.crew = mini(10, p_def.max_crew)
	s.cargo = CargoHold.new(p_def.cargo_capacity)
	return s

func effective_speed(align: float, horizontal: float, vertical: float) -> float:
	## align: 1 = wind dead astern, 0 = wind on the beam (side), -1 = dead ahead.
	## horizontal/vertical: 0..1 how far each sail is set. Their thrust is added.
	if def == null:
		return 0.0
	# Horizontal (square) sail: best dead downwind, fades to nothing into the wind.
	var h_eff := (align + 1.0) / 2.0 + 0.5 * maxf(0.0, align) # head 0 .. beam 0.5 .. astern 1.5
	# Vertical (fore-and-aft) sail: best on the beam, keeps some thrust downwind,
	# nothing dead into the wind.
	var v_eff := (1.0 - absf(align)) + maxf(0.0, align) * 0.4 # head 0 .. astern 0.4 .. beam 1.0
	var sail_power := horizontal * h_eff * def.horizontal_sail_power + vertical * v_eff * def.vertical_sail_power
	var crew_mult := clampf(float(crew) / float(def.max_crew), 0.4, 1.0)
	var morale_mult := lerpf(0.7, 1.0, morale)
	return sail_power * crew_mult * morale_mult

func max_durability() -> int:
	return def.max_durability if def else durability

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	durability = maxi(durability - amount, 0)

func to_dict() -> Dictionary:
	return {
		"def_path": def.resource_path if def else "",
		"custom_name": custom_name,
		"durability": durability,
		"crew": crew,
		"supplies": {"water": supplies[&"water"], "food": supplies[&"food"]},
		"morale": morale,
		"cargo": cargo.to_dict(),
	}

static func from_dict_static(d: Dictionary) -> ShipState:
	var s := ShipState.new()
	var path: String = d.get("def_path", "")
	if path != "":
		s.def = load(path)
	s.custom_name = d.get("custom_name", "")
	s.durability = int(d.get("durability", 100))
	s.crew = int(d.get("crew", 10))
	var sup: Dictionary = d.get("supplies", {})
	s.supplies = {&"water": int(sup.get("water", 50)), &"food": int(sup.get("food", 50))}
	s.morale = float(d.get("morale", 1.0))
	s.cargo = CargoHold.from_dict_static(d.get("cargo", {}))
	return s
