extends Control
## Main menu: New Game / Continue / Settings / Quit. UI built from code
## (consistent with the rest of the greybox UI). The scene flow:
##   main_menu.tscn (project main scene) -> world.tscn (gameplay) -> back here.

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _main_box: VBoxContainer
var _settings_box: VBoxContainer

func _ready() -> void:
	_build_ui()

func _new_game() -> void:
	GameState.new_game()
	get_tree().change_scene_to_file(WORLD_SCENE)

func _continue_game() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file(WORLD_SCENE)

## --- UI ------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.12, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(340, 0)
	stack.add_theme_constant_override("separation", 10)
	center.add_child(stack)

	var title := Label.new()
	title.text = "Age of Discovery"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "an Uncharted Waters reimagining"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	stack.add_child(subtitle)

	stack.add_child(HSeparator.new())

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 8)
	stack.add_child(_main_box)

	_add_button(_main_box, "New Game", _new_game)
	var cont := _add_button(_main_box, "Continue", _continue_game)
	cont.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)
	if cont.disabled:
		cont.tooltip_text = "No save found"
	_add_button(_main_box, "Settings", _show_settings)
	_add_button(_main_box, "Quit", func(): get_tree().quit())

	# Settings (same contents as the pause menu's panel)
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
	slider.value_changed.connect(func(v: float): Settings.master_volume = v)
	slider.drag_ended.connect(func(_changed: bool): Settings.save_settings())
	_settings_box.add_child(slider)
	_add_button(_settings_box, "Back", _show_main)

func _show_settings() -> void:
	_main_box.hide()
	_settings_box.show()

func _show_main() -> void:
	_settings_box.hide()
	_main_box.show()

func _add_button(parent: Node, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	parent.add_child(b)
	return b
