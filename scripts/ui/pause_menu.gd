class_name PauseMenu
extends CanvasLayer
## Esc (ui_cancel) pauses the game and shows: Resume / Settings / Save & Main Menu.
## Settings panel holds the master volume slider (persisted via the Settings
## autoload). Quitting to menu autosaves first (via world.autosave()).
##
## Plays nice with the other modal UIs (voyage events, spyglass), which also
## pause the tree: if the tree is paused and it wasn't us, Esc is ignored.

const MAIN_MENU_SCENE := "res://scenes/menu/main_menu.tscn"

var world: Node = null  # set by world.gd; must expose autosave()

var _root: Control
var _main_box: VBoxContainer
var _settings_box: VBoxContainer

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _root.visible:
		_resume()
	elif not get_tree().paused:  # don't steal pause from event/spyglass modals
		_open()

func _open() -> void:
	_show_main()
	_root.show()
	get_tree().paused = true

func _resume() -> void:
	_root.hide()
	get_tree().paused = false

func _show_main() -> void:
	_settings_box.hide()
	_main_box.show()

func _show_settings() -> void:
	_main_box.hide()
	_settings_box.show()

func _quit_to_menu() -> void:
	if world and world.has_method("autosave"):
		world.autosave()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

## --- UI ------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 0)
	_root.add_child(panel)

	var stack := VBoxContainer.new()
	panel.add_child(stack)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	# Main buttons
	_main_box = VBoxContainer.new()
	stack.add_child(_main_box)
	_add_button(_main_box, "Resume", _resume)
	_add_button(_main_box, "Settings", _show_settings)
	_add_button(_main_box, "Save & Main Menu", _quit_to_menu)

	# Settings
	_settings_box = VBoxContainer.new()
	_settings_box.hide()
	stack.add_child(_settings_box)
	var vol_label := Label.new()
	vol_label.text = "Master volume"
	_settings_box.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.master_volume
	slider.custom_minimum_size = Vector2(280, 0)
	slider.value_changed.connect(func(v: float): Settings.master_volume = v)
	slider.drag_ended.connect(func(_changed: bool): Settings.save_settings())
	_settings_box.add_child(slider)
	_add_button(_settings_box, "Back", _show_main)

func _add_button(parent: Node, text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)
