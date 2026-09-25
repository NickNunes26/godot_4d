## Headless tests for the georeference layer: UTM conversion, reading the
## georeference out of IFC text, what GDIFCRecenter strips and records,
## GeoOrigin's map maths, and the sun. No network, no GDIFC needed.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_geo.gd
extends SceneTree

const FIXTURES := "res://addons/construction_4d_tool/tests/fixtures/"

var _fails := 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   " + detail])

func _near(label: String, got: float, want: float, tol: float) -> void:
	_check(label, absf(got - want) <= tol, "got=%.9f want=%.9f tol=%s" % [got, want, str(tol)])

func _init() -> void:
	_test_utm()
	_test_ifc_georef()
	_test_recenter()
	_test_geo_origin()
	_test_solar()
	print("\n%s (%d failure(s))" % ["ALL PASSED" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails > 0 else 0)

func _test_utm() -> void:
	print("=== UTM")
	# Invented points; reference values from an independent implementation of the same series.
	var a := Utm.to_geo(440000.0, 4474000.0, 30)
	_near("zone 30 point lat", a.lat, 40.414460, 1e-6)
	_near("zone 30 point lon", a.lon, -3.707199, 1e-6)
	var b := Utm.to_geo(537000.0, 4700000.0, 29)
	_near("zone 29 point lat", b.lat, 42.451448, 1e-6)
	_near("zone 29 point lon", b.lon, -8.550041, 1e-6)
	# Same E/N in the neighbouring zones is a different place entirely.
	_near("same E/N in zone 31 is 6 deg east", Utm.to_geo(440000.0, 4474000.0, 31).lon, a.lon + 6.0, 1e-9)
	# Round trips, including far off the central meridian and in the south.
	for p in [[42.5, -4.4, 30], [36.1, -6.2, 29], [43.7, 3.9, 31], [40.0, 0.0, 30], [-33.9, 18.4, 34], [60.2, 24.9, 35]]:
		var en := Utm.from_geo(p[0], p[1], p[2])
		var back := Utm.to_geo(en.easting, en.northing, p[2], p[0] < 0.0)
		var err_m := Vector2((back.lat - p[0]) * 111000.0, (back.lon - p[1]) * 111000.0 * cos(deg_to_rad(p[0]))).length()
		_check("round trip %s (err %.6f m)" % [str(p), err_m], err_m < 0.001, "err %.6f m" % err_m)
	var en2 := Utm.from_geo(a.lat, a.lon, 30)
	_near("from_geo easting", en2.easting, 440000.0, 0.05)
	_near("from_geo northing", en2.northing, 4474000.0, 0.05)
	_check("zone for lon -4.37 is 30", Utm.zone_for_lon(-4.37) == 30)
	_check("zone for lon 2.1 is 31", Utm.zone_for_lon(2.1) == 31)
	_check("zone from EPSG:25830", Utm.zone_from_crs_text("EPSG:25830") == 30)
	_check("zone from 'ETRS89 / UTM zone 29N'", Utm.zone_from_crs_text("ETRS89 / UTM zone 29N") == 29)
	_check("zone from '31N'", Utm.zone_from_crs_text("31N") == 31)
	_check("no zone in 'Local'", Utm.zone_from_crs_text("Local") == 0)

func _read(name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURES + name)

func _test_ifc_georef() -> void:
	print("=== IfcGeoref")
	var root := IfcGeoref.read(_read("georef_root_point.ifc"))
	_check("root point file: no map conversion", root.map_conversion.is_empty())
	_check("root point file: one root", root.root_points.size() == 1)
	var c: PackedFloat64Array = root.root_points[0].coords
	_check("root point coords exact in 64-bit", c[0] == 500100.0 and c[1] == 4400200.0 and c[2] == 650.0, str(c))

	var mc := IfcGeoref.read(_read("georef_map_conversion.ifc"))
	_check("map conversion found", not mc.map_conversion.is_empty())
	_near("map conversion E", mc.map_conversion.e, 500100.0, 0.0)
	_near("map conversion abscissa", mc.map_conversion.abscissa, 0.8660254037844387, 1e-12)
	_near("map conversion ordinate", mc.map_conversion.ordinate, 0.5, 1e-12)
	_near("unset scale defaults to 1", mc.map_conversion.scale, 1.0, 0.0)
	_check("CRS zone from IfcProjectedCRS", mc.crs_zone == 30, str(mc.crs_zone))
	_check("CRS name", mc.crs_name == "EPSG:25830", mc.crs_name)

	_check("split_args keeps nested/quoted", IfcGeoref.split_args("#1,'a,b',(1.,2.),$").size() == 4)
	_check("typed measure parsed", IfcGeoref.parse_float_list("(IFCLENGTHMEASURE(2.5),3.)")[0] == 2.5)

func _test_recenter() -> void:
	print("=== GDIFCRecenter")
	var info := GDIFCRecenter.recenter_with_info(FIXTURES + "georef_root_point.ifc")
	_check("recentered copy written", info.path.begins_with(GDIFCRecenter.CACHE_DIR), info.path)
	var ro: PackedFloat64Array = info.root_offset
	_check("root offset recorded", ro[0] == 500100.0 and ro[1] == 4400200.0 and ro[2] == 650.0, str(ro))
	_check("root point zeroed in the copy", FileAccess.get_file_as_string(info.path).contains("#20=IFCCARTESIANPOINT((0.,0.,0.));"))
	_check("old API still returns a path", GDIFCRecenter.recenter(FIXTURES + "georef_root_point.ifc") == info.path)

	var mci := GDIFCRecenter.recenter_with_info(FIXTURES + "georef_map_conversion.ifc")
	_check("map conversion reported", not mci.map_conversion.is_empty() and mci.crs_zone == 30)
	# GDIFC ignores the map conversion, so a file whose only offset is there is not copied.
	_check("map conversion alone: file loads as-is", mci.path == FIXTURES + "georef_map_conversion.ifc", mci.path)
	var ro2: PackedFloat64Array = mci.root_offset
	_check("no root offset when root is small", ro2[0] == 0.0 and ro2[1] == 0.0 and ro2[2] == 0.0)

	var plain := GDIFCRecenter.recenter_with_info(FIXTURES + "not_georeferenced.ifc")
	_check("small model loads unchanged", plain.path == FIXTURES + "not_georeferenced.ifc")

	# Two roots with different large offsets keep their relative position.
	var two := "#1=IFCCARTESIANPOINT((500000.,4400000.,600.));\n#2=IFCAXIS2PLACEMENT3D(#1,$,$);\n#3=IFCLOCALPLACEMENT($,#2);\n" \
		+ "#4=IFCCARTESIANPOINT((500010.5,4400020.,600.));\n#5=IFCAXIS2PLACEMENT3D(#4,$,$);\n#6=IFCLOCALPLACEMENT($,#5);\n"
	var res := GDIFCRecenter._strip_large_offsets(two, IfcGeoref.read(two))
	_check("first root zeroed", res.text.contains("#1=IFCCARTESIANPOINT((0.,0.,0.));"))
	var second: PackedFloat64Array = IfcGeoref.read(res.text).root_points[1].coords
	_check("second root keeps its offset from the first", second[0] == 10.5 and second[1] == 20.0 and second[2] == 0.0, res.text)

	# CRLF line endings (most exporters write them): the root must still be stripped.
	var crlf := FileAccess.get_file_as_string(FIXTURES + "georef_root_point.ifc").replace("\r\n", "\n").replace("\n", "\r\n")
	var rc := GDIFCRecenter._strip_large_offsets(crlf, IfcGeoref.read(crlf))
	_check("CRLF file: root offset stripped", rc.changed and rc.text.contains("#20=IFCCARTESIANPOINT((0.,0.,0.));\r\n"), str(rc.changed))
	_check("CRLF file: offset recorded", rc.root_offset[0] == 500100.0 and rc.root_offset[1] == 4400200.0)
	var crlf_mc := FileAccess.get_file_as_string(FIXTURES + "georef_map_conversion.ifc").replace("\r\n", "\n").replace("\n", "\r\n")
	var gm := IfcGeoref.read(crlf_mc)
	_check("CRLF file: map conversion and zone read", gm.map_conversion.get("e", 0.0) == 500100.0 and gm.crs_zone == 30, str(gm))

func _test_geo_origin() -> void:
	print("=== GeoOrigin")
	# Root-point model, framing shift as the dock applies it (Godot axes).
	var shift := Vector3(57.25, -2.5, -83.0)
	var info := {"root_offset": PackedFloat64Array([452300.0, 4461200.0, 650.0]), "map_conversion": {}, "crs_zone": 0}
	var g := GeoOrigin.from_ifc_import(info, shift)
	_check("coordinates source", g.source == "ifc_coordinates", g.source)
	_near("E = root + shift.x", g.easting, 452357.25, 1e-9)
	_near("N = root - shift.z", g.northing, 4461283.0, 1e-9)
	_near("H = root + shift.y", g.height, 647.5, 1e-9)
	_check("zone unknown until detected", g.utm_zone == 0 and not g.is_located())

	# Map conversion rotated 30 deg: a local point must land where the IFC says.
	var mc := {"e": 500100.0, "n": 4400200.0, "h": 650.0, "abscissa": 0.8660254037844387, "ordinate": 0.5, "scale": 1.0}
	var gm := GeoOrigin.from_ifc_import({"root_offset": PackedFloat64Array([0.0, 0.0, 0.0]), "map_conversion": mc, "crs_zone": 30}, Vector3(10.0, 7.0, -20.0))
	_check("map conversion source + zone", gm.source == "ifc_map_conversion" and gm.utm_zone == 30 and gm.zone_source == "ifc_crs")
	_near("rotation", gm.rotation_deg, 30.0, 1e-9)
	# IFC local point (x=12, y=25, z=9) is, in Godot container-local, (12, 9, -25) minus the shift.
	var p := Vector3(12.0, 9.0, -25.0) - Vector3(10.0, 7.0, -20.0)
	var m := gm.local_to_map(p)
	var ce := cos(deg_to_rad(30.0))
	var se := sin(deg_to_rad(30.0))
	_near("rotated E", m[0], 500100.0 + 12.0 * ce - 25.0 * se, 1e-6)
	_near("rotated N", m[1], 4400200.0 + 12.0 * se + 25.0 * ce, 1e-6)
	_near("H", m[2], 659.0, 1e-6)
	var back := gm.map_to_local(m[0], m[1], m[2])
	_check("map_to_local inverts local_to_map", back.distance_to(p) < 1e-3, str(back))
	# The map frame: +X east, +Y up, -Z north.
	var frame := gm.map_frame_transform()
	var east := gm.local_to_map(frame * Vector3(1, 0, 0))
	var north := gm.local_to_map(frame * Vector3(0, 0, -1))
	var o := gm.local_to_map(Vector3.ZERO)
	_near("frame +X is 1 m east", east[0] - o[0], 1.0, 1e-5)
	_near("frame +X keeps N", east[1] - o[1], 0.0, 1e-5)
	_near("frame -Z is 1 m north", north[1] - o[1], 1.0, 1e-5)
	_near("frame -Z keeps E", north[0] - o[0], 0.0, 1e-5)

	var none := GeoOrigin.from_ifc_import({"root_offset": PackedFloat64Array([0.0, 0.0, 0.0]), "map_conversion": {}}, Vector3(3, 1, -4))
	_check("small model: no position", not none.has_position() and not none.height_known)
	var placeholder := GeoOrigin.from_ifc_import({"root_offset": PackedFloat64Array([0.0, 0.0, 0.0]), "map_conversion": {"e": 0.0, "n": 0.0, "h": 0.0, "abscissa": 1.0, "ordinate": 0.0, "scale": 1.0}, "crs_zone": 0}, Vector3.ZERO)
	_check("0,0 map conversion without CRS is not a location", not placeholder.has_position())

	var changed := [0]
	g.changed.connect(func(): changed[0] += 1)
	g.height = 900.0
	_check("editing an origin emits changed", changed[0] == 1)

	# Two models of one site: a point of the second, carried into the first's
	# container space by relative_transform(), is the same map point.
	var first := GeoOrigin.from_ifc_import({"root_offset": PackedFloat64Array([0.0, 0.0, 0.0]), "map_conversion": mc, "crs_zone": 30}, Vector3(10.0, 7.0, -20.0))
	var cases := {
		"same map conversion": [mc, 30],
		"other rotation and scale": [{"e": 500130.0, "n": 4400180.0, "h": 648.0, "abscissa": 0.0, "ordinate": 1.0, "scale": 1.25}, 30],
		"zone unknown on one side": [mc, 0],
	}
	for label in cases:
		var second := GeoOrigin.from_ifc_import({"root_offset": PackedFloat64Array([0.0, 0.0, 0.0]), "map_conversion": cases[label][0], "crs_zone": cases[label][1]}, Vector3(-4.0, 3.0, 11.0))
		_check("%s: same map" % label, first.same_map_as(second))
		var rel := first.relative_transform(second)
		var worst := 0.0
		for q in [Vector3.ZERO, Vector3(12.0, -3.0, 7.5), Vector3(-40.0, 5.0, -60.0)]:
			var want := second.local_to_map(q)
			var got := first.local_to_map(rel * q)
			worst = maxf(worst, Vector3(got[0] - want[0], got[1] - want[1], got[2] - want[2]).length())
		_check("%s: points land on the same map spot (off %.5f m)" % [label, worst], worst < 1e-3)
	var other_zone := GeoOrigin.from_ifc_import({"root_offset": PackedFloat64Array([0.0, 0.0, 0.0]), "map_conversion": mc, "crs_zone": 31}, Vector3.ZERO)
	_check("different zones are not the same map", not first.same_map_as(other_zone))
	_check("no position is not the same map", not first.same_map_as(none))

func _test_solar() -> void:
	print("=== Solar")
	var summer_noon := float(Time.get_unix_time_from_datetime_dict({"year": 2024, "month": 6, "day": 21, "hour": 12, "minute": 0, "second": 0}))
	var s := Solar.position(40.4168, -3.7038, summer_noon)
	_near("Madrid midsummer 12 UTC elevation ~73 deg", rad_to_deg(s.elevation), 73.0, 1.0)
	_check("azimuth just east of south", rad_to_deg(s.azimuth) > 160.0 and rad_to_deg(s.azimuth) < 182.0, str(rad_to_deg(s.azimuth)))
	var eq := Solar.position(0.0, 0.0, float(Time.get_unix_time_from_datetime_dict({"year": 2024, "month": 3, "day": 20, "hour": 6, "minute": 7, "second": 0})))
	_near("equinox sunrise elevation ~0", rad_to_deg(eq.elevation), 0.0, 1.5)
	_near("equinox sunrise azimuth ~east", rad_to_deg(eq.azimuth), 90.0, 2.0)

	var dst_start := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 3, "day": 29, "hour": 1, "minute": 0, "second": 0}))
	_check("summer time starts 29 Mar 2026 01:00 UTC", Solar.is_eu_summer_time(dst_start) and not Solar.is_eu_summer_time(dst_start - 60.0))
	var dst_end := float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 25, "hour": 1, "minute": 0, "second": 0}))
	_check("summer time ends 25 Oct 2026 01:00 UTC", Solar.is_eu_summer_time(dst_end - 60.0) and not Solar.is_eu_summer_time(dst_end))
	var july := Solar.local_to_unix(2026, 7, 1, 11.0, 1.0, true)
	_check("11:00 in July (CEST) is 09:00 UTC", Time.get_datetime_string_from_unix_time(int(july)) == "2026-07-01T09:00:00", Time.get_datetime_string_from_unix_time(int(july)))
	var jan := Solar.local_to_unix(2026, 1, 15, 11.0, 1.0, true)
	_check("11:00 in January (CET) is 10:00 UTC", Time.get_datetime_string_from_unix_time(int(jan)) == "2026-01-15T10:00:00")
	_check("sun to the east is +X", Solar.direction_to_sun(0.0, PI / 2.0).distance_to(Vector3(1, 0, 0)) < 1e-6)
	_check("sun to the south is +Z", Solar.direction_to_sun(0.0, PI).distance_to(Vector3(0, 0, 1)) < 1e-6)
