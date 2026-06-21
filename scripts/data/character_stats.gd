class_name CharacterStats
extends Resource
## Player skills + fame. Skills grow by use ("learn by doing"), no XP grind bars.

@export var observation: int = 5
@export var navigation: int = 5
@export var trade: int = 5
@export var combat: int = 5
@export var leadership: int = 5

# fame per playstyle, UWO-style but unified
var fame := {&"adventure": 0, &"trade": 0, &"battle": 0}

func grow(skill: StringName, amount: int = 1) -> void:
	if skill in self:
		set(skill, get(skill) + amount)

func add_fame(category: StringName, amount: int) -> void:
	fame[category] = fame.get(category, 0) + amount
	EventBus.fame_changed.emit(category, fame[category])

func to_dict() -> Dictionary:
	return {
		"observation": observation, "navigation": navigation, "trade": trade,
		"combat": combat, "leadership": leadership,
		"fame": {"adventure": fame[&"adventure"], "trade": fame[&"trade"], "battle": fame[&"battle"]},
	}

func from_dict(d: Dictionary) -> void:
	observation = int(d.get("observation", 5))
	navigation = int(d.get("navigation", 5))
	trade = int(d.get("trade", 5))
	combat = int(d.get("combat", 5))
	leadership = int(d.get("leadership", 5))
	var f: Dictionary = d.get("fame", {})
	fame = {
		&"adventure": int(f.get("adventure", 0)),
		&"trade": int(f.get("trade", 0)),
		&"battle": int(f.get("battle", 0)),
	}
