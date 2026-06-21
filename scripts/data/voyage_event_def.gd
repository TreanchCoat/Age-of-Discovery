class_name VoyageEventDef
extends Resource
## Data-driven voyage event. Drop .tres files in data/events/ — VoyageEventSystem
## auto-loads the folder. Effects are simple key/value pairs applied to the ship,
## with optional player choice.

@export var id: StringName
@export var display_name: String
@export_multiline var text: String              # shown to player when it fires

## When can it fire?
@export_enum("hourly", "daily") var tick: String = "daily"
@export_range(0.0, 1.0) var base_chance: float = 0.05
@export var requires_at_sea: bool = true
@export var min_days_at_sea: int = 0            # e.g. scurvy needs long voyages
@export var requires_low_supplies: bool = false # only fires when water or food == 0
@export var min_wind_strength: float = 0.0      # e.g. storms need strong wind

## Effects (applied to the active ship / player). 0 = no effect.
@export var durability_delta: int = 0
@export var morale_delta: float = 0.0
@export var crew_delta: int = 0
@export var gold_delta: int = 0
@export var water_delta: int = 0
@export var food_delta: int = 0

## Optional choice: if choice_text is non-empty the player may accept it
## (e.g. "Heave to and ride out the storm" reduces damage but costs time).
@export var choice_text: String = ""
@export var choice_durability_delta: int = 0
@export var choice_morale_delta: float = 0.0
@export var choice_crew_delta: int = 0
@export var choice_gold_delta: int = 0
@export var choice_hours_lost: int = 0

## Skill interaction: higher skill reduces chance/severity; grows when survived.
@export var mitigating_skill: StringName = &""  # e.g. &"navigation"
