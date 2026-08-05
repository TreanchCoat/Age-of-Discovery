class_name TavernFacility
extends Facility
## Example facility proving the pipeline (building interact -> Facilities ->
## UI). Real tavern features (rumors pointing at discoveries, crew hiring,
## quest board) hang their buttons here later — see the quest framework plans.

func facility_title() -> String:
	return "The Tavern — %s" % String(city_id).capitalize()

func _build_content(box: VBoxContainer) -> void:
	var flavor := Label.new()
	flavor.text = "Smoke, dice, and sailors' lies. The keeper nods as you enter."
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.custom_minimum_size = Vector2(400, 0)
	box.add_child(flavor)

	# Placeholder hooks — wire these to real systems when they exist:
	var rumor := Button.new()
	rumor.text = "Ask for rumors (coming soon)"
	rumor.disabled = true
	box.add_child(rumor)

	var hire := Button.new()
	hire.text = "Hire crew (coming soon)"
	hire.disabled = true
	box.add_child(hire)
