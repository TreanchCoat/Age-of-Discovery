class_name CharacterSheetUI
extends CanvasLayer
## The captain's sheet (toggle with C): three columns — Skills (SkillDB defs +
## SkillSet levels/XP), Inventory & equipment, and the StatSheet with a
## per-stat modifier breakdown. Deliberately plain; it exists so the new
## systems are VISIBLE the moment content lands in data/skills & data/items.

var _root: Control
var _skills_box: VBoxContainer
var _items_box: VBoxContainer
var _stats_box: VBoxContainer

func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.hide()
	GameState.inventory.changed.connect(_refresh)
	GameState.skills.skill_leveled.connect(func(_id, _lvl): _refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_character"):
		_root.visible = not _root.visible
		if _root.visible:
			_refresh()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 420)
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Captain's Sheet   (C to close)"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)

	_skills_box = _make_column(columns, "Skills")
	_items_box = _make_column(columns, "Inventory")
	_stats_box = _make_column(columns, "Stats")

func _make_column(parent: Node, heading: String) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(outer)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 18)
	outer.add_child(h)
	outer.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _refresh() -> void:
	_fill_skills()
	_fill_items()
	_fill_stats()

func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()

func _fill_skills() -> void:
	_clear(_skills_box)
	var defs := SkillDB.all_defs()
	if defs.is_empty():
		_add_line(_skills_box, "(no skills defined yet —\nadd .tres files to data/skills/,\nsee DOCUMENTATION.md §11)")
		return
	for def in defs:
		var lvl: int = GameState.skills.level(def.id)
		var line := "%s  —  Lv %d/%d" % [def.display_name, lvl, def.max_level]
		if lvl < def.max_level:
			line += "  (%.0f/%.0f xp)" % [GameState.skills.xp(def.id), GameState.skills.xp_to_next(def.id, lvl)]
		_add_line(_skills_box, line)
		for mod in def.modifiers:
			if lvl > 0:
				_add_line(_skills_box, "    " + mod.describe(lvl), Color(0.6, 0.8, 0.6))

func _fill_items() -> void:
	_clear(_items_box)
	var eq: Dictionary = GameState.inventory.equipped_slots()
	if not eq.is_empty():
		_add_line(_items_box, "Equipped:", Color(0.8, 0.75, 0.5))
		for slot in eq:
			var def := ItemDB.get_def(eq[slot])
			_add_line(_items_box, "  [%s] %s" % [slot, def.display_name if def else String(eq[slot])])
	var items: Dictionary = GameState.inventory.all_items()
	if items.is_empty() and eq.is_empty():
		_add_line(_items_box, "(empty — items come from\ndata/items/ + RewardBundles)")
		return
	if not items.is_empty():
		_add_line(_items_box, "Carried:", Color(0.8, 0.75, 0.5))
		for id in items:
			var def := ItemDB.get_def(id)
			_add_line(_items_box, "  %dx %s" % [items[id], def.display_name if def else String(id)])

func _fill_stats() -> void:
	_clear(_stats_box)
	var sheet: StatSheet = GameState.sheet
	if sheet.stats().is_empty():
		_add_line(_stats_box, "(no stats registered yet —\nsystems will populate this as\nthey adopt the StatSheet)")
		return
	for stat in sheet.stats():
		_add_line(_stats_box, "%s: %.2f" % [stat, sheet.value(stat)])
		for m in sheet.modifiers_for(stat):
			_add_line(_stats_box, "    %s: %+.2f ×%.2f" % [m.source, m.add, m.mul], Color(0.6, 0.7, 0.85))

func _add_line(box: VBoxContainer, text: String, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	box.add_child(l)
