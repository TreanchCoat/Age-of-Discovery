class_name ObjectiveUI
extends CanvasLayer
## Renders the demo objective: a small checklist (bottom-left, out of the way
## of status text, minimap and helm) and, on completion, the voyage summary
## overlay — the demo's finish line.

@export var system: ObjectiveSystem

var _list: VBoxContainer
var _summary: Control

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_checklist()
	_refresh()
	EventBus.objective_updated.connect(_refresh)
	EventBus.objective_completed.connect(_show_summary)
	EventBus.gold_changed.connect(func(_g): _refresh())  # live gold count in goal text

func _build_checklist() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -160)
	panel.modulate = Color(1, 1, 1, 0.85)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "First Voyage"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	_list = VBoxContainer.new()
	box.add_child(_list)

func _refresh() -> void:
	if system == null:
		return
	for c in _list.get_children():
		c.queue_free()
	for goal in system.goals():
		var l := Label.new()
		var done: bool = goal["done"]
		l.text = ("[x] " if done else "[  ] ") + goal["text"]
		if done:
			l.add_theme_color_override("font_color", Color(0.45, 0.8, 0.5))
		_list.add_child(l)

## --- Voyage summary --------------------------------------------------------

func _show_summary() -> void:
	if _summary:
		return
	var stats: Dictionary = system.summary_stats()

	_summary = Control.new()
	_summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_summary)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summary.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	_summary.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Voyage Complete!"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "You've earned your sea legs, captain."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)
	box.add_child(sub)

	box.add_child(HSeparator.new())
	_add_stat(box, "Days at sea", str(stats["days"]))
	_add_stat(box, "Gold earned", str(stats["gold_earned"]))
	_add_stat(box, "Discoveries", str(stats["discoveries"]))
	_add_stat(box, "Events survived", str(stats["events_survived"]))
	box.add_child(HSeparator.new())

	var keep := Button.new()
	keep.text = "Keep sailing"
	keep.pressed.connect(_close_summary)
	box.add_child(keep)

	var quit := Button.new()
	quit.text = "Save & Main Menu"
	quit.pressed.connect(_to_menu)
	box.add_child(quit)

	get_tree().paused = true

func _add_stat(parent: Node, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value
	row.add_child(v)
	parent.add_child(row)

func _close_summary() -> void:
	get_tree().paused = false
	if _summary:
		_summary.queue_free()
		_summary = null

func _to_menu() -> void:
	get_tree().paused = false
	var world := get_parent()
	if world and world.has_method("autosave"):
		world.autosave()
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
