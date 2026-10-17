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
##   Between two jobs close in time it stays where it is when it can still
##   reach the next piece, and otherwise drives there by the shortest route
##   round what is built (RoutePlanner).
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
const ACCESS_RUN := 40.0 # metres out from a mobile crane's spot to where it leaves the site
const DRIVE_MPD := 150.0 # metres a mobile crane drives per day of schedule
const DRIVE_DAYS := Vector2(0.15, 0.6) # shortest and longest drive, in days
const REMOVES := ["fade_out", "sink_down"] # animations after which a part is gone
const MAST_CLEAR := 3.0 # metres round the tower crane's mast a vehicle keeps clear
const BOOM_CLEAR := 0.8 # metres either side of the boom's axis kept clear (half its width + room)
const BOOM_RAISE := [0.0, 3.0, 6.0, 10.0, 15.0, 22.0] # metres higher than usual the boom tip may go to clear something

@export var tower_crane: bool = true:
	set(v):
		tower_crane = v
		_rebuild_preview()
@export var mobile_crane: bool = true
## The mobile crane stays on site, parked, between two jobs this many days
## apart or fewer (and drives from one to the next); further apart, it leaves
## by the road it came and comes back for the next.
@export_range(0.0, 365.0, 1.0, "or_greater") var hold_days: float = 30.0
## Draw the mobile crane's drives on the ground (orange lines).
@export var show_routes: bool = false:
	set(v):
		show_routes = v
		_draw_routes()
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
# The excavator and its truck together, moved as one to each dig: under the
# ExcavatorSite marker for the model's own pit, under this node for the
# terrain's pits (placed per job, see _pit_jobs()).
var _rig: Node3D = null
var _pit_sites: Dictionary = {} # TerrainPlatform -> Transform3D
# More crews for digs at the terrain's pits that overlap the first one's:
# [{rig, excavator, truck, dig}], made as needed, under this node.
var _crews: Array = []

var _plan: Dictionary = {}
var _plan_schedule: ConstructionSchedule = null
var _following := false
var _day := NAN
var _last_day := NAN
var _anim_time := 0.0
var _dig: Dictionary = {} # the active dig/fill window, or {}
var _tower_part: Node3D = null
var _mobile_job: Dictionary = {}
var _mobile_seg := -1
var _routes: MeshInstance3D = null
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
	var model_pit: bool = not ctx.dig_box.size.is_zero_approx()
	if excavator_and_truck and (model_pit or not _terrain_pits(tree).is_empty()):
		var holder: Node3D = self
		if model_pit:
			holder = get_node_or_null(EXCAVATOR_SITE) as Node3D
			if not holder:
				holder = _add_marker(EXCAVATOR_SITE, _propose_excavator_site(ctx, tree))
		_make_rig(holder)
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
	if excavator_and_truck and (exc_marker or not _terrain_pits(get_tree()).is_empty()):
		_make_rig(exc_marker if exc_marker else self)
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
	_rig = null
	_pit_sites.clear()
	_crews.clear()
	_tower_part = null


## The excavator with its truck parked on its right, under `holder`.
func _make_rig(holder: Node3D) -> void:
	_rig = _generated(Node3D.new(), holder)
	_rig.name = "DigRig"
	_excavator = EquipmentModels.excavator()
	_rig.add_child(_excavator)
	_truck = EquipmentModels.truck()
	_rig.add_child(_truck)
	_truck.position = TRUCK_SPOT
	_truck.rotation.y = PI

## The terrains' platforms that are dug or filled by an activity -- a
## footing's pit: [{terrain, platform}].
static func _terrain_pits(tree: SceneTree) -> Array:
	var out: Array = []
	if not tree:
		return out
	for t in tree.get_nodes_in_group(ConstructionTerrain.GROUP):
		for p in (t as ConstructionTerrain).platforms:
			if p and p.enabled and (not p.activities.is_empty() or not p.backfill_activities.is_empty()):
				out.append({"terrain": t, "platform": p})
	return out

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
		_draw_routes()
	_following = true
	_day = day
	_apply_tower(day)
	_apply_mobile(day)
	_apply_dig(day)


## When and where each machine works, from the schedule:
## {tower: {on, off, parts: [{name, start, end, kind}]},
##  mobile: [{start, finish, pos, yaw, parts}] (the spots it sets up at),
##  mobile_segments: [{kind: stand|park|drive, t0, t1, ...}] (where it is, when),
##  drives: [{t0, t1, points, length, ok, direct, ...}],
##  digs: [{start, finish, fill}]}.
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
			digs.append({"id": a.id, "start": span.start_day, "finish": span.finish_day, "fill": a.category in FILL})
		if not (a.category in LIGHT_LIFTS):
			lift_actions.append(a)
	# The terrain's pits: each activity that digs one (its `activities`) or
	# fills it back (`backfill_activities`) is a job at that pit, whatever its
	# name says. An action already listed above by its category is replaced.
	var pit_jobs := _pit_jobs(schedule, building_parts)
	if not pit_jobs.is_empty():
		var covered := {}
		for j in pit_jobs:
			covered[j.id] = true
		digs = digs.filter(func(d): return not covered.has(d.get("id", "")))
		digs.append_array(pit_jobs)
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
			# A part is there from the end of its window -- or, for one the schedule
			# removes (cleared trees, a stripped scaffold), until it.
			var removes: bool = not w.is_empty() and w.anim_type in REMOVES
			standing.append({"box": b,
				"from": -INF if removes else (w.end_day if not w.is_empty() else -INF),
				"begin": w.start_day if not w.is_empty() else -INF,
				"gone": w.end_day if removes else INF})
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
	var mobile := _plan_mobile(mobile_jobs, standing, work, tower, mast)
	return {"tower": tower, "mobile": mobile.stands, "mobile_segments": mobile.segments,
		"drives": mobile.drives, "digs": digs}


## Dig and fill jobs at the terrain's pits: {id, start, finish, fill, site}.
func _pit_jobs(schedule: ConstructionSchedule, building_parts: Dictionary) -> Array:
	var jobs: Array = []
	for pit in _terrain_pits(get_tree()):
		var p: TerrainPlatform = pit.platform
		for pair in [[p.activities, false], [p.backfill_activities, true]]:
			for id in pair[0]:
				var span := schedule.get_action_day_range(id)
				if span.is_empty():
					continue
				if not _pit_sites.has(p):
					_pit_sites[p] = _pit_site(pit.terrain, p, building_parts, schedule, span.start_day)
				jobs.append({"id": id, "start": span.start_day, "finish": span.finish_day,
					"fill": pair[1], "site": _pit_sites[p]})
	return jobs

## Where the excavator stands to dig (or fill) a pit: on natural ground just
## past the top of its banks -- walking out from the middle of the pit until
## the ground under its tracks is no longer cut or filled -- facing the pit.
## Of eight ways out, the nearest that isn't against anything of the model
## already built on `day` (the first dig); the excavator's own reach is not
## modelled, so a deep pit's machine stands well back from the bottom, as it
## would on a ramp's head.
func _pit_site(terrain: ConstructionTerrain, p: TerrainPlatform, building_parts: Dictionary, schedule: ConstructionSchedule, day: float) -> Transform3D:
	var anchor := terrain.get_node_or_null(terrain.anchor_path) as Node3D
	var to_world := anchor.global_transform if anchor else Transform3D()
	var c2 := Vector2.ZERO
	for q in p.footprint:
		c2 += q
	c2 /= maxf(p.footprint.size(), 1)
	var centre := to_world * Vector3(c2.x, p.level, c2.y)
	var boxes: Array = []
	for n in building_parts:
		var w := schedule.get_part_window(n)
		if not w.is_empty() and w.end_day > day:
			continue
		var b := rest_box(building_parts[n])
		if b.size != Vector3.ZERO:
			boxes.append(b)
	var half_track := EquipmentModels.EXC_TRACK_CENTRES / 2.0 + EquipmentModels.EXC_TRACK_WHEEL_R
	var best := Transform3D()
	var best_d := INF
	for k in 8:
		var dir := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0))
		for step in range(1, 120):
			var at := centre + dir * float(step)
			var clear := true
			for off in [-half_track, 0.0, half_track]:
				var q: Vector3 = at + Vector3(-dir.z, 0, dir.x) * off
				var graded := terrain.world_height_at(q)
				var natural := terrain.natural_world_height_at(q)
				if is_nan(graded) or is_nan(natural) or absf(graded - natural) > 0.2:
					clear = false
					break
			if not clear:
				continue
			at += dir * 2.0
			if _blocked(boxes, Vector2(at.x, at.z), 3.0, terrain.natural_world_height_at(at)):
				break
			var d := float(step)
			if d < best_d:
				best_d = d
				at.y = terrain.natural_world_height_at(at)
				# The excavator digs along its -Z: turned to face the pit's middle.
				var to_pit := centre - at
				best = Transform3D(Basis(Vector3.UP, atan2(to_pit.x, to_pit.z) + PI), at)
			break
	if best_d == INF:
		best = Transform3D(Basis(), centre + Vector3(0, 0, 10))
	return best

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
	# outriggers out needs about 5 m all round -- and with its boom clear of
	# everything standing too. Away from the building first, then turning round
	# the pieces and stepping out until a spot is free (on the test project the
	# first guess for the granary was on the boundary wall). A spot where the
	# boom clears at its usual height wins; failing that, the one where it needs
	# to go least higher; failing that the first free one (it will clash).
	var present: Array = []
	for s in standing:
		if s.from <= start and start < s.get("gone", INF):
			present.append(s.box)
	var obstacles := _boom_obstacles(standing, box, finish)
	var nears := _boom_nears(entries, obstacles)
	var roads := _road_map(c, away, radius, work, start - 0.75, standing)
	# ...and one the crane can get to by road from outside the site.
	var dir := away
	var p2 := c + away * (radius + 7.5)
	var up := INF
	var found := false
	var good := false # the best so far has a road in
	for dist in [radius + 7.5, radius + 10.0, radius + 13.0, radius + 17.0, radius + 22.0, radius + 30.0]:
		for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.2, -2.2, PI]:
			var d: Vector2 = away.rotated(turn)
			var spot: Vector2 = c + d * dist
			if _blocked(present, spot, 5.0, _ground_level):
				continue
			var lift := _boom_lift(_mobile_transform(spot, d), entries, obstacles, nears)
			if not found:
				found = true
				dir = d
				p2 = spot
				up = lift
			# A spot the boom does not clear from is no better for having a road.
			if is_inf(lift) or (good and lift >= up):
				continue
			var road: bool = RoutePlanner.reached(roads, spot)
			if (road and not good) or (road == good and lift < up):
				good = road
				dir = d
				p2 = spot
				up = lift
			if good and up == 0.0:
				break
		if good and up == 0.0:
			break
	var pos := Vector3(p2.x, 0, p2.y)
	pos.y = ground_at(get_tree(), pos, _ground_level)
	var tangent := Vector2(dir.y, -dir.x)
	return {"start": start, "finish": finish, "pos": pos,
		"yaw": atan2(-tangent.x, -tangent.y), "parts": entries,
		"aim": Vector3(c.x, box.end.y, c.y),
		"tip_up": 0.0 if is_inf(up) else up, "boom_ok": not is_inf(up)}


## Where a mobile crane can drive on `day`, round the job at `c`: the ground
## reachable from outside the site (60 m out the way away from the work),
## round what stands then.
func _road_map(c: Vector2, away: Vector2, radius: float, work: Vector2, day: float, standing: Array) -> Dictionary:
	var half := radius + 70.0
	var area := Rect2(c - Vector2.ONE * half, Vector2.ONE * half * 2.0)
	var rects: Array = []
	for s in standing:
		var b: AABB = s.box
		if s.begin <= day and day < s.get("gone", INF) and b.end.y >= _ground_level + 0.5:
			rects.append(Rect2(b.position.x, b.position.z, b.size.x, b.size.z))
	return RoutePlanner.flood(c + away * (half - 3.0), rects, area)


## The crane's transform at a spot (plan position) with its carrier along the
## tangent of `dir` -- the way _mobile_job_for() turns it.
func _mobile_transform(spot: Vector2, dir: Vector2) -> Transform3D:
	var tangent := Vector2(dir.y, -dir.x)
	var p := Vector3(spot.x, 0, spot.y)
	p.y = ground_at(get_tree(), p, _ground_level)
	return Transform3D(Basis(Vector3.UP, atan2(-tangent.x, -tangent.y)), p)


## What the boom of a crane working near `box` until `until` can hit: every
## part started by then and standing above the ground, within the boom's
## longest reach (plus a margin) of it -- {box, begin}.
func _boom_obstacles(standing: Array, box: AABB, until: float) -> Array:
	var c := Vector2(box.get_center().x, box.get_center().z)
	var reach: float = EquipmentModels.BOOM_MAX + 20.0
	var out: Array = []
	for s in standing:
		var b: AABB = s.box
		if s.begin > until or b.end.y < _ground_level + 0.5:
			continue
		if Vector2(b.get_center().x, b.get_center().z).distance_to(c) - Vector2(b.size.x, b.size.z).length() * 0.5 > reach:
			continue
		out.append({"box": b, "begin": s.begin, "gone": s.get("gone", INF)})
	return out


## How much higher than 6 m over each piece the boom tip has to be, from a
## crane standing at `tf`, for the boom and the hook line to clear what stands
## when the piece is placed -- the worst over the pieces. INF when it cannot
## from here (out of reach, or nothing high enough clears).
func _boom_lift(tf: Transform3D, entries: Array, obstacles: Array, nears: Array = []) -> float:
	if nears.is_empty():
		nears = _boom_nears(entries, obstacles)
	var worst := 0.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var c: Vector3 = e.box.get_center()
		var target := Vector3(c.x, e.box.end.y, c.z)
		var up := INF
		for k in BOOM_RAISE:
			if _boom_clear(tf, target, k, nears[i]):
				up = k
				break
		if is_inf(up):
			return INF
		worst = maxf(worst, up)
	return worst


## For each piece, the boxes its boom could hit: what has started by the time
## it is placed and is still there, except what touches the piece itself.
func _boom_nears(entries: Array, obstacles: Array) -> Array:
	var out: Array = []
	for e in entries:
		var seat: AABB = e.box.grow(0.3)
		var near: Array = []
		for o in obstacles:
			if o.begin <= e.start and e.start < o.gone and not (o.box as AABB).intersects(seat):
				near.append(o.box)
		out.append(near)
	return out


## Whether the boom, from its foot to a tip `up` m higher than usual over
## `target` (the top of the piece, world), and the hook line down from the tip,
## miss `near` (boxes) and the crane can make the lift at all.
func _boom_clear(tf: Transform3D, target: Vector3, up: float, near: Array) -> bool:
	var g := _boom_geometry(tf, target + Vector3(0, up, 0))
	if sqrt(g.y * g.y + g.z * g.z) > EquipmentModels.BOOM_MAX or atan2(g.z, g.y) > deg_to_rad(80.0):
		return false
	var pivot: Vector3 = tf * EquipmentModels.MOBILE_SLEW
	var dir := Vector2(target.x - pivot.x, target.z - pivot.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector2(0, -1)
	var foot := Vector3(pivot.x - dir.x * EquipmentModels.MOBILE_FOOT.z, pivot.y + EquipmentModels.MOBILE_FOOT.y,
		pivot.z - dir.y * EquipmentModels.MOBILE_FOOT.z)
	var tip := Vector3(target.x, target.y + 6.0 + up, target.z)
	var lo := foot.min(tip) - Vector3.ONE * (BOOM_CLEAR + 0.1)
	var hi := foot.max(tip) + Vector3.ONE * (BOOM_CLEAR + 0.1)
	for b in near:
		var box: AABB = b
		if box.end.x < lo.x or box.position.x > hi.x or box.end.z < lo.z or box.position.z > hi.z 				or box.end.y < lo.y or box.position.y > hi.y:
			continue
		if LiftPlanner.segment_hits(foot, tip, (b as AABB).grow(BOOM_CLEAR)) \
				or LiftPlanner.segment_hits(target, tip, (b as AABB).grow(0.4)):
			return false
	return true


# --- The mobile crane's life on site: where it stands, and how it gets there ---

## Turns the jobs (one per lift, in order) into where the crane stands and
## when it is on the move. Two jobs close in time share a spot when the crane
## can still reach the second one's pieces from the first (no need to drive at
## all); otherwise it drives there -- straight if the way is clear, round what
## is built if not. Jobs further apart than `hold_days` mean it leaves the
## site and comes back. Returns {stands, segments, drives}; `segments` tile the
## time the crane is on site (stand: working, park: waiting, drive: moving).
func _plan_mobile(jobs: Array, standing: Array, work: Vector2, tower: Dictionary, mast: Vector2) -> Dictionary:
	var stands: Array = []
	var stay: Array = [] # stay[i]: the crane waits on site from stand i to i + 1
	for j in jobs:
		if not stands.is_empty():
			var cur: Dictionary = stands[stands.size() - 1]
			var gap: float = (j.start - 0.75) - (cur.finish + 0.75)
			if gap <= hold_days and _can_serve(cur, j, standing):
				cur["parts"] = cur.parts + j.parts
				cur["finish"] = maxf(cur.finish, j.finish)
				cur["merged"] = int(cur.get("merged", 1)) + 1
				var box: AABB = cur.parts[0].box
				for e in cur.parts:
					box = box.merge(e.box)
				cur["aim"] = Vector3(box.get_center().x, box.end.y, box.get_center().z)
				continue
			stay.append(gap <= hold_days)
		stands.append(j.duplicate())
	var segments: Array = []
	var drives: Array = []
	for i in stands.size():
		var s: Dictionary = stands[i]
		var here := Vector2(s.pos.x, s.pos.z)
		var arrive: float = s.start - 0.75
		if i > 0 and stay[i - 1]:
			var q: Dictionary = stands[i - 1]
			var d := _drive(Vector2(q.pos.x, q.pos.z), here, arrive, standing, tower, mast, q.yaw, s.yaw)
			d["t1"] = arrive
			d["t0"] = maxf(q.finish + 0.75, arrive - d.days)
			if d.t0 > q.finish + 0.75:
				segments.append({"kind": "park", "t0": q.finish + 0.75, "t1": d.t0, "pos": q.pos, "yaw": q.yaw})
			segments.append(d)
			drives.append(d)
		else:
			var d := _drive(_gate(here, work), here, arrive, standing, tower, mast, NAN, s.yaw)
			d["t1"] = arrive
			d["t0"] = arrive - d.days
			segments.append(d)
			drives.append(d)
		segments.append({"kind": "stand", "t0": arrive, "t1": s.finish + 0.75, "job": s})
		if i + 1 >= stands.size() or not stay[i]:
			var d := _drive(here, _gate(here, work), s.finish + 0.75, standing, tower, mast, s.yaw, NAN)
			d["t0"] = s.finish + 0.75
			d["t1"] = d.t0 + d.days
			segments.append(d)
			drives.append(d)
	for k in segments.size():
		segments[k]["id"] = k
	for d in drives:
		if not d.ok:
			var last: int = d.points.size() - 1
			push_warning("SiteEquipment: no route for the mobile crane from (%.0f, %.0f) to (%.0f, %.0f) on day %.0f -- it drives straight through." % [d.points[0].x, d.points[0].y, d.points[last].x, d.points[last].y, d.t0])
	return {"stands": stands, "segments": segments, "drives": drives}


## Where the crane leaves the site from `spot`: out, away from the work.
func _gate(spot: Vector2, work: Vector2) -> Vector2:
	var away := spot - work
	away = away.normalized() if away.length() > 0.5 else Vector2(0, 1)
	return spot + away * ACCESS_RUN


## The mobile crane's drive from `a` to `b` (x, z) on `day`: the straight line
## if it is free, else the shortest route round what stands then. `yaw_a` and
## `yaw_b` are the crane's yaw at either end (NAN where it is just a point on
## the road): the road eases into the way the crane stands. Times are set by
## the caller; `days` is how long it takes.
func _drive(a: Vector2, b: Vector2, day: float, standing: Array, tower: Dictionary, mast: Vector2, yaw_a: float, yaw_b: float) -> Dictionary:
	var rects: Array = []
	for s in standing:
		var box: AABB = s.box
		if s.begin <= day and day < s.get("gone", INF) and box.end.y >= _ground_level + 0.5:
			rects.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	if not tower.is_empty() and day >= tower.on and day <= tower.off:
		rects.append(Rect2(mast - Vector2.ONE * MAST_CLEAR, Vector2.ONE * MAST_CLEAR * 2.0))
	var r := RoutePlanner.find(a, b, rects, EquipmentModels.MOBILE_LENGTH, EquipmentModels.MOBILE_WIDTH)
	r["kind"] = "drive"
	r["days"] = clampf(r.length / DRIVE_MPD, DRIVE_DAYS.x, DRIVE_DAYS.y)
	var pts: PackedVector2Array = r.points
	var first := (pts[1] - pts[0]).normalized()
	var last := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	r["start_heading"] = _stand_heading(yaw_a, first)
	r["end_heading"] = _stand_heading(yaw_b, last)
	return r


## The heading (radians) the crane has standing with `yaw`, facing whichever
## way along its length agrees with `travel` (it can back in as well as drive
## in); NAN for no yaw.
static func _stand_heading(yaw: float, travel: Vector2) -> float:
	if is_nan(yaw):
		return NAN
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	return fwd.angle() if fwd.dot(travel) >= 0.0 else (-fwd).angle()


## Whether the crane, standing at `cur`'s spot, can do `job`'s lifts too: the
## spot is still clear of what is built by then, and every piece is within the
## boom's reach. Then it need not move.
func _can_serve(cur: Dictionary, job: Dictionary, standing: Array) -> bool:
	var present: Array = []
	for s in standing:
		if s.from <= job.start and job.start < s.get("gone", INF):
			present.append(s.box)
	if _blocked(present, Vector2(cur.pos.x, cur.pos.z), 5.0, _ground_level):
		return false
	var tf := Transform3D(Basis(Vector3.UP, cur.yaw), cur.pos)
	for e in job.parts:
		var c: Vector3 = e.box.get_center()
		if boom_needed(tf, Vector3(c.x, e.box.end.y, c.z)) > EquipmentModels.BOOM_MAX:
			return false
	# ...and the boom must clear what stands by then, perhaps held higher.
	var box: AABB = job.parts[0].box
	for e in job.parts:
		box = box.merge(e.box)
	var up := _boom_lift(tf, job.parts, _boom_obstacles(standing, box, job.finish))
	if is_inf(up):
		return false
	cur["tip_up"] = maxf(cur.get("tip_up", 0.0), up)
	return true


## Orange lines on the ground along every drive of the mobile crane.
func _draw_routes() -> void:
	if is_instance_valid(_routes):
		_routes.get_parent().remove_child(_routes)
		_routes.free()
	_routes = null
	if not show_routes or not is_inside_tree():
		return
	var drives: Array = _plan.get("drives", [])
	if drives.is_empty():
		return
	var mesh := ImmediateMesh.new()
	for d in drives:
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in d.points:
			var at := Vector3(p.x, 0, p.y)
			at.y = ground_at(get_tree(), at, _ground_level) + 0.4
			mesh.surface_add_vertex(at)
		mesh.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.05)
	mat.no_depth_test = true
	_routes = MeshInstance3D.new()
	_routes.name = "MobileRoutes"
	_routes.mesh = mesh
	_routes.material_override = mat
	_routes.top_level = true
	_generated(_routes, self)


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
	var seg: Dictionary = {}
	for sg in _plan.get("mobile_segments", []):
		if day >= sg.t0 and day <= sg.t1:
			seg = sg
			break
	if seg.is_empty():
		_mobile.visible = false
		_mobile_job = {}
		_mobile_seg = -1
		return
	if seg.id != _mobile_seg:
		_mobile_seg = seg.id
		_mobile_pose = {"slew": 0.0, "luff": 0.0, "extend": 0.0, "out": 0.0, "drop": 2.0}
	_mobile.visible = true
	if seg.kind != "stand":
		_mobile_job = {}
		_mobile_target.merge({"out": 0.0, "slew": 0.0, "luff": 0.0, "extend": 0.0, "top": NAN}, true)
		if seg.kind == "park":
			_mobile.global_transform = Transform3D(Basis(Vector3.UP, seg.yaw), seg.pos)
		else:
			_place_on_drive(seg, day)
		return
	var job: Dictionary = seg.job
	if job != _mobile_job:
		_mobile_job = job
		_mobile.global_transform = Transform3D(Basis(Vector3.UP, job.yaw), job.pos)
	var out := clampf(minf(day - (job.start - 0.75), (job.finish + 0.75) - day) / 0.5, 0.0, 1.0)
	_mobile_target.out = out
	var target: Vector3 = job.aim + Vector3(0, 6.0 + job.get("tip_up", 0.0), 0)
	var top := NAN
	for e in job.parts:
		if day >= e.start and day < e.end and _parts.has(e.name):
			target = _part_top(_parts[e.name])
			top = target.y
			target.y += job.get("tip_up", 0.0)
			break
	if out < 1.0:
		_mobile_target.merge({"slew": 0.0, "luff": 0.0, "extend": 0.0, "top": NAN}, true)
	else:
		_mobile_target.merge(aim_mobile(_mobile.global_transform, target), true)
		_mobile_target.top = top


## The crane on the road: where it is `day` along its drive, facing the way
## it is going.
func _place_on_drive(drive: Dictionary, day: float) -> void:
	var u := clampf((day - drive.t0) / maxf(drive.t1 - drive.t0, 0.0001), 0.0, 1.0)
	var at := RoutePlanner.sample(drive.points, u * drive.length, drive.start_heading, drive.end_heading)
	var d := Vector2.from_angle(at.heading)
	var p := Vector3(at.pos.x, 0, at.pos.y)
	p.y = ground_at(get_tree(), p, _ground_level)
	_mobile.global_transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), p)


## Slew, luff and telescope that put the mobile crane's boom tip 6 m above
## `target` (world), as far as its 13--42 m boom allows.
## The boom length that puts its tip 6 m above `target` (world); more than
## EquipmentModels.BOOM_MAX means the crane cannot make that lift from where
## it stands.
static func boom_needed(crane_tf: Transform3D, target: Vector3) -> float:
	var g := _boom_geometry(crane_tf, target)
	return sqrt(g.y * g.y + g.z * g.z)


## (slew angle, horizontal reach from the boom foot, height of the tip above it).
static func _boom_geometry(crane_tf: Transform3D, target: Vector3) -> Vector3:
	var p := crane_tf.affine_inverse() * target
	var s := EquipmentModels.MOBILE_SLEW
	var dx := p.x - s.x
	var dz := p.z - s.z
	return Vector3(atan2(-dx, -dz), sqrt(dx * dx + dz * dz) + EquipmentModels.MOBILE_FOOT.z,
		p.y + 6.0 - (s.y + EquipmentModels.MOBILE_FOOT.y))


static func aim_mobile(crane_tf: Transform3D, target: Vector3) -> Dictionary:
	var g := _boom_geometry(crane_tf, target)
	var slew := g.x
	var r := g.y
	var h := g.z
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
	var active: Array = _plan.get("digs", []).filter(func(d): return day >= d.start and day <= d.finish)
	_dig = active[0] if not active.is_empty() else {}
	_excavator.visible = not _dig.is_empty()
	_truck.visible = _excavator.visible
	if _dig.has("site"):
		_rig.global_transform = _dig.site
	elif _rig:
		_rig.transform = Transform3D()
	# Digs at the terrain's pits that overlap: a crew each -- an excavator
	# and its truck -- as a site with several footings on the go would have.
	var extra: Array = active.slice(1).filter(func(d): return d.has("site"))
	while _crews.size() < extra.size():
		var rig: Node3D = _generated(Node3D.new(), self)
		rig.name = "DigRig%d" % (_crews.size() + 2)
		var ex := EquipmentModels.excavator()
		rig.add_child(ex)
		var tr := EquipmentModels.truck()
		rig.add_child(tr)
		tr.position = TRUCK_SPOT
		tr.rotation.y = PI
		_crews.append({"rig": rig, "excavator": ex, "truck": tr, "dig": {}})
	for i in _crews.size():
		var crew: Dictionary = _crews[i]
		crew.dig = extra[i] if i < extra.size() else {}
		crew.rig.visible = not crew.dig.is_empty()
		if not crew.dig.is_empty():
			crew.rig.global_transform = crew.dig.site
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
	if not _excavator:
		return
	if not _dig.is_empty():
		_animate_crew(_excavator, _truck, _dig.fill, _anim_time)
	for i in _crews.size():
		var crew: Dictionary = _crews[i]
		if not crew.dig.is_empty():
			# Out of step with the others, so the crews don't move as one.
			_animate_crew(crew.excavator, crew.truck, crew.dig.fill, _anim_time + DIG_CYCLE * (1.37 * (i + 1)))

## One crew's dig cycle and truck round at time `time` (see _animate_dig()).
func _animate_crew(excavator: Node3D, truck: Node3D, fill: bool, time: float) -> void:
	var round_t := fmod(time, DIG_CYCLE * TRUCK_ROUND)
	var cycle := int(round_t / DIG_CYCLE)
	var u := fmod(round_t, DIG_CYCLE) / DIG_CYCLE
	var truck_here := cycle >= 1 and cycle <= 4
	var pose := dig_pose(u)
	var dump_slew := -PI / 2.0 if truck_here and not fill else PI / 3.0
	EquipmentModels.pose_excavator(excavator, pose.slew * dump_slew, pose.boom, pose.stick, pose.bucket, pose.loaded)

	var spot := TRUCK_SPOT
	var far := TRUCK_SPOT + Vector3(0, 0, TRUCK_RUN)
	var load_level := 0.0
	var tip := 0.0
	var pos := spot
	truck.visible = true
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
		truck.visible = u < 0.75
	truck.position = pos
	var ground := ground_at(get_tree(), truck.global_position, truck.get_parent().global_position.y)
	truck.global_position.y = ground
	EquipmentModels.pose_truck(truck, tip, load_level)


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
		_mobile_seg = -1
	for crew in _crews:
		crew.rig.visible = false
		crew.dig = {}
	if _excavator:
		# On its marker it shows where it will dig; working the terrain's pits
		# it has no place of its own until a job puts it at one.
		var placed := _rig.get_parent() != self
		_rig.transform = Transform3D()
		_excavator.visible = placed
		_truck.visible = placed
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
