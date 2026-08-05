class_name Requirement
extends Resource
## A single reusable condition. Quests, dialogue choices, facilities, titles,
## events — anything that gates on player state builds an Array[Requirement]
## and calls Requirement.all_met(reqs) instead of rolling its own checks.

@export_enum("gold_at_least", "skill_at_least", "fame_at_least", "flag_set", "discovery_found", "item_held")
var type: String = "gold_at_least"
## Meaning depends on type: skill id / fame category / flag name / discovery id / item id.
@export var key: StringName = &""
## Threshold or count (unused for flag_set / discovery_found).
@export var amount := 0

func is_met() -> bool:
	match type:
		"gold_at_least":
			return GameState.gold >= amount
		"skill_at_least":
			return GameState.skills.level(key) >= amount
		"fame_at_least":
			return GameState.stats.fame.get(key, 0) >= amount
		"flag_set":
			return bool(GameState.flags.get(String(key), false))
		"discovery_found":
			return DiscoveryDB.is_found(key)
		"item_held":
			return GameState.inventory.count(key) >= maxi(amount, 1)
	return false

func describe() -> String:
	match type:
		"gold_at_least":
			return "%d gold" % amount
		"skill_at_least":
			return "%s %d" % [String(key).capitalize(), amount]
		"fame_at_least":
			return "%d %s fame" % [amount, key]
		"flag_set":
			return String(key).capitalize()
		"discovery_found":
			return "Discovered: %s" % String(key).capitalize()
		"item_held":
			return "%dx %s" % [maxi(amount, 1), String(key).capitalize()]
	return "?"

static func all_met(reqs: Array) -> bool:
	for r in reqs:
		if r is Requirement and not r.is_met():
			return false
	return true
