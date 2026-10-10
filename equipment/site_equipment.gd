@tool
class_name SiteEquipment
extends Node3D

## The site's plant -- tower crane, mobile crane, excavator and truck -- placed
## from the model and brought on and off site by the schedule.
##
## Nothing to model and nothing to configure: on Play, a SequenceManager whose
## scene has no SiteEquipment creates one (SequenceManager.auto_equipment).
## Add one from the dock (*Maquinaria*) to see the proposed positions in the
## editor and move them: the two site markers it creates (TowerCraneSite,
## ExcavatorSite) are ordinary saved nodes, and whatever transform they have is
## where the machine stands. The models themselves are generated and never
## saved, like generated formwork.
##
## What follows the schedule (categories from TaskClassifier):
## - **Tower crane**: erected (mast section by section, then the jib) over
##   `erect_days` before the first structural activity, dismantled after the
##   roof. It is a real Crane (runtime/crane.gd), so `install` lifts use it and
##   start from its laydown area (PickupZone); it also follows each `drop_in`
##   piece it can reach while it is lowered into place.
## - **Mobile crane**: set up beside each lift the tower crane can't make -- a
##   piece out of its reach, or after it has gone -- and driven away after.
## - **Excavator and truck**: at the dig during excavation and earth-fill
##   activities; dig -> slew -> dump into the truck, which leaves full and
##   comes back empty (for fill: arrives full and tips).
##
## Visual only: no machine is a part, none is clash-checked, none appears in
## the schedule inspector. See docs/13_SITE_EQUIPMENT.md.

const GROUP := "site_equipment"
const TOWER_SITE := "TowerCraneSite"
const EXCAVATOR_SITE := "ExcavatorSite"
const _GENERATED := "_equipment_generated"

## TaskClassifier categories the tower crane is there for.
const STRUCTURE := ["concrete_pour", "concrete_element", "concrete_columns", "rebar",
	"steel_timber_frame", "precast", "stone_pieces", "masonry"]
const ROOF := ["roofing"]
const DIG := ["excavation"]
const FILL := ["earth_fill"]
## drop_in work light enough to place by hand or with a telehandler -- no crane.
const LIGHT_LIFTS := ["ironwork_gates", "lighting", "landscaping", "openings", "finishes",
	"services", "curtain_wall"]
## A lift that starts this many days after the roof is done goes to the mobile
## crane: the tower crane has been taken down by then.
const TOWER_GRACE_DAYS := 7.0

## Excavator dig cycle and truck round, in seconds of playback.
const DIG_CYCLE := 11.0
const TRUCK_ROUND := 6 # dig cycles per truck round: arrive, 4 loads, leave
const TRUCK_SPOT := Vector3(7.4, 0, 1.0) # truck origin, excavator space
const TRUCK_RUN := 40.0 # metres from the loading spot to where it leaves view

@export var tower_crane: bool = true:
	set(v):
		tower_crane = v
		_rebuild_preview()
@export var mobile_crane: bool = true
@export var excavator_and_truck: bool = true:
	set(v):
		excavator_and_truck = v
		_rebuild_preview()
## Ground to the underside of the jib, in metres. 0: the tallest part within
## reach plus 10 m.
@export_range(0.0, 200.0, 0.5, "or_greater") var tower_height: float = 0.0:
	set(v):
		tower_height = v
		_rebuild_preview()
## Hook reach from the mast. 0: enough to cover the building, 30--75 m.
@export_range(0.0, 90.0, 1.0) var jib_length: float = 0.0:
	set(v):
		jib_length = v
		_rebuild_preview()
## Days to put the tower crane up, and to take it down.
@export_range(0.0, 30.0, 0.5) var erect_days: float = 4.0

var _tower: Node3D = null
var _tower_jib := 0.0
var _mobile: Node3D = null
var _excavator: Node3D = null
var _truck: Node3D = null

var _plan: Dictionary = {}
var _plan_schedule: ConstructionSchedule = null
var _following := false
var _day := NAN
var _last_day := NAN
var _anim_time := 0.0
var _dig: Dictionary = {} # the active dig/fill window, or {}
var _tower_part: Node3D = null
var _mobile_job: Dictionary = {}
var _mobile_pose := {"slew": 0.0, "luff": 0.0, "extend": 0.0, "out": 0.0, "drop": 2.0}
var _mobile_target := {"slew": 0.0, "luff": 0.0, "extend": 0.0, "out": 0.0, "top": NAN}
var _parts: Dictionary = {}
var _building := false
var _ground_level := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	# A saved SiteEquipment opened in the editor: show the machines on their
	# markers so they can be seen and moved.
	if Engine.is_editor_hint():
		_rebuild_preview.call_deferred()


# --- Setup --------------------------------------------------------------------

## Finds the scene's SiteEquipment, or (with `create`) makes one next to
## `sequence_manager`, then builds its machines for a run. Returns it, or null.
static func ensure(sequence_manager: Node3D, create := true) -> SiteEquipment:
	var tree := sequence_manager.get_tree()
	var found: SiteEquipment = null
	for n in tree.get_nodes_in_group(GROUP):
		found = n
		break
	if not found:
		if not create:
			return null
		found = SiteEquipment.new()
		found.name = "SiteEquipment"
		sequence_manager.add_child(found)
	found.build(sequence_manager, true)
	return found


## Adds a SiteEquipment to the edited scene with its markers at the proposed
## positions and the computed crane size written into its properties, so the
## user sees what Play will do and can change it. Editor only.
static func propose(sequence_manager: Node3D, scene_root: Node) -> SiteEquipment:
	var eq: SiteEquipment = null
	for n in sequence_manager.get_tree().get_nodes_in_group(GROUP):
		eq = n
		break
	if not eq:
		eq = SiteEquipment.new()
		eq.name = "SiteEquipment"
		sequence_manager.add_child(eq, true)
		eq.owner = scene_root
	else:
		for marker_name in [TOWER_SITE, EXCAVATOR_SITE]:
			var old := eq.get_node_or_null(marker_name)
			if old:
				eq.remove_child(old)
				old.free()
	# Fresh proposal: sizes from the model as it is now.
	eq._building = true
	eq.tower_height = 0.0
	eq.jib_length = 0.0
	eq._building = false
	eq.build(sequence_manager, false)
	for marker_name in [TOWER_SITE, EXCAVATOR_SITE]:
		var marker := eq.get_node_or_null(marker_name)
		if marker:
			marker.owner = scene_root
	return eq


## Builds every enabled machine. Markers that already exist are used where
## they stand; missing ones are proposed from the model. `runtime` makes the
## tower crane a working Crane.
func build(sequence_manager: Node3D, runtime: bool) -> void:
	_building = true
	_build(sequence_manager, runtime)
	_building = false


func _build(sequence_manager: Node3D, runtime: bool) -> void:
	_clear_models()
	_plan_schedule = null
	var ctx := site_context(sequence_manager)
	if ctx.boxes.is_empty():
		return
	_ground_level = ctx.ground
	var tree := get_tree()
	if tower_crane and not (runtime and _scene_has_other_crane(tree)):
		var marker := get_node_or_null(TOWER_SITE) as Node3D
		if not marker:
			marker = _add_marker(TOWER_SITE, _propose_tower_site(ctx, tree))
		var size := tower_size(ctx, marker.global_position, tower_height, jib_length)
		if not runtime:
			tower_height = size.height
			jib_length = size.jib
		_build_tower(marker, size, ctx, tree, runtime)
	if excavator_and_truck and not ctx.dig_box.size.is_zero_approx():
		var marker := get_node_or_null(EXCAVATOR_SITE) as Node3D
		if not marker:
			marker = _add_marker(EXCAVATOR_SITE, _propose_excavator_site(ctx, tree))
		_excavator = _generated(EquipmentModels.excavator(), marker)
		_truck = _generated(EquipmentModels.truck(), marker)
		_truck.position = TRUCK_SPOT
		_truck.rotation.y = PI
	if mobile_crane:
		_mobile = _generated(EquipmentModels.mobile_crane(), self)
		_mobile.visible = false
	_show_rest()


## Editor display of a saved SiteEquipment: the machines on their markers,
## sized from the exported values.
func _rebuild_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _following or _building:
		return
	_clear_models()
	var tower_marker := get_node_or_null(TOWER_SITE) as Node3D
	if tower_crane and tower_marker:
		var h := tower_height if tower_height > 0.0 else 30.0
		var j := jib_length if jib_length > 0.0 else 40.0
		_tower = _generated(EquipmentModels.tower_crane(h, j, clampf(j * 0.3, 10.0, 22.0)), tower_marker)
		_tower_jib = j
	_ground_level = tower_marker.global_position.y if tower_marker else 0.0
	var exc_marker := get_node_or_null(EXCAVATOR_SITE) as Node3D
	if excavator_and_truck and exc_marker:
		_excavator = _generated(EquipmentModels.excavator(), exc_marker)
		_truck = _generated(EquipmentModels.truck(), exc_marker)
		_truck.position = TRUCK_SPOT
		_truck.rotation.y = PI
	if mobile_crane:
		_mobile = _generated(EquipmentModels.mobile_crane(), self)
	_show_rest()


func _build_tower(marker: Node3D, size: Dictionary, ctx: Dictionary, tree: SceneTree, runtime: bool) -> void:
	var laydown := _propose_laydown(marker, ctx, tree)
	_tower = EquipmentModels.tower_crane(size.height, size.jib, size.counter_jib, laydown, runtime)
	_tower_jib = size.jib
	_tower.set_meta(_GENERATED, true)
	# Added last: a Crane reads its parts' transforms in _ready().
	marker.add_child(_tower)


func _clear_models() -> void:
	for holder in [self, get_node_or_null(TOWER_SITE), get_node_or_null(EXCAVATOR_SITE)]:
		if not holder:
			continue
		for child in holder.get_children():
			if child.has_meta(_GENERATED):
				holder.remove_child(child)
				child.free()
	_tower = null
	_mobile = null
	_excavator = null
	_truck = null
	_tower_part = null


func _generated(model: Node3D, parent: Node3D) -> Node3D:
	model.set_meta(_GENERATED, true)
	parent.add_child(model)
	return model


func _add_marker(marker_name: String, tf: Transform3D) -> Node3D:
	var m := Node3D.new()
	m.name = marker_name
	add_child(m)
	m.global_transform = tf
	return m


## True when the scene already has a crane of its own (one the user modelled),
## in which case no tower crane is added.
func _scene_has_other_crane(tree: SceneTree) -> bool:
	var scene := tree.current_scene if tree else null
	if not scene:
		return false
	for n in scene.find_children("*", "Node3D", true, false):
		if n is Crane and not is_ancestor_of(n):
			return true
	return false


# --- Site analysis ------------------------------------------------------------

## What placement works from: every part's rest box (world), the actions with
## their categories and parts, the building's box, the dig's box, and a
## fallback ground level (the level most of the model stands on).
static func site_context(sequence_manager: Node3D) -> Dictionary:
	var boxes: Dictionary = {}
	for part in sequence_manager.collect_part_nodes():
		if part is Node3D:
			var b := rest_box(part)
			if b.size != Vector3.ZERO:
				boxes[String(part.name)] = b
	var actions := actions_of(sequence_manager.sequence_data, boxes.keys())
	var building: Array = []
	var dig: Array = []
	for a in actions:
		if a.category in STRUCTURE or a.category in ROOF:
			for p in a.parts:
				building.append(boxes[p])
		if a.category in DIG or a.category in FILL:
			for p in a.parts:
				dig.append(boxes[p])
	if building.is_empty():
		building = boxes.values()
	var ground := 0.0
	var container = sequence_manager._parts_container()
	if container is Node3D:
		var acts: Array = actions.map(func(a): return {"id": a.id, "prefix": a.prefix, "text": a.text})
		var platforms := TerrainGrading.platforms_from_model(container, acts)
		if not platforms.is_empty():
			ground = ((container as Node3D).global_transform * Vector3(0, platforms[0].level, 0)).y
	# The pit: dig parts that go down more than half a metre. Stripping the
	# topsoil off the whole plot is excavator work too, but the machine belongs
	# at the hole.
	var deep := dig.filter(func(b): return b.position.y < ground - 0.5)
	var dig_box := AABB()
	for b in deep if not deep.is_empty() else dig:
		dig_box = b if dig_box.size == Vector3.ZERO else dig_box.merge(b)
	return {
		"boxes": boxes,
		"actions": actions,
		"work_box": robust_box(building),
		"dig_box": dig_box,
		"ground": ground,
	}


## [{id, prefix, type, category, text, parts}] for every action, `parts` being
## the names in `part_names` its prefix matches.
static func actions_of(sequence_data: Dictionary, part_names: Array) -> Array:
	var out: Array = []
	for step in sequence_data.get("steps", []):
		for action in step.get("actions", []):
			var prefix := str(action.get("target_prefix", action.get("commander_prefix", "")))
			var text := TaskClassifier.action_text(action)
			var parts: Array = []
			if prefix != "":
				for n in part_names:
					if String(n).begins_with(prefix):
						parts.append(n)
			out.append({
				"id": ConstructionSchedule._action_id(action),
				"prefix": prefix,
				"type": str(action.get("type", "")),
				"category": str(TaskClassifier.classify(text).get("category", "")),
				"text": text,
				"parts": parts,
			})
	return out


## A part's world box where it rests in the finished building -- while a
## timeline runs, parts sit wherever their animation has them (hidden, scaled
## to nothing, metres up), and SequenceManager keeps the rest placement in
## metas.
static func rest_box(part: Node3D) -> AABB:
	var own := TerrainBuilder._local_aabb(part, part)
	if own.size == Vector3.ZERO:
		return AABB()
	var tf := part.transform
	if part.has_meta("original_transform"):
		tf = part.get_meta("original_transform")
	elif part.is_inside_tree():
		tf = part.global_transform
	return tf * own


## Where the building is, without its outliers: per axis, the span of the
## middle 80 % of box centres, grown by half the median box size (the same
## measure SequenceManager frames its default camera on). A boundary wall, a
## granary or a cross at the far end of the plot shouldn't decide where the
## crane stands or how long its jib is.
static func robust_box(boxes: Array) -> AABB:
	if boxes.is_empty():
		return AABB()
	var c := [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var sizes := PackedFloat32Array()
	for b in boxes:
		var m: Vector3 = b.get_center()
		for k in 3:
			c[k].append(m[k])
		sizes.append(b.size.length())
	sizes.sort()
	var n := sizes.size()
	var lo_i := int(n * 0.1)
	var hi_i := maxi(int(ceil(n * 0.9)) - 1, lo_i)
	var lo := Vector3()
	var hi := Vector3()
	for k in 3:
		c[k].sort()
		lo[k] = c[k][lo_i]
		hi[k] = c[k][hi_i]
	var pad := Vector3.ONE * sizes[n >> 1] * 0.5
	return AABB(lo - pad, hi - lo + pad * 2.0)


## Ground under a world point: the terrain if there is one, else `fallback`.
static func ground_at(tree: SceneTree, p: Vector3, fallback: float) -> float:
	var h := ConstructionTerrain.ground_y(tree, p)
	return fallback if is_nan(h) else h


## The tower crane's place: just off a corner of the building, the back-right
## one first (+X, -Z: behind and to the side of the default camera), moved out
## in 2 m steps until it is clear of every part. Its jib (+X) faces the
## building's centre.
static func _propose_tower_site(ctx: Dictionary, tree: SceneTree) -> Transform3D:
	var box: AABB = ctx.work_box
	var c := Vector2(box.get_center().x, box.get_center().z)
	var corners := [Vector2(box.end.x, box.position.z), Vector2(box.position.x, box.position.z),
		Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)]
	var best := Vector2.ZERO
	var best_steps := 1 << 30
	for corner in corners:
		var dir: Vector2 = (corner - c).normalized() if corner != c else Vector2(1, 0)
		var steps := 0
		var p: Vector2 = corner + dir * 4.0
		while steps < 15 and _blocked(ctx.boxes.values(), p, 2.5, ctx.ground):
			p += dir * 2.0
			steps += 1
		if steps < best_steps:
			best_steps = steps
			best = p
	var y := ground_at(tree, Vector3(best.x, 0, best.y), ctx.ground)
	var to_c := c - best
	return Transform3D(Basis(Vector3.UP, atan2(-to_c.y, to_c.x)), Vector3(best.x, y, best.y))


## Mast height and jib for a crane standing at `at`; explicit values win.
static func tower_size(ctx: Dictionary, at: Vector3, height := 0.0, jib := 0.0) -> Dictionary:
	var box: AABB = ctx.work_box
	var reach := 0.0
	for corner in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z),
			Vector2(box.position.x, box.end.z), Vector2(box.end.x, box.end.z)]:
		reach = maxf(reach, corner.distance_to(Vector2(at.x, at.z)))
	var j := jib if jib > 0.0 else clampf(ceil((reach + 6.0) / 5.0) * 5.0, 30.0, 75.0)
	var top := box.end.y
	for b in ctx.boxes.values():
		if Vector2(b.get_center().x, b.get_center().z).distance_to(Vector2(at.x, at.z)) <= j:
			top = maxf(top, b.end.y)
	var h := height if height > 0.0 else maxf(snappedf(top - at.y + 10.0, 0.5), 18.0)
	return {"height": h, "jib": j, "counter_jib": clampf(j * 0.3, 10.0, 22.0)}


## Laydown area beside the mast, the first free spot of a few, in the crane's
## own space and at the ground's height there.
static func _propose_laydown(marker: Node3D, ctx: Dictionary, tree: SceneTree) -> Vector3:
	for local in [Vector3(0, 0, 10), Vector3(0, 0, -10), Vector3(-9, 0, 7), Vector3(-9, 0, -7)]:
		var w: Vector3 = marker.global_transform * local
		if not _blocked(ctx.boxes.values(), Vector2(w.x, w.z), 3.0, ctx.ground):
			w.y = ground_at(tree, w, marker.global_position.y)
			return marker.global_transform.affine_inverse() * w
	return Vector3(0, 0, 10)


## The excavator stands off the dig's front (+Z) edge, mid-way along it, facing
## in; its truck loads on its right and drives off behind it. At least 4 m off,
## and further, a metre at a time, until the whole length of its tracks is on
## the pad rather than down the pit's bank: graded terrain follows a 5 m grid,
## so the pit comes out several metres wider than the parts that draw it (on
## the test project the excavator stood 1.6 m down the bank at 4 m).
static func _propose_excavator_site(ctx: Dictionary, tree: SceneTree) -> Transform3D:
	var dig: AABB = ctx.dig_box
	var p := Vector3(dig.get_center().x, 0, dig.end.z + 4.0)
	var half_track := EquipmentModels.EXC_TRACK_CENTRES / 2.0 + EquipmentModels.EXC_TRACK_WHEEL_R
	for i in 13:
		var low := INF
		for dz in [-half_track, 0.0, half_track]:
			low = minf(low, ground_at(tree, p + Vector3(0, 0, dz), ctx.ground))
		if low > ctx.ground - 0.3:
			break
		p.z += 1.0
	p.y = ground_at(tree, p, ctx.ground)
	return Transform3D(Basis(), p)


## Whether anything standing on the ground is within `clearance` of `p`.
## Ground-level layers (topsoil, a terrain slab, the dig itself) don't count.
static func _blocked(boxes: Array, p: Vector2, clearance: float, ground: float) -> bool:
	for b in boxes:
		if b.end.y < ground + 0.5:
			continue
		if p.x > b.position.x - clearance and p.x < b.end.x + clearance \
				and p.y > b.position.z - clearance and p.y < b.end.z + clearance:
			return true
	return false


# --- Following the schedule ---------------------------------------------------

## Called by TimelineController.scrub_to() for every SiteEquipment in the tree.
static func update_all(tree: SceneTree, schedule: ConstructionSchedule, day: float, building_parts: Dictionary) -> void:
	for n in tree.get_nodes_in_group(GROUP):
		(n as SiteEquipment).follow_schedule(schedule, day, building_parts)


## Back to the finished site (the dock's Stop Preview).
static func reset_all(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group(GROUP):
		(n as SiteEquipment).stop_following()


func stop_following() -> void:
	_following = false
	_plan_schedule = null
	_tower_part = null
	_show_rest()


## Shows the site as it is on `day`.
func follow_schedule(schedule: ConstructionSchedule, day: float, building_parts: Dictionary) -> void:
	if not schedule:
		return
	if schedule != _plan_schedule:
		_parts = building_parts
		_plan = make_plan(schedule, building_parts)
		_plan_schedule = schedule
	_following = true
	_day = day
	_apply_tower(day)
	_apply_mobile(day)
	_apply_dig(day)


## When and where each machine works, from the schedule:
## {tower: {on, off, parts: [{name, start, end, kind}]},
##  mobile: [{start, finish, pos, yaw, parts}], digs: [{start, finish, fill}]}.
func make_plan(schedule: ConstructionSchedule, building_parts: Dictionary) -> Dictionary:
	var actions := actions_of(schedule.source_data, building_parts.keys())
	var struct_on := INF
	var struct_off := -INF
	var roof_off := -INF
	var digs: Array = []
	var lift_actions: Array = []
	for a in actions:
		var span := schedule.get_action_day_range(a.id)
		if span.is_empty():
			continue
		if a.category in STRUCTURE:
			struct_on = minf(struct_on, span.start_day)
			struct_off = maxf(struct_off, span.finish_day)
		if a.category in ROOF:
			roof_off = maxf(roof_off, span.finish_day)
		if a.category in DIG or a.category in FILL:
			digs.append({"start": span.start_day, "finish": span.finish_day, "fill": a.category in FILL})
		if not (a.category in LIGHT_LIFTS):
			lift_actions.append(a)
	digs.sort_custom(func(x, y): return x.start < y.start)
	var tower_off := roof_off if roof_off > -INF else struct_off

	var mast := Vector2.ZERO
	var has_tower := _tower != null
	if has_tower:
		mast = Vector2(_tower.global_position.x, _tower.global_position.z)
	var all_boxes: Array = []
	# What stands on site from which day: a part from the end of its window, an
	# unscheduled (static) one from the start. The mobile crane must set up clear
	# of whatever is there on the day of its lift.
	var standing: Array = []
	for n in building_parts:
		var b := rest_box(building_parts[n])
		if b.size != Vector3.ZERO:
			all_boxes.append(b)
			var w := schedule.get_part_window(n)
			standing.append({"box": b, "from": w.end_day if not w.is_empty() else -INF})
	var wb := robust_box(all_boxes)
	var work := Vector2(wb.get_center().x, wb.get_center().z)

	var tower_parts: Array = []
	var mobile_jobs: Array = []
	for a in lift_actions:
		var off_reach: Array = []
		for p in a.parts:
			var w := schedule.get_part_window(p)
			if w.is_empty() or not (w.anim_type in ["drop_in", "install"]):
				continue
			var entry := {"name": p, "start": w.start_day, "end": w.end_day, "kind": w.anim_type}
			var b := rest_box(building_parts[p])
			var c := Vector2(b.get_center().x, b.get_center().z)
			var in_time: bool = w.start_day <= tower_off + TOWER_GRACE_DAYS
			if has_tower and in_time and c.distance_to(mast) <= _tower_jib - 1.0:
				tower_parts.append(entry)
			elif w.anim_type == "drop_in":
				entry["box"] = b
				off_reach.append(entry)
		if not off_reach.is_empty():
			mobile_jobs.append(_mobile_job_for(off_reach, work, standing))
	tower_parts.sort_custom(func(x, y): return x.start < y.start)
	mobile_jobs.sort_custom(func(x, y): return x.start < y.start)

	var tower := {}
	if has_tower:
		var on := struct_on
		var off := tower_off
		for t in tower_parts:
			on = minf(on, t.start)
			off = maxf(off, t.end)
		if on < INF:
			tower = {"on": on - erect_days, "off": off + erect_days, "parts": tower_parts}
	return {"tower": tower, "mobile": mobile_jobs, "digs": digs}


## Where the mobile crane sets up for a lift: outside the pieces, on the side
## away from the building, its carrier side-on to them.
func _mobile_job_for(entries: Array, work: Vector2, standing: Array = []) -> Dictionary:
	var box: AABB = entries[0].box
	var start := INF
	var finish := -INF
	for e in entries:
		box = box.merge(e.box)
		start = minf(start, e.start)
		finish = maxf(finish, e.end)
	var c := Vector2(box.get_center().x, box.get_center().z)
	var away := c - work
	away = away.normalized() if away.length() > 0.5 else Vector2(0, 1)
	var radius := Vector2(box.size.x, box.size.z).length() * 0.5
	# Clear of everything standing by the day of the lift -- the crane with its
	# outriggers out needs about 5 m all round. Away from the building first,
	# then turning round the pieces and stepping out until a spot is free (on
	# the test project the first guess for the granary was on the boundary wall).
	var present: Array = []
	for s in standing:
		if s.from <= start:
			present.append(s.box)
	var dir := away
	var p2 := c + away * (radius + 7.5)
	var found := false
	for dist in [radius + 7.5, radius + 10.0, radius + 13.0, radius + 17.0]:
		for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.2, -2.2, PI]:
			var d: Vector2 = away.rotated(turn)
			if not _blocked(present, c + d * dist, 5.0, _ground_level):
				dir = d
				p2 = c + d * dist
				found = true
				break
		if found:
			break
	var pos := Vector3(p2.x, 0, p2.y)
	pos.y = ground_at(get_tree(), pos, _ground_level)
	var tangent := Vector2(dir.y, -dir.x)
	return {"start": start, "finish": finish, "pos": pos,
		"yaw": atan2(-tangent.x, -tangent.y), "parts": entries,
		"aim": Vector3(c.x, box.end.y, c.y)}


func _apply_tower(day: float) -> void:
	if not _tower:
		return
	var plan: Dictionary = _plan.get("tower", {})
	if plan.is_empty():
		_tower.visible = false
		return
	var on: float = plan.on
	var off: float = plan.off
	_tower.visible = day >= on and day <= off
	if not _tower.visible:
		_tower_part = null
		return
	var e := 1.0 if erect_days <= 0.0 else clampf(minf(day - on, off - day) / erect_days, 0.0, 1.0)
	_set_erected(e)
	if not (_tower is Crane) or Engine.is_editor_hint():
		return
	# Follow the drop_in piece most recently started; lifts of `install` parts
	# are TimelineController's (Crane.swing() per install unit), left alone.
	var active: Node3D = null
	var best := -INF
	for t in plan.parts:
		if t.start > day:
			break
		if day < t.end and t.start >= best:
			best = t.start
			active = _parts.get(t.name)
	var crane := _tower as Crane
	var current = crane.get("_tracked_part")
	if current and current != active and _is_installing(current, day):
		return
	var tracked: bool = current == active
	if active and (active != _tower_part or not tracked):
		crane.swing(_part_top(active), _part_top(active), 1.2, 0.0, active)
	elif not active and _tower_part:
		crane.retract(2.0)
	_tower_part = active


func _is_installing(part: Node3D, day: float) -> bool:
	if not _plan_schedule:
		return false
	var w := _plan_schedule.get_part_window(String(part.name))
	return not w.is_empty() and w.anim_type == "install" and day >= w.start_day and day < w.end_day


## Mast sections appear bottom-up over the first 75 % of the erection, the
## jib, counter-jib and cab over the rest -- and the reverse to dismantle.
func _set_erected(level: float) -> void:
	var mast: Node3D = _tower.get_node("Mast")
	var n: int = mast.get_meta("sections")
	var shown := int(ceil(clampf(level / 0.75, 0.0, 1.0) * n))
	for i in n:
		(mast.get_child(i) as Node3D).visible = i < shown
	(_tower.get_node("Arm") as Node3D).visible = level >= 0.8
	(_tower.get_node("PickupZone") as Node3D).visible = level > 0.0


func _apply_mobile(day: float) -> void:
	if not _mobile:
		return
	var job: Dictionary = {}
	for j in _plan.get("mobile", []):
		if day >= j.start - 0.75 and day <= j.finish + 0.75:
			job = j
			break
	if job.is_empty():
		_mobile.visible = false
		_mobile_job = {}
		return
	if job != _mobile_job:
		_mobile_job = job
		_mobile.global_transform = Transform3D(Basis(Vector3.UP, job.yaw), job.pos)
		_mobile_pose = {"slew": 0.0, "luff": 0.0, "extend": 0.0, "out": 0.0, "drop": 2.0}
	_mobile.visible = true
	var out := clampf(minf(day - (job.start - 0.75), (job.finish + 0.75) - day) / 0.5, 0.0, 1.0)
	_mobile_target.out = out
	var target: Vector3 = job.aim + Vector3(0, 6.0, 0)
	var top := NAN
	for e in job.parts:
		if day >= e.start and day < e.end and _parts.has(e.name):
			target = _part_top(_parts[e.name])
			top = target.y
			break
	if out < 1.0:
		_mobile_target.merge({"slew": 0.0, "luff": 0.0, "extend": 0.0, "top": NAN}, true)
	else:
		_mobile_target.merge(aim_mobile(_mobile.global_transform, target), true)
		_mobile_target.top = top


## Slew, luff and telescope that put the mobile crane's boom tip 6 m above
## `target` (world), as far as its 13--42 m boom allows.
static func aim_mobile(crane_tf: Transform3D, target: Vector3) -> Dictionary:
	var p := crane_tf.affine_inverse() * target
	var s := EquipmentModels.MOBILE_SLEW
	var dx := p.x - s.x
	var dz := p.z - s.z
	var slew := atan2(-dx, -dz)
	var r := sqrt(dx * dx + dz * dz) + EquipmentModels.MOBILE_FOOT.z
	var h := p.y + 6.0 - (s.y + EquipmentModels.MOBILE_FOOT.y)
	var need := sqrt(r * r + h * h)
	var length := clampf(need, EquipmentModels.BOOM_MIN, EquipmentModels.BOOM_MAX)
	var luff := atan2(h, r) if length == need else acos(clampf(r / length, 0.0, 1.0))
	luff = clampf(luff, deg_to_rad(10.0), deg_to_rad(80.0))
	var extend := (length - EquipmentModels.BOOM_MIN) / (EquipmentModels.BOOM_MAX - EquipmentModels.BOOM_MIN)
	return {"slew": slew, "luff": luff, "extend": extend}


func _step_mobile(k: float) -> void:
	var t := _mobile_target
	var p := _mobile_pose
	p.out = lerpf(p.out, t.out, k)
	p.slew = lerp_angle(p.slew, t.slew, k)
	p.luff = lerpf(p.luff, t.luff, k)
	p.extend = lerpf(p.extend, t.extend, k)
	EquipmentModels.pose_mobile_crane(_mobile, p.slew, p.luff, p.extend, p.out, p.drop)
	var tip := EquipmentModels.boom_tip(_mobile)
	var want: float = 3.0 if is_nan(t.top) else tip.y - t.top - 1.2
	p.drop = lerpf(p.drop, clampf(want, 0.5, 60.0), k)
	EquipmentModels.pose_mobile_crane(_mobile, p.slew, p.luff, p.extend, p.out, p.drop)


func _apply_dig(day: float) -> void:
	if not _excavator:
		return
	_dig = {}
	for d in _plan.get("digs", []):
		if day >= d.start and day <= d.finish:
			_dig = d
			break
	_excavator.visible = not _dig.is_empty()
	_truck.visible = _excavator.visible
	_animate_dig()


func _process(delta: float) -> void:
	if not _following:
		return
	# Machines move while the timeline plays, and hold still while it is
	# paused or scrubbed -- a recording stays steady, a paused one stays put.
	var playing := not is_nan(_day) and _day != _last_day
	_last_day = _day
	if playing:
		_anim_time += delta
		_animate_dig()
	if _mobile and _mobile.visible:
		_step_mobile(1.0 - exp(-3.0 * delta))


## Excavator: dig -> lift -> slew -> dump, DIG_CYCLE seconds. Truck: a round of
## TRUCK_ROUND cycles -- reverse in, four loads, drive off, out of sight.
## For a fill, the truck arrives loaded and tips at the spot instead.
func _animate_dig() -> void:
	if _dig.is_empty() or not _excavator:
		return
	var fill: bool = _dig.fill
	var round_t := fmod(_anim_time, DIG_CYCLE * TRUCK_ROUND)
	var cycle := int(round_t / DIG_CYCLE)
	var u := fmod(round_t, DIG_CYCLE) / DIG_CYCLE
	var truck_here := cycle >= 1 and cycle <= 4
	var pose := dig_pose(u)
	var dump_slew := -PI / 2.0 if truck_here and not fill else PI / 3.0
	EquipmentModels.pose_excavator(_excavator, pose.slew * dump_slew, pose.boom, pose.stick, pose.bucket, pose.loaded)

	var spot := TRUCK_SPOT
	var far := TRUCK_SPOT + Vector3(0, 0, TRUCK_RUN)
	var load_level := 0.0
	var tip := 0.0
	var pos := spot
	_truck.visible = true
	if cycle == 0:
		var k := smoothstep(0.0, 0.8, u)
		pos = far.lerp(spot, k)
		load_level = 1.0 if fill else 0.0
	elif truck_here:
		var dumps := cycle - 1 + (1 if u >= 0.72 else 0)
		if fill:
			var f := clampf(((cycle - 1) + u) / 2.0, 0.0, 1.0)
			tip = sin(f * PI)
			load_level = 1.0 - clampf(f * 1.6, 0.0, 1.0)
		else:
			load_level = dumps / 4.0
	else:
		var k := smoothstep(0.0, 0.75, u)
		pos = spot.lerp(far, k)
		load_level = 0.0 if fill else 1.0
		_truck.visible = u < 0.75
	_truck.position = pos
	var ground := ground_at(get_tree(), _truck.global_position, _truck.get_parent().global_position.y)
	_truck.global_position.y = ground
	EquipmentModels.pose_truck(_truck, tip, load_level)


## Excavator pose at phase `u` (0..1) of a dig cycle: {slew (fraction of the
## dump slew), boom, stick, bucket, loaded}. Keyframes eased with smoothstep.
static func dig_pose(u: float) -> Dictionary:
	# Solved against the model's own kinematics (EquipmentModels.excavator_teeth())
	# so the teeth really go 1 m into the ground and the bucket pin passes 4.9 m
	# up over the truck body, 7.4 m out.
	const KEYS := [
		[0.00, 0.0, 0.06, 0.455, -0.8, false], # reach out, bucket open
		[0.14, 0.0, -0.105, 0.475, -0.5, false], # teeth into the ground
		[0.30, 0.0, -0.025, 0.265, 0.4, true], # drag in
		[0.42, 0.0, -0.035, -0.03, 1.6, true], # curl full
		[0.54, 0.0, 0.6, 0.265, 1.6, true], # lift clear
		[0.66, 1.0, 0.45, 0.85, 1.6, true], # slew over the truck
		[0.74, 1.0, 0.45, 0.85, -0.9, false], # dump
		[0.84, 1.0, 0.45, 0.85, -0.8, false], # shake out
		[1.00, 0.0, 0.06, 0.455, -0.8, false], # back
	]
	var i := 0
	while i < KEYS.size() - 2 and u >= KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var t := smoothstep(0.0, 1.0, clampf((u - a[0]) / (b[0] - a[0]), 0.0, 1.0))
	return {
		"slew": lerpf(a[1], b[1], t), "boom": lerpf(a[2], b[2], t),
		"stick": lerpf(a[3], b[3], t), "bucket": lerpf(a[4], b[4], t),
		"loaded": a[5] if t < 0.5 else b[5],
	}


## Everything visible in its resting pose: the editor's view of the site.
func _show_rest() -> void:
	if _tower:
		_tower.visible = tower_crane
		_set_erected(1.0)
	if _mobile:
		_mobile.visible = false
	if _excavator:
		_excavator.visible = true
		_truck.visible = true
		var rest := dig_pose(0.0)
		EquipmentModels.pose_excavator(_excavator, 0.0, rest.boom, rest.stick, rest.bucket, false)
		_truck.position = TRUCK_SPOT
		EquipmentModels.pose_truck(_truck, 0.0, 0.0)


static func _part_top(part: Node3D) -> Vector3:
	if part is MeshInstance3D and (part as MeshInstance3D).mesh:
		var aabb := (part as MeshInstance3D).mesh.get_aabb()
		var c := aabb.get_center()
		return part.global_transform * Vector3(c.x, aabb.end.y, c.z)
	return part.global_position
