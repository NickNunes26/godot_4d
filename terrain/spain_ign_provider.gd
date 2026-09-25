@tool
class_name SpainIgnProvider
extends TerrainProvider

## Mainland Spain and the Balearic Islands from the Instituto Geográfico
## Nacional's open services (CC BY 4.0):
## - elevation: MDT05 (5 m) through the INSPIRE WCS, delivered in ETRS89
##   geographic degrees (EPSG:4258) as an ASC grid wrapped in multipart MIME;
## - imagery: PNOA "máxima actualidad" through the INSPIRE WMS, requested
##   directly in the project's UTM zone (EPSG:258zz), max 4096 px a side.
## The Canary Islands (zone 28, REGCAN95) are not covered.

const WCS := "https://servicios.idee.es/wcs-inspire/mdt"
const WMS := "https://www.ign.es/wms-inspire/pnoa-ma"
const COVERAGE := "Elevacion4258_5"

func id() -> String:
	return "es_ign"

func display_name() -> String:
	return "IGN España (MDT05 + PNOA)"

func covers(lat: float, lon: float) -> bool:
	return lat > 35.0 and lat < 44.5 and lon > -10.0 and lon < 4.5

func has_imagery() -> bool:
	return true

func attribution() -> String:
	return "© Instituto Geográfico Nacional de España — PNOA / MDT05, CC BY 4.0 (scne.es)"

func candidate_zones() -> Array:
	return [29, 30, 31]

func elevation_downloads(spec: TerrainSpec) -> Array:
	var b := spec.geo_bounds(spec.dem_half)
	return [{"url": wcs_url(b[0], b[1], b[2], b[3]), "file": "dem_wcs.asc", "timeout": 600.0}]

static func wcs_url(lat0: float, lat1: float, lon0: float, lon1: float) -> String:
	return "%s?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage&COVERAGEID=%s&SUBSET=Lat(%.6f,%.6f)&SUBSET=Long(%.6f,%.6f)&FORMAT=application/asc" % [
		WCS, COVERAGE, lat0, lat1, lon0, lon1]

static func wms_url(zone: int, e0: float, n0: float, e1: float, n1: float, px: int) -> String:
	# WMS 1.3.0 with a projected EPSG:258zz CRS: BBOX axis order is E,N.
	return "%s?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=OI.OrthoimageCoverage&STYLES=&CRS=EPSG:258%02d&BBOX=%.2f,%.2f,%.2f,%.2f&WIDTH=%d&HEIGHT=%d&FORMAT=image/jpeg" % [
		WMS, zone, e0, n0, e1, n1, px, px]

func build_heights(spec: TerrainSpec, dir: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(dir.path_join("dem_wcs.asc"))
	var err := {}
	var grid := AscGrid.parse(text, err)
	if grid == null:
		return {"error": "the elevation service returned no grid (%s)" % err.get("message", "")}
	if grid.fill_nodata() == 0:
		return {"error": "the elevation grid is empty: is the site outside Spain?"}
	return {"heights": TerrainBuilder.sample_geographic(grid, spec), "error": ""}

func validate_elevation(path: String) -> String:
	var err := {}
	return "" if AscGrid.parse(FileAccess.get_file_as_string(path), err) else "incomplete or invalid grid: %s" % err.get("message", "")

func ortho_download(spec: TerrainSpec, half: float, name: String) -> Dictionary:
	if half <= 0.0:
		return {}
	var e0 := spec.center_e - half
	var n0 := spec.center_n - half
	var e1 := spec.center_e + half
	var n1 := spec.center_n + half
	return {"url": wms_url(spec.zone, e0, n0, e1, n1, spec.ortho_px), "file": name + ".jpg", "timeout": 300.0,
		"rect": PackedFloat64Array([e0, n0, e1, n1])}

func probe_download(lat: float, lon: float) -> Dictionary:
	var m := 0.0025
	return {"url": wcs_url(lat - m, lat + m, lon - m, lon + m), "file": "probe_%.4f_%.4f.asc" % [lat, lon], "timeout": 120.0}

func probe_height(path: String) -> float:
	var grid := AscGrid.parse(FileAccess.get_file_as_string(path))
	return grid.land_mean() if grid else NAN
