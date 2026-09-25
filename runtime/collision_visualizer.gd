## Draws a translucent red box at the live overlap region of every current
## collision (TimelineController.get_collisions()), refreshed every frame.
## Distinct from CollisionOverlay (2D, paints the slider from a one-shot
## scan_collisions() scan) -- this is the 3D "where in the building is it
## happening right now" view for whatever day/progress is currently applied.
class_name CollisionVisualizer
extends Node3D

## Minimum marker size per axis, in meters. Raised well above the tiny AABB
## overlaps a graze produces (often just a few cm) so the marker stays easy
## to spot instead of shrinking to something you have to hunt for.
@export var min_marker_size: float = 0.6
## Extra margin added around the actual overlap region per axis (both
## sides), so even a large real overlap gets a visible "halo" beyond its
## exact bounds rather than blending into the geometry it's marking.
@export var size_padding: float = 0.3

var _timeline_controller: TimelineController = null
var _markers: Array = [] # pooled MeshInstance3D, reused/hidden rather than freed each frame

func set_timeline_controller(controller: TimelineController) -> void:
	_timeline_controller = controller

func _process(_delta: float) -> void:
	if not _timeline_controller:
		return
	_update_markers(_timeline_controller.get_collisions())

func _update_markers(collisions: Array) -> void:
	while _markers.size() < collisions.size():
		_markers.append(_make_marker())

	for i in range(_markers.size()):
		var marker: MeshInstance3D = _markers[i]
		if i >= collisions.size():
			marker.visible = false
			continue

		var aabb: AABB = collisions[i].overlap_aabb
		var box_size := aabb.size + Vector3.ONE * (size_padding * 2.0)
		box_size.x = maxf(box_size.x, min_marker_size)
		box_size.y = maxf(box_size.y, min_marker_size)
		box_size.z = maxf(box_size.z, min_marker_size)

		# Set world transform directly (not local scale/position) so the
		# marker's size is exact regardless of this node's own ancestors'
		# transform/scale.
		marker.global_transform = Transform3D(Basis().scaled(box_size), aabb.get_center())
		marker.visible = true

func _make_marker() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.15, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.1)
	mat.emission_energy_multiplier = 2.0
	# Collision markers are, by definition, usually sitting inside the solid
	# parts that are clashing -- without this they'd often be fully hidden
	# behind whatever they're marking.
	mat.no_depth_test = true
	mesh_instance.material_override = mat
	mesh_instance.visible = false

	add_child(mesh_instance)
	return mesh_instance
