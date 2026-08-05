class_name SkillDef
extends Resource
## Catalog entry for a skill. Drop .tres files in data/skills/ — SkillDB
## auto-loads the folder. No skills ship yet; see DOCUMENTATION.md §11 for a
## copy-paste template.
##
## Passive skills: fill `modifiers` — applied per level via SkillSet.apply_to.
## Active skills: set `ability_id`; using the skill fires
## EventBus.ability_used(ability_id, level) and gameplay code implements the
## actual effect in a listener (keeps defs data-only).

@export var id: StringName
@export var display_name := ""
@export_enum("sailing", "trade", "adventure", "combat") var category: String = "adventure"
@export_multiline var description := ""

@export_group("Progression")
@export var max_level := 10
@export var base_xp := 100.0     # XP for level 0 -> 1
@export var xp_growth := 1.5     # each level costs this much more

@export_group("Effects")
@export var modifiers: Array[StatModDef] = []   # passive, per level
@export var ability_id: StringName = &""        # optional active ability hook
