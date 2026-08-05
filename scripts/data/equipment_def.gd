class_name EquipmentDef
extends ItemDef
## An item that can be equipped into a slot. Slots are free-form StringNames;
## keep the vocabulary in DOCUMENTATION.md §11 (&"spyglass", &"weapon",
## &"coat" now; ship slots like &"cannon", &"sail_main" when the shipyard
## arrives). Modifiers apply once (not per level) under source "equip:<slot>".

@export var slot: StringName = &"misc"
@export var modifiers: Array[StatModDef] = []
@export var ability_id: StringName = &""   # optional active ability hook
