class_name NPCDef
extends Resource
## Catalog entry for an NPC. Drop .tres files in data/npcs/ — NPCDB auto-loads
## the folder. NPCs with a home_city spawn in that city's street mode.
##
## `lines` is placeholder dialogue (rotated per interaction) until the real
## dialogue framework lands; keep flavor here for now.

@export var id: StringName
@export var display_name := ""
@export_enum("citizen", "merchant", "guard", "official", "sailor", "captain") var role: String = "citizen"
@export var home_city: StringName = &""      # matches a CityScene.city_id; empty = not auto-spawned
@export var color := Color(0.4, 0.5, 0.7)    # greybox body color until models exist
@export var lines: Array[String] = []        # placeholder dialogue, cycled on interact
