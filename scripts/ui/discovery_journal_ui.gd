class_name DiscoveryJournalUI
extends CanvasLayer
## The captain's journal (toggle with J): every discovery as a card — found
## ones show category, the day they were confirmed, and their lore; unfound
## ones appear as "???" with only a category hint, so the journal doubles as
## a到-do list for explorers.
##
## Discoveries with DiscoveryDef.hidden = true don't appear at all until
## found — that's the hook for quest-gated and mythic discoveries (Bermuda,
## norse legends...): the quest system reveals them by leading you there.

var _root: Control
var _list: VBoxContainer
var _count: Label

func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.hide()
	EventBus.discovery_made.connect(func(_id):
		if _root.visible:
			_refresh())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_journal"):
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
	panel.custom_minimum_size = Vector2(560, 460)
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Journal of Discoveries   (J to close)"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.modulate = Color(1, 1, 1, 0.65)
	vbox.add_child(_count)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()

	var defs := DiscoveryDB.all_defs()
	var found_defs: Array = []
	var unfound_defs: Array = []
	for def in defs:
		if DiscoveryDB.is_found(def.id):
			found_defs.append(def)
		elif not def.hidden:
			unfound_defs.append(def)
	# Hidden + unfound entries are absent entirely (quest/myth reveals).

	_count.text = "%d of %d charted" % [found_defs.size(), found_defs.size() + unfound_defs.size()]

	for def in found_defs:
		_add_card(def, true)
	for def in unfound_defs:
		_add_card(def, false)

	if found_defs.is_empty() and unfound_defs.is_empty():
		var l := Label.new()
		l.text = "(the seas hold their secrets — for now)"
		_list.add_child(l)

func _add_card(def: DiscoveryDef, found: bool) -> void:
	var card := PanelContainer.new()
	_list.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)

	var head := Label.new()
	if found:
		var day := int(DiscoveryDB.found.get(def.id, {}).get("day", 0))
		head.text = "%s   —   %s, charted day %d" % [def.display_name, def.category.capitalize(), day]
		head.add_theme_color_override("font_color", Color(0.85, 0.72, 0.4))
	else:
		head.text = "???   —   %s, rumored" % def.category.capitalize()
		head.modulate = Color(1, 1, 1, 0.55)
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)

	if found:
		var lore := Label.new()
		lore.text = def.lore
		lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore.custom_minimum_size = Vector2(500, 0)
		lore.modulate = Color(1, 1, 1, 0.8)
		box.add_child(lore)