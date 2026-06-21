class_name VoyageEventUI
extends CanvasLayer
## Modal popup for voyage events. Pauses the game, shows text, offers the
## optional choice, then tells VoyageEventSystem to apply effects.

@export var system: VoyageEventSystem

var _panel: PanelContainer
var _title: Label
var _text: Label
var _choice_btn: Button
var _accept_btn: Button

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while tree is paused
	_build_ui()
	_panel.hide()
	EventBus.voyage_event_fired.connect(_on_event)

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(420, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(_text)

	_choice_btn = Button.new()
	_choice_btn.pressed.connect(_on_choice)
	vbox.add_child(_choice_btn)

	_accept_btn = Button.new()
	_accept_btn.text = "Endure it"
	_accept_btn.pressed.connect(_on_accept)
	vbox.add_child(_accept_btn)

func _on_event(def: VoyageEventDef) -> void:
	_title.text = def.display_name
	_text.text = def.text
	_choice_btn.visible = def.choice_text != ""
	_choice_btn.text = def.choice_text
	_panel.show()
	get_tree().paused = true

func _close() -> void:
	_panel.hide()
	get_tree().paused = false

func _on_choice() -> void:
	system.resolve(true)
	_close()

func _on_accept() -> void:
	system.resolve(false)
	_close()
