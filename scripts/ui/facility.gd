class_name Facility
extends CanvasLayer
## Base class for city facility screens (bank, tavern, shipyard...). Handles
## the frame: dimmer, centered panel, title, Close button, Esc-to-close.
## Subclasses override facility_title() and _build_content(box).
##
## Opened by the Facilities autoload when the player interacts with a
## building whose type is registered. See DOCUMENTATION.md §11 for the recipe.

signal closed()

var city_id: StringName = &""

var _panel: PanelContainer

func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_frame()

func facility_title() -> String:
	return "Facility"

## Override: add your controls to `box` (a VBoxContainer inside the panel).
func _build_content(_box: VBoxContainer) -> void:
	pass

func close() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()  # don't let the pause menu open too
		close()

func _build_frame() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(440, 0)
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)

	var title := Label.new()
	title.text = facility_title()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(HSeparator.new())

	_build_content(box)

	box.add_child(HSeparator.new())
	var close_btn := Button.new()
	close_btn.text = "Leave"
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
