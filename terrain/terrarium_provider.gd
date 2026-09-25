@tool
class_name TerrariumProvider
extends TerrainProvider

## Worldwide elevation, no imagery: the open "Terrain Tiles" dataset on AWS,
## in Terrarium PNG encoding (height = R*256 + G + B/256 - 32768 metres).
## Resolution depends on the region's source data (a few metres to ~30 m);
## zoom 14 is ~9.5 m/px at the equator. Used where no national provider exists.

const TILE_URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const MAX_ZOOM := 14
const MAX_TILES := 25

func id() -> String:
	return "terrarium"

func display_name() -> String:
	return "Terrain Tiles (AWS, mundial, sin ortofoto)"

func covers(lat: float, _lon: float) -> bool:
	return absf(lat) < 85.0

func attribution() -> String:
	return "Elevation: Terrain Tiles (AWS Open Data). ArcticDEM terrain data DEM(s) were created from DigitalGlobe, Inc., imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736; Australia terrain data © Commonwealth of Australia (Geoscience Australia) 2017; Austria terrain data © offene Daten Österreichs – Digitales Geländemodell (DGM) Österreich; Canada terrain data contains information licensed under the Open Government Licence – Canada; Europe terrain data produced using Copernicus data and information funded by the European Union - EU-DEM layers; Global ETOPO1 terrain data U.S. National Oceanic and Atmospheric Administration; Mexico terrain data source: INEGI, Continental relief, 2016; New Zealand terrain data Copyright 2011 Crown copyright (c) Land Information New Zealand and the New Zealand Government (All rights reserved); Norway terrain data © Kartverket; United Kingdom terrain data © Environment Agency copyright and/or database right 2015. All rights reserved; United States 3DEP (formerly NED) and global GMTED2010 and SRTM terrain data courtesy of the U.S. Geological Survey."

## Web-Mercator tile coordinates (fractional) of a point at `zoom`.
static func tile_xy(lat: float, lon: float, zoom: int) -> Vector2:
	var n := float(1 << zoom)
	var phi := deg_to_rad(clampf(lat, -85.0511, 85.0511))
	return Vector2((lon + 180.0) / 360.0 * n, (1.0 - log(tan(phi) + 1.0 / cos(phi)) / PI) / 2.0 * n)

## {zoom, x0, y0, x1, y1} (inclusive tile ranges) covering the spec.
static func tile_range(spec: TerrainSpec) -> Dictionary:
	var b := spec.geo_bounds(spec.dem_half, 0.001)
	for zoom in range(MAX_ZOOM, 0, -1):
		var a := tile_xy(b[1], b[2], zoom) # north-west
		var c := tile_xy(b[0], b[3], zoom) # south-east
		var r := {"zoom": zoom, "x0": int(floor(a.x)), "y0": int(floor(a.y)), "x1": int(floor(c.x)), "y1": int(floor(c.y))}
		if (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1) <= MAX_TILES:
			return r
	return {"zoom": 0, "x0": 0, "y0": 0, "x1": 0, "y1": 0}

func elevation_downloads(spec: TerrainSpec) -> Array:
	var r := tile_range(spec)
	var out: Array = []
	for ty in range(r.y0, r.y1 + 1):
		for tx in range(r.x0, r.x1 + 1):
			out.append({"url": TILE_URL % [r.zoom, tx, ty], "file": "terrarium_%d_%d_%d.png" % [r.zoom, tx, ty], "timeout": 120.0})
	return out

func validate_elevation(path: String) -> String:
	var bad := image_complete(path)
	if bad != "":
		return bad
	var img := Image.load_from_file(path)
	return "" if img and img.get_width() == 256 and img.get_height() == 256 else "not a 256 px elevation tile"

## Heights of one decoded tile image, row-major.
static func decode(img: Image) -> PackedFloat32Array:
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var out := PackedFloat32Array()
	out.resize(img.get_width() * img.get_height())
	for i in out.size():
		out[i] = data[i * 3] * 256.0 + data[i * 3 + 1] + data[i * 3 + 2] / 256.0 - 32768.0
	return out

func build_heights(spec: TerrainSpec, dir: String) -> Dictionary:
	var r := tile_range(spec)
	var cols: int = r.x1 - r.x0 + 1
	var rows: int = r.y1 - r.y0 + 1
	var w := cols * 256
	var h := rows * 256
	var mosaic := PackedFloat32Array()
	mosaic.resize(w * h)
	for ty in range(r.y0, r.y1 + 1):
		for tx in range(r.x0, r.x1 + 1):
			var path := dir.path_join("terrarium_%d_%d_%d.png" % [r.zoom, tx, ty])
			var img := Image.load_from_file(path)
			if img == null or img.get_width() != 256 or img.get_height() != 256:
				return {"error": "bad elevation tile %s" % path.get_file()}
			var tile := decode(img)
			var ox: int = (tx - r.x0) * 256
			var oy: int = (ty - r.y0) * 256
			for y in 256:
				for x in 256:
					mosaic[(oy + y) * w + ox + x] = tile[y * 256 + x]
	var geo := spec.geo_grid()
	var lat: PackedFloat64Array = geo.lat
	var lon: PackedFloat64Array = geo.lon
	var heights := PackedFloat32Array()
	heights.resize(lat.size())
	var zoom: int = r.zoom
	for i in lat.size():
		var t := tile_xy(lat[i], lon[i], zoom)
		var gx := clampf((t.x - r.x0) * 256.0 - 0.5, 0.0, w - 1.001)
		var gy := clampf((t.y - r.y0) * 256.0 - 0.5, 0.0, h - 1.001)
		var x0 := int(gx)
		var y0 := int(gy)
		var fx := gx - x0
		var fy := gy - y0
		var j := y0 * w + x0
		heights[i] = lerpf(lerpf(mosaic[j], mosaic[j + 1], fx), lerpf(mosaic[j + w], mosaic[j + w + 1], fx), fy)
	return {"heights": heights, "error": ""}
