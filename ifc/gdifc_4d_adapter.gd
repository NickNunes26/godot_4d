@tool
class_name GDIFC4DAdapter
extends RefCounted

## Adapts a loaded GDIFCManager's tree into what
## `runtime/sequence_manager.gd`'s `initialize_parts()` actually expects:
## a flat container of named `MeshInstance3D` children, each with its
## placement in its own node transform. See
## `addons/construction_4d_tool/docs/05_IFC_INTEGRATION.md` for the full
## writeup of why GDIFC's raw output satisfies none of that -- this class
## implements that doc's "The adapter" section.
##
## Call `adapt()` once, after GDIFCManager's `ifc_read` signal has fired (and
## after any global recenter, e.g. `read_ifc.gd`'s shift, has already run --
## this only re-origins *individual* parts, it doesn't touch the model's
## overall position). Returns a new, unparented flat Node3D container;
## the caller decides where to attach it and whether to set `owner` on its
## children for persistence.

## Parts are named after the property the user selected as **Element ID**
## (IfcMapping). Parts that carry no value for it fall back to a name built
## from their structural zone, so they still render, collide and are visible,
## just not individually schedulable. With no mapping at all every part uses
## the fallback.

static func adapt(ifc_root: Node, mapping: IfcMapping = null, taken_names: Dictionary = {}) -> Node3D:
	var container := Node3D.new()
	container.name = "IFCParts"

	var leaves: Array[Dictionary] = []
	_collect_leaves(ifc_root, ifc_root.name, leaves)

	# Seeded with the names other models in the scene already use, so a part
	# that repeats one gets a suffix instead of shadowing it.
	var used_names := taken_names.duplicate()
	var missing_pset_count := 0
	var renamed_count := 0

	for entry in leaves:
		var leaf := entry.node as MeshInstance3D
		var zone: String = entry.zone

		# Compute the part's correct absolute placement (and re-origin its
		# mesh) while it's still under its original GDIFC-built ancestry, but
		# don't apply the transform yet: reparenting below does NOT preserve
		# global_transform in Godot -- it keeps `transform` (local) numerically
		# unchanged and reinterprets it under the new parent. If any ancestor
		# in GDIFC's nested tree (the IFC spatial-structure containers) carries a
		# non-identity scale, applying the transform before reparenting would
		# silently scale every part wrong once it lands under `container`.
		var desired_global := _reorigin(leaf)
		_strip_collision_helpers(leaf)

		var psets := get_property_sets(leaf)
		# Plain `=`, not `:=`: get_value() returns an untyped Variant, which
		# `:=` cannot infer a type from.
		var element_id = IfcMapping.get_value(psets, mapping.element_id) if mapping else null
		var display_name = IfcMapping.get_value(psets, mapping.display_name) if mapping else null

		var base_name: String
		if element_id != null and not str(element_id).strip_edges().is_empty():
			base_name = str(element_id).strip_edges()
		else:
			missing_pset_count += 1
			base_name = "%s_%s" % [zone, leaf.name]

		if taken_names.has(base_name):
			renamed_count += 1
		leaf.name = _uniquify(base_name, used_names)
		if display_name != null:
			leaf.set_meta("ifc_display_name", display_name)
		leaf.set_meta("ifc_zone", zone)

		leaf.get_parent().remove_child(leaf)
		container.add_child(leaf)
		# `container` is still unparented at this point (own global_transform
		# == identity), so this assigns exactly `desired_global` as the part's
		# new local transform -- correct regardless of where `container`
		# itself gets attached afterwards.
		leaf.global_transform = desired_global

	if missing_pset_count > 0:
		push_warning("GDIFC4DAdapter: %d/%d parts had no Element ID value -- named by structural zone instead, so they render/collide but aren't individually schedulable" % [missing_pset_count, leaves.size()])
	if renamed_count > 0:
		push_warning("GDIFC4DAdapter: %d part(s) repeat a name another model in the scene already uses -- suffixed (_2, _3...) so both stay registered" % renamed_count)

	return container


## Walks the raw GDIFC tree, collecting every mesh-bearing leaf together with
## the name of the nearest ancestor that looks like a structural grouping
## (an IFC spatial-structure container -- i.e. an IFCNode with no mesh of its
## own). Used as the fallback naming zone for parts with no Element ID value.
static func _collect_leaves(node: Node, current_zone: String, out: Array[Dictionary]) -> void:
	for child in node.get_children():
		var zone := current_zone
		if child is MeshInstance3D and (child as MeshInstance3D).mesh == null:
			zone = child.name # mesh-less container node
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append({"node": child, "zone": zone})
		_collect_leaves(child, zone, out)


## Moves each vertex's survey-scale placement out of the mesh data and into
## the node's own transform, without changing where anything renders. GDIFC
## leaves every leaf's local position at (0,0,0) with the real placement
## baked into the mesh's vertex buffer (see the doc above) -- that breaks
## SequenceManager's scale/position math, since scaling a node scales its
## mesh about the node's *own* origin, and every part's origin sits nowhere
## near its geometry.
##
## Replaces `leaf.mesh` immediately (order doesn't matter for that), but only
## returns the part's correct resulting global_transform rather than applying
## it -- the caller must apply it *after* reparenting into the flat
## container, since reparenting doesn't preserve global_transform.
static func _reorigin(leaf: MeshInstance3D) -> Transform3D:
	var mesh := leaf.mesh
	if not mesh:
		return leaf.global_transform

	var center := mesh.get_aabb().get_center()
	if center == Vector3.ZERO:
		return leaf.global_transform # already origin-centered, nothing to do

	var new_mesh := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] -= center
		arrays[Mesh.ARRAY_VERTEX] = verts
		new_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), arrays)
		var mat := mesh.surface_get_material(surface)
		if mat:
			new_mesh.surface_set_material(surface, mat)

	# The node's new origin becomes where the old mesh-space center used to
	# render (basis/scale untouched, since only the vertex data and
	# translation are shifting) -- computed here, while `leaf` still has its
	# original GDIFC-built ancestry, so this reads the correct current scale.
	var old_global := leaf.global_transform
	leaf.mesh = new_mesh
	return Transform3D(old_global.basis, old_global * center)


## Removes GDIFC's own native collision helper children (created when the
## dock's "Create collisions" option is on: a "<name>_col" MeshInstance3D
## holding a CollisionShape3D). The 4D tool never reads these -- CollisionQuery
## builds its own convex/concave shapes straight from each part's `.mesh` at
## schedule time -- and they're placed using the pre-recenter, un-re-origined
## coordinates, so left in place after adaptation they render as a huge,
## disconnected box nowhere near the part they belong to.
static func _strip_collision_helpers(leaf: MeshInstance3D) -> void:
	for child in leaf.get_children():
		if child.name.ends_with("_col"):
			leaf.remove_child(child)
			child.queue_free()


## Reads GDIFC's IFC property sets off an IFCNode.
##
## Verified on Godot 4.6.2: property sets arrive as the node's `properties`
## **Dictionary** property, keyed by property-set name --
## `{"<pset name>": {"<property name>": <value>, ...}, ...}`.
##
## An older version called `get_ifc_property_sets()`. That name appears in the
## library's symbol table but is NOT bound on IFCNode (`has_method()` is false
## for every part), so that lookup silently returned {}. The method call is
## kept as a fallback in case a future GDIFC build binds it, but `properties`
## is what actually works today.
static func get_property_sets(leaf: MeshInstance3D) -> Dictionary:
	var props = leaf.get("properties")
	if props is Dictionary and not (props as Dictionary).is_empty():
		return props
	if leaf.has_method("get_ifc_property_sets"):
		var result = leaf.call("get_ifc_property_sets")
		if result is Dictionary:
			return result
	return {}


static func _uniquify(name: String, used_names: Dictionary) -> String:
	if not used_names.has(name):
		used_names[name] = 1
		return name
	# Skip suffixed names already in use too ("X_2" may be a name of its own,
	# or another model's suffixed "X").
	var n: int = used_names[name]
	var candidate := name
	while used_names.has(candidate):
		n += 1
		candidate = "%s_%d" % [name, n]
	used_names[name] = n
	used_names[candidate] = 1
	return candidate
