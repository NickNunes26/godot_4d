@tool
class_name IfcSceneModels
extends RefCounted

## Where an imported IFC model goes in a scene that may already hold others --
## e.g. the two carriageways of one bridge, exported as two files that share a
## map conversion. Pure scene logic, no editor API, so it is testable headless;
## the dock's Load IFC (4D) calls attach().
##
## Invariant kept: `SequenceManager.geo_origin` describes the local origin of
## the **primary** container (`parts_container_path`). Terrain and sun anchor to
## that container. Every other model's container is a sibling in
## `extra_part_containers`, whose transform places it relative to the primary
## where the map says (GeoOrigin.relative_transform()). Each model keeps small
## local coordinates of its own (the dock still centres it on load), so nothing
## reaches float32 at map magnitude.
##
## Rules:
## - The first model becomes the primary and its origin the scene's.
## - A later model is placed relative to the scene's origin, which is kept, and
##   appended to `extra_part_containers`.
## - Importing a file again (same file name) replaces that model's container in
##   place, primary or extra. Replacing the primary rebases the origin onto the
##   new container; the site on the map does not move.
## - A model without a georeference cannot be placed: it goes at the primary's
##   origin, with a message saying so.

## Meta on each container: the IFC file name it was imported from.
const SOURCE_META := "ifc_source_file"

## The containers the SequenceManager uses, primary first. Missing paths are
## skipped.
static func containers(sm: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var primary := _primary(sm)
	if primary:
		out.append(primary)
	for path in sm.get("extra_part_containers"):
		var n := sm.get_node_or_null(path) as Node3D
		if n and not out.has(n):
			out.append(n)
	return out

## Names of the parts already in the scene, excluding the container that an
## import of `source_file` would replace: pass to GDIFC4DAdapter.adapt() so a
## second model's parts don't collide with the first's (SequenceManager
## registers parts by name, so a collision would drop one of them).
static func taken_part_names(sm: Node, source_file: String) -> Dictionary:
	var taken := {}
	for c in containers(sm):
		if c.get_meta(SOURCE_META, "") == source_file:
			continue
		for part in c.get_children():
			taken[String(part.name)] = 1
	return taken

## Adds `container` (fresh from GDIFC4DAdapter.adapt(), unparented) under the
## SequenceManager, placed and registered per the rules above. `fresh` is the
## model's own origin (GeoOrigin.from_ifc_import()). Returns
## {"role": "primary"|"extra", "replaced": bool, "placement": "first"|"map"|"unplaced",
##  "geo_changed": bool, "message": String}.
## The caller sets `owner` on the new nodes.
static func attach(sm: Node, container: Node3D, fresh: GeoOrigin, source_file: String) -> Dictionary:
	var out := {"role": "extra", "replaced": false, "placement": "first", "geo_changed": false, "message": ""}
	container.name = ("IFCParts_" + source_file.get_basename()).validate_node_name()
	container.set_meta(SOURCE_META, source_file)

	var primary := _primary(sm)
	var extras: Array[NodePath] = []
	extras.assign(sm.get("extra_part_containers"))
	var replaced: Node3D = null
	for c in containers(sm):
		if c.get_meta(SOURCE_META, "") == source_file:
			replaced = c
			break
	var existing = sm.get("geo_origin")
	var geo: GeoOrigin = existing if existing is GeoOrigin else null
	var anchor_tf := primary.transform if primary else Transform3D()
	var becomes_primary := primary == null or replaced == primary

	# Placement, in the SequenceManager's space.
	if geo and geo.has_position():
		if geo.same_map_as(fresh):
			container.transform = anchor_tf * geo.relative_transform(fresh)
			out.placement = "map"
		else:
			container.transform = anchor_tf
			out.placement = "unplaced"
			out.message = ("'%s' has no georeference: it was put at the origin of the first model -- move it into place by hand." % source_file) \
				if not fresh.has_position() else \
				("'%s' is on another map grid (zone %d vs %d): it was put at the origin of the first model -- move it into place by hand." % [source_file, fresh.utm_zone, geo.utm_zone])
	else:
		container.transform = anchor_tf

	# Into the tree, in the replaced container's slot if there is one (removed
	# first, so the new one can take its name).
	if replaced:
		out.replaced = true
		var slot := replaced.get_index() if replaced.get_parent() == sm else -1
		var extra_index := -1
		for i in extras.size():
			if sm.get_node_or_null(extras[i]) == replaced:
				extra_index = i
		replaced.get_parent().remove_child(replaced)
		replaced.queue_free()
		sm.add_child(container, true)
		if slot >= 0:
			sm.move_child(container, slot)
		if extra_index >= 0:
			extras[extra_index] = sm.get_path_to(container)
	else:
		sm.add_child(container, true)
	if becomes_primary:
		out.role = "primary"
		sm.set("parts_container_path", sm.get_path_to(container))
	elif not replaced:
		extras.append(sm.get_path_to(container))
	sm.set("extra_part_containers", extras)

	# The scene's origin: kept, except when the primary is (re)placed by a
	# georeferenced model -- its own origin then describes the new primary.
	var new_geo := geo
	if fresh.has_position() and (becomes_primary or geo == null or not geo.has_position()):
		new_geo = fresh
		if new_geo.utm_zone == 0 and geo and geo.utm_zone > 0 and geo.same_map_as(fresh):
			new_geo.utm_zone = geo.utm_zone
			new_geo.zone_source = geo.zone_source
	elif geo == null:
		new_geo = fresh
	if new_geo != geo:
		sm.set("geo_origin", new_geo)
		out.geo_changed = true
	return out

static func _primary(sm: Node) -> Node3D:
	var path: NodePath = sm.get("parts_container_path")
	return sm.get_node_or_null(path) as Node3D if not path.is_empty() else null
