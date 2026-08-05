class_name StatModDef
extends Resource
## One stat modifier line, embedded in SkillDefs and EquipmentDefs.
##
## On a SKILL: applied per level — at level L it contributes
##   add: add_per_level * L      mul: 1 + percent_per_level * L / 100
## On EQUIPMENT: applied once (L treated as 1).
##
## `stat` names are open-ended; agree on them in DOCUMENTATION.md §11 as they
## get consumed (e.g. &"ship_speed_mult", &"spot_radius", &"trade_discount").

@export var stat: StringName
@export var add_per_level := 0.0       # flat bonus
@export var percent_per_level := 0.0   # +X% per level (multiplicative)

func describe(level := 1) -> String:
	var parts: PackedStringArray = []
	if add_per_level != 0.0:
		parts.append("%+.1f %s" % [add_per_level * level, stat])
	if percent_per_level != 0.0:
		parts.append("%+.0f%% %s" % [percent_per_level * level, stat])
	return ", ".join(parts)
