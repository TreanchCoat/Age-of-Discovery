class_name NPCShip
extends ShipController
## An AI-crewed ship. Extends ShipController, so it sails with EXACTLY the same
## physics as the player: wind alignment, sail spool-up, wheel momentum, pace,
## steerageway, shallows drag, coast damage. The brain (_think) only sets the
## command channels — turn_input and the two sail targets — like ghostly hands
## on the same controls.
##
## Combat step 0 behavior: anchored until the player closes to aggro_range,
## raises sails (for real — they spool via SAIL_CHANGE_RATE), then chases.
## Upwind escapes genuinely work now: if the prey sails a line the wind hates,
## the pirate suffers the same physics.

enum State { ANCHORED, RAISING_SAILS, CHASING }

@export var target: Node3D
@export var aggro_range := 160.0
@export var keep_distance := 18.0     # ease off here; loom rather than grind
@export var raise_sails_time := 2.0   # order-shouting delay before pursuit

var state := State.ANCHORED

var _raise_left := 0.0
var _label: Label3D
var _hp_sprite: Sprite3D
var _hp_image: Image
var _hp_texture: ImageTexture

const HP_W := 64
const HP_H := 8

func _init() -> void:
	is_player = false

func _ready() -> void:
	super()
	add_to_group("npc_ship")
	# Own hull state — same starter hull as the player for a fair chase.
	var def := load("res://data/ships/balsa.tres") as ShipDef
	if def:
		ship_state = ShipState.new_from_def(def)
		ship_state.crew = def.max_crew  # pirates run full crews
	_label = Label3D.new()
	_label.text = "Pirate"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.06
	_label.position.y = 14.0
	_label.modulate = Color(0.9, 0.85, 0.7)
	add_child(_label)
	# TEMP damage-testing health bar: a billboarded sprite above the name,
	# redrawn from a tiny image on every hit. Replace with real "visual damage
	# reads" (sail tatters, listing) per the combat design later.
	_hp_image = Image.create(HP_W, HP_H, false, Image.FORMAT_RGBA8)
	_hp_texture = ImageTexture.create_from_image(_hp_image)
	_hp_sprite = Sprite3D.new()
	_hp_sprite.texture = _hp_texture
	_hp_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_sprite.pixel_size = 0.14
	_hp_sprite.no_depth_test = true
	_hp_sprite.position.y = 16.5
	add_child(_hp_sprite)
	_redraw_hp()

func _physics_process(delta: float) -> void:
	_think(delta)
	super(delta)

## The brain: writes the command channels; the inherited physics does the rest.
func _think(delta: float) -> void:
	match state:
		State.ANCHORED:
			turn_input = 0.0
			horizontal_sail_target = 0.0
			vertical_sail_target = 0.0
			if target and global_position.distance_to(target.global_position) < aggro_range:
				state = State.RAISING_SAILS
				_raise_left = raise_sails_time
				_set_label("Pirate — raising sails!", Color(0.95, 0.45, 0.25))
		State.RAISING_SAILS:
			# Crew aloft: sails start filling immediately, pursuit begins shortly.
			horizontal_sail_target = 1.0
			vertical_sail_target = 1.0
			_raise_left -= delta
			if _raise_left <= 0.0:
				state = State.CHASING
				_set_label("Pirate!", Color(0.9, 0.2, 0.15))
		State.CHASING:
			_chase()
			_try_fire()

func _chase() -> void:
	if target == null:
		state = State.ANCHORED
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	# Helm toward the prey: signed angle between our bow and the target bearing.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	var angle := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	# Proportional helm with a deadzone; sign convention: +turn_input = port (CCW).
	turn_input = clampf(angle * 2.0, -1.0, 1.0) if absf(angle) > 0.03 else 0.0

	# Sail handling: full chase until close aboard, then furl to come alongside.
	if dist < keep_distance:
		horizontal_sail_target = 0.0
		vertical_sail_target = 0.0
	elif dist < keep_distance * 2.5:
		horizontal_sail_target = 0.0
		vertical_sail_target = 1.0   # fore-and-aft only: slow, controllable approach
	else:
		horizontal_sail_target = 1.0
		vertical_sail_target = 1.0

## Loose a broadside whenever the prey drifts into either arc.
func _try_fire() -> void:
	if target == null or broadside == null:
		return
	for side in [Broadside.Side.PORT, Broadside.Side.STARBOARD]:
		if broadside.can_fire(side) and broadside.target_in_arc(target, side):
			broadside.fire_side(side)

func receive_hit(damage: int, attacker: Node3D) -> void:
	super(damage, attacker)
	_redraw_hp()

func _redraw_hp() -> void:
	if _hp_image == null or ship_state == null:
		return
	var frac := float(ship_state.durability) / maxf(float(ship_state.max_durability()), 1.0)
	var fill_w := int(roundf(frac * (HP_W - 2)))
	var color := Color(0.35, 0.75, 0.3)
	if frac <= 0.25:
		color = Color(0.85, 0.25, 0.2)
	elif frac <= 0.5:
		color = Color(0.85, 0.65, 0.2)
	_hp_image.fill(Color(0.06, 0.06, 0.08, 0.85))  # trough + border
	for y in range(1, HP_H - 1):
		for x in range(1, 1 + fill_w):
			_hp_image.set_pixel(x, y, color)
	_hp_texture.update(_hp_image)

func _set_label(text: String, color: Color) -> void:
	if _label:
		_label.text = text
		_label.modulate = color
