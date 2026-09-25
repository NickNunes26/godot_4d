@tool
class_name TerrainData
extends Resource

## One downloaded site, saved as a binary resource next to its raw downloads
## (res://terrain/<site>/terrain.res) so scenes only reference it and exports
## carry it. ConstructionTerrain rebuilds its mesh and collision from this on
## load; nothing heavy is ever written into the .tscn.

## UTM zone / hemisphere of every coordinate below.
@export var zone: int = 0
@export var south: bool = false
## Grid centre, whole metres.
@export var center_e: float = 0.0
@export var center_n: float = 0.0
## Grid spacing (m) and points per side.
@export var cell: float = 5.0
@export var grid_n: int = 0
## Absolute heights (m), grid_n * grid_n, row-major, row 0 = north edge,
## column 0 = west edge; point (c, r) is at E = center_e + (c - (grid_n-1)/2) * cell,
## N = center_n - (r - (grid_n-1)/2) * cell.
@export var heights := PackedFloat32Array()
@export var min_height: float = 0.0
@export var max_height: float = 0.0
## Orthophotos and their map rectangles [e0, n0, e1, n1] (absolute metres).
@export var detail_texture: Texture2D
@export var detail_rect := PackedFloat64Array()
@export var context_texture: Texture2D
@export var context_rect := PackedFloat64Array()
## Collision grid: collision_n^2 samples over the same square, pre-divided by
## their spacing (HeightMapShape3D places samples 1 unit apart, so the shape is
## scaled uniformly by the spacing). 2^k + 1 samples per side, which Jolt can
## build as a real height field instead of a triangle mesh.
@export var collision_n: int = 0
@export var collision_map := PackedFloat32Array()
## Where the data came from (provider id or "files") and the credit line to show.
@export var provider_id: String = ""
@export_multiline var attribution: String = ""

## Height (m) at map point (e, n), bilinear, clamped to the grid; NAN when the
## grid is empty.
func height_at(e: float, n: float) -> float:
	if grid_n < 2 or heights.size() != grid_n * grid_n:
		return NAN
	var half := (grid_n - 1) * 0.5
	var u := clampf((e - center_e) / cell + half, 0.0, grid_n - 1.001)
	var v := clampf((center_n - n) / cell + half, 0.0, grid_n - 1.001)
	var c0 := int(u)
	var r0 := int(v)
	var fu := u - c0
	var fv := v - r0
	var i := r0 * grid_n + c0
	return lerpf(lerpf(heights[i], heights[i + 1], fu), lerpf(heights[i + grid_n], heights[i + grid_n + 1], fu), fv)

## Whether (e, n) lies within the grid.
func contains(e: float, n: float) -> bool:
	var half := (grid_n - 1) * 0.5 * cell
	return absf(e - center_e) <= half and absf(n - center_n) <= half

## Distance between collision samples, metres.
func collision_spacing() -> float:
	return (grid_n - 1) * cell / float(collision_n - 1) if collision_n > 1 else cell

## The heights as a single-channel float image (for the shader and collision).
func height_image() -> Image:
	return Image.create_from_data(grid_n, grid_n, false, Image.FORMAT_RF, heights.to_byte_array())
