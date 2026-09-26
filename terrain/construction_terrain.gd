@tool
class_name ConstructionTerrain
extends Node3D

## The ground around the model, built from a saved TerrainData.
##
## Its children (the ground mesh and its collision) are generated on load and
## never saved into the scene: the .tscn only stores this node and a reference
## to the terrain resource, which keeps scenes small and makes a rebuild just a
## matter of pointing `data` at a new file.
##
## Placement: the node positions itself so the terrain lines up with the model,
## from `geo_origin` (where the model is on the map) and `anchor_path` (the
## parts container the origin refers to). Edit the origin -- move it, turn it,
## raise it -- and the terrain follows. Keep it a sibling of the parts
## container, never inside it: everything in there is treated as a part.

@export var data: TerrainData:
	set(value):
		data = value
		if is_inside_tree():
			rebuild()
@export var geo_origin: GeoOrigin:
	set(value):
		if geo_origin and geo_origin.changed.is_connected(_on_origin_changed):
			geo_origin.changed.disconnect(_on_origin_changed)
		geo_origin = value
		if geo_origin and not geo_origin.changed.is_connected(_on_origin_changed):
			geo_origin.changed.connect(_on_origin_changed)
		if is_inside_tree():
			_on_origin_changed()
## The parts container `geo_origin` describes, relative to this node.
@export var anchor_path: NodePath
## Tiled leaf-litter / rock textures close to the camera (see GroundTextures).
@export var use_near_textures: bool = true:
	set(value):
		use_near_textures = value
		if is_inside_tree():
			_apply_material()
@export var grade_orthophoto: bool = true:
	set(value):
		grade_orthophoto = value
		if _material:
			_material.set_shader_parameter("grade_ortho", value)
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		if is_inside_tree():
			rebuild()
## Where GroundTextures keeps the near textures.
@export var ground_textures_dir: String = GroundTextures.DEFAULT_DIR
## Levelled areas cut and filled into the ground, applied in order (a building
## pad, then its excavation pit). Empty: the natural ground as downloaded --
## right for a bridge or anything else built on the land as it is. Each one can
## follow its earthwork activities on the timeline. See TerrainPlatform.
@export var platforms: Array[TerrainPlatform] = []:
	set(value):
		for p in platforms:
			if p and p.changed.is_connected(_queue_rebuild):
				p.changed.disconnect(_queue_rebuild)
		platforms = value
		for p in platforms:
			if p and not p.changed.is_connected(_queue_rebuild):
				p.changed.connect(_queue_rebuild)
		_queue_rebuild()

## Every ConstructionTerrain joins this group, so the timeline can find them.
const GROUP := "construction_terrain"

const _SHADER := preload("res://addons/construction_4d_tool/terrain/ground.gdshader")
const _GENERATED := "_generated"

var _material: ShaderMaterial
var _grading: TerrainGrading
var _progress := PackedFloat32Array()
var _rebuild_queued := false

func _enter_tree() -> void:
	add_to_group(GROUP)

func _ready() -> void:
	rebuild()

## The platforms' cut/fill, or null when there are none (natural ground).
func grading() -> TerrainGrading:
	return _grading

## Regenerates the mesh, material and collision from `data`.
func rebuild() -> void:
	_rebuild_queued = false
	_clear_generated()
	update_placement()
	_grading = null
	if not data or data.grid_n < 2 or data.heights.size() != data.grid_n * data.grid_n:
		return
	if not platforms.is_empty():
		_grading = TerrainGrading.compute(data, platforms, _container_to_terrain())
	_progress.resize(TerrainGrading.MAX_PLATFORMS)
	_progress.fill(1.0)
	var n := data.grid_n
	var size := (n - 1) * data.cell

	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = n - 2
	plane.subdivide_depth = n - 2
	# Heights are applied in the shader, so tell culling how tall it really is.
	var low := minf(data.min_height, _grading.min_height) if _grading else data.min_height
	var high := maxf(data.max_height, _grading.max_height) if _grading else data.max_height
	plane.custom_aabb = AABB(Vector3(-size / 2.0, low, -size / 2.0),
		Vector3(size, maxf(high - low, 0.1), size))

	var mesh := MeshInstance3D.new()
	mesh.name = "Ground"
	mesh.mesh = plane
	mesh.set_meta(_GENERATED, true)
	add_child(mesh)
	_material = ShaderMaterial.new()
	_material.shader = _SHADER
	mesh.material_override = _material
	_apply_material()

	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "GroundBody"
		body.set_meta(_GENERATED, true)
		if data.collision_n < 2:
			TerrainBuilder.add_collision(data)
		var shape := HeightMapShape3D.new()
		shape.map_width = data.collision_n
		shape.map_depth = data.collision_n
		# Collision is the finished ground: platforms complete, whatever day the
		# timeline shows. Rebuilding a 1025^2 height field per frame is not worth it.
		shape.map_data = _grading.patched_collision() if _grading else data.collision_map
		var col := CollisionShape3D.new()
		col.shape = shape
		col.scale = Vector3.ONE * data.collision_spacing()
		body.add_child(col)
		add_child(body)

func _apply_material() -> void:
	if not _material or not data:
		return
	var m := _material
	m.set_shader_parameter("heightmap", ImageTexture.create_from_image(data.height_image()))
	m.set_shader_parameter("grid_n", data.grid_n)
	m.set_shader_parameter("cell", data.cell)
	m.set_shader_parameter("has_context", data.context_texture != null and data.context_rect.size() == 4)
	m.set_shader_parameter("ortho_context", data.context_texture)
	m.set_shader_parameter("context_rect", _local_rect(data.context_rect))
	m.set_shader_parameter("has_detail", data.detail_texture != null and data.detail_rect.size() == 4)
	m.set_shader_parameter("ortho_detail", data.detail_texture)
	m.set_shader_parameter("detail_rect", _local_rect(data.detail_rect))
	m.set_shader_parameter("grade_ortho", grade_orthophoto)
	m.set_shader_parameter("has_grading", _grading != null)
	if _grading:
		var r := _grading.rect
		m.set_shader_parameter("grading", ImageTexture.create_from_image(_grading.image))
		m.set_shader_parameter("grading_rect", Vector4i(r.position.x, r.position.y, r.size.x, r.size.y))
		m.set_shader_parameter("grade_bare", _grading.bare_flags())
		m.set_shader_parameter("grade_progress", _progress)
	var tex := GroundTextures.load_all(ground_textures_dir) if use_near_textures else {}
	m.set_shader_parameter("use_near", not tex.is_empty())
	for key in tex:
		m.set_shader_parameter(key, tex[key])

## Map rectangle [e0, n0, e1, n1] -> shader rect (x0, z_north, x1, z_south)
## in this node's local metres.
func _local_rect(r: PackedFloat64Array) -> Vector4:
	if r.size() != 4 or not data:
		return Vector4.ZERO
	return Vector4(r[0] - data.center_e, -(r[3] - data.center_n), r[2] - data.center_e, -(r[1] - data.center_n))

## Puts the node where the terrain lines up with the model. Without an origin
## the terrain sits at its own centre, which is only right for a model placed
## there by hand.
func update_placement() -> void:
	if not data or not geo_origin or not geo_origin.has_position():
		return
	var anchor_tf := _anchor_transform()
	var offset := Vector3(data.center_e - geo_origin.easting, -geo_origin.height, -(data.center_n - geo_origin.northing))
	transform = anchor_tf * geo_origin.map_frame_transform() * Transform3D(Basis(), offset)

## The parts container's transform in this node's parent's space (identity
## without one).
func _anchor_transform() -> Transform3D:
	var anchor := get_node_or_null(anchor_path) as Node3D
	if anchor and anchor.get_parent() == get_parent():
		return anchor.transform
	elif anchor:
		return (get_parent() as Node3D).global_transform.affine_inverse() * anchor.global_transform if get_parent() is Node3D else anchor.global_transform
	return Transform3D()

## Parts container space -> this node's space, where platforms are applied.
func _container_to_terrain() -> Transform3D:
	return transform.affine_inverse() * _anchor_transform()

## Moving the origin moves the terrain under the model, so the platforms
## (drawn in the model's space) land on different grid points.
func _on_origin_changed() -> void:
	update_placement()
	if not platforms.is_empty():
		_queue_rebuild()

func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()

## Ground height (absolute metres) under a map point, platforms included;
## NAN outside the grid.
func height_at(e: float, n: float) -> float:
	if not data:
		return NAN
	return _grading.height_at(e, n) if _grading else data.height_at(e, n)

## Shows each platform as far along as its activities are on `day`.
func follow_schedule(schedule: ConstructionSchedule, day: float) -> void:
	if not _grading or not _material:
		return
	var p := PackedFloat32Array()
	p.resize(TerrainGrading.MAX_PLATFORMS)
	p.fill(1.0)
	for i in _grading.used.size():
		p[i] = _grading.used[i].progress_on(schedule, day)
	if p != _progress:
		_progress = p
		_material.set_shader_parameter("grade_progress", _progress)

## Back to the finished ground (every platform complete).
func show_finished() -> void:
	follow_schedule(null, 0.0)

## Called by TimelineController.scrub_to() for every terrain in the tree.
static func update_all(tree: SceneTree, schedule: ConstructionSchedule, day: float) -> void:
	for t in tree.get_nodes_in_group(GROUP):
		(t as ConstructionTerrain).follow_schedule(schedule, day)

static func reset_all(tree: SceneTree) -> void:
	for t in tree.get_nodes_in_group(GROUP):
		(t as ConstructionTerrain).show_finished()

func _clear_generated() -> void:
	_material = null
	for child in get_children():
		if child.has_meta(_GENERATED):
			remove_child(child)
			child.queue_free()
