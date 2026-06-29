class_name HeightmapTerrain
extends StaticBody3D
## Terrain built from a raw float32 height grid (a GEBCO bathymetry+topo crop).
## Heights are metres with sea level at 0; we scale them into world Y so the ocean
## plane (y=0) meets the land at the real coastline. Sits in the "land" group so the
## ship grounds on it via the existing coast-damage logic in ship_controller.gd.

@export var height_path := "res://assets/terrain/region_height.bin"
@export var grid_n := 513                            # samples per side in the .bin
@export var world_size := Vector2(3236.0, 4000.0)    # X (east-west), Z (north-south) world units
## Land height uses a saturating curve: ~linear near sea level (land_near_slope) while
## tall mountains compress toward land_max_height, so peaks are not absurdly tall.
@export var land_near_slope := 0.06    # world units per metre near sea level
@export var land_max_height := 60.0    # peaks saturate toward this many world units

var _heights: PackedFloat32Array

func _ready() -> void:
	add_to_group("land")
	if not _load_heights():
		push_warning("HeightmapTerrain: could not load %s" % height_path)
		return
	_build_mesh()
	_build_collision()

func _load_heights() -> bool:
	var f := FileAccess.open(height_path, FileAccess.READ)
	if f == null:
		return false
	var n := grid_n * grid_n
	var bytes := f.get_buffer(n * 4)
	if bytes.size() < n * 4:
		return false
	_heights = bytes.to_float32_array()
	return _heights.size() >= n

func _h(ix: int, iz: int) -> float:
	return _shape_height(_heights[iz * grid_n + ix])

func _shape_height(e: float) -> float:
	# Saturating exponential: ~e*land_near_slope near 0, asymptotes to land_max_height.
	if e >= 0.0:
		return land_max_height * (1.0 - exp(-e * land_near_slope / land_max_height))
	return e * land_near_slope   # seabed stays linear (hidden under the ocean)

func _build_mesh() -> void:
	var n := grid_n
	var dx := world_size.x / float(n - 1)
	var dz := world_size.y / float(n - 1)
	var ox := -world_size.x * 0.5
	var oz := -world_size.y * 0.5
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	for iz in range(n):
		for ix in range(n):
			var idx := iz * n + ix
			verts[idx] = Vector3(ox + ix * dx, _h(ix, iz), oz + iz * dz)
			var hl := _h(maxi(ix - 1, 0), iz)
			var hr := _h(mini(ix + 1, n - 1), iz)
			var hd := _h(ix, maxi(iz - 1, 0))
			var hu := _h(ix, mini(iz + 1, n - 1))
			norms[idx] = Vector3((hl - hr) / (2.0 * dx), 1.0, (hd - hu) / (2.0 * dz)).normalized()
	var indices := PackedInt32Array(); indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in range(n - 1):
		for ix in range(n - 1):
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices[k] = a; indices[k + 1] = c; indices[k + 2] = d; k += 3
			indices[k] = a; indices[k + 1] = d; indices[k + 2] = b; k += 3
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/terrain/terrain.gdshader")
	mi.material_override = mat
	add_child(mi)

func _build_collision() -> void:
	var n := grid_n
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var data := PackedFloat32Array(); data.resize(n * n)
	for i in range(n * n):
		data[i] = _shape_height(_heights[i])
	shape.map_data = data
	var cs := CollisionShape3D.new()
	# The shape is unit-spaced and centred; stretch X/Z to cover world_size (Y stays 1:1).
	cs.scale = Vector3(world_size.x / float(n - 1), 1.0, world_size.y / float(n - 1))
	cs.shape = shape
	add_child(cs)
