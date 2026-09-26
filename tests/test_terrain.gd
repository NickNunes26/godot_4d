## Headless tests for the terrain pipeline: ASC parsing, Terrarium decoding,
## grid resampling, zone decision, provider URLs, the saved data, the
## position check, and that ConstructionTerrain lines up with the model.
## No network: every input is a tiny synthetic fixture built here.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_terrain.gd
extends SceneTree

var _fails := 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   " + detail])

func _near(label: String, got: float, want: float, tol: float) -> void:
	_check(label, absf(got - want) <= tol, "got=%.6f want=%.6f" % [got, want])

func _initialize() -> void:
	_test_asc()
	_test_terrarium()
	_test_spec_and_resample()
	_test_zone_pick()
	_test_providers()
	_test_data_and_check()
	_test_world_files()
	_test_grading()
	_test_platforms_from_model()

## The node test needs a live tree, which a --script run only has once the main
## loop is going.
var _ran_node_test := false

func _process(_delta: float) -> bool:
	if _ran_node_test:
		return false
	_ran_node_test = true
	_test_terrain_node()
	_test_graded_node()
	print("\n%s (%d failure(s))" % ["ALL PASSED" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)
	return false

## The WCS wraps the grid in multipart MIME exactly like this.
const MULTIPART := """
--wcs
Content-Type: application/asc
Content-ID: coverage/out.asc

ncols        5
nrows        4
xllcorner    -3.710000000000
yllcorner    40.410000000000
cellsize     0.001
NODATA_value -9999
 10 11 12 13 14
 20 21 22 23 24
 30 31 -9999 33 34
 40 41 42 43 44
--wcs
Content-Type: text/plain
Content-ID: coverage/out.prj

GEOGCS["GCS_WGS_1984"]
--wcs--
"""

func _test_asc() -> void:
	print("=== AscGrid")
	var g := AscGrid.parse(MULTIPART)
	_check("parsed multipart", g != null)
	if not g:
		return
	_check("size", g.ncols == 5 and g.nrows == 4)
	_near("xll", g.xll, -3.71, 1e-12)
	_check("row 0 is the first (north) line", g.values[0] == 10.0 and g.values[19] == 44.0)
	_check("boundary text ignored", g.values.size() == 20)
	var valid := g.fill_nodata()
	_check("one no-data cell", valid == 19)
	_check("no-data filled with the median", g.values[12] == 24.0, str(g.values[12]))
	# Cell (col 1, row 1) centre: x = xll + 1.5 cs, y = top - 1.5 cs.
	var top := g.yll + g.nrows * g.cellsize
	_near("sample at a cell centre", g.sample(g.xll + 1.5 * g.cellsize, top - 1.5 * g.cellsize), 21.0, 1e-6)
	_near("bilinear between centres", g.sample(g.xll + 2.0 * g.cellsize, top - 1.5 * g.cellsize), 21.5, 1e-6)
	_near("clamped outside", g.sample(-100.0, 100.0), 10.0, 1e-6)
	_near("land mean", g.land_mean(), (10+11+12+13+14+20+21+22+23+24+30+31+24+33+34+40+41+42+43+44) / 20.0, 1e-6)

	var sea := AscGrid.parse("ncols 2\nnrows 2\nxllcorner 0\nyllcorner 0\ncellsize 1\n0 0\n0 0\n")
	_check("all-zero probe is sea", is_nan(sea.land_mean()))
	var coast := AscGrid.parse("ncols 2\nnrows 2\nxllcorner 0\nyllcorner 0\ncellsize 1\n0 2\n0 6\n")
	_near("a real coast is land", coast.land_mean(), 2.0, 1e-9)
	var centre := AscGrid.parse("ncols 2\nnrows 2\nxllcenter 100\nyllcenter 200\ncellsize 10\n1 2\n3 4\n")
	_near("xllcenter converted to corner", centre.xll, 95.0, 1e-9)
	var err := {}
	_check("service error text rejected", AscGrid.parse("<ServiceException>bad</ServiceException>", err) == null and err.has("message"))
	_check("all no-data -> 0 valid", AscGrid.parse("ncols 1\nnrows 1\nxllcorner 0\nyllcorner 0\ncellsize 1\n-9999\n").fill_nodata() == 0)

func _test_terrarium() -> void:
	print("=== Terrarium")
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(128, 0, 0))
	img.set_pixel(1, 0, Color8(128, 100, 128))
	var h := TerrariumProvider.decode(img)
	_near("sea level", h[0], 0.0, 1e-6)
	_near("100.5 m", h[1], 100.5, 1e-6)
	var t := TerrariumProvider.tile_xy(0.0, 0.0, 1)
	_check("tile of (0,0) at zoom 1", t.distance_to(Vector2(1, 1)) < 1e-9)
	var spec := TerrainSpec.create(30, 440000.0, 4474000.0)
	var r := TerrariumProvider.tile_range(spec)
	var count: int = (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1)
	_check("tile range within the cap (zoom %d, %d tiles)" % [r.zoom, count], count <= TerrariumProvider.MAX_TILES and r.zoom >= 12)
	_check("one download per tile", TerrariumProvider.new().elevation_downloads(spec).size() == count)

func _test_spec_and_resample() -> void:
	print("=== TerrainSpec + resampling")
	var spec := TerrainSpec.create(30, 440000.4, 4473999.6)
	_check("centre rounded to whole metres", spec.center_e == 440000.0 and spec.center_n == 4474000.0)
	_check("standard grid is 840 points", spec.grid_n() == 840)
	_near("first column easting", spec.grid_e(0), 440000.0 - 2100.0 + 2.5, 1e-9)
	_near("first row is the north edge", spec.grid_north(0), 4474000.0 + 2100.0 - 2.5, 1e-9)
	_check("cache key", spec.key() == "utm30_440000_4474000_4200_5p0", spec.key())
	# Interpolated geographic grid vs exact conversion.
	var small := TerrainSpec.create(30, 440000.0, 4474000.0, "small")
	var geo := small.geo_grid()
	var n := small.grid_n()
	var worst := 0.0
	for idx in [0, 17, n * 37 + 5, (n * n >> 1) + 3, n * n - 1]:
		var row: int = floori(float(idx) / n)
		var col: int = idx % n
		var exact := Utm.to_geo(small.grid_e(col), small.grid_north(row), 30)
		worst = maxf(worst, maxf(absf(exact.lat - geo.lat[idx]), absf(exact.lon - geo.lon[idx])))
	_check("interpolated lat/lon within 1e-8 deg (~1 mm)", worst < 1e-8, str(worst))

	# A tilted plane in UTM metres must come back exactly at the grid points.
	var plane := AscGrid.new()
	plane.ncols = 300
	plane.nrows = 300
	plane.cellsize = 10.0
	plane.xll = small.center_e - 1500.0
	plane.yll = small.center_n - 1500.0
	plane.values.resize(300 * 300)
	for rr in 300:
		for cc in 300:
			var e := plane.xll + (cc + 0.5) * 10.0
			var nn := plane.yll + (300 - rr - 0.5) * 10.0
			plane.values[rr * 300 + cc] = 0.01 * (e - small.center_e) + 0.02 * (nn - small.center_n) + 800.0
	var hp := TerrainBuilder.sample_projected(plane, small)
	var c := 123
	var rw := 45
	_near("projected resample on a plane", hp[rw * n + c], 0.01 * (small.grid_e(c) - small.center_e) + 0.02 * (small.grid_north(rw) - small.center_n) + 800.0, 1e-3)

	# A geographic grid whose height is a function of latitude.
	var b := small.geo_bounds(small.dem_half)
	var gg := AscGrid.new()
	gg.cellsize = 0.0001
	gg.xll = b[2]
	gg.yll = b[0]
	gg.ncols = int(ceil((b[3] - b[2]) / gg.cellsize)) + 1
	gg.nrows = int(ceil((b[1] - b[0]) / gg.cellsize)) + 1
	gg.values.resize(gg.ncols * gg.nrows)
	for rr in gg.nrows:
		var lat := gg.yll + (gg.nrows - rr - 0.5) * gg.cellsize
		for cc in gg.ncols:
			gg.values[rr * gg.ncols + cc] = (lat - 42.0) * 10000.0
	var hg := TerrainBuilder.sample_geographic(gg, small)
	var lat_c: float = Utm.to_geo(small.grid_e(c), small.grid_north(rw), 30).lat
	_near("geographic resample follows latitude", hg[rw * n + c], (lat_c - 42.0) * 10000.0, 0.01)

func _test_zone_pick() -> void:
	print("=== Zone decision")
	var clear := TerrainService.pick_zone([{"zone": 30, "ground": 652.0, "diff": 2.0}, {"zone": 29, "ground": 1900.0, "diff": 1250.0}], 650.0)
	_check("clear winner accepted", clear.zone == 30, clear.detail)
	var close := TerrainService.pick_zone([{"zone": 30, "ground": 900.0, "diff": 50.0}, {"zone": 31, "ground": 1050.0, "diff": 200.0}], 850.0)
	_check("close call refused", close.zone == 0)
	var far := TerrainService.pick_zone([{"zone": 30, "ground": 1000.0, "diff": 150.0}, {"zone": 31, "ground": 2000.0, "diff": 1150.0}], 850.0)
	_check("best more than 120 m off refused", far.zone == 0)
	_check("single candidate accepted", TerrainService.pick_zone([{"zone": 29, "ground": 12.0, "diff": 400.0}], 412.0).zone == 29)
	_check("no candidate -> 0", TerrainService.pick_zone([], 100.0).zone == 0)

func _test_providers() -> void:
	print("=== Providers")
	var ign := SpainIgnProvider.new()
	_check("IGN covers the Spanish mainland", ign.covers(40.41, -3.70))
	_check("IGN does not cover the Canaries", not ign.covers(28.1, -15.4))
	_check("IGN does not cover Paris", not ign.covers(48.85, 2.35))
	var url := SpainIgnProvider.wms_url(30, 439500.0, 4473500.0, 440500.0, 4474500.0, 4000)
	_check("WMS asks EPSG:25830 with an E,N box", url.contains("CRS=EPSG:25830&BBOX=439500.00,4473500.00,440500.00,4474500.00&WIDTH=4000&HEIGHT=4000"), url)
	var wcs := SpainIgnProvider.wcs_url(40.4, 40.5, -3.8, -3.7)
	_check("WCS asks Lat then Long subsets", wcs.contains("SUBSET=Lat(40.400000,40.500000)&SUBSET=Long(-3.800000,-3.700000)"), wcs)
	var spec := TerrainSpec.create(30, 440000.0, 4474000.0)
	var job := ign.ortho_download(spec, 500.0, "ortho_detail")
	_check("detail ortho is 1 km", job.rect[2] - job.rect[0] == 1000.0 and job.file == "ortho_detail.jpg")
	_check("provider pick: Spain -> IGN", TerrainService.provider_for(40.41, -3.70).id() == "es_ign")
	_check("provider pick: elsewhere -> Terrarium", TerrainService.provider_for(48.85, 2.35).id() == "terrarium")
	var tmp := "user://test_ortho_check.bin"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9]))
	f.close()
	_check("complete JPEG accepted", ign.validate_ortho(tmp) == "")
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x12, 0x34]))
	f.close()
	_check("truncated JPEG rejected", ign.validate_ortho(tmp).begins_with("incomplete"))
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(MULTIPART.substr(0, MULTIPART.find("33 34")))
	f.close()
	_check("truncated ASC rejected", ign.validate_elevation(tmp) != "")
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(MULTIPART)
	f.close()
	_check("complete ASC accepted", ign.validate_elevation(tmp) == "")
	f = FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("<ServiceExceptionReport>no</ServiceExceptionReport>")
	f.close()
	_check("service error rejected with its text", ign.validate_ortho(tmp).contains("ServiceException"))

func _make_data(n: int, cell: float, base: float) -> TerrainData:
	var spec := TerrainSpec.new()
	spec.zone = 30
	spec.center_e = 500000.0
	spec.center_n = 4400000.0
	spec.cell = cell
	spec.dem_half = n * cell / 2.0
	var h := PackedFloat32Array()
	h.resize(n * n)
	for r in n:
		for c in n:
			h[r * n + c] = base + 0.1 * (spec.grid_e(c) - spec.center_e) # rises 10 cm per metre east
	return TerrainBuilder.make_data(spec, h)

func _test_data_and_check() -> void:
	print("=== TerrainData + position check")
	var d := _make_data(40, 5.0, 600.0)
	_check("grid size", d.grid_n == 40)
	_near("height at the centre", d.height_at(500000.0, 4400000.0), 600.0, 1e-3)
	_near("height 20 m east", d.height_at(500020.0, 4400000.0), 602.0, 1e-3)
	_check("min/max", absf(d.min_height - (600.0 + 0.1 * (-97.5))) < 1e-3 and absf(d.max_height - (600.0 + 0.1 * 97.5)) < 1e-3)
	_check("collision grid is 2^k+1 >= visual", d.collision_n == 65)
	var sp := d.collision_spacing()
	_near("collision samples carry height / spacing", d.collision_map[32 * 65 + 32] * sp, 600.0, 1e-3)
	_check("height image is RF", d.height_image().get_format() == Image.FORMAT_RF)
	var big := TerrainBuilder.make_data(TerrainSpec.create(30, 500000.0, 4400000.0), PackedFloat32Array())
	_check("empty heights -> NAN", is_nan(big.height_at(500000.0, 4400000.0)))

	var ok := TerrainBuilder.position_check(d, [{"e": 500000.0, "n": 4400000.0, "bottom": 598.0, "top": 620.0}, {"e": 500010.0, "n": 4400000.0, "bottom": 601.0, "top": 630.0}])
	_check("sensible model passes", ok.ok, ok.text)
	_near("lift puts the deepest part on the ground", ok.lift, 2.0, 1e-3)
	var floating := TerrainBuilder.position_check(d, [{"e": 500000.0, "n": 4400000.0, "bottom": 700.0, "top": 720.0}])
	_check("floating model flagged", not floating.ok and floating.text.contains("flota"))
	var buried := TerrainBuilder.position_check(d, [{"e": 500000.0, "n": 4400000.0, "bottom": 500.0, "top": 520.0}])
	_check("buried model flagged", not buried.ok and buried.text.contains("bajo el terreno"))
	var outside := TerrainBuilder.position_check(d, [{"e": 0.0, "n": 0.0, "bottom": 0.0, "top": 1.0}])
	_check("model outside the terrain", outside.count == 0 and not outside.ok)

func _test_world_files() -> void:
	print("=== World files")
	var img_path := "user://test_ortho.jpg"
	var rect := PackedFloat64Array([439500.0, 4473500.0, 440500.0, 4474500.0])
	TerrainBuilder.write_world_file(img_path, rect, 4000)
	var back := TerrainBuilder.world_file_rect(img_path, 4000, 4000)
	var ok := back.size() == 4
	for i in 4:
		ok = ok and absf(back[i] - rect[i]) < 1e-3
	_check("world file round trip", ok, str(back))
	_check("no world file -> empty", TerrainBuilder.world_file_rect("user://nothing_here.jpg", 10, 10).is_empty())

## The terrain node must put a map point exactly where the model's own
## GeoOrigin says that point is -- with a rotated origin and a moved container.
func _test_terrain_node() -> void:
	print("=== ConstructionTerrain placement")
	var sm := Node3D.new()
	root.add_child(sm)
	var container := Node3D.new()
	container.name = "Parts"
	container.position = Vector3(3.0, 1.0, -2.0)
	container.rotation_degrees = Vector3(0, 12, 0)
	sm.add_child(container)
	var geo := GeoOrigin.new()
	geo.easting = 500003.7
	geo.northing = 4399998.2
	geo.height = 612.5
	geo.rotation_deg = 25.0
	geo.utm_zone = 30
	geo.source = "manual"
	var d := _make_data(40, 5.0, 600.0)
	var terrain := ConstructionTerrain.new()
	terrain.use_near_textures = false
	sm.add_child(terrain)
	terrain.geo_origin = geo
	terrain.anchor_path = terrain.get_path_to(container)
	terrain.data = d
	var e := 500012.5
	var n := 4399990.0
	var h := d.height_at(e, n)
	var in_terrain := Vector3(e - d.center_e, h, -(n - d.center_n))
	var via_terrain := sm.global_transform.affine_inverse() * terrain.global_transform * in_terrain
	var via_model := container.transform * geo.map_to_local(e, n, h)
	_check("terrain and model agree on a map point (%.4f m)" % via_terrain.distance_to(via_model), via_terrain.distance_to(via_model) < 1e-3)
	geo.height = 620.0
	var after := sm.global_transform.affine_inverse() * terrain.global_transform * in_terrain
	_check("editing the origin moves the terrain", after.distance_to(container.transform * geo.map_to_local(e, n, h)) < 1e-3)
	var mesh := terrain.get_node_or_null("Ground") as MeshInstance3D
	_check("ground mesh built", mesh != null and mesh.mesh is PlaneMesh and (mesh.mesh as PlaneMesh).subdivide_width == 38)
	var body := terrain.get_node_or_null("GroundBody")
	_check("collision built", body != null and body.get_child(0).shape is HeightMapShape3D)
	_check("generated children are not saved", mesh != null and mesh.owner == null)
	terrain.collision_enabled = false
	_check("collision can be turned off", terrain.get_node_or_null("GroundBody") == null or terrain.get_node("GroundBody").is_queued_for_deletion())
	sm.queue_free()

func _square(half: float, center := Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(-half, -half), center + Vector2(half, -half),
		center + Vector2(half, half), center + Vector2(-half, half)])

func _platform(footprint: PackedVector2Array, level: float, slope: float) -> TerrainPlatform:
	var p := TerrainPlatform.new()
	p.footprint = footprint
	p.level = level
	p.bank_slope = slope
	return p

## Grid of _make_data(40, 5.0, 600.0): points at x = (c - 19.5) * 5, ground
## 600 + 0.1 * x. Platforms are given in the terrain's own space (identity).
func _test_grading() -> void:
	print("=== Terrain platforms (cut / fill)")
	var d := _make_data(40, 5.0, 600.0)
	_check("no platforms: nothing to grade", TerrainGrading.compute(d, [], Transform3D()) == null)
	var off := _platform(_square(20.0), 600.0, 2.0)
	off.enabled = false
	_check("disabled platforms are skipped", TerrainGrading.compute(d, [off], Transform3D()) == null)

	var pad := _platform(_square(20.0), 600.0, 2.0)
	var g := TerrainGrading.compute(d, [pad], Transform3D())
	_check("pad graded", g != null)
	# (c=20, r=20) is x = z = 2.5, inside: natural 600.25.
	_near("inside the pad the ground is at its level", d.heights[20 * 40 + 20] + g.change_at(20, 20), 600.0, 1e-4)
	# c=24: x = 22.5, 2.5 m out: within one cell diagonal (7.07 m), so levelled too.
	_near("points within a cell diagonal are levelled", d.heights[20 * 40 + 24] + g.change_at(24, 20), 600.0, 1e-4)
	# c=26: x = 32.5, 12.5 m out, 5.43 past the levelled ring; the bank allows 5.43 / 2 above.
	_near("bank limits the ground beyond the ring", d.heights[20 * 40 + 26] + g.change_at(26, 20), 600.0 + (12.5 - 5.0 * sqrt(2.0)) / 2.0, 1e-3)
	# c=28: x = 42.5; the bank would allow 7.7 m, the ground is 4.25 m up.
	_near("ground beyond the bank is untouched", g.change_at(28, 20), 0.0, 1e-6)
	_near("far away nothing changes", g.change_at(0, 0), 0.0, 1e-6)
	_check("cut on the high side, fill on the low side", g.cut_m3 > 0.0 and g.fill_m3 > 0.0,
		"cut=%.1f fill=%.1f" % [g.cut_m3, g.fill_m3])
	_check("only the changed area is kept", g.rect.size.x < 20 and g.rect.size.y < 20, str(g.rect))
	_near("height_at follows the platform", g.height_at(500002.5, 4399997.5), 600.0, 1e-3)

	var pit := _platform(_square(5.0), 597.0, 0.5)
	var g2 := TerrainGrading.compute(d, [pad, pit], Transform3D())
	_near("a pit is dug into the pad", d.heights[20 * 40 + 20] + g2.change_at(20, 20), 597.0, 1e-4)
	var tex := g2.image.get_pixel(20 - g2.rect.position.x, 20 - g2.rect.position.y)
	_near("slot 0 is the pad step", tex.r, -0.25, 1e-4)
	_near("slot 1 is the pit step", tex.b, -3.0, 1e-4)
	_near("slot codes: pad inside, pit inside", tex.g + tex.a * 10.0, 1.5 + 25.0, 1e-4)
	var col := g2.patched_collision()
	_near("collision follows the pit", col[32 * 65 + 32] * d.collision_spacing(), 597.0, 1e-3)
	_near("collision far away is unchanged", col[2 * 65 + 2], d.collision_map[2 * 65 + 2], 1e-6)

	var cliff := _platform(_square(20.0), 590.0, 0.0)
	var g3 := TerrainGrading.compute(d, [cliff], Transform3D())
	_near("slope 0: no bank beyond the levelled ring", g3.change_at(26, 20), 0.0, 1e-6)

	# Timing: natural before the activity, levelled after, linear between.
	var sched := ConstructionSchedule.new({"steps": [{"actions": [
		{"id": "E0", "target_prefix": "Nothing", "type": "fade_in", "start_date": "2027-03-01", "duration_days": 2},
		{"id": "E1", "target_prefix": "Nothing", "type": "fade_in", "duration_days": 10, "depends_on": "E0"}]}]},
		{}, SpatialGrouper.new(), {})
	var timed := _platform(_square(20.0), 600.0, 2.0)
	timed.activities = PackedStringArray(["E1"])
	var span := sched.get_action_day_range("E1")
	if span.is_empty():
		_check("schedule resolves an action with no parts", false, "get_action_day_range(E1) is empty")
	else:
		_near("before the activity: natural", timed.progress_on(sched, span.start_day - 1.0), 0.0, 1e-6)
		_near("halfway", timed.progress_on(sched, (span.start_day + span.finish_day) / 2.0), 0.5, 1e-6)
		_near("after: levelled", timed.progress_on(sched, span.finish_day + 1.0), 1.0, 1e-6)
	timed.activities = PackedStringArray(["NoSuchAction"])
	_near("unknown activity: levelled from day 0", timed.progress_on(sched, 0.0), 1.0, 1e-6)

## A small "building": a ground slab, a wall on it, a dig and a footing under it.
func _test_platforms_from_model() -> void:
	print("=== Platforms from a model")
	var container := Node3D.new()
	var add := func(name: String, pos: Vector3, size: Vector3):
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mi.mesh = box
		mi.name = name
		mi.position = pos + size / 2.0
		container.add_child(mi)
	add.call("Ground", Vector3(-15, -0.3, -10), Vector3(30, 0.3, 20))
	add.call("Wall", Vector3(-6, 0.0, -4), Vector3(12, 3.0, 0.5))
	add.call("Dig_1", Vector3(-7, -2.0, -5), Vector3(14, 1.7, 10))
	add.call("Footing", Vector3(-5, -2.0, -3), Vector3(2, 0.7, 2))
	var actions := [
		{"id": "A1", "prefix": "Topsoil", "text": "A1 Retirada de terra vexetal"},
		{"id": "A2", "prefix": "Dig", "text": "A2 Escavación ata cota"},
		{"id": "A3", "prefix": "Wall", "text": "A3 Muros"}]
	var list := TerrainGrading.platforms_from_model(container, actions, 2.0, 1.5)
	_check("a pad and a pit", list.size() == 2, str(list.size()))
	if list.size() == 2:
		var pad: TerrainPlatform = list[0]
		var pit: TerrainPlatform = list[1]
		_near("pad at the bottom of the widest resting part", pad.level, -0.3, 1e-4)
		_near("pad covers the model plus the margin (x)", pad.footprint[1].x - pad.footprint[0].x, 34.0, 1e-4)
		_check("pad follows the levelling activity", pad.activities == PackedStringArray(["A1"]), str(pad.activities))
		_near("pit down to the lowest part", pit.level, -2.0, 1e-4)
		_near("pit is the drawn dig, no extra room", pit.footprint[1].x - pit.footprint[0].x, 14.0, 1e-4)
		_check("pit follows the excavation activity", pit.activities == PackedStringArray(["A2"]), str(pit.activities))
		_check("pit banks are steep", pit.bank_slope <= 0.5)
	container.free()

## The node: platforms move the ground's bounds and height, the timeline
## blends them, and clearing them gives the natural ground back.
func _test_graded_node() -> void:
	print("=== ConstructionTerrain with platforms")
	var sm := Node3D.new()
	root.add_child(sm)
	var container := Node3D.new()
	sm.add_child(container)
	var d := _make_data(40, 5.0, 600.0)
	var terrain := ConstructionTerrain.new()
	terrain.use_near_textures = false
	sm.add_child(terrain)
	terrain.anchor_path = terrain.get_path_to(container)
	terrain.data = d
	_check("natural ground: no grading", terrain.grading() == null)
	var list: Array[TerrainPlatform] = [_platform(_square(20.0), 580.0, 1.0)]
	terrain.platforms = list
	terrain.rebuild()
	_check("platform graded", terrain.grading() != null)
	_near("height_at sees the platform", terrain.height_at(500002.5, 4399997.5), 580.0, 1e-3)
	var mesh := terrain.get_node("Ground") as MeshInstance3D
	var aabb: AABB = (mesh.mesh as PlaneMesh).custom_aabb
	_check("mesh bounds reach down to the platform", aabb.position.y <= 580.0 + 1e-3, str(aabb))
	var mat := mesh.material_override as ShaderMaterial
	_check("shader gets the grading", mat.get_shader_parameter("has_grading") == true and mat.get_shader_parameter("grading") is ImageTexture)
	terrain.follow_schedule(null, 0.0)
	_near("no schedule: finished ground", (mat.get_shader_parameter("grade_progress") as PackedFloat32Array)[0], 1.0, 1e-6)
	var none: Array[TerrainPlatform] = []
	terrain.platforms = none
	terrain.rebuild()
	_check("clearing platforms gives the natural ground", terrain.grading() == null and absf(terrain.height_at(500002.5, 4399997.5) - 600.25) < 1e-3)
	sm.queue_free()
