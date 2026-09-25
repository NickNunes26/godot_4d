@tool
class_name GeoSun
extends DirectionalLight3D

## A sun that stands where the real one would over the site on the timeline's
## current date, at a fixed time of day. SequenceManager (at runtime) and the
## editor dock (during Start Preview) push the date in; nothing moves on its own.
##
## Only the calendar date is used, never the fractional day: playback runs at
## days per second, and a sun sweeping through day and night several times a
## second would be useless as lighting.
##
## Position on Earth and orientation come from SequenceManager's GeoOrigin;
## with no georeference it falls back to `fallback_lat_lon` and treats -Z as north.

const GROUP := "construction_4d_geo_sun"

## Follow the schedule date. Off: the light is left exactly as you set it.
@export var follow_schedule: bool = true
## Local clock time the scene is lit at, in hours (11.5 = 11:30).
@export_range(0.0, 24.0, 0.25) var time_of_day: float = 11.0:
	set(value):
		time_of_day = value
		_refresh()
## Winter (standard) UTC offset of the site: +1 mainland Spain and most of
## central Europe, 0 for Portugal and the Canary Islands.
@export_range(-12.0, 14.0, 0.5) var utc_offset_hours: float = 1.0:
	set(value):
		utc_offset_hours = value
		_refresh()
## Apply the EU summer-time rule (last Sunday of March to last Sunday of October).
@export var eu_summer_time: bool = true:
	set(value):
		eu_summer_time = value
		_refresh()
## Used when no GeoOrigin is available.
@export var fallback_lat_lon := Vector2(40.4, -3.7)
## The SequenceManager whose GeoOrigin locates the site (empty: search the scene).
@export var sequence_manager_path: NodePath

var _date := {} # {year, month, day} last applied

func _enter_tree() -> void:
	add_to_group(GROUP)

## Sets the date from a unix time (only its calendar date is used).
func set_date_from_unix(unix: float) -> void:
	var d := Time.get_datetime_dict_from_unix_time(int(floor(unix)))
	set_date(d.year, d.month, d.day)

func set_date(year: int, month: int, day: int) -> void:
	if not follow_schedule:
		return
	var key := {"year": year, "month": month, "day": day}
	if key == _date:
		return
	_date = key
	_refresh()

func _refresh() -> void:
	if _date.is_empty() or not is_inside_tree():
		return
	var geo := _geo_origin()
	var lat := fallback_lat_lon.x
	var lon := fallback_lat_lon.y
	var frame := Basis()
	if geo and geo.is_located():
		var ll := geo.lat_lon()
		lat = ll.lat
		lon = ll.lon
		frame = _map_frame_basis(geo)
	var unix := Solar.local_to_unix(_date.year, _date.month, _date.day, time_of_day, utc_offset_hours, eu_summer_time)
	var sun := Solar.position(lat, lon, unix)
	var to_sun := (frame * Solar.direction_to_sun(sun.elevation, sun.azimuth)).normalized()
	# A light shines along its -Z; below the horizon, keep a grazing light rather than lighting from underneath.
	if to_sun.y < 0.02:
		to_sun = Vector3(to_sun.x, 0.02, to_sun.z).normalized()
	var up := Vector3.UP if absf(to_sun.y) < 0.999 else Vector3.FORWARD
	global_basis = Basis.looking_at(-to_sun, up)

## The map frame's orientation in global space (east/up/south axes).
func _map_frame_basis(geo: GeoOrigin) -> Basis:
	var sm := _sequence_manager()
	var container: Node3D = null
	if sm and sm.get("parts_container_path") is NodePath and not sm.get("parts_container_path").is_empty():
		container = sm.get_node_or_null(sm.get("parts_container_path")) as Node3D
	var base := container.global_basis if container else Basis()
	return (base * geo.map_frame_transform().basis).orthonormalized()

func _geo_origin() -> GeoOrigin:
	var sm := _sequence_manager()
	if sm and sm.get("geo_origin") is GeoOrigin:
		return sm.get("geo_origin")
	return null

func _sequence_manager() -> Node:
	if not sequence_manager_path.is_empty():
		return get_node_or_null(sequence_manager_path)
	var root := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	return _find_with_property(root, "geo_origin") if root else null

static func _find_with_property(node: Node, prop: String) -> Node:
	if node.get_script() and prop in node:
		return node
	for child in node.get_children():
		var found := _find_with_property(child, prop)
		if found:
			return found
	return null

## Pushes a unix time into every GeoSun in the tree.
static func update_all(tree: SceneTree, unix: float) -> void:
	for sun in tree.get_nodes_in_group(GROUP):
		(sun as GeoSun).set_date_from_unix(unix)
