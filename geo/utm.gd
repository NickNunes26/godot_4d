@tool
class_name Utm
extends RefCounted

## UTM <-> geographic conversion on the GRS80 ellipsoid (ETRS89, which is what
## European national mapping agencies publish in; WGS84 differs by well under a
## millimetre in these formulas, so this is also fine for global data).
##
## Plain transverse-Mercator series (Snyder, "Map Projections -- A Working
## Manual", eqs. 8-9 .. 8-25): millimetre-level agreement within a zone, which
## is far below the 5 m grid of any terrain this tool downloads.
##
## All values are GDScript `float`, i.e. 64-bit. Never route eastings/northings
## through Vector2/Vector3: those are 32-bit and lose ~0.5 m at northings of
## 4.7 million.

const A := 6378137.0
const F := 1.0 / 298.257222101
const K0 := 0.9996
const FALSE_EASTING := 500000.0
const FALSE_NORTHING_SOUTH := 10000000.0

static func _e2() -> float:
	return F * (2.0 - F)

## Central meridian of a zone, in degrees.
static func central_meridian(zone: int) -> float:
	return zone * 6.0 - 183.0

## The standard zone for a longitude (no Norway/Svalbard exceptions).
static func zone_for_lon(lon: float) -> int:
	return clampi(int(floor((lon + 180.0) / 6.0)) + 1, 1, 60)

## (easting, northing, zone) -> {lat, lon} in degrees.
static func to_geo(easting: float, northing: float, zone: int, south := false) -> Dictionary:
	var e2 := _e2()
	var ep2 := e2 / (1.0 - e2)
	var x := easting - FALSE_EASTING
	var y := northing - (FALSE_NORTHING_SOUTH if south else 0.0)
	var m := y / K0
	var mu := m / (A * (1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0))
	var e1 := (1.0 - sqrt(1.0 - e2)) / (1.0 + sqrt(1.0 - e2))
	var p1 := mu + (3.0 * e1 / 2.0 - 27.0 * pow(e1, 3) / 32.0) * sin(2.0 * mu) \
		+ (21.0 * e1 * e1 / 16.0 - 55.0 * pow(e1, 4) / 32.0) * sin(4.0 * mu) \
		+ (151.0 * pow(e1, 3) / 96.0) * sin(6.0 * mu) \
		+ (1097.0 * pow(e1, 4) / 512.0) * sin(8.0 * mu)
	var sp := sin(p1)
	var cp := cos(p1)
	var c1 := ep2 * cp * cp
	var t1 := tan(p1) * tan(p1)
	var n1 := A / sqrt(1.0 - e2 * sp * sp)
	var r1 := A * (1.0 - e2) / pow(1.0 - e2 * sp * sp, 1.5)
	var d := x / (n1 * K0)
	var lat := p1 - (n1 * tan(p1) / r1) * (d * d / 2.0
		- (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1 * c1 - 9.0 * ep2) * pow(d, 4) / 24.0
		+ (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1 * t1 - 252.0 * ep2 - 3.0 * c1 * c1) * pow(d, 6) / 720.0)
	var lon := (d - (1.0 + 2.0 * t1 + c1) * pow(d, 3) / 6.0
		+ (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1 * c1 + 8.0 * ep2 + 24.0 * t1 * t1) * pow(d, 5) / 120.0) / cp
	return {"lat": rad_to_deg(lat), "lon": central_meridian(zone) + rad_to_deg(lon)}

## (lat, lon) in degrees -> {easting, northing} in `zone` (which may be a
## neighbouring zone, as national grids often extend one past its edge).
static func from_geo(lat: float, lon: float, zone: int) -> Dictionary:
	var e2 := _e2()
	var ep2 := e2 / (1.0 - e2)
	var phi := deg_to_rad(lat)
	var sp := sin(phi)
	var cp := cos(phi)
	var n := A / sqrt(1.0 - e2 * sp * sp)
	var t := tan(phi) * tan(phi)
	var c := ep2 * cp * cp
	var a := cp * deg_to_rad(lon - central_meridian(zone))
	var e4 := e2 * e2
	var e6 := e4 * e2
	var m := A * ((1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * phi
		- (3.0 * e2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * sin(2.0 * phi)
		+ (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * sin(4.0 * phi)
		- (35.0 * e6 / 3072.0) * sin(6.0 * phi))
	var easting := FALSE_EASTING + K0 * n * (a + (1.0 - t + c) * pow(a, 3) / 6.0
		+ (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * ep2) * pow(a, 5) / 120.0)
	var northing := K0 * (m + n * tan(phi) * (a * a / 2.0
		+ (5.0 - t + 9.0 * c + 4.0 * c * c) * pow(a, 4) / 24.0
		+ (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * ep2) * pow(a, 6) / 720.0))
	if lat < 0.0:
		northing += FALSE_NORTHING_SOUTH
	return {"easting": easting, "northing": northing}

## The UTM zone written in a CRS name or map-zone string: the last number in
## it, with EPSG codes of the 258zz / 326zz / 327zz families reduced to zz
## ("EPSG:25830" -> 30, "UTM zone 30N" -> 30, "30" -> 30). 0 if none.
static func zone_from_crs_text(text: String) -> int:
	var re := RegEx.new()
	re.compile("\\d+")
	var found := re.search_all(text)
	if found.is_empty():
		return 0
	var z := found[found.size() - 1].get_string().to_int()
	if z > 1000:
		z = z % 100
	return z if z >= 1 and z <= 60 else 0
