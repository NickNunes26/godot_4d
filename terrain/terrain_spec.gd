@tool
class_name TerrainSpec
extends RefCounted

## What to download: a square of terrain on a UTM grid, centred on a whole-metre
## point, plus the two orthophoto squares draped over it.
##
## Defaults are the reference workflow's (4.2 km of 5 m elevation, a 1 km
## detail orthophoto at 0.25 m/px and a 4 km context orthophoto at 1 m/px).

var zone: int = 0
var south: bool = false
var center_e: float = 0.0
var center_n: float = 0.0
## Half the side of the elevation square, metres.
var dem_half: float = 2100.0
## Elevation grid spacing, metres.
var cell: float = 5.0
## Half sides of the detail / context orthophotos (0 = don't download).
var detail_half: float = 500.0
var context_half: float = 2000.0
## Orthophoto size in pixels (the Spanish WMS caps a side at 4096).
var ortho_px: int = 4000

const PRESETS := {
	"small": {"label": "Reducido (2 km)", "dem_half": 1000.0, "cell": 5.0, "detail_half": 500.0, "context_half": 1000.0, "ortho_px": 4000},
	"standard": {"label": "Estándar (4,2 km)", "dem_half": 2100.0, "cell": 5.0, "detail_half": 500.0, "context_half": 2000.0, "ortho_px": 4000},
	"large": {"label": "Amplio (8 km)", "dem_half": 4000.0, "cell": 10.0, "detail_half": 500.0, "context_half": 4000.0, "ortho_px": 4000},
}
const DEFAULT_PRESET := "standard"

static func create(zone_: int, e: float, n: float, preset: String = DEFAULT_PRESET, south_ := false) -> TerrainSpec:
	var s := TerrainSpec.new()
	s.zone = zone_
	s.south = south_
	s.center_e = roundf(e)
	s.center_n = roundf(n)
	var p: Dictionary = PRESETS.get(preset, PRESETS[DEFAULT_PRESET])
	s.dem_half = p.dem_half
	s.cell = p.cell
	s.detail_half = p.detail_half
	s.context_half = p.context_half
	s.ortho_px = p.ortho_px
	return s

## Grid points per side.
func grid_n() -> int:
	return int(round(2.0 * dem_half / cell))

## Cache folder name: changes whenever anything that changes the download does.
func key() -> String:
	return "utm%d%s_%d_%d_%d_%s" % [zone, "s" if south else "", int(center_e), int(center_n), int(dem_half * 2.0), str(cell).replace(".", "p")]

## Easting of grid column `col` / northing of grid row `row` (row 0 = north edge).
func grid_e(col: int) -> float:
	return center_e - dem_half + (col + 0.5) * cell

func grid_north(row: int) -> float:
	return center_n + dem_half - (row + 0.5) * cell

## [min_lat, max_lat, min_lon, max_lon] of the square, padded by `pad_deg`.
## Corners and edge midpoints are all checked, since grid north and true north
## differ away from the central meridian.
func geo_bounds(half: float, pad_deg: float = 0.002) -> PackedFloat64Array:
	var lat_min := INF
	var lat_max := -INF
	var lon_min := INF
	var lon_max := -INF
	for dx in [-1.0, 0.0, 1.0]:
		for dy in [-1.0, 0.0, 1.0]:
			var g := Utm.to_geo(center_e + dx * half, center_n + dy * half, zone, south)
			lat_min = minf(lat_min, g.lat)
			lat_max = maxf(lat_max, g.lat)
			lon_min = minf(lon_min, g.lon)
			lon_max = maxf(lon_max, g.lon)
	return PackedFloat64Array([lat_min - pad_deg, lat_max + pad_deg, lon_min - pad_deg, lon_max + pad_deg])

## {lat, lon} of the centre.
func center_geo() -> Dictionary:
	return Utm.to_geo(center_e, center_n, zone, south)

## Latitude/longitude of every grid point, row-major from the north-west
## corner. Exact conversions on a coarse lattice, bilinear in between: the
## mapping is smooth enough that the error is sub-millimetre, and it is ~250x
## fewer trig-heavy conversions than doing every point.
func geo_grid() -> Dictionary:
	var n := grid_n()
	var step := 16
	var cn := int(ceil(float(n - 1) / step)) + 1
	var clat := PackedFloat64Array()
	var clon := PackedFloat64Array()
	clat.resize(cn * cn)
	clon.resize(cn * cn)
	for r in cn:
		for c in cn:
			var g := Utm.to_geo(grid_e(mini(c * step, n - 1)), grid_north(mini(r * step, n - 1)), zone, south)
			clat[r * cn + c] = g.lat
			clon[r * cn + c] = g.lon
	var lat := PackedFloat64Array()
	var lon := PackedFloat64Array()
	lat.resize(n * n)
	lon.resize(n * n)
	for row in n:
		var r0 := mini(floori(float(row) / step), cn - 2)
		var r_span := float(mini((r0 + 1) * step, n - 1) - r0 * step)
		var fr := (row - r0 * step) / r_span
		for col in n:
			var c0 := mini(floori(float(col) / step), cn - 2)
			var c_span := float(mini((c0 + 1) * step, n - 1) - c0 * step)
			var fc := (col - c0 * step) / c_span
			var i00 := r0 * cn + c0
			var i := row * n + col
			lat[i] = lerpf(lerpf(clat[i00], clat[i00 + 1], fc), lerpf(clat[i00 + cn], clat[i00 + cn + 1], fc), fr)
			lon[i] = lerpf(lerpf(clon[i00], clon[i00 + 1], fc), lerpf(clon[i00 + cn], clon[i00 + cn + 1], fc), fr)
	return {"lat": lat, "lon": lon}
