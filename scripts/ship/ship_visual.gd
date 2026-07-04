class_name ShipVisual
extends Node3D
## Sits on the ship's HullPivot (the node ShipBuoyancy heaves/tilts).
## Two jobs:
##
## 1. FIT THE HULL MODEL. The placeholder OBJ is huge (~4965u long) and authored
##    off-origin, so at ready we scale it and centre it on this pivot, resting
##    the keel (AABB min Y) at `keel_y`. Yaw lives on the HullYaw wrapper node
##    in ship.tscn (the model faces astern, hence 180°). If the mesh is missing,
##    we fall back to the old greybox box so the game still runs.
##
## 2. SAIL MOUNTS. Sails will eventually be separate, swappable models (square /
##    fore-and-aft variants with their own looks and stats). The current
##    placeholder hull has sails baked into the mesh, so the mounts are empty
##    Node3D markers for now — but the API below is what the shipyard/refit
##    screen should already code against:
##
##       visual.set_sail(&"main", preload("res://assets/sails/square_01.tscn"))
##       visual.clear_sail(&"fore")
##
##    When real hull models (sail-less) arrive: assign their scene in ship.tscn,
##    reposition the mounts to the mast positions, and drop the baked-in look.
##    Mounts live under HullYaw so sails inherit hull yaw + buoyancy tilt.
##    ShipController's sail toggles (F/G) can later show/hide or furl these
##    per-mount instances instead of being purely abstract.

const HULL_MESH_PATH := "res://assets/ships/medieval_boat.obj"

@export var hull: MeshInstance3D          # the hull mesh (child HullYaw/Hull)
@export var model_scale := 0.0024         # ~4965u long -> ~12 world units
@export var keel_y := -1.5                # keel height vs this pivot

## Sail mount markers, keyed by slot name. Filled from ship.tscn.
@export var sail_mount_paths: Dictionary = {}  # slot name -> NodePath

var _sails := {}  # StringName -> Node3D (instanced sail scene)

func _ready() -> void:
	_fit_hull()

func _fit_hull() -> void:
	# Self-wire: don't trust exported node refs from a hand-authored .tscn.
	if hull == null:
		hull = get_node_or_null(^"HullYaw/Hull") as MeshInstance3D
	if hull and hull.mesh == null:
		hull.mesh = load(HULL_MESH_PATH) as Mesh
	if hull == null or hull.mesh == null:
		push_warning("ShipVisual: hull mesh missing — using greybox box")
		if hull:
			hull.visible = false
		var box_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4, 3, 12)
		box_mesh.mesh = box
		add_child(box_mesh)
		return
	hull.scale = Vector3.ONE * model_scale
	var aabb := hull.mesh.get_aabb()
	var c := aabb.position + aabb.size * 0.5
	# Centre X/Z on the pivot; rest the keel (min Y) at keel_y.
	hull.position = Vector3(
		-c.x * model_scale,
		keel_y - aabb.position.y * model_scale,
		-c.z * model_scale
	)

## --- Swappable sails API ---------------------------------------------------

func get_mount(slot: StringName) -> Node3D:
	var path: NodePath = sail_mount_paths.get(slot, NodePath())
	var mount := get_node_or_null(path) as Node3D
	if mount == null:
		# Fallback: find by convention, e.g. &"main" -> "MainSailMount".
		mount = get_node_or_null("HullYaw/%sSailMount" % String(slot).capitalize()) as Node3D
	return mount

## Replace whatever is in `slot` with an instance of `sail_scene` (null = clear).
func set_sail(slot: StringName, sail_scene: PackedScene) -> void:
	clear_sail(slot)
	if sail_scene == null:
		return
	var mount := get_mount(slot)
	if mount == null:
		push_warning("ShipVisual: no sail mount named '%s'" % slot)
		return
	var sail := sail_scene.instantiate()
	mount.add_child(sail)
	_sails[slot] = sail

func clear_sail(slot: StringName) -> void:
	if _sails.has(slot):
		var old: Node = _sails[slot]
		if is_instance_valid(old):
			old.queue_free()
		_sails.erase(slot)

## For ShipController later: e.g. furl/unfurl visuals on F/G toggles.
func get_sail(slot: StringName) -> Node3D:
	return _sails.get(slot)
