## An ordered list of camera keyframes -- "on this date the camera is here" --
## and the interpolation that turns them into a pose for any day in between.
##
## Kept in its own `camera_track.json`, deliberately NOT as a key inside
## construction_steps.json: that file is regenerated wholesale from the IFC by
## IFCScheduleGenerator, and camera work is hand-authored. Two feature-2
## geometry lists already have to be explicitly carried across a regeneration
## to survive it; a camera track is far more laborious to author and there is
## no reason to expose it to that hazard at all when a separate file removes it
## completely.
##
## Pure data + math, with no reference to a Camera3D or to the scene tree --
## CameraDriver (camera_driver.gd) is what applies a sample to an actual
## camera, and the Phase 3 dock writes keyframes into this without ever
## instantiating a driver.
##
## File shape:
##
##     {
##       "keyframes": [
##         {
##           "date": "2026-04-14",       # or "day": 0.0 -- see _resolve_day()
##           "position": [40.0, 25.0, 60.0],
##           "rotation": [-15.0, 33.0, 0.0],   # euler degrees, YXZ (Godot's default)
##           "fov": 70.0,                # optional
##           "hold_days": 5.0,           # optional, see sample()
##           "cut": false,               # optional, see sample()
##           "comment": "wide establishing shot"
##         }
##       ]
##     }
##
## Euler degrees rather than a Transform3D literal or a quaternion because this
## file is meant to stay hand-editable: nudging a shot ten degrees left should
## not require recomputing a basis. The dock's Capture button writes the same
## shape, so captured and hand-written keyframes are indistinguishable.
class_name CameraTrack
extends RefCounted

## Raw JSON keyframe dictionaries, exactly as loaded/saved. Kept separate from
## the resolved list below so save_to() round-trips anything this class doesn't
## understand (comments, future fields) instead of silently dropping it.
var keyframes: Array = []

## resolve()'s output: the same keyframes with dates turned into day numbers,
## euler degrees into a Basis, and every optional field defaulted -- sorted by
## day. Empty until resolve() has been called.
var _resolved: Array = []


static func load_from(path: String) -> CameraTrack:
	var track := CameraTrack.new()
	if not FileAccess.file_exists(path):
		return track
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("CameraTrack: could not open '%s'" % path)
		return track
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("CameraTrack: '%s' is not a JSON object, ignoring" % path)
		return track
	var raw = parsed.get("keyframes", [])
	if not (raw is Array):
		push_warning("CameraTrack: '%s' has no \"keyframes\" array, ignoring" % path)
		return track
	for entry in raw:
		if entry is Dictionary:
			track.keyframes.append(entry)
	return track


func save_to(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"keyframes": keyframes}, "\t"))
	file.close()
	return OK


## True when there is nothing to drive the camera with -- the case movie mode
## treats as "leave the camera exactly where the scene put it".
func is_empty() -> bool:
	return _resolved.is_empty()


func size() -> int:
	return _resolved.size()


## Turns the raw keyframes into something samplable, using `schedule` to
## convert `"date"` strings into the same relative day numbers
## TimelineController.current_day speaks in. Must be called before sample().
##
## A keyframe whose date can't be resolved is dropped with a warning rather
## than defaulting to day 0 -- silently parking a shot at the start of the
## project is far worse than losing it, because it would drag the camera there
## and look like a bug in the interpolation.
func resolve(schedule: ConstructionSchedule) -> void:
	_resolved.clear()
	for i in range(keyframes.size()):
		var kf: Dictionary = keyframes[i]
		var day = _resolve_day(kf, schedule)
		if day == null:
			push_warning("CameraTrack: keyframe %d has no usable \"date\"/\"day\", skipped" % i)
			continue
		_resolved.append({
			"day": float(day),
			"position": _to_vector3(kf.get("position", [0, 0, 0])),
			"basis": Basis.from_euler(_to_vector3(kf.get("rotation", [0, 0, 0])) * (PI / 180.0)),
			# null (not a number) means "this keyframe doesn't change the fov",
			# which CameraDriver fills in from the camera's own starting value.
			# A default of 75 here would silently re-frame every shot in a track
			# authored without fov in mind.
			"fov": float(kf["fov"]) if kf.has("fov") else null,
			"hold_days": maxf(float(kf.get("hold_days", 0.0)), 0.0),
			"cut": bool(kf.get("cut", false)),
		})
	_resolved.sort_custom(func(a, b): return a.day < b.day)

	# Forward-fill fov: a keyframe that doesn't mention fov keeps whatever the
	# last one that did set, rather than reverting to the camera's own. Without
	# this, a track that pulls in to 30 and then has any later keyframe silently
	# pops back to the scene's fov the instant that keyframe is reached -- the
	# segment before it already interpolates toward the carried-forward value,
	# so the jump lands exactly on the keyframe and reads as a glitch.
	# Keyframes before the first one to specify an fov stay null, which
	# CameraDriver fills from the camera's own starting value.
	var carried = null
	for kf in _resolved:
		if kf.fov == null:
			kf.fov = carried
		else:
			carried = kf.fov


## Accepts either a literal `"day"` number or a `"date"` string, since a track
## may be hand-written against either. Dates are the authored form (the dock
## writes them, and a schedule is discussed in dates), day numbers exist for a
## schedule with no calendar dates at all, where day_to_date_string() has
## nothing to convert against.
func _resolve_day(kf: Dictionary, schedule: ConstructionSchedule):
	if kf.has("day"):
		return float(kf["day"])
	if not kf.has("date") or not schedule:
		return null
	var epoch := ConstructionSchedule.parse_date_to_epoch(str(kf["date"]))
	if is_nan(epoch) or not schedule.has_calendar_dates():
		return null
	return (epoch - schedule.day_to_epoch(0.0)) / 86400.0


static func _to_vector3(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


## The camera pose at `day`: {position, basis, fov} -- fov null when no
## keyframe in play sets one. Returns {} for an empty track.
##
## Semantics, which the spec left open as "arrive at this date" vs "stay from
## this date": **both**, explicitly. A keyframe means *be here on this date*
## (the standard keyframe reading, and what "on day X the camera is here" says
## literally), and `hold_days` then keeps it there for that many days before
## the move to the next one starts. Defaulting hold_days to 0 makes a track
## authored without thinking about it behave the obvious way, and one field
## covers the other reading -- the same trade the resolved cuts-vs-moves
## decision made.
##
## Before the first keyframe and after the last, the nearest one is held rather
## than extrapolated: a camera drifting off into space either side of the
## authored range would be nobody's intent.
func sample(day: float) -> Dictionary:
	if _resolved.is_empty():
		return {}
	if day <= _resolved[0].day:
		return _pose(_resolved[0])

	var index := 0
	for i in range(_resolved.size()):
		if _resolved[i].day <= day:
			index = i
	if index >= _resolved.size() - 1:
		return _pose(_resolved[index])

	var from: Dictionary = _resolved[index]
	var to: Dictionary = _resolved[index + 1]

	# A cut is a hard switch at the target keyframe's own date: hold the
	# previous pose right up to it, then be somewhere else on the next frame.
	# That is the whole point -- a glide across the site to reach a close-up
	# would waste ten seconds of video.
	if to.cut:
		return _pose(from)

	var move_start: float = from.day + from.hold_days
	if day <= move_start:
		return _pose(from)
	var span: float = to.day - move_start
	if span <= 0.0:
		# hold_days runs past the next keyframe -- an authoring mistake, but a
		# recoverable one: honor the next keyframe's date and drop the overrun
		# rather than dividing by zero or overshooting past it.
		return _pose(to)

	var t: float = clampf((day - move_start) / span, 0.0, 1.0)
	# Ease in and out, so a move starts and stops smoothly instead of changing
	# velocity abruptly at every key -- with linear t, a track of several
	# keyframes reads as a series of jerks even though each segment is smooth.
	t = t * t * (3.0 - 2.0 * t)

	var fov = to.fov if to.fov != null else from.fov
	if from.fov != null and to.fov != null:
		fov = lerpf(from.fov, to.fov, t)

	return {
		"position": from.position.lerp(to.position, t),
		# slerp via Quaternion rather than lerping the basis vectors: a
		# component-wise basis blend does not stay orthonormal, which shears
		# the view partway through every move.
		"basis": Basis(Quaternion(from.basis).slerp(Quaternion(to.basis), t)),
		"fov": fov,
	}


func _pose(kf: Dictionary) -> Dictionary:
	return {"position": kf.position, "basis": kf.basis, "fov": kf.fov}


## Appends a keyframe in the file's own shape. Used by the Phase 3 dock's
## Capture button; `date` may be "" for a schedule with no calendar dates, in
## which case the day number is written instead (see _resolve_day()).
##
## Does not sort -- call sort_by_day() before saving. Playback never depends on
## file order (resolve() sorts its own list), so this is purely so the file
## stays readable in the order the shots actually happen.
func add_keyframe(day: float, date: String, transform: Transform3D, fov: float, comment: String = "") -> Dictionary:
	var euler := transform.basis.get_euler() * (180.0 / PI)
	var kf := {
		"position": [
			snappedf(transform.origin.x, 0.001),
			snappedf(transform.origin.y, 0.001),
			snappedf(transform.origin.z, 0.001),
		],
		"rotation": [
			snappedf(euler.x, 0.01),
			snappedf(euler.y, 0.01),
			snappedf(euler.z, 0.01),
		],
		"fov": snappedf(fov, 0.01),
	}
	if date != "":
		kf["date"] = date
	else:
		kf["day"] = snappedf(day, 0.01)
	if comment != "":
		kf["comment"] = comment
	keyframes.append(kf)
	return kf


## Orders the raw keyframes by resolved day, so the saved file reads in the
## order the shots happen. Anything unresolvable sorts to the end rather than
## to day 0, where it would look like a deliberate opening shot.
func sort_by_day(schedule: ConstructionSchedule) -> void:
	keyframes.sort_custom(func(a, b):
		var da = _resolve_day(a, schedule)
		var db = _resolve_day(b, schedule)
		if da == null:
			return false
		if db == null:
			return true
		return float(da) < float(db))
