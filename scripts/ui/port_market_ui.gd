class_name PortMarketUI
extends CanvasLayer
## Market panel, opens on port_entered. Built from code (greybox UI).
## Lists every good traded at the port with live prices; buy/sell 1 or 10.
## Also offers resupply (water/food) — see SupplySystem.

var _panel: PanelContainer
var _banner: Label
var _title: Label
var _rows: VBoxContainer
var _enter_city_btn: Button
var _port_id: StringName = &""
var _good_defs := {}  # good_id -> GoodDef

func _ready() -> void:
	layer = 10
	_load_goods()
	_build_ui()
	hide_panel()
	EventBus.port_entered.connect(_on_port_entered)
	EventBus.port_left.connect(func(_p): hide_panel())
	EventBus.prices_updated.connect(_on_prices_updated)
	EventBus.trade_executed.connect(_on_trade_executed)
	EventBus.gold_changed.connect(_on_gold_changed)

func _load_goods() -> void:
	var dir := DirAccess.open("res://data/goods")
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".tres"):
			var g := load("res://data/goods/" + file) as GoodDef
			if g:
				_good_defs[g.id] = g

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.add_theme_color_override("font_color", Color(0.3, 0.75, 0.4))
	vbox.add_child(_banner)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title)

	_rows = VBoxContainer.new()
	vbox.add_child(_rows)

	_enter_city_btn = Button.new()
	_enter_city_btn.text = "Enter the city"
	_enter_city_btn.pressed.connect(_on_enter_city)
	vbox.add_child(_enter_city_btn)

	var close := Button.new()
	close.text = "Weigh anchor — set sail"
	close.pressed.connect(_on_set_sail)
	vbox.add_child(close)

	EventBus.city_left.connect(_on_city_left)

func _on_set_sail() -> void:
	hide_panel()
	EventBus.undock_requested.emit()

func _on_enter_city() -> void:
	_panel.hide()  # keep docked state; just step ashore
	EventBus.city_enter_requested.emit(_port_id)

func _on_city_left(city_id: StringName) -> void:
	# Back from the streets: reopen the port screen if we're still docked here.
	if city_id == _port_id and GameState.current_port == _port_id:
		_refresh()
		_panel.show()

func _on_port_entered(port_id: StringName) -> void:
	_port_id = port_id
	var port_name := String(port_id).capitalize()
	_banner.text = "Voyage Successful!  —  Welcome to %s" % port_name
	# Only offer the city button where a city scene exists.
	_enter_city_btn.visible = ResourceLoader.exists("res://scenes/city/city_%s.tscn" % String(port_id))
	_refresh()
	_panel.show()
	get_tree().paused = false

func hide_panel() -> void:
	_panel.hide()

func _on_prices_updated(port_id: StringName) -> void:
	if port_id == _port_id and _panel.visible:
		_refresh()

func _on_trade_executed(port_id: StringName, _g: StringName, _q: int, _t: int) -> void:
	if port_id == _port_id:
		_refresh()

func _on_gold_changed(_gold: int) -> void:
	if _panel.visible:
		_refresh()

func _refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()

	_title.text = "%s — Market   (Gold: %d)" % [String(_port_id).capitalize(), GameState.gold]

	var goods: Dictionary = EconomySim.market.get(_port_id, {})
	for good_id in goods:
		var good: GoodDef = _good_defs.get(good_id)
		if good == null:
			continue
		_rows.add_child(_make_row(good))

	_rows.add_child(HSeparator.new())
	_rows.add_child(_make_resupply_row())
	_rows.add_child(_make_cargo_label())

func _make_row(good: GoodDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	var price := EconomySim.get_price(_port_id, good.id)
	var held: int = GameState.ship.cargo.items.get(good.id, 0)

	var name_l := Label.new()
	name_l.text = "%s  %dg  (held: %d)" % [good.display_name, price, held]
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	for qty in [1, 10]:
		var b := Button.new()
		b.text = "Buy %d" % qty
		b.pressed.connect(func(): EconomySim.buy(_port_id, good.id, qty))
		row.add_child(b)
		var s := Button.new()
		s.text = "Sell %d" % qty
		s.pressed.connect(func(): EconomySim.sell(_port_id, good.id, qty))
		row.add_child(s)
	return row

func _make_resupply_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var ship := GameState.ship
	var l := Label.new()
	l.text = "Water: %d  Food: %d" % [ship.supplies[&"water"], ship.supplies[&"food"]]
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var cost := SupplySystem.resupply_cost(ship)
	var b := Button.new()
	b.text = "Resupply (%dg)" % cost
	b.disabled = cost == 0 or GameState.gold < cost
	b.pressed.connect(_on_resupply_pressed)
	row.add_child(b)
	return row

func _on_resupply_pressed() -> void:
	SupplySystem.resupply(GameState.ship)
	_refresh()

func _make_cargo_label() -> Label:
	var l := Label.new()
	var hold := GameState.ship.cargo
	l.text = "Cargo: %.0f / %.0f" % [hold.used_weight(), hold.capacity]
	return l
