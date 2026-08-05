class_name RewardBundle
extends Resource
## A reusable "what you get" package. Quests, events, discoveries, facilities
## all grant one of these instead of hand-writing gold/fame/item code.

@export var gold := 0
@export var fame_category: StringName = &""   # &"adventure" / &"trade" / &"battle"
@export var fame := 0
@export var item_ids: Array[StringName] = []  # each granted x1
@export var skill_id: StringName = &""        # optional skill XP grant
@export var skill_xp := 0.0
@export var set_flags: Array[StringName] = [] # world flags set true

func grant() -> void:
	if gold != 0:
		GameState.gold += gold
	if fame != 0 and fame_category != &"":
		GameState.stats.add_fame(fame_category, fame)
	for id in item_ids:
		GameState.inventory.add(id)
	if skill_id != &"" and skill_xp > 0.0:
		GameState.skills.add_xp(skill_id, skill_xp)
	for f in set_flags:
		GameState.flags[String(f)] = true

func describe() -> String:
	var parts: PackedStringArray = []
	if gold != 0:
		parts.append("%d gold" % gold)
	if fame != 0:
		parts.append("%d %s fame" % [fame, fame_category])
	for id in item_ids:
		var def := ItemDB.get_def(id)
		parts.append(def.display_name if def else String(id))
	if skill_xp > 0.0:
		parts.append("%s XP" % String(skill_id).capitalize())
	return ", ".join(parts) if parts.size() > 0 else "nothing"
