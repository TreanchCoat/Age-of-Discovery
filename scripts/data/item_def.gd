class_name ItemDef
extends Resource
## Catalog entry for a personal item (distinct from trade GoodDefs). Drop
## .tres files in data/items/ — ItemDB auto-loads the folder (including
## EquipmentDefs, which extend this).

@export var id: StringName
@export var display_name := ""
@export_enum("consumable", "equipment", "quest", "misc") var category: String = "misc"
@export_multiline var description := ""
@export var base_price := 0        # shop price; 0 = not sold
@export var icon: Texture2D        # optional, for future UI
