class_name Broadside
extends Node
## A ship's gun batteries: PORT (left, -X) and STARBOARD (right, +X), reloaded
## independently. Created in code by ShipController for any armed hull —
## player and AI share it, like everything else on deck.
##
## Firing is a true broadside: each ball flies out the SIDE (with scatter and
## a slight spread along the hull), so aiming means maneuvering the ship.
## The battery's stats come from the ship's CannonDef (ShipState.cannon_id).

enum Side { PORT, STARBOARD }

var ship: ShipController   # set by creator

var _reload := [0.0, 0.0]  # seconds left per side

func _physics_process(delta: float) -> void:
	_reload[0] = maxf(_reload[0] - delta, 0.0)
	_reload[1] = maxf(_reload[1] - delta, 0.0)

func cannon_def() -> CannonDef:
	if ship == null or ship.ship_state == null:
		return null
	return ItemDB.get_def(ship.ship_state.cannon_id) as CannonDef

func reload_left(side: int) -> float:
	return _reload[side]

func can_fire(side: int) -> bool:
	return _reload[side] <= 0.0 and cannon_def() != null \
		and ship.ship_state.cannons_per_side() > 0

## The world-space direction this side shoots (perpendicular to the keel).
func side_dir(side: int) -> Vector3:
	var right := ship.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	return -right if side == Side.PORT else right

## Is `target` inside this side's firing arc and range?
func target_in_arc(target: Node3D, side: int) -> bool:
	var def := cannon_def()
	if def == null:
		return false
	var to_t := target.global_position - ship.global_position
	to_t.y = 0.0
	if to_t.length() > def.fire_range:
		return false
	return side_dir(side).angle_to(to_t.normalized()) < deg_to_rad(55.0)

## Loose the broadside: one ball per cannon on that side, spread along the
## hull and scattered a few degrees. Returns true if it fired.
func fire_side(side: int) -> bool:
	if not can_fire(side):
		return false
	var def := cannon_def()
	var n: int = ship.ship_state.cannons_per_side()
	_reload[side] = def.reload_time
	var dir := side_dir(side)
	var along := -ship.global_transform.basis.z  # bow-ward axis for muzzle spread
	for i in n:
		# Muzzles spaced along the hull; each ball gets its own scatter.
		var offset: float = lerpf(-4.0, 4.0, float(i) / maxf(n - 1, 1))
		var origin: Vector3 = ship.global_position + dir * 2.5 + along * offset + Vector3.UP * 2.0
		var scatter: float = deg_to_rad(randf_range(-def.scatter_deg, def.scatter_deg))
		var ball_dir := dir.rotated(Vector3.UP, scatter)
		CannonBall.launch(ship, origin, ball_dir, def)
		CombatFX.muzzle(ship, origin, ball_dir)
	CombatFX.sound(ship, ship.global_position + dir * 3.0, CombatFX.BOOM_WAV, 3.0)
	EventBus.broadside_fired.emit(ship, side)
	return true
