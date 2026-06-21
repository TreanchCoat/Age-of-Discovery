class_name PortDef
extends Resource
## Immutable catalog entry for a port.

@export var id: StringName
@export var display_name: String
@export var culture: StringName = &"iberian"     # flavors visuals/goods/dialogue
@export var world_position: Vector3              # position on the 3D sea
@export var size: int = 1                        # 1 small village .. 5 capital
@export var produces: Array[StringName] = []     # good ids sold cheap here
@export var demands: Array[StringName] = []      # good ids bought high here
@export var has_shipyard: bool = false
@export_multiline var description: String
