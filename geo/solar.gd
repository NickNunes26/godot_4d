@tool
class_name Solar
extends RefCounted

## Sun position from date, time and place (NOAA's low-precision formulas,
## about 0.5 degrees -- plenty to light a scene), plus the local-time helpers
## needed to turn "11:00 on the schedule's date" into UTC.

## {elevation, azimuth} in radians for a UTC unix time. Azimuth is measured
## from grid north, clockwise (east = PI/2); elevation is above the horizon.
static func position(lat: float, lon: float, unix_utc: float) -> Dictionary:
	var dt := Time.get_datetime_dict_from_unix_time(int(floorf(unix_utc)))
	var start := Time.get_unix_time_from_datetime_dict({"year": dt.year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var day_of_year := int(floorf((unix_utc - start) / 86400.0)) + 1
	var h := (unix_utc - floorf(unix_utc / 86400.0) * 86400.0) / 3600.0
	var g := TAU / 365.0 * (day_of_year - 1 + (h - 12.0) / 24.0)
	var eqt := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) + 0.000907 * sin(2.0 * g) \
		- 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var ha := deg_to_rad((h * 60.0 + eqt + 4.0 * lon) / 4.0 - 180.0)
	var la := deg_to_rad(lat)
	var el := asin(clampf(sin(la) * sin(decl) + cos(la) * cos(decl) * cos(ha), -1.0, 1.0))
	var az := fposmod(atan2(sin(ha), cos(ha) * sin(la) - tan(decl) * cos(la)) + PI, TAU)
	return {"elevation": el, "azimuth": az}

## Unit vector pointing *towards* the sun in the map frame used by GeoOrigin
## (+X = east, +Y = up, -Z = north).
static func direction_to_sun(elevation: float, azimuth: float) -> Vector3:
	var ce := cos(elevation)
	return Vector3(ce * sin(azimuth), sin(elevation), -ce * cos(azimuth))

## EU summer time: from 01:00 UTC on the last Sunday of March to 01:00 UTC on
## the last Sunday of October (the rule every EU country follows).
static func is_eu_summer_time(unix_utc: float) -> bool:
	var year: int = Time.get_datetime_dict_from_unix_time(int(floorf(unix_utc))).year
	return unix_utc >= _last_sunday_1utc(year, 3) and unix_utc < _last_sunday_1utc(year, 10)

## UTC unix time of a local wall-clock time. `std_offset_hours` is the zone's
## winter offset (Spain mainland and most of central Europe: +1; Canary
## Islands, Portugal: 0); `eu_dst` adds the EU summer hour when in force.
static func local_to_unix(year: int, month: int, day: int, local_hours: float, std_offset_hours: float, eu_dst: bool) -> float:
	var midnight := float(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0}))
	var t := midnight + (local_hours - std_offset_hours) * 3600.0
	if eu_dst and is_eu_summer_time(t):
		t -= 3600.0
	return t

static func _last_sunday_1utc(year: int, month: int) -> float:
	var last := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 31, "hour": 1, "minute": 0, "second": 0})
	var weekday: int = Time.get_datetime_dict_from_unix_time(last).weekday # 0 = Sunday
	return float(last - weekday * 86400)
