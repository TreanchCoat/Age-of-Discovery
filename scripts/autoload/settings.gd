extends Node
## User settings, persisted to user://settings.cfg. Currently just audio volume;
## add new fields + load/save lines as settings grow (fullscreen, keybinds...).

const PATH := "user://settings.cfg"

var master_volume := 0.8:
	set(v):
		master_volume = clampf(v, 0.0, 1.0)
		_apply_volume()

func _ready() -> void:
	load_settings()

func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.001)))

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		master_volume = float(cfg.get_value("audio", "master_volume", 0.8))
	else:
		_apply_volume()  # apply defaults

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(PATH)
