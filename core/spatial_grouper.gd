class_name SpatialGrouper

var _cache = {}

func get_groups(commander_prefix: String, child_prefixes: Array, building_parts: Dictionary) -> Dictionary:
	var cache_key = commander_prefix + "|" + "|".join(child_prefixes)
	if not _cache.has(cache_key):
		_cache[cache_key] = _compute(commander_prefix, child_prefixes, building_parts)
	return _cache[cache_key]

func _compute(commander_prefix: String, child_prefixes: Array, building_parts: Dictionary) -> Dictionary:
	var commanders = []
	for part_name in building_parts.keys():
		if part_name.begins_with(commander_prefix):
			commanders.append(part_name)
	commanders.sort()

	var result = {}
	for cmd in commanders:
		result[cmd] = []

	# Precompute each commander's world-space XZ centroid once
	var cmd_xz = {}
	for cmd_name in commanders:
		var cmd_part = building_parts[cmd_name]
		var cmd_xform: Transform3D = cmd_part.get_meta("original_transform")
		var world_center: Vector3
		if cmd_part is MeshInstance3D:
			world_center = cmd_xform * cmd_part.get_meta("original_aabb").get_center()
		else:
			world_center = cmd_xform.origin
		cmd_xz[cmd_name] = Vector2(world_center.x, world_center.z)

	for cp in child_prefixes:
		for part_name in building_parts.keys():
			if not part_name.begins_with(cp):
				continue

			var child_part = building_parts[part_name]
			var child_xform: Transform3D = child_part.get_meta("original_transform")
			var child_world: Vector3
			if child_part is MeshInstance3D:
				child_world = child_xform * child_part.get_meta("original_aabb").get_center()
			else:
				child_world = child_xform.origin
			var child_xz = Vector2(child_world.x, child_world.z)

			var best_cmd = ""
			var best_dist = INF
			for cmd_name in commanders:
				var dist = child_xz.distance_to(cmd_xz[cmd_name])
				if dist < best_dist:
					best_dist = dist
					best_cmd = cmd_name

			if best_cmd != "":
				result[best_cmd].append(part_name)

	return result

## Pieces whose bases are within this many metres of each other count as one
## level, and are then ordered by plan position.
const LEVEL_BAND := 0.5

## Placement order for staggered parts: bottom-up by level, then across the plan
## (z, then x). Building goes upwards -- a quoin is set on the one below it, a
## first-floor surround after the ground-floor one -- and ordering by plan alone
## had pieces placed above ones still to come, which a crane lift then had to
## pass through on its way down.
static func sort_by_position(parts: Array, building_parts: Dictionary) -> Array:
	var level := {}
	for name in parts:
		level[name] = floori(_base_height(building_parts[name]) / LEVEL_BAND)
	var sorted = parts.duplicate()
	sorted.sort_custom(func(a, b):
		if level[a] != level[b]:
			return level[a] < level[b]
		var pa: Vector3 = building_parts[a].get_meta("original_pos")
		var pb: Vector3 = building_parts[b].get_meta("original_pos")
		if pa.z != pb.z:
			return pa.z > pb.z
		return pa.x > pb.x
	)
	return sorted

## World height of a part's underside at its finished placement.
static func _base_height(part: Node3D) -> float:
	if part.has_meta("original_transform") and part.has_meta("original_aabb"):
		var box: AABB = part.get_meta("original_transform") * (part.get_meta("original_aabb") as AABB)
		return box.position.y
	if part.has_meta("original_transform"):
		return (part.get_meta("original_transform") as Transform3D).origin.y
	return 0.0
