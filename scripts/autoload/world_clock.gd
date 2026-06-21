extends Node
## Game time. Real seconds -> game minutes. Emits hour/day ticks via EventBus.
## All simulation (economy, supplies, events) hangs off these ticks.

const MINUTES_PER_REAL_SECOND := 2.0  # 1 game day = 12 real minutes; tune freely

var total_minutes: float = 8.0 * 60.0  # start at 08:00, day 0
var paused := false

var day: int:
	get: return int(total_minutes / 1440.0)
var hour: int:
	get: return int(fmod(total_minutes, 1440.0) / 60.0)
var minute: int:
	get: return int(fmod(total_minutes, 60.0))

var _last_hour := -1
var _last_day := -1

func _process(delta: float) -> void:
	if paused:
		return
	total_minutes += delta * MINUTES_PER_REAL_SECOND
	if hour != _last_hour:
		_last_hour = hour
		EventBus.hour_passed.emit(hour)
	if day != _last_day:
		_last_day = day
		EventBus.day_passed.emit(day)

func time_string() -> String:
	return "Day %d, %02d:%02d" % [day, hour, minute]

func to_dict() -> Dictionary:
	return {"total_minutes": total_minutes}

func from_dict(d: Dictionary) -> void:
	total_minutes = d.get("total_minutes", 480.0)
	_last_hour = hour
	_last_day = day
