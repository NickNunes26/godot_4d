@tool
class_name EquipmentModels
extends RefCounted

## Procedural site plant: a tower crane, an all-terrain mobile crane, a 3-axle
## tipper truck and a ~20 t crawler excavator, each built from boxes and
## cylinders in code.
##
## Broad strokes on purpose -- a recognisable outline with roughly the right
## proportions, not a manufacturer's model. Built in code so the addon ships
## no assets (nothing to license or download), every machine is a few hundred
## to a couple of thousand triangles, and colours are flat materials.
##
## Every model stands on its own origin at ground level. Forward is -Z for the
## vehicles; the tower crane's jib points along +X, which is what
## runtime/crane.gd expects. Moving parts are named child nodes, posed with
## the pose_*() helpers below so callers never need to know the hierarchy.
## See docs/13_SITE_EQUIPMENT.md.

const YELLOW := Color(0.93, 0.69, 0.07)
const WHITE := Color(0.92, 0.92, 0.9)
const DARK := Color(0.11, 0.11, 0.12)
const STEEL := Color(0.38, 0.39, 0.41)
const GREY := Color(0.56, 0.57, 0.58)
const CONCRETE := Color(0.62, 0.61, 0.58)
const GLASS := Color(0.12, 0.18, 0.24)
const GREY_DARK := Color(0.22, 0.22, 0.23)
const SOIL := Color(0.40, 0.30, 0.20)
const STONE := Color(0.70, 0.68, 0.62)
const TIMBER := Color(0.55, 0.40, 0.24)

## Telescopic boom of the mobile crane: base section length, the length each
## of the three inner sections can slide out, and how much the retracted
## sections overlap the one before.
const BOOM_BASE := 11.0
const BOOM_SLIDE := 9.6
const BOOM_STEP := 0.8
const BOOM_SECTIONS := 3
## Boom-foot to boom-tip, fully retracted / fully extended.
const BOOM_MIN := BOOM_BASE + BOOM_STEP * BOOM_SECTIONS - 0.6 + 0.2
const BOOM_MAX := BOOM_MIN + BOOM_SLIDE * BOOM_SECTIONS
## Mobile crane: where the slewing superstructure sits on the carrier, and
## where the boom foot sits on the superstructure.
const MOBILE_SLEW := Vector3(0.0, 1.95, 1.6)
const MOBILE_FOOT := Vector3(0.3, 1.2, 1.8)

## Excavator geometry, in metres. Dimensions from Caterpillar's 320 sheet
## (equipment/specs/excavator_cat_320.json, checked against it by the test);
## the front's pins and joint limits fitted so the model's working range
## matches the sheet's (reach at ground 10.0 m vs 9.86, digging depth 6.74 vs
## 6.72, cutting height 9.07 vs 9.37).
const EXC_TRACK_CENTRES := 3.65 # idler to sprocket ("length to centre of rollers")
const EXC_TRACK_WHEEL_R := 0.4 # 3.65 + 2 x 0.4 = 4.45 m overall
const EXC_TRACK_GAUGE := 2.38
const EXC_SHOE := 0.6 # 2.38 + 0.6 = 2.98 m overall width
const EXC_GROUND_CLEARANCE := 0.47
const EXC_SLEW_Y := 1.0 # top of the slew ring
const EXC_CW_CLEARANCE := 1.05 # ground to the counterweight's underside
const EXC_UPPER_WIDTH := 2.78
const EXC_TAIL_SWING := 2.83
const EXC_CAB_TOP := 2.96
const EXC_HANDRAIL := 2.95
const EXC_BOOM_FOOT := Vector3(0.15, 1.05, -0.2) # upper-structure space
const EXC_BOOM_TIP := Vector3(0.0, 1.35, -5.54) # boom space: 5.70 m pin to pin
const EXC_STICK := 2.9
const EXC_STICK_STUB := Vector3(0, 0.75, 0.3) # stick space: the stick ram's pin
const EXC_TIP_RADIUS := 1.57
const EXC_BUCKET_WIDTH := 1.2
const EXC_CUTTING_EDGE := Vector2(-1.4, 0.1) # bucket space (Y, Z)
const EXC_TEETH_TIP := Vector2(-1.55, 0.25) # |tip| = EXC_TIP_RADIUS
const EXC_LINK_PIN := Vector2(0.1, -0.42) # bucket space (Y, Z)
const EXC_RAM_BASE := Vector3(0.15, 0.35, -1.25) # upper space
const EXC_RAM_END := Vector3(0, 0.55, -2.25) # boom space
const EXC_STICK_RAM_BASE := Vector3(0, 2.75, -2.25) # boom space
const EXC_BUCKET_RAM_BASE := Vector3(0, 0.45, -0.36) # stick space, on its back
## Joint limits, radians: boom (+ raises), stick (+ out), bucket (+ curls in).
const EXC_BOOM_RANGE := Vector2(-1.1, 0.6)
const EXC_STICK_RANGE := Vector2(-0.5, 1.4)
const EXC_BUCKET_RANGE := Vector2(-1.9, 1.6)

static var _materials: Dictionary = {}
static var _box_mesh: BoxMesh
static var _cyl_mesh: CylinderMesh
static var _cyl_mesh_small: CylinderMesh


# --- Tower crane --------------------------------------------------------------

## A flat-top tower crane. `height`: from the ground to the underside of the
## jib. `jib`: hook reach from the mast centre. `counter_jib`: length of the
## counterweight arm. `laydown`: where the materials are stacked, in the
## crane's own space (a PickupZone node is put there).
##
## With `as_crane` the root runs runtime/crane.gd, so the scene's lifts drive
## it: it exposes the node names that script looks for -- Arm (slews; +X is
## the jib), Track (the trolley, slides along Arm's X), Hook and Rope (Rope's
## Y scale is its length in metres) -- plus PickupZone.
static func tower_crane(height: float, jib: float, counter_jib: float, laydown := Vector3(0, 0, 9), as_crane := false) -> Node3D:
	var root: Node3D = Crane.new() if as_crane else Node3D.new()
	root.name = "TowerCrane"
	_box(root, Vector3(5.5, 0.3, 5.5), Vector3(0, 0.0, 0), CONCRETE, "Footing")

	# Mast: 1.6 m square lattice in ~3 m sections, so it can be shown going up
	# one section at a time.
	var mast := Node3D.new()
	mast.name = "Mast"
	root.add_child(mast)
	var n := maxi(int(ceil(height / 3.0)), 1)
	var s := height / n
	var w := 0.8
	for i in n:
		var sec := Node3D.new()
		sec.name = "Section%d" % i
		sec.position.y = i * s
		mast.add_child(sec)
		for c in [Vector2(w, w), Vector2(-w, w), Vector2(-w, -w), Vector2(w, -w)]:
			_strut(sec, Vector3(c.x, 0, c.y), Vector3(c.x, s, c.y), 0.16, YELLOW)
		var flip := 1.0 if i % 2 == 0 else -1.0
		_strut(sec, Vector3(w, 0, -w * flip), Vector3(w, s, w * flip), 0.08, YELLOW)
		_strut(sec, Vector3(-w, 0, w * flip), Vector3(-w, s, -w * flip), 0.08, YELLOW)
		_strut(sec, Vector3(-w * flip, 0, w), Vector3(w * flip, s, w), 0.08, YELLOW)
		_strut(sec, Vector3(w * flip, 0, -w), Vector3(-w * flip, s, -w), 0.08, YELLOW)
		_strut(sec, Vector3(-w, s, -w), Vector3(w, s, -w), 0.08, YELLOW)
		_strut(sec, Vector3(-w, s, w), Vector3(w, s, w), 0.08, YELLOW)
	mast.set_meta("sections", n)

	var arm := Node3D.new()
	arm.name = "Arm"
	arm.position.y = height
	root.add_child(arm)
	_cyl(arm, 1.0, 0.6, Vector3(0, 0.3, 0), Vector3.UP, STEEL)
	_box(arm, Vector3(2.4, 0.5, 2.4), Vector3(0, 0.85, 0), YELLOW)
	# Cab beside the jib root, glazed towards the jib.
	_box(arm, Vector3(1.8, 2.0, 1.5), Vector3(0.9, 1.0, 1.75), WHITE, "Cab")
	_box(arm, Vector3(0.06, 1.2, 1.3), Vector3(1.82, 1.25, 1.75), GLASS)

	# Jib: triangular lattice, bottom chords 1.2 m apart, apex 1.4 m up.
	var y0 := 1.1
	var y1 := 2.5
	var bay := 2.5
	var bays := maxi(int(ceil((jib - 0.8) / bay)), 1)
	var jx0 := 0.8
	var jx1 := jib + 1.0
	_strut(arm, Vector3(jx0, y0, -0.6), Vector3(jx1, y0, -0.6), 0.14, YELLOW)
	_strut(arm, Vector3(jx0, y0, 0.6), Vector3(jx1, y0, 0.6), 0.14, YELLOW)
	_strut(arm, Vector3(jx0, y1, 0), Vector3(jx1, y0 + 0.3, 0), 0.14, YELLOW)
	var step := (jx1 - jx0) / bays
	for i in bays:
		var xa := jx0 + i * step
		var xb := xa + step
		var top_a := lerpf(y1, y0 + 0.3, float(i) / bays)
		var top_b := lerpf(y1, y0 + 0.3, float(i + 1) / bays)
		_strut(arm, Vector3(xa, y0, -0.6), Vector3(xb, top_b, 0), 0.06, YELLOW)
		_strut(arm, Vector3(xa, y0, 0.6), Vector3(xb, top_b, 0), 0.06, YELLOW)
		_strut(arm, Vector3(xb, y0, -0.6), Vector3(xb, top_b, 0), 0.05, YELLOW)
		_strut(arm, Vector3(xb, y0, 0.6), Vector3(xb, top_b, 0), 0.05, YELLOW)
		_strut(arm, Vector3(xa, y0, -0.6), Vector3(xb, y0, 0.6), 0.05, YELLOW)
		if i == 0:
			_strut(arm, Vector3(xa, y0, -0.6), Vector3(xa, top_a, 0), 0.05, YELLOW)
			_strut(arm, Vector3(xa, y0, 0.6), Vector3(xa, top_a, 0), 0.05, YELLOW)

	# Counter-jib: a walkway with the hoist winch and the counterweight blocks.
	var cx := -counter_jib
	_strut(arm, Vector3(-0.8, y0, -0.8), Vector3(cx, y0, -0.8), 0.16, YELLOW)
	_strut(arm, Vector3(-0.8, y0, 0.8), Vector3(cx, y0, 0.8), 0.16, YELLOW)
	_box(arm, Vector3(counter_jib - 0.8, 0.08, 1.6), Vector3((cx - 0.8) / 2.0, y0 + 0.1, 0), STEEL)
	for side in [-1.0, 1.0]:
		_strut(arm, Vector3(-0.8, y0 + 1.0, side * 0.8), Vector3(cx, y0 + 1.0, side * 0.8), 0.04, YELLOW)
	_box(arm, Vector3(1.6, 1.0, 1.2), Vector3(-2.6, y0 + 0.65, 0), YELLOW, "Winch")
	var blocks := clampi(int(counter_jib / 3.0), 2, 6)
	for i in blocks:
		_box(arm, Vector3(0.5, 2.4, 2.0), Vector3(cx + 0.35 + i * 0.55, y0 - 0.4, 0), CONCRETE)

	# Trolley, rope and hook block.
	var track := Node3D.new()
	track.name = "Track"
	track.position = Vector3(jib * 0.45, y0 - 0.15, 0)
	arm.add_child(track)
	_box(track, Vector3(1.4, 0.35, 1.5), Vector3.ZERO, STEEL)
	var rope := Node3D.new()
	rope.name = "Rope"
	rope.scale.y = 4.0
	track.add_child(rope)
	for z in [-0.18, 0.18]:
		_box(rope, Vector3(0.04, 1.0, 0.04), Vector3(0, -0.5, z), DARK)
	var hook := Node3D.new()
	hook.name = "Hook"
	hook.position.y = -4.0
	track.add_child(hook)
	_box(hook, Vector3(0.7, 0.9, 0.45), Vector3(0, -0.45, 0), YELLOW)
	_cyl(hook, 0.12, 0.5, Vector3(0, -1.15, 0), Vector3.UP, DARK)

	var zone := Node3D.new()
	zone.name = "PickupZone"
	zone.position = laydown
	root.add_child(zone)
	_laydown_stack(zone)
	return root


## Timber dunnage with a few stone blocks and a pallet -- what a laydown area
## looks like from a distance.
static func _laydown_stack(zone: Node3D) -> void:
	for x in [-1.6, 1.6]:
		for z in [-0.6, 0.6]:
			_box(zone, Vector3(1.4, 0.12, 0.12), Vector3(x, 0.06, z), TIMBER)
	_box(zone, Vector3(1.2, 0.7, 0.9), Vector3(-1.6, 0.47, 0), STONE)
	_box(zone, Vector3(1.0, 0.5, 0.8), Vector3(1.6, 0.37, 0.05), STONE)
	_box(zone, Vector3(0.8, 0.35, 0.7), Vector3(1.55, 0.8, 0.0), STONE)
	_box(zone, Vector3(1.2, 0.14, 1.0), Vector3(0, 0.07, 1.8), TIMBER)


# --- Mobile crane -------------------------------------------------------------

## A 4-axle all-terrain crane: carrier, slewing superstructure with its own cab
## and counterweight, a 4-section telescopic boom and four outriggers.
## Pose it with pose_mobile_crane().
static func mobile_crane() -> Node3D:
	var root := Node3D.new()
	root.name = "MobileCrane"
	_box(root, Vector3(2.0, 0.5, 11.0), Vector3(0, 0.95, 0), DARK)
	_box(root, Vector3(2.55, 0.9, 11.6), Vector3(0, 1.5, 0), YELLOW, "Carrier")
	for z in [-4.3, -2.75, 2.45, 4.0]:
		for x in [-1.0, 1.0]:
			_cyl(root, 0.65, 0.55, Vector3(x, 0.65, z), Vector3.RIGHT, DARK)
			_cyl(root, 0.3, 0.57, Vector3(x, 0.65, z), Vector3.RIGHT, GREY)
	_box(root, Vector3(1.15, 1.6, 1.7), Vector3(-0.75, 2.45, -4.85), YELLOW, "CarrierCab")
	_box(root, Vector3(1.0, 0.9, 0.06), Vector3(-0.75, 2.75, -5.72), GLASS)

	var i := 0
	for z in [-5.3, 5.3]:
		for side in [-1.0, 1.0]:
			var o := Node3D.new()
			o.name = "Outrigger%d" % i
			o.position = Vector3(side * 1.0, 1.15, z)
			o.set_meta("side", side)
			root.add_child(o)
			_box(o, Vector3(2.4, 0.35, 0.4), Vector3(-side * 1.1, 0, 0), YELLOW)
			var jack := Node3D.new()
			jack.name = "Jack"
			o.add_child(jack)
			_cyl(jack, 0.14, 1.0, Vector3(0, -0.5, 0), Vector3.UP, STEEL)
			_box(jack, Vector3(0.7, 0.06, 0.7), Vector3(0, -1.0, 0), DARK)
			i += 1

	var slew := Node3D.new()
	slew.name = "Slew"
	slew.position = MOBILE_SLEW
	root.add_child(slew)
	_cyl(slew, 1.15, 0.3, Vector3(0, 0.15, 0), Vector3.UP, STEEL)
	_box(slew, Vector3(2.4, 0.6, 4.2), Vector3(0, 0.6, 0.7), YELLOW, "Deck")
	_box(slew, Vector3(2.5, 1.3, 1.0), Vector3(0, 1.05, 2.9), GREY, "Counterweight")
	_box(slew, Vector3(0.9, 1.5, 1.8), Vector3(-1.3, 1.15, -0.5), YELLOW, "CraneCab")
	_box(slew, Vector3(0.8, 1.0, 0.06), Vector3(-1.3, 1.35, -1.41), GLASS)

	var boom := Node3D.new()
	boom.name = "Boom"
	boom.position = MOBILE_FOOT
	slew.add_child(boom)
	var parent := boom
	var widths := [0.95, 0.8, 0.66, 0.52]
	for k in BOOM_SECTIONS + 1:
		var sec := Node3D.new()
		sec.name = "Section%d" % k
		parent.add_child(sec)
		var length := BOOM_BASE if k == 0 else BOOM_BASE - 0.6
		if k > 0:
			sec.position.z = -BOOM_STEP
		_box(sec, Vector3(widths[k], widths[k], length), Vector3(0, 0, -length / 2.0), YELLOW)
		parent = sec
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position.z = -(BOOM_BASE - 0.6) - 0.2
	parent.add_child(tip)
	_cyl(tip, 0.35, 0.45, Vector3.ZERO, Vector3.RIGHT, STEEL)
	# Boom-raising cylinder from the deck to under the base section.
	var ram := Node3D.new()
	ram.name = "Ram"
	slew.add_child(ram)
	_box(ram, Vector3(0.35, 1.0, 0.35), Vector3(0, 0.5, 0), STEEL)

	var rope := Node3D.new()
	rope.name = "Rope"
	root.add_child(rope)
	_box(rope, Vector3(0.05, 1.0, 0.05), Vector3(0, -0.5, 0), DARK)
	var hook := Node3D.new()
	hook.name = "Hook"
	root.add_child(hook)
	_box(hook, Vector3(0.6, 0.8, 0.4), Vector3(0, -0.4, 0), YELLOW)
	_cyl(hook, 0.11, 0.45, Vector3(0, -1.0, 0), Vector3.UP, DARK)
	pose_mobile_crane(root, 0.0, 0.0, 0.0, 0.0, 2.0)
	return root


## `slew` (radians about Y, 0 = boom over the front), `luff` (radians above
## horizontal), `extend` 0..1 (telescope), `outriggers` 0..1 (stowed..set on
## pads), `hook_drop` metres of rope below the boom tip.
static func pose_mobile_crane(root: Node3D, slew: float, luff: float, extend: float, outriggers: float, hook_drop: float) -> void:
	var slew_node: Node3D = root.get_node("Slew")
	slew_node.rotation.y = slew
	var boom: Node3D = slew_node.get_node("Boom")
	boom.rotation.x = luff
	var sec: Node3D = boom.get_node("Section0")
	for k in range(1, BOOM_SECTIONS + 1):
		sec = sec.get_node("Section%d" % k)
		sec.position.z = -BOOM_STEP - BOOM_SLIDE * clampf(extend, 0.0, 1.0)
	# Ram: from the deck up to a point 3.5 m along the boom.
	var ram: Node3D = slew_node.get_node("Ram")
	var a := Vector3(0, 0.9, -1.2)
	var b := MOBILE_FOOT + Basis(Vector3.RIGHT, luff) * Vector3(0, -0.5, -3.5)
	_orient_strut(ram, a, b)
	for o in root.get_children():
		if not String(o.name).begins_with("Outrigger"):
			continue
		var side: float = o.get_meta("side")
		var t := clampf(outriggers, 0.0, 1.0)
		o.position.x = side * lerpf(1.0, 3.6, minf(t * 1.5, 1.0))
		var jack: Node3D = o.get_node("Jack")
		jack.scale.y = lerpf(0.35, 1.0, clampf(t * 3.0 - 2.0, 0.0, 1.0))
	var tip := boom_tip(root)
	var rope: Node3D = root.get_node("Rope")
	var hook: Node3D = root.get_node("Hook")
	var tip_local := root.global_transform.affine_inverse() * tip if root.is_inside_tree() else _tip_local(root)
	rope.position = tip_local
	rope.scale.y = maxf(hook_drop, 0.3)
	hook.position = tip_local - Vector3(0, maxf(hook_drop, 0.3), 0)


## World position of the mobile crane's boom tip (its own space when the
## model is not in a tree).
static func boom_tip(root: Node3D) -> Vector3:
	if not root.is_inside_tree():
		return _tip_local(root)
	return (root.get_node("Slew/Boom/Section0/Section1/Section2/Section3/Tip") as Node3D).global_position


static func _tip_local(root: Node3D) -> Vector3:
	var tf := Transform3D()
	var n: Node = root.get_node("Slew/Boom/Section0/Section1/Section2/Section3/Tip")
	while n and n != root:
		tf = (n as Node3D).transform * tf
		n = n.get_parent()
	return tf.origin


# --- Truck --------------------------------------------------------------------

## A rigid 3-axle tipper, ~9 m x 2.5 m x 3.3 m: cab, chassis, tipping body
## with a soil load. Pose it with pose_truck().
static func truck() -> Node3D:
	var root := Node3D.new()
	root.name = "Truck"
	_box(root, Vector3(1.0, 0.3, 8.6), Vector3(0, 0.95, 0.0), DARK)
	for z in [-2.9]:
		for x in [-1.0, 1.0]:
			_cyl(root, 0.52, 0.42, Vector3(x, 0.52, z), Vector3.RIGHT, DARK)
	for z in [1.7, 3.05]:
		for x in [-0.92, 0.92]:
			_cyl(root, 0.52, 0.66, Vector3(x, 0.52, z), Vector3.RIGHT, DARK)
	_box(root, Vector3(2.45, 2.1, 1.9), Vector3(0, 2.0, -3.6), WHITE, "Cab")
	_box(root, Vector3(2.2, 0.9, 0.06), Vector3(0, 2.45, -4.56), GLASS)
	for x in [-1.235, 1.235]:
		_box(root, Vector3(0.04, 0.8, 1.0), Vector3(x, 2.45, -3.85), GLASS)
	_box(root, Vector3(2.45, 0.35, 0.15), Vector3(0, 0.95, -4.62), DARK)
	_box(root, Vector3(2.45, 0.5, 0.9), Vector3(0, 0.8, -2.9), GREY, "Wings")
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 1.25, 4.3)
	root.add_child(body)
	_box(body, Vector3(2.4, 0.12, 6.6), Vector3(0, 0.06, -3.3), GREY)
	for x in [-1.16, 1.16]:
		_box(body, Vector3(0.08, 1.5, 6.6), Vector3(x, 0.81, -3.3), GREY)
	_box(body, Vector3(2.4, 1.9, 0.1), Vector3(0, 1.0, -6.55), GREY)
	_box(body, Vector3(2.4, 1.5, 0.08), Vector3(0, 0.81, -0.04), GREY, "Tailgate")
	var load_node := Node3D.new()
	load_node.name = "Load"
	load_node.position.y = 0.12
	body.add_child(load_node)
	_box(load_node, Vector3(2.2, 1.0, 6.3), Vector3(0, 0.5, -3.3), SOIL)
	pose_truck(root, 0.0, 0.0)
	return root


## `tip` 0..1 (body down..fully raised, ~50 degrees), `load` 0..1 (empty..heaped).
static func pose_truck(root: Node3D, tip: float, load_level: float) -> void:
	var body: Node3D = root.get_node("Body")
	body.rotation.x = deg_to_rad(50.0) * clampf(tip, 0.0, 1.0)
	var l: Node3D = body.get_node("Load")
	l.visible = load_level > 0.01
	l.scale.y = maxf(clampf(load_level, 0.0, 1.0) * 1.5, 0.01)


# --- Excavator ----------------------------------------------------------------

## A ~22 t crawler excavator: the external frame of a Caterpillar 320 with the
## reach boom, R2.9 stick and 1.19 m3 bucket, sized from Caterpillar's published
## dimensions (equipment/specs/excavator_cat_320.json; EquipmentSpecs) and with
## joint limits fitted so its working range matches theirs. Broad strokes still:
## no hoses, no steps, no lights. Pose it with pose_excavator().
static func excavator() -> Node3D:
	var root := Node3D.new()
	root.name = "Excavator"
	var under := Node3D.new()
	under.name = "Undercarriage"
	root.add_child(under)
	# Tracks: idler (front) and sprocket (rear) 3.65 m apart on a 2.38 m gauge,
	# 0.6 m shoes -- 4.45 m long and 2.98 m wide overall.
	var r := EXC_TRACK_WHEEL_R
	var half := EXC_TRACK_CENTRES / 2.0
	for side in [-1.0, 1.0]:
		var x: float = side * EXC_TRACK_GAUGE / 2.0
		_box(under, Vector3(EXC_SHOE, 0.07, EXC_TRACK_CENTRES), Vector3(x, 0.035, 0), DARK)
		_box(under, Vector3(EXC_SHOE, 0.07, EXC_TRACK_CENTRES), Vector3(x, 2.0 * r - 0.035, 0), DARK)
		for z in [-half, half]:
			_cyl(under, r, EXC_SHOE, Vector3(x, r, z), Vector3.RIGHT, DARK)
		_cyl(under, 0.24, EXC_SHOE + 0.04, Vector3(x, r, -half), Vector3.RIGHT, STEEL)
		_cyl(under, 0.3, EXC_SHOE + 0.04, Vector3(x, r, half), Vector3.RIGHT, GREY)
		for i in 7:
			_box(under, Vector3(EXC_SHOE + 0.02, 0.05, 0.06), Vector3(x, 2.0 * r + 0.02, -1.5 + i * 0.5), DARK)
		# Track frame between the runs, rollers under it, carrier rollers on top.
		_box(under, Vector3(0.36, 0.42, EXC_TRACK_CENTRES - 2.0 * r), Vector3(x, 0.4, 0), GREY_DARK)
		for i in 8:
			_cyl(under, 0.1, 0.42, Vector3(x, 0.17, -1.3 + i * (2.6 / 7.0)), Vector3.RIGHT, STEEL)
		for z in [-0.6, 0.6]:
			_cyl(under, 0.08, 0.3, Vector3(x, 2.0 * r - 0.14, z), Vector3.RIGHT, STEEL)
	_box(under, Vector3(EXC_TRACK_GAUGE - 0.3, 0.32, 2.2), Vector3(0, EXC_GROUND_CLEARANCE + 0.16, 0), GREY_DARK, "CarBody")
	_cyl(under, 0.95, EXC_SLEW_Y - 0.79, Vector3(0, (EXC_SLEW_Y + 0.79) / 2.0, 0), Vector3.UP, STEEL)

	var upper := Node3D.new()
	upper.name = "Upper"
	upper.position.y = EXC_SLEW_Y
	root.add_child(upper)
	var w := EXC_UPPER_WIDTH / 2.0
	# Frame deck, the house behind the cab and the right-hand compartment in front.
	_box(upper, Vector3(EXC_UPPER_WIDTH, 0.2, 3.3), Vector3(0, 0.15, 0.15), GREY_DARK, "Deck")
	_box(upper, Vector3(EXC_UPPER_WIDTH, 1.0, 1.6), Vector3(0, 0.75, 0.95), YELLOW, "House")
	_box(upper, Vector3(0.94, 0.9, 1.7), Vector3(w - 0.47, 0.7, -0.7), YELLOW, "Compartment")
	_box(upper, Vector3(1.5, 0.16, 1.1), Vector3(0.5, 1.33, 1.1), YELLOW, "Hood")
	_box(upper, Vector3(1.2, 0.04, 0.5), Vector3(0.5, 1.42, 1.1), GREY_DARK)
	_cyl(upper, 0.07, 0.55, Vector3(0.95, 1.6, 0.85), Vector3.UP, DARK)
	# Counterweight: its underside at the published clearance, its back corners on
	# the tail swing radius.
	var cw_z := sqrt(EXC_TAIL_SWING * EXC_TAIL_SWING - 1.3 * 1.3)
	var cw_bottom := EXC_CW_CLEARANCE - EXC_SLEW_Y
	_box(upper, Vector3(2.6, 1.25 - cw_bottom, cw_z - 1.75), Vector3(0, (1.25 + cw_bottom) / 2.0, (cw_z + 1.75) / 2.0), GREY, "Counterweight")
	_box(upper, Vector3(2.0, 0.08, 0.3), Vector3(0, 0.95, cw_z - 0.05), YELLOW)
	# Cab, front left: dark frame, glazing, roof at the published cab height.
	var cab_h := EXC_CAB_TOP - EXC_SLEW_Y - 0.25
	var cab_c := Vector3(-w + 0.5, 0.25 + cab_h / 2.0, -0.65)
	_box(upper, Vector3(1.0, cab_h, 1.75), cab_c, GREY_DARK, "Cab")
	_box(upper, Vector3(0.86, cab_h - 0.55, 0.04), cab_c + Vector3(0, 0.15, -0.88), GLASS)
	_box(upper, Vector3(0.04, cab_h - 0.6, 1.45), cab_c + Vector3(-0.51, 0.18, 0), GLASS)
	_box(upper, Vector3(0.04, cab_h - 0.9, 0.9), cab_c + Vector3(0.51, 0.3, -0.25), GLASS)
	_box(upper, Vector3(1.04, 0.06, 1.8), cab_c + Vector3(0, cab_h / 2.0, 0), YELLOW)
	# Handrails along the right-hand side, top at the published height.
	var rail_top := EXC_HANDRAIL - EXC_SLEW_Y
	for z in [-1.3, 0.2, 1.6]:
		_box(upper, Vector3(0.04, rail_top - 1.25, 0.04), Vector3(w - 0.05, (rail_top + 1.25) / 2.0, z), STEEL)
	_box(upper, Vector3(0.04, 0.04, 2.95), Vector3(w - 0.05, rail_top, 0.15), STEEL)

	# Boom: a banana-shaped box section, deeper at the foot, on a foot pin
	# between the cab and the compartment.
	var boom := Node3D.new()
	boom.name = "Boom"
	boom.position = EXC_BOOM_FOOT
	upper.add_child(boom)
	var knee := Vector3(0, 2.3, -2.55)
	_strut(boom, Vector3(0, -0.15, 0.25), knee, 0.62, YELLOW, 0.5)
	_strut(boom, knee, EXC_BOOM_TIP, 0.5, YELLOW, 0.44)
	_box(boom, Vector3(0.5, 0.5, 0.5), knee, YELLOW)
	_cyl(boom, 0.13, 0.7, Vector3.ZERO, Vector3.RIGHT, STEEL)
	_cyl(boom, 0.12, 0.56, EXC_BOOM_TIP, Vector3.RIGHT, STEEL)
	# Hydraulic cylinders, re-aimed by pose_excavator(): two boom rams from the
	# frame to the boom's belly, the stick ram along the boom's back.
	for side in ["L", "R"]:
		_strut(upper, Vector3.ZERO, Vector3.UP, 0.17, STEEL).name = "BoomRam" + side
	_strut(boom, Vector3.ZERO, Vector3.UP, 0.19, STEEL).name = "StickRam"

	var stick := Node3D.new()
	stick.name = "Stick"
	stick.position = EXC_BOOM_TIP
	boom.add_child(stick)
	_strut(stick, EXC_STICK_STUB, Vector3(0, 0.05, 0), 0.5, YELLOW, 0.4)
	_strut(stick, Vector3(0, 0.1, 0), Vector3(0, -EXC_STICK + 0.05, 0), 0.46, YELLOW, 0.36)
	_cyl(stick, 0.1, 0.5, Vector3(0, -EXC_STICK, 0), Vector3.RIGHT, STEEL)
	_strut(stick, Vector3.ZERO, Vector3.UP, 0.15, STEEL).name = "BucketRam"
	_strut(stick, Vector3.ZERO, Vector3.UP, 0.08, GREY_DARK, 0.3).name = "PowerLink"
	_strut(stick, Vector3.ZERO, Vector3.UP, 0.08, GREY_DARK, 0.42).name = "IdlerLink"

	var bucket := Node3D.new()
	bucket.name = "Bucket"
	bucket.position.y = -EXC_STICK
	stick.add_child(bucket)
	_bucket(bucket)
	pose_excavator(root, 0.0, 0.06, 0.455, -0.8, false)
	return root


## The 1.2 m, 1.19 m3 digging bucket, in its own space: the stick pin at the
## origin, the mouth open towards +Z (the machine), the wrapper's back towards
## -Z, teeth reaching EXC_TIP_RADIUS from the pin.
static func _bucket(bucket: Node3D) -> void:
	var half := EXC_BUCKET_WIDTH / 2.0
	# Profile (Y, Z): lip, top plate past the pins, the curved back, cutting edge.
	var profile := PackedVector2Array([
		Vector2(-0.12, 0.42), Vector2(0.14, 0.14), Vector2(0.1, -0.3), Vector2(-0.32, -0.6),
		Vector2(-0.78, -0.72), Vector2(-1.18, -0.58), Vector2(-1.42, -0.26), EXC_CUTTING_EDGE])
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		_strut(bucket, Vector3(0, a.x, a.y), Vector3(0, b.x, b.y), 0.05, YELLOW, EXC_BUCKET_WIDTH)
	for x in [-half, half]:
		_prism(bucket, profile, x, 0.04, YELLOW)
	# Wear strips under the back, the cutting edge, five teeth on adapters,
	# side cutters.
	for x in [-0.3, 0.3]:
		_strut(bucket, Vector3(x, -0.84, -0.74), Vector3(x, -1.22, -0.6), 0.04, GREY_DARK, 0.1)
	var edge := Vector3(0, EXC_CUTTING_EDGE.x, EXC_CUTTING_EDGE.y)
	var tip := Vector3(0, EXC_TEETH_TIP.x, EXC_TEETH_TIP.y)
	_strut(bucket, edge + Vector3(0, 0.06, -0.08), edge + Vector3(0, -0.02, 0.06), 0.05, STEEL, EXC_BUCKET_WIDTH + 0.04)
	for i in 5:
		var x := -half + 0.12 + i * (EXC_BUCKET_WIDTH - 0.24) / 4.0
		_strut(bucket, edge + Vector3(x, 0.05, -0.05), edge.lerp(tip, 0.55) + Vector3(x, 0, 0), 0.1, YELLOW, 0.12)
		_strut(bucket, edge.lerp(tip, 0.45) + Vector3(x, 0, 0), tip + Vector3(x, 0, 0), 0.07, DARK, 0.09)
	for x in [-half - 0.03, half + 0.03]:
		_strut(bucket, edge + Vector3(x, 0.25, -0.18), edge + Vector3(x, -0.05, 0.08), 0.06, STEEL, 0.04)
	# Ears around the stick and link pins, and the pins.
	for x in [-0.22, 0.22]:
		_box(bucket, Vector3(0.05, 0.42, 0.75), Vector3(x, 0.08, -0.2), YELLOW)
	_cyl(bucket, 0.08, 0.5, Vector3.ZERO, Vector3.RIGHT, STEEL)
	_cyl(bucket, 0.08, 0.5, Vector3(0, EXC_LINK_PIN.x, EXC_LINK_PIN.y), Vector3.RIGHT, STEEL)
	var load_node := Node3D.new()
	load_node.name = "Load"
	bucket.add_child(load_node)
	_box(load_node, Vector3(EXC_BUCKET_WIDTH - 0.1, 0.62, 0.8), Vector3(0, -0.72, -0.12), SOIL)
	_box(load_node, Vector3(EXC_BUCKET_WIDTH - 0.3, 0.2, 0.55), Vector3(0, -0.36, 0.05), SOIL)


## `slew` radians about Y (0 = facing -Z), `boom` radians (+ raises), `stick`
## radians (+ swings out forward), `bucket` radians (+ curls closed, towards
## the machine), `loaded` shows soil in the bucket. Angles are clamped to the
## joint limits EXC_*_RANGE; the cylinders and the bucket linkage follow.
static func pose_excavator(root: Node3D, slew: float, boom: float, stick: float, bucket: float, loaded: bool) -> void:
	boom = clampf(boom, EXC_BOOM_RANGE.x, EXC_BOOM_RANGE.y)
	stick = clampf(stick, EXC_STICK_RANGE.x, EXC_STICK_RANGE.y)
	bucket = clampf(bucket, EXC_BUCKET_RANGE.x, EXC_BUCKET_RANGE.y)
	var upper: Node3D = root.get_node("Upper")
	upper.rotation.y = slew
	var boom_node: Node3D = upper.get_node("Boom")
	boom_node.rotation.x = boom
	var boom_basis := Basis(Vector3.RIGHT, boom)
	for side in ["L", "R"]:
		var dx := -0.33 if side == "L" else 0.33
		_orient_strut(upper.get_node("BoomRam" + side), EXC_RAM_BASE + Vector3(dx, 0, 0),
			EXC_BOOM_FOOT + boom_basis * EXC_RAM_END + Vector3(dx, 0, 0), 0.17)
	var stick_node: Node3D = boom_node.get_node("Stick")
	stick_node.rotation.x = stick
	_orient_strut(boom_node.get_node("StickRam"), EXC_STICK_RAM_BASE,
		EXC_BOOM_TIP + Basis(Vector3.RIGHT, stick) * EXC_STICK_STUB, 0.19)
	var bucket_node: Node3D = stick_node.get_node("Bucket")
	bucket_node.rotation.x = -bucket
	# Bucket linkage, in stick space: the ram pushes a joint that is held by the
	# idler link to the stick and by the power link to the bucket's link pin.
	var pin := Vector3(0, -EXC_STICK, 0) + Basis(Vector3.RIGHT, -bucket) * Vector3(0, EXC_LINK_PIN.x, EXC_LINK_PIN.y)
	var idler := Vector3(0, -EXC_STICK + 0.55, -0.3)
	var joint := _link_joint(Vector2(idler.y, idler.z), Vector2(pin.y, pin.z), 0.6, 0.55)
	_orient_strut(stick_node.get_node("BucketRam"), EXC_BUCKET_RAM_BASE, joint, 0.15)
	_orient_strut(stick_node.get_node("PowerLink"), joint, pin, 0.08, 0.3)
	_orient_strut(stick_node.get_node("IdlerLink"), idler, joint, 0.08, 0.42)
	(bucket_node.get_node("Load") as Node3D).visible = loaded


## Where the idler link (length `a`, from `idler`) and the power link (length
## `b`, from the bucket's `pin`) meet, in the stick's (Y, Z) plane: the circle
## intersection on the stick's back (-Z), where the bucket ram pushes.
static func _link_joint(idler: Vector2, pin: Vector2, a: float, b: float) -> Vector3:
	var d := maxf(idler.distance_to(pin), 0.001)
	var u := (pin - idler) / d
	var along := clampf((d * d + a * a - b * b) / (2.0 * d), -a, a)
	var h := sqrt(maxf(a * a - along * along, 0.0))
	var j1 := idler + u * along + Vector2(-u.y, u.x) * h
	var j2 := idler + u * along - Vector2(-u.y, u.x) * h
	var j := j1 if j1.y < j2.y else j2
	return Vector3(0, j.x, j.y)


## The bucket's teeth tips, in the excavator's own space, for a pose.
static func excavator_teeth(slew: float, boom: float, stick: float, bucket: float) -> Vector3:
	return _excavator_bucket_tf(slew, boom, stick, bucket) * Vector3(0, EXC_TEETH_TIP.x, EXC_TEETH_TIP.y)


## The bucket's stick pin, in the excavator's own space, for a pose.
static func excavator_bucket_pin(slew: float, boom: float, stick: float) -> Vector3:
	return _excavator_bucket_tf(slew, boom, stick, 0.0).origin


static func _excavator_bucket_tf(slew: float, boom: float, stick: float, bucket: float) -> Transform3D:
	var t := Transform3D(Basis(Vector3.UP, slew), Vector3(0, EXC_SLEW_Y, 0))
	t *= Transform3D(Basis(Vector3.RIGHT, clampf(boom, EXC_BOOM_RANGE.x, EXC_BOOM_RANGE.y)), EXC_BOOM_FOOT)
	t *= Transform3D(Basis(Vector3.RIGHT, clampf(stick, EXC_STICK_RANGE.x, EXC_STICK_RANGE.y)), EXC_BOOM_TIP)
	t *= Transform3D(Basis(Vector3.RIGHT, -clampf(bucket, EXC_BUCKET_RANGE.x, EXC_BUCKET_RANGE.y)), Vector3(0, -EXC_STICK, 0))
	return t


## The model's working range, scanned over its joint limits: {reach (at ground
## line, from the slew centre), depth, cut (cutting height)} in metres. The test
## compares it with Caterpillar's published working ranges; clash checks can
## read the spec file directly (EquipmentSpecs).
static func excavator_envelope(steps := 40) -> Dictionary:
	var reach := 0.0
	var depth := 0.0
	var cut := 0.0
	for i in steps + 1:
		var b := lerpf(EXC_BOOM_RANGE.x, EXC_BOOM_RANGE.y, float(i) / steps)
		for j in steps + 1:
			var s := lerpf(EXC_STICK_RANGE.x, EXC_STICK_RANGE.y, float(j) / steps)
			for k in 17:
				var t := excavator_teeth(0.0, b, s, lerpf(EXC_BUCKET_RANGE.x, EXC_BUCKET_RANGE.y, k / 16.0))
				if absf(t.y) < 0.15:
					reach = maxf(reach, -t.z)
				depth = maxf(depth, -t.y)
				cut = maxf(cut, t.y)
	return {"reach": reach, "depth": depth, "cut": cut}


# --- Primitives ---------------------------------------------------------------

## Counts the triangles of every mesh under `root` (for docs and tests).
static func triangle_count(root: Node) -> int:
	var total := 0
	var nodes: Array = [root] if root is MeshInstance3D else []
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for m in nodes:
		var mesh: Mesh = (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			total += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


static func _box(parent: Node3D, size: Vector3, center: Vector3, color: Color, node_name := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if node_name != "":
		m.name = node_name
	m.mesh = _unit_box()
	m.material_override = material(color)
	m.position = center
	m.scale = size
	parent.add_child(m)
	return m


static func _cyl(parent: Node3D, radius: float, height: float, center: Vector3, axis: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _unit_cylinder(radius < 0.15)
	m.material_override = material(color)
	var basis := Basis()
	if axis.is_equal_approx(Vector3.RIGHT):
		basis = Basis(Vector3.FORWARD, PI / 2.0)
	elif axis.is_equal_approx(Vector3.BACK) or axis.is_equal_approx(Vector3.FORWARD):
		basis = Basis(Vector3.RIGHT, PI / 2.0)
	m.transform = Transform3D(basis * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), center)
	parent.add_child(m)
	return m


## A bar from `a` to `b`, `thickness` deep and `width` wide (square when
## `width` is left out). For a bar in a Y-Z plane the width runs along X.
static func _strut(parent: Node3D, a: Vector3, b: Vector3, thickness: float, color: Color, width := -1.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _unit_box()
	m.material_override = material(color)
	parent.add_child(m)
	_orient_strut(m, a, b, thickness, width)
	return m


## Places `node` (a unit-height box or a node whose children span 0..1 in Y)
## from `a` to `b`. With `thickness` the node is a unit box scaled to it;
## without, only its length (Y) is scaled.
static func _orient_strut(node: Node3D, a: Vector3, b: Vector3, thickness := -1.0, width := -1.0) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var y := d / length
	# Width across the machine (X) whenever the bar isn't itself along X: X with
	# its component along the bar removed. (Crossing with a fixed axis instead
	# turned the width of a bar lying along Z into a vertical fin.)
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := (ref - y * y.dot(ref)).normalized()
	var z := x.cross(y)
	if thickness > 0.0:
		node.transform = Transform3D(Basis(x * (width if width > 0.0 else thickness), y * length, z * thickness), (a + b) / 2.0)
	else:
		node.transform = Transform3D(Basis(x, y * length, z), a)


## A flat plate: `profile` (Y, Z) extruded `thickness` along X, centred on `x`.
static func _prism(parent: Node3D, profile: PackedVector2Array, x: float, thickness: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(profile)
	var x0 := x - thickness / 2.0
	var x1 := x + thickness / 2.0
	for side in [x0, x1]:
		var order: Array = [0, 1, 2] if side == x1 else [0, 2, 1]
		for i in range(0, tris.size(), 3):
			for o in order:
				var p := profile[tris[i + o]]
				st.add_vertex(Vector3(side, p.x, p.y))
	for i in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		for v in [Vector3(x0, a.x, a.y), Vector3(x1, a.x, a.y), Vector3(x1, b.x, b.y),
				Vector3(x0, a.x, a.y), Vector3(x1, b.x, b.y), Vector3(x0, b.x, b.y)]:
			st.add_vertex(v)
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = material(color)
	parent.add_child(m)
	return m


## One shared material per colour: equipment never fades, so sharing is safe.
static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.15 if color == GLASS else 0.7
	mat.metallic = 0.4 if color == GLASS or color == STEEL else 0.0
	_materials[key] = mat
	return mat


static func _unit_box() -> BoxMesh:
	if not _box_mesh:
		_box_mesh = BoxMesh.new()
	return _box_mesh


## 14 sides, or 8 for the small ones (pins, rollers, ropes' hubs) where nobody
## can count them from a site camera.
static func _unit_cylinder(small := false) -> CylinderMesh:
	if small and _cyl_mesh_small:
		return _cyl_mesh_small
	if not small and _cyl_mesh:
		return _cyl_mesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8 if small else 14
	mesh.rings = 1
	if small:
		_cyl_mesh_small = mesh
	else:
		_cyl_mesh = mesh
	return mesh
