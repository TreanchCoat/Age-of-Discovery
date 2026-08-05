@tool
extends EditorScript
## Converts the resampled float32 height grid into an EXR for the Terrain3D
## importer. Run from the editor: open this script → File > Run (Ctrl+Shift+X).
##
## Input:  res://assets/terrain/terrain3d_height_2048_f32.bin
##         (float32 row-major, PADDED to 2048x2048 so the image corner is
##          region-aligned — the importer FLOORS the corner to the region grid,
##          which shifted the unpadded map by (-430,-48). Data is centered:
##          world coverage -2048..+2048 at vertex_spacing 2.0, curve baked.)
## Output: res://assets/terrain/terrain3d_height.exr  (FORMAT_RF, lossless)
##
## Then in the Terrain3D importer (addons/terrain_3d/tools/importer.tscn):
##   vertex spacing 2.0 · height file = the EXR · scale 1 · offset 0
##   import position = (-2048, -2048)   <- MUST be exactly this
## Save regions to res://assets/terrain/t3d_data (delete old contents first).

const IN_PATH := "res://assets/terrain/terrain3d_height_2048_f32.bin"
const OUT_PATH := "res://assets/terrain/terrain3d_height.exr"
const W := 2048
const H := 2048

func _run() -> void:
	var f := FileAccess.open(IN_PATH, FileAccess.READ)
	if f == null:
		push_error("missing input: " + IN_PATH)
		return
	var bytes := f.get_buffer(W * H * 4)
	if bytes.size() != W * H * 4:
		push_error("size mismatch: got %d bytes, expected %d" % [bytes.size(), W * H * 4])
		return
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RF, bytes)
	var err := img.save_exr(OUT_PATH, false)
	if err != OK:
		push_error("save_exr failed: %d" % err)
		return
	print("wrote %s (%dx%d)" % [OUT_PATH, W, H])
