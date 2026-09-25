@tool
class_name GeoOrigin
extends Resource

## Where a model sits on Earth: the projected-map (UTM) coordinates of the
## parts container's local origin, plus how its axes turn onto the map.
##
## Kept on SequenceManager (`geo_origin`) so it is saved with the scene and
## editable in the inspector. Every coordinate is a 64-bit float; nothing here
## ever becomes a vertex or node position at map magnitude (see GDIFCRecenter
## for why that matters).
##
## Axes. GDIFC (web-ifc) turns IFC (x = east, y = north, z = up) into Godot
## (x, z, -y): east = +X, up = +Y, north = -Z. Verified on Godot 4.6.2 with a
## box whose IFC extent is x 109..111, y 218.5..221.5, z 55..59 -- it loads as
## X 109..111, Y 55..59, Z -221.5..-218.5.
##
## Map conversion. A container-local point p is, in IFC axes relative to the
## origin, (i, j, k) = (p.x, -p.z, p.y); on the map
##   E = easting  + scale * (i * cos(r) - j * sin(r))
##   N = northing + scale * (i * sin(r) + j * cos(r))
##   H = height   + scale * k
## with r = rotation_deg, the grid bearing of the model's local +x measured
## counter-clockwise from grid east (IfcMapConversion's XAxisAbscissa/Ordinate).

## Grid easting of the container's local origin, metres.
@export var easting: float = 0.0:
	set(value):
		easting = value
		emit_changed()
## Grid northing of the container's local origin, metres.
@export var northing: float = 0.0:
	set(value):
		northing = value
		emit_changed()
## Orthometric height of the container's local origin, metres.
@export var height: float = 0.0:
	set(value):
		height = value
		emit_changed()
## Counter-clockwise angle from grid east to the model's local +x axis.
@export var rotation_deg: float = 0.0:
	set(value):
		rotation_deg = value
		emit_changed()
## Map units per model unit (IfcMapConversion.Scale).
@export var scale: float = 1.0:
	set(value):
		scale = value
		emit_changed()
## UTM zone of easting/northing (0 = not known yet).
@export_range(0, 60) var utm_zone: int = 0:
	set(value):
		utm_zone = value
		emit_changed()
## Southern-hemisphere UTM (false northing 10 000 km).
@export var south: bool = false:
	set(value):
		south = value
		emit_changed()
## False when the height is a guess (a model with no georeference placed by
## hand): the terrain tools then offer to sit the model on the ground.
@export var height_known: bool = true:
	set(value):
		height_known = value
		emit_changed()
## Where easting/northing came from: "ifc_map_conversion", "ifc_coordinates",
## "manual", or "" (unknown).
@export var source: String = "":
	set(value):
		source = value
		emit_changed()
## Where the zone came from: "ifc_crs", "auto", "manual", or "".
@export var zone_source: String = "":
	set(value):
		zone_source = value
		emit_changed()
## CRS name as written in the IFC (e.g. "EPSG:25830"), informational.
@export var crs_name: String = "":
	set(value):
		crs_name = value
		emit_changed()

## True when easting/northing and the zone are both known.
func is_located() -> bool:
	return source != "" and utm_zone > 0

## True when easting/northing are known, whatever the zone.
func has_position() -> bool:
	return source != ""

## Container-local point -> [E, N, H].
func local_to_map(p: Vector3) -> PackedFloat64Array:
	var r := deg_to_rad(rotation_deg)
	var i := float(p.x)
	var j := -float(p.z)
	var k := float(p.y)
	return PackedFloat64Array([
		easting + scale * (i * cos(r) - j * sin(r)),
		northing + scale * (i * sin(r) + j * cos(r)),
		height + scale * k])

## [E, N, H] -> container-local point. Only meaningful near the origin (the
## result is 32-bit).
func map_to_local(e: float, n: float, h: float) -> Vector3:
	var r := deg_to_rad(rotation_deg)
	var de := (e - easting) / scale
	var dn := (n - northing) / scale
	var i := de * cos(r) + dn * sin(r)
	var j := -de * sin(r) + dn * cos(r)
	return Vector3(i, (h - height) / scale, -j)

## Whether `other` is on the same map grid as this origin, so that
## relative_transform() is exact: both have a position, same hemisphere, and
## the same UTM zone (an unknown zone on either side is taken to be the other's
## -- models of one site share a grid).
func same_map_as(other: GeoOrigin) -> bool:
	return other != null and has_position() and other.has_position() and south == other.south \
		and (utm_zone == 0 or other.utm_zone == 0 or utm_zone == other.utm_zone)

## Takes points from `other`'s container-local space into this one's: the
## transform to give a second model's container (relative to this origin's
## container) so both sit where the map says. Rotation and scale differences
## between the two map conversions are included. Check same_map_as() first.
func relative_transform(other: GeoOrigin) -> Transform3D:
	var p := other.local_to_map(Vector3.ZERO)
	var basis := Basis(Vector3.UP, deg_to_rad(other.rotation_deg - rotation_deg)).scaled(Vector3.ONE * (other.scale / scale))
	return Transform3D(basis, map_to_local(p[0], p[1], p[2]))

## The map frame anchored at (easting, northing, height), expressed in the
## container's local space: +X = grid east, +Y = up, -Z = grid north, metres.
## A node given this transform (relative to the container's parent frame:
## container.transform * this) can place map-aligned content -- terrain, the
## sun -- in plain metre offsets from the origin.
func map_frame_transform() -> Transform3D:
	var r := deg_to_rad(rotation_deg)
	var c := cos(r) / scale
	var s := sin(r) / scale
	var basis := Basis(Vector3(c, 0.0, s), Vector3(0.0, 1.0 / scale, 0.0), Vector3(-s, 0.0, c))
	return Transform3D(basis, Vector3.ZERO)

## {lat, lon} of the origin, or {} when not located.
func lat_lon() -> Dictionary:
	if not is_located():
		return {}
	return Utm.to_geo(easting, northing, utm_zone, south)

## Builds an origin from what GDIFCRecenter.recenter_with_info() found and the
## framing shift the import applied afterwards (`godot_shift`: the Godot-space
## vector that was *subtracted* from every part so the model sits around the
## container origin).
static func from_ifc_import(info: Dictionary, godot_shift: Vector3) -> GeoOrigin:
	var o := GeoOrigin.new()
	var ro: PackedFloat64Array = info.get("root_offset", PackedFloat64Array([0.0, 0.0, 0.0]))
	# Undo the framing shift in IFC axes, then put back what was stripped from
	# the root placement: this is the container origin in the file's own
	# (pre-map-conversion) coordinates.
	var ix := float(godot_shift.x) + ro[0]
	var iy := -float(godot_shift.z) + ro[1]
	var iz := float(godot_shift.y) + ro[2]
	var mc: Dictionary = info.get("map_conversion", {})
	var zone: int = info.get("crs_zone", 0)
	o.crs_name = info.get("crs_name", "")
	if not mc.is_empty():
		var ca: float = mc.abscissa
		var sa: float = mc.ordinate
		var norm := sqrt(ca * ca + sa * sa)
		if norm < 1e-12:
			ca = 1.0
			sa = 0.0
		else:
			ca /= norm
			sa /= norm
		o.scale = mc.scale
		o.rotation_deg = rad_to_deg(atan2(sa, ca))
		o.easting = mc.e + o.scale * (ix * ca - iy * sa)
		o.northing = mc.n + o.scale * (ix * sa + iy * ca)
		o.height = mc.h + o.scale * iz
		# A map conversion at 0,0 with no CRS is an exporter's placeholder, not a location.
		if absf(mc.e) > 0.0 or absf(mc.n) > 0.0 or zone != 0:
			o.source = "ifc_map_conversion"
	else:
		o.easting = ix
		o.northing = iy
		o.height = iz
	if o.source == "" and looks_like_utm(o.easting, o.northing):
		o.source = "ifc_coordinates"
	if o.source == "":
		o.height_known = false
	if zone != 0:
		o.utm_zone = zone
		o.zone_source = "ifc_crs"
	return o

## Whether (e, n) are plausible UTM metres (the zone still can't be told from
## them -- the same pair is valid in every zone).
static func looks_like_utm(e: float, n: float) -> bool:
	return e > 100000.0 and e < 900000.0 and n > 0.0 and n < 10000000.0

## One line for the dock.
func describe() -> String:
	if not has_position():
		return "sin georreferencia"
	var s := "E %.1f  N %.1f  H %.1f%s" % [easting, northing, height, "" if height_known else " (?)"]
	s += "  huso %s" % (str(utm_zone) if utm_zone > 0 else "?")
	if not is_zero_approx(rotation_deg):
		s += "  giro %.2f°" % rotation_deg
	return s
