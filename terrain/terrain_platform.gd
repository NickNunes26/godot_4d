@tool
class_name TerrainPlatform
extends Resource

## One levelled area cut and filled into the terrain: a building pad, an
## excavation pit, a road bed. ConstructionTerrain applies its `platforms` in
## order (a pit listed after the pad is dug into the pad); with none, the
## ground stays natural -- which is right for a bridge over a valley.
##
## Everything is in the parts container's space (the model's own axes), so the
## platform moves with the model when its georeference is edited, and "level"
## reads like a level in the model: a platform at the bottom of the ground slab
## is at that slab's local Y.
##
## The ground inside `footprint` is set to `level`. Outside it, banks at
## `bank_slope` (horizontal per 1 vertical) run from the edge until they meet
## the natural ground: cut where the ground was higher, fill where it was lower.

## Shown in the inspector and in reports only.
@export var name: String = "":
	set(value):
		name = value
		emit_changed()
@export var enabled: bool = true:
	set(value):
		enabled = value
		emit_changed()
## Outline in the parts container's X/Z plane (Vector2(x, z)), metres, at least
## three points, either winding.
@export var footprint: PackedVector2Array = PackedVector2Array():
	set(value):
		footprint = value
		emit_changed()
## Height of the levelled surface in the parts container's Y, metres.
@export var level: float = 0.0:
	set(value):
		level = value
		emit_changed()
## Banks: metres of horizontal run per metre of height (1.5 = a usual earth
## slope, 0.5 = a steep excavation face). 0 leaves the edge as steep as the
## 5 m terrain grid can make it.
@export_range(0.0, 10.0, 0.05, "or_greater") var bank_slope: float = 1.5:
	set(value):
		bank_slope = value
		emit_changed()
## Schedule action ids (construction_steps.json "id") that do this earthwork.
## On the timeline the ground changes from natural to levelled between the
## earliest start and the latest finish among them. Empty (or no id found in
## the schedule): the platform is there from day 0.
@export var activities: PackedStringArray = PackedStringArray():
	set(value):
		activities = value
		emit_changed()
## Schedule action ids that fill it back in -- the pit dug for a footing, filled
## once the footing and the first lift of its column stand above the ground.
## Between the earliest start and the latest finish among them the ground goes
## back from levelled to natural. Empty: it stays levelled.
@export var backfill_activities: PackedStringArray = PackedStringArray():
	set(value):
		backfill_activities = value
		emit_changed()
## Show the levelled area and its banks as bare earth instead of the orthophoto.
@export var bare_earth: bool = true:
	set(value):
		bare_earth = value
		emit_changed()

## 0 (natural ground) .. 1 (levelled) on `day` of `schedule`: up over its
## activities, and back down over its backfill_activities if it has any. With
## no schedule (the finished site) a backfilled platform is natural ground.
func progress_on(schedule: ConstructionSchedule, day: float) -> float:
	var back := _window(backfill_activities, schedule)
	if not schedule:
		return 0.0 if not backfill_activities.is_empty() else 1.0
	if not is_nan(back.x) and day > back.x:
		return 0.0 if day >= back.y else 1.0 - (day - back.x) / maxf(back.y - back.x, 1e-6)
	var dig := _window(activities, schedule)
	if is_nan(dig.x):
		return 1.0
	if day <= dig.x:
		return 0.0
	if day >= dig.y:
		return 1.0
	return (day - dig.x) / maxf(dig.y - dig.x, 1e-6)

## (earliest start, latest finish) of `ids` in `schedule`; NAN when none is in it.
static func _window(ids: PackedStringArray, schedule: ConstructionSchedule) -> Vector2:
	if ids.is_empty() or not schedule:
		return Vector2(NAN, NAN)
	var start := INF
	var finish := -INF
	for id in ids:
		var span := schedule.get_action_day_range(id)
		if span.is_empty():
			continue
		start = minf(start, span.start_day)
		finish = maxf(finish, span.finish_day)
	return Vector2(start, finish) if start != INF else Vector2(NAN, NAN)
