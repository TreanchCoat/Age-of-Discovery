class_name ObjectiveSystem
extends Node
## The demo's guided goal (PROJECT_PLAN M5): three checks that walk a new
## player through the whole loop, then a voyage summary.
##
##   1. Dock at Funchal            (sail + navigate)
##   2. Amass 1500 gold            (trade; start is 1000)
##   3. Confirm a discovery        (spot + spyglass)
##
## All progress lives in GameState.flags["objective"] (plain JSON types), so it
## saves/loads and resets with new_game() for free. The system is pure logic —
## ObjectiveUI renders it via the objective_updated/completed signals.
## Later, goals become data (.tres defs) for real quests; this is the training
## wheels version.

const GOLD_TARGET := 1500
const DOCK_TARGET: StringName = &"funchal"

func _ready() -> void:
	if not GameState.flags.has("objective"):
		GameState.flags["objective"] = {
			"dock_done": false,
			"gold_done": false,
			"discovery_done": false,
			"completed": false,      # summary already shown
			"start_day": WorldClock.day,
			"start_gold": GameState.gold,
			"events_survived": 0,
		}
	EventBus.port_entered.connect(_on_port_entered)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.discovery_made.connect(_on_discovery_made)
	EventBus.voyage_event_resolved.connect(_on_event_resolved)
	# Late-join check (loaded save may already satisfy goals).
	_check(&"", true)

func state() -> Dictionary:
	return GameState.flags.get("objective", {})

## Goal list for the UI: [{text, done}, ...]
func goals() -> Array:
	var s := state()
	return [
		{"text": "Dock at Funchal", "done": bool(s.get("dock_done", false))},
		{"text": "Amass %d gold (%d)" % [GOLD_TARGET, GameState.gold], "done": bool(s.get("gold_done", false))},
		{"text": "Confirm a discovery with the spyglass", "done": bool(s.get("discovery_done", false))},
	]

func summary_stats() -> Dictionary:
	var s := state()
	return {
		"days": WorldClock.day - int(s.get("start_day", 0)),
		"gold_earned": GameState.gold - int(s.get("start_gold", 1000)),
		"discoveries": DiscoveryDB.found.size(),
		"events_survived": int(s.get("events_survived", 0)),
	}

func _on_port_entered(port_id: StringName) -> void:
	if port_id == DOCK_TARGET:
		_mark(&"dock_done")

func _on_gold_changed(new_gold: int) -> void:
	if new_gold >= GOLD_TARGET:
		_mark(&"gold_done")

func _on_discovery_made(_id: StringName) -> void:
	_mark(&"discovery_done")

func _on_event_resolved(_def: VoyageEventDef) -> void:
	var s := state()
	s["events_survived"] = int(s.get("events_survived", 0)) + 1

func _mark(key: StringName) -> void:
	var s := state()
	if bool(s.get(key, false)):
		return
	s[String(key)] = true
	_check(key, false)

func _check(_changed: StringName, silent_if_done: bool) -> void:
	var s := state()
	EventBus.objective_updated.emit()
	var all_done: bool = s.get("dock_done", false) and s.get("gold_done", false) and s.get("discovery_done", false)
	if all_done and not bool(s.get("completed", false)):
		s["completed"] = true
		if not silent_if_done:
			EventBus.objective_completed.emit()
		# On a loaded already-complete save, stay silent — no re-celebration.
