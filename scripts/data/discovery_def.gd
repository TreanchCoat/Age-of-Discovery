class_name DiscoveryDef
extends Resource
## A discoverable thing in the world: landmark, ruin, species, current, island...
## Design rule: every discovery has (a) a story hook, (b) a reward, (c) a world effect.

@export var id: StringName
@export var display_name: String
@export_enum("geography", "ruin", "flora_fauna", "treasure", "sea_phenomenon") var category: String = "geography"
@export var world_position: Vector3
@export var spot_radius: float = 60.0       # distance at which it becomes "spotted"
@export var difficulty: int = 10            # observation check threshold
@export var fame_category: StringName = &"adventure"
@export var fame_reward: int = 50
@export var gold_reward: int = 0
@export var unlock_flag: StringName = &""   # optional world effect, e.g. unlocks a route/good
@export_multiline var lore: String          # shown in encyclopedia on discovery
