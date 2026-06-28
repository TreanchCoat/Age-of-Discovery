class_name OceanParamUI
extends CanvasLayer
## Native live-tuning panel for the ocean — a no-ImGui replacement for the demo's
## parameter sliders (the original used the imgui-godot C# extension, which doesn't
## run in Godot 4.7). Visible on start; press P to hide/show. Edits the selected
## wave cascade live, plus resolution and water/foam colour.

var water  # the Water node, assigned by main.gd

var _cascade_index := 0
var _sliders := {}   # param name -> HSlider
var _values := {}    # param name -> Label
var _panel: PanelContainer
var _spray           # the WaterSprayEmitter node

# name, min, max, step
const PARAMS := [
	["wind_speed", 0.0, 35.0, 0.5],
	["wind_direction", -180.0, 180.0, 1.0],
	["fetch_length", 10.0, 1000.0, 5.0],
	["swell", 0.0, 2.0, 0.05],
	["spread", 0.0, 1.0, 0.02],
	["detail", 0.0, 1.0, 0.02],
	["whitecap", 0.0, 2.0, 0.05],
	["foam_amount", 0.0, 10.0, 0.1],
	["displacement_scale", 0.0, 2.0, 0.05],
]
const SIZES := [128, 256, 512, 1024]

func _ready() -> void:
	layer = 50
	_build()

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_P:
		_panel.visible = not _panel.visible

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0
	add_child(_panel)

	var vb := VBoxContainer.new()
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "Ocean parameters  (P to hide)"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)

	# Cascade selector
	var cas := OptionButton.new()
	for i in range(water.parameters.size()):
		cas.add_item("Cascade %d" % (i + 1))
	cas.item_selected.connect(_on_cascade_selected)
	vb.add_child(cas)

	# Per-cascade sliders
	for p in PARAMS:
		var pname := String(p[0])
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = pname
		lbl.custom_minimum_size = Vector2(150, 0)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = p[1]
		sl.max_value = p[2]
		sl.step = p[3]
		sl.custom_minimum_size = Vector2(220, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Label.new()
		val.custom_minimum_size = Vector2(56, 0)
		sl.value_changed.connect(_on_param_changed.bind(pname, val))
		row.add_child(sl)
		row.add_child(val)
		vb.add_child(row)
		_sliders[pname] = sl
		_values[pname] = val

	# Resolution
	var res_row := HBoxContainer.new()
	var res_lbl := Label.new()
	res_lbl.text = "resolution"
	res_lbl.custom_minimum_size = Vector2(150, 0)
	res_row.add_child(res_lbl)
	var res := OptionButton.new()
	for s in SIZES:
		res.add_item("%dx%d" % [s, s])
	res.item_selected.connect(_on_resolution_selected)
	res_row.add_child(res)
	vb.add_child(res_row)

	# Colours
	var col_row := HBoxContainer.new()
	var wc_lbl := Label.new()
	wc_lbl.text = "water / foam colour"
	wc_lbl.custom_minimum_size = Vector2(150, 0)
	col_row.add_child(wc_lbl)
	var wc := ColorPickerButton.new()
	wc.color = water.water_color
	wc.custom_minimum_size = Vector2(110, 28)
	wc.color_changed.connect(_on_water_color)
	col_row.add_child(wc)
	var fc := ColorPickerButton.new()
	fc.color = water.foam_color
	fc.custom_minimum_size = Vector2(110, 28)
	fc.color_changed.connect(_on_foam_color)
	col_row.add_child(fc)
	vb.add_child(col_row)

	# Updates per second (wave update rate; 0 = uncapped)
	var ups_row := HBoxContainer.new()
	var ups_lbl := Label.new()
	ups_lbl.text = "updates_per_second"
	ups_lbl.custom_minimum_size = Vector2(150, 0)
	ups_row.add_child(ups_lbl)
	var ups := HSlider.new()
	ups.min_value = 0.0
	ups.max_value = 60.0
	ups.step = 1.0
	ups.value = water.updates_per_second
	ups.custom_minimum_size = Vector2(220, 0)
	ups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ups_val := Label.new()
	ups_val.custom_minimum_size = Vector2(56, 0)
	ups_val.text = "%.0f" % water.updates_per_second
	ups.value_changed.connect(_on_updates_changed.bind(ups_val))
	ups_row.add_child(ups)
	ups_row.add_child(ups_val)
	vb.add_child(ups_row)

	# Wave mesh quality
	var mq_row := HBoxContainer.new()
	var mq_lbl := Label.new()
	mq_lbl.text = "mesh_quality"
	mq_lbl.custom_minimum_size = Vector2(150, 0)
	mq_row.add_child(mq_lbl)
	var mq := OptionButton.new()
	mq.add_item("Low")
	mq.add_item("High")
	mq.add_item("High 8K")
	mq.selected = int(water.mesh_quality)
	mq.item_selected.connect(_on_mesh_quality_selected)
	mq_row.add_child(mq)
	vb.add_child(mq_row)

	# Enable sea spray (checkbox)
	_spray = water.get_node_or_null("WaterSprayEmitter")
	var spray_chk := CheckBox.new()
	spray_chk.text = "Enable sea spray"
	spray_chk.button_pressed = _spray.visible if _spray else false
	spray_chk.toggled.connect(_on_spray_toggled)
	vb.add_child(spray_chk)

	_refresh()

func _on_cascade_selected(idx: int) -> void:
	_cascade_index = idx
	_refresh()

func _on_param_changed(value: float, pname: String, val_label: Label) -> void:
	water.parameters[_cascade_index].set(pname, value)
	val_label.text = "%.2f" % value

func _on_resolution_selected(idx: int) -> void:
	water.map_size = SIZES[idx]

func _on_water_color(c: Color) -> void:
	water.water_color = c

func _on_foam_color(c: Color) -> void:
	water.foam_color = c

func _on_updates_changed(value: float, val_label: Label) -> void:
	water.updates_per_second = value
	val_label.text = "%.0f" % value

func _on_mesh_quality_selected(idx: int) -> void:
	water.mesh_quality = idx

func _on_spray_toggled(pressed: bool) -> void:
	if _spray:
		_spray.visible = pressed
		_spray.emitting = pressed

func _refresh() -> void:
	var c = water.parameters[_cascade_index]
	for pn in _sliders:
		var v: float = float(c.get(pn))
		_sliders[pn].value = v
		_values[pn].text = "%.2f" % v
