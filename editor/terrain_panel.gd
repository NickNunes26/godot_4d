@tool
class_name TerrainPanel
extends VBoxContainer

## The dock's "Terreno" section: shows where the model is on the map, lets the
## user fix that by hand, and downloads / builds / removes the terrain and the
## sun. Owned by timeline_dock.gd, which calls on_ifc_imported() after a Load
## IFC so the terrain can follow automatically.
##
## Labels are Spanish like the rest of the dock; tooltips carry the English
## explanation. Nothing here knows about a specific country or project: the
## provider is chosen from the site's latitude/longitude (TerrainService).

const CACHE_ROOT := "res://terrain"
const _META_SECTION := "construction_4d_tool"

var _toggle: Button
var _body: VBoxContainer
var _origin_label: Label
# The hand-typed origin: shown when the model is not georeferenced, and behind
# "Cambiar origen…" when it is -- a georeferenced import needs none of it.
var _origin_toggle: Button
var _origin_box: VBoxContainer
var _latlon_edit: LineEdit
var _e_edit: LineEdit
var _n_edit: LineEdit
var _zone_spin: SpinBox
var _h_edit: LineEdit
var _rot_edit: LineEdit
var _preset: OptionButton
var _auto_check: CheckBox
var _near_check: CheckBox
var _level_check: CheckBox
var _more_toggle: Button
var _more_box: VBoxContainer
var _download_button: Button
var _cancel_button: Button
var _status: Label
var _attribution: Label
var _service: TerrainService
var _files_dialog: EditorFileDialog
var _busy := false

func _ready() -> void:
	_service = TerrainService.new()
	add_child(_service)
	_service.progress.connect(_set_status)
	_build_ui()
	refresh()

# --- UI ---------------------------------------------------------------------
#
# Only what the usual case needs is in view: where the model is, Descargar
# terreno and the levelling switch. A georeferenced model needs nothing else --
# the download starts after the import, the model is sat on the ground when its
# height is unknown, and the date's sun is added. The rest is folded away.

func _build_ui() -> void:
	add_child(HSeparator.new())
	_toggle = _fold_button(self, "Terreno", _meta("expanded", true),
		"Terrain around the model: download elevation and orthophotos for the site, drape them under the model, and light it with the sun of the schedule's date.",
		func(on):
			_body.visible = on
			_set_meta("expanded", on))

	_body = VBoxContainer.new()
	_body.visible = _toggle.button_pressed
	add_child(_body)

	_origin_label = Label.new()
	_origin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_origin_label.tooltip_text = "Where the parts container's origin is on the map (SequenceManager.geo_origin): UTM easting/northing, height, zone, and where each came from."
	_body.add_child(_origin_label)

	_origin_toggle = _fold_button(_body, "Cambiar origen", false,
		"Type the model's position by hand: for a model that is not georeferenced, or one placed wrongly.",
		func(_on): _refresh_origin_box())
	_origin_box = VBoxContainer.new()
	_body.add_child(_origin_box)
	var grid := GridContainer.new()
	grid.columns = 4
	_origin_box.add_child(grid)
	_latlon_edit = _field(grid, "Lat, lon", "40.41680, -3.70380", "Latitude, longitude of the model's centre in decimal degrees (e.g. copied from a web map). Applying it sets E/N and the UTM zone for you.")
	_zone_spin = SpinBox.new()
	_zone_spin.min_value = 0
	_zone_spin.max_value = 60
	_zone_spin.tooltip_text = "UTM zone of E/N (0 = unknown: worked out at the download). Spain: 29 Galicia and the west, 30 most of the mainland, 31 Catalonia and the Balearics."
	_label(grid, "Huso")
	grid.add_child(_zone_spin)
	_e_edit = _field(grid, "E", "", "Grid easting of the model's centre (the parts container origin), metres.")
	_n_edit = _field(grid, "N", "", "Grid northing of the model's centre, metres.")
	_h_edit = _field(grid, "Altura", "?", "Height of the parts container origin, metres. Leave empty if unknown: the model is then sat on the ground after the download.")
	_rot_edit = _field(grid, "Giro °", "0", "Counter-clockwise angle from grid east to the model's local +X axis, degrees (IfcMapConversion rotation). Use it to turn a model that is not georeferenced.")
	var apply_row := HFlowContainer.new()
	_origin_box.add_child(apply_row)
	_button(apply_row, "Aplicar origen", "Writes the fields above into SequenceManager.geo_origin (source: manual) and fetches the terrain for that place -- unless the terrain already there covers it, in which case it just moves under the model. Lat/lon wins over E/N when both are filled.", _on_apply_origin)

	var actions := HFlowContainer.new()
	_body.add_child(actions)
	_download_button = _button(actions, "Descargar terreno", "Downloads (or reuses) elevation and orthophotos for the site and builds the terrain under the SequenceManager. Files go to res://terrain/<site>/. Runs by itself after Load IFC (4D) for a georeferenced model.", _on_download)
	_cancel_button = _button(actions, "Cancelar", "Stops the download in progress after the current request.", func(): _service.cancelled = true)
	_cancel_button.visible = false
	_level_check = CheckBox.new()
	_level_check.text = "Nivelar para edificio"
	_level_check.tooltip_text = "On: a levelled pad at the level the model stands on and a pit down to the footings, following the schedule's earthworks (site levelling / topsoil, excavation). Off: the ground as downloaded, e.g. for a bridge.

Switched on by itself when the terrain is first built for a schedule with earthworks. Adjust the platforms afterwards in the Terrain node's Inspector (Platforms; slope and margin under Levelling from the model)."
	_level_check.toggled.connect(_on_level_toggled)
	actions.add_child(_level_check)

	_more_toggle = _fold_button(_body, "Más opciones", _meta("more", false),
		"Terrain size, near textures, your own files, and setting the model on the ground.",
		func(on):
			_more_box.visible = on
			_set_meta("more", on))
	_more_box = VBoxContainer.new()
	_more_box.visible = _more_toggle.button_pressed
	_body.add_child(_more_box)
	var opts := HFlowContainer.new()
	_more_box.add_child(opts)
	_preset = OptionButton.new()
	var keys := TerrainSpec.PRESETS.keys()
	for i in keys.size():
		_preset.add_item(TerrainSpec.PRESETS[keys[i]].label, i)
		_preset.set_item_metadata(i, keys[i])
	_preset.select(maxi(keys.find(_meta("preset", TerrainSpec.DEFAULT_PRESET)), 0))
	_preset.tooltip_text = "How much terrain to download around the model. Standard: 4.2 km of 5 m elevation, a 1 km orthophoto at 0.25 m/px and a 4 km one at 1 m/px."
	_preset.item_selected.connect(func(i): _set_meta("preset", _preset.get_item_metadata(i)))
	opts.add_child(_preset)
	_auto_check = CheckBox.new()
	_auto_check.text = "Al importar IFC"
	_auto_check.button_pressed = _meta("auto", true)
	_auto_check.tooltip_text = "Download the terrain automatically right after Load IFC (4D) when the model is georeferenced."
	_auto_check.toggled.connect(func(on): _set_meta("auto", on))
	opts.add_child(_auto_check)
	_near_check = CheckBox.new()
	_near_check.text = "Texturas cercanas"
	_near_check.button_pressed = _meta("near", true)
	_near_check.tooltip_text = "Also fetch tiled leaf-litter and rock textures (Poly Haven, CC0, ~15 MB once per project) that replace the blurry orthophoto close to the camera."
	_near_check.toggled.connect(func(on): _set_meta("near", on))
	opts.add_child(_near_check)
	var more_actions := HFlowContainer.new()
	_more_box.add_child(more_actions)
	_button(more_actions, "Archivos propios…", "Builds the terrain from your own files instead: an .asc elevation grid (UTM in the model's zone, or degrees) plus optional JPG/PNG orthophotos with world files (.jgw/.pgw). GeoTIFF is not supported by Godot.", _on_files)
	_button(more_actions, "Asentar en el suelo", "Changes the origin height so the part reaching deepest into the ground just touches it. Done by itself after the download when the height is unknown; this is for a known height that is wrong.", _on_sit)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)
	_attribution = Label.new()
	_attribution.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attribution.add_theme_font_size_override("font_size", 11)
	_attribution.modulate = Color(1, 1, 1, 0.7)
	_attribution.tooltip_text = "Data licences require this credit wherever the terrain is shown."
	_body.add_child(_attribution)

## A flat "▸ Title" / "▾ Title" button that folds a section.
func _fold_button(parent: Control, title: String, pressed: bool, tip: String, on_toggled: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_pressed = pressed
	b.tooltip_text = tip
	var label := func(): b.text = ("▾ " if b.button_pressed else "▸ ") + title
	label.call()
	b.toggled.connect(func(on):
		label.call()
		on_toggled.call(on))
	parent.add_child(b)
	return b

## The manual-origin fields: always for a model with no position, otherwise
## only when asked for.
func _refresh_origin_box() -> void:
	var geo := _geo(_sequence_manager())
	var located := geo != null and geo.has_position()
	_origin_toggle.visible = located
	_origin_box.visible = not located or _origin_toggle.button_pressed

## Descargar terreno and Cancelar share one place: only one of them can act.
func _set_busy(on: bool) -> void:
	_busy = on
	_download_button.visible = not on
	_cancel_button.visible = on

func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)

func _field(parent: Control, label: String, placeholder: String, tip: String) -> LineEdit:
	_label(parent, label)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.tooltip_text = tip
	e.custom_minimum_size.x = 110
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(e)
	return e

func _spin(parent: Control, lo: float, hi: float, step: float, value: float, tip: String) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = value
	sb.tooltip_text = tip
	parent.add_child(sb)
	return sb

func _button(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _meta(key: String, default: Variant) -> Variant:
	return EditorInterface.get_editor_settings().get_project_metadata(_META_SECTION, "terrain_" + key, default)

func _set_meta(key: String, value: Variant) -> void:
	EditorInterface.get_editor_settings().set_project_metadata(_META_SECTION, "terrain_" + key, value)

func _set_status(text: String) -> void:
	_status.text = text
	print("4D terreno: ", text)

# --- Scene lookups -----------------------------------------------------------

func _sequence_manager() -> Node:
	var root := EditorInterface.get_edited_scene_root()
	return GeoSun._find_with_property(root, "geo_origin") if root else null

func _container(sm: Node) -> Node3D:
	if not sm:
		return null
	var path: NodePath = sm.get("parts_container_path")
	return sm.get_node_or_null(path) as Node3D if not path.is_empty() else null

## Samples of every model in the scene (primary and extra containers), in the
## primary's space, which is the one the origin describes.
func _samples(sm: Node, geo: GeoOrigin) -> Array:
	var anchor := _container(sm)
	var out: Array = []
	if not anchor:
		return out
	for c in IfcSceneModels.containers(sm):
		var to_anchor := Transform3D() if c == anchor else anchor.transform.affine_inverse() * c.transform
		out.append_array(TerrainBuilder.model_samples(c, geo, to_anchor))
	return out

func _geo(sm: Node, create := false) -> GeoOrigin:
	if not sm:
		return null
	var g = sm.get("geo_origin")
	if g == null and create:
		g = GeoOrigin.new()
		sm.set("geo_origin", g)
	return g

func _terrain_node(sm: Node) -> ConstructionTerrain:
	if not sm:
		return null
	for child in sm.get_children():
		if child is ConstructionTerrain:
			return child
	return null

## Updates the labels and fields from the open scene.
func refresh() -> void:
	if not is_inside_tree() or not _origin_label:
		return
	var sm := _sequence_manager()
	var geo := _geo(sm)
	if not sm:
		_origin_label.text = "Origen: no hay SequenceManager en la escena."
	elif not geo or not geo.has_position():
		_origin_label.text = "Origen: sin georreferencia — indica lat/lon (o E, N y huso) y pulsa Aplicar origen."
	else:
		var src := {"ifc_map_conversion": "IfcMapConversion", "ifc_coordinates": "coordenadas del IFC", "manual": "manual"}
		var zsrc := {"ifc_crs": "IfcProjectedCRS", "auto": "deducido", "manual": "manual"}
		var text := "Origen: %s — posición: %s" % [geo.describe(), src.get(geo.source, geo.source)]
		if geo.utm_zone > 0:
			text += ", huso: %s" % zsrc.get(geo.zone_source, geo.zone_source)
			var ll := geo.lat_lon()
			text += "  (%.5f, %.5f)" % [ll.lat, ll.lon]
		_origin_label.text = text
		_e_edit.text = "%.2f" % geo.easting
		_n_edit.text = "%.2f" % geo.northing
		_zone_spin.set_value_no_signal(geo.utm_zone)
		_h_edit.text = "%.2f" % geo.height if geo.height_known else ""
		_rot_edit.text = "%.4f" % geo.rotation_deg
	_refresh_origin_box()
	var terrain := _terrain_node(sm)
	_level_check.disabled = not (terrain and terrain.data)
	_level_check.set_pressed_no_signal(terrain != null and not terrain.platforms.is_empty())
	_attribution.text = terrain.data.attribution if terrain and terrain.data else ""
	if terrain and terrain.data and _near_check.button_pressed and GroundTextures.present():
		_attribution.text += "\n" + GroundTextures.CREDIT

# --- Actions -------------------------------------------------------------------

func _on_apply_origin() -> void:
	var sm := _sequence_manager()
	if not sm:
		_set_status("No hay SequenceManager en la escena.")
		return
	var geo := _geo(sm, true)
	var ll := _latlon_edit.text.replace(";", ",").split(",", false)
	var zone := int(_zone_spin.value)
	if ll.size() == 2 and ll[0].strip_edges().is_valid_float() and ll[1].strip_edges().is_valid_float():
		var lat := ll[0].strip_edges().to_float()
		var lon := ll[1].strip_edges().to_float()
		if zone == 0:
			zone = Utm.zone_for_lon(lon)
		var en := Utm.from_geo(lat, lon, zone)
		geo.easting = en.easting
		geo.northing = en.northing
		geo.south = lat < 0.0
	elif _e_edit.text.is_valid_float() and _n_edit.text.is_valid_float():
		geo.easting = _e_edit.text.to_float()
		geo.northing = _n_edit.text.to_float()
	else:
		_set_status("Escribe lat, lon (p. ej. 40.41680, -3.70380) o E y N en metros.")
		return
	geo.utm_zone = zone
	geo.zone_source = "manual" if zone > 0 else ""
	geo.source = "manual"
	if _h_edit.text.strip_edges().is_valid_float():
		geo.height = _h_edit.text.to_float()
		geo.height_known = true
	else:
		geo.height_known = false
	if _rot_edit.text.strip_edges().is_valid_float():
		geo.rotation_deg = _rot_edit.text.to_float()
	_latlon_edit.text = ""
	EditorInterface.mark_scene_as_unsaved()
	_origin_toggle.button_pressed = false
	refresh()
	# Applying an origin is always followed by the terrain for it: a terrain
	# that already covers the new place just moves under the model (it follows
	# geo_origin), anything else is fetched.
	var terrain := _terrain_node(sm)
	if terrain and terrain.data and _covers(terrain.data, geo, _samples(sm, geo)):
		var msg := "Origen aplicado; el terreno actual ya lo cubre."
		if not geo.height_known:
			var lift := _sit(sm, geo, terrain.data)
			if not is_nan(lift):
				msg += " Altura desconocida: modelo asentado en el suelo (origen a %.2f m)." % geo.height
		_set_status(msg + " " + TerrainBuilder.position_check(terrain.data, _samples(sm, geo)).text)
		refresh()
		return
	_set_status("Origen aplicado.")
	_on_download()

## Zone from ground heights; 0 (with the reason in the status line) if it
## cannot be told safely.
func _detect_zone(sm: Node, geo: GeoOrigin) -> int:
	if not geo.height_known:
		_set_status("El huso no se puede deducir sin la altura real del modelo: indícalo a mano (o usa lat/lon).")
		return 0
	var samples := _samples(sm, geo)
	var bottoms: Array = samples.map(func(s): return s.bottom)
	bottoms.sort()
	var model_h: float = bottoms[bottoms.size() >> 1] if not bottoms.is_empty() else geo.height
	var provider := SpainIgnProvider.new()
	var result := await _service.detect_zone(provider, geo.easting, geo.northing, model_h, CACHE_ROOT.path_join("_zone_probes"))
	_set_status(result.detail)
	return result.zone

func _on_download() -> void:
	if _busy:
		_set_status("Ya hay una descarga en marcha.")
		return
	var sm := _sequence_manager()
	var geo := _geo(sm)
	if not geo or not geo.has_position():
		_set_status("El modelo no tiene georreferencia: indica lat/lon (o E, N y huso) y pulsa Aplicar origen.")
		return
	_set_busy(true)
	await _download(sm, geo)
	_set_busy(false)
	refresh()

func _download(sm: Node, geo: GeoOrigin) -> void:
	if geo.utm_zone == 0:
		var zone := await _detect_zone(sm, geo)
		if zone == 0:
			return
		geo.utm_zone = zone
		geo.zone_source = "auto"
	var ll := geo.lat_lon()
	var provider := TerrainService.provider_for(ll.lat, ll.lon)
	if not provider:
		_set_status("No hay proveedor de terreno para %.4f, %.4f." % [ll.lat, ll.lon])
		return
	var spec := TerrainSpec.create(geo.utm_zone, geo.easting, geo.northing, _preset.get_item_metadata(_preset.selected), geo.south)
	_set_status("Terreno de %s alrededor de %.5f, %.5f (huso %d)..." % [provider.display_name(), ll.lat, ll.lon, geo.utm_zone])
	var result := await _service.build(spec, provider, CACHE_ROOT)
	if result.error != "":
		return
	await _finish(sm, geo, result)

func _finish(sm: Node, geo: GeoOrigin, result: Dictionary) -> void:
	if _near_check.button_pressed:
		var err := await GroundTextures.ensure(_service)
		if err != "":
			_set_status("Texturas de suelo no disponibles (%s); el terreno usa solo la ortofoto." % err)
	EditorInterface.get_resource_filesystem().scan()
	var data: TerrainData = result.data
	var is_new := _terrain_node(sm) == null
	var terrain := _place_terrain(sm, geo, data)
	var msg := "Terreno listo: %d x %d puntos cada %.0f m, alturas %.1f a %.1f m (%s)." % [
		data.grid_n, data.grid_n, data.cell, data.min_height, data.max_height, result.path]
	if not geo.height_known:
		var lift := _sit(sm, geo, data)
		msg += " Altura desconocida: modelo asentado en el suelo (origen a %.2f m, ajústalo en Altura si hace falta)." % geo.height
		if is_nan(lift):
			msg += " (No se pudo asentar: el modelo no tiene piezas sobre el terreno.)"
	var check := TerrainBuilder.position_check(data, _samples(sm, geo))
	msg += " " + check.text
	# A first terrain under a schedule with earthworks is a building site:
	# level it. Later downloads keep whatever the levelling is now.
	if terrain and is_new:
		var levelled := _level(sm, terrain, true)
		if levelled != "":
			msg += " " + levelled
	var sun := _ensure_sun()
	if sun != "":
		msg += " " + sun
	_set_status(msg)
	if terrain:
		EditorInterface.mark_scene_as_unsaved()

func _place_terrain(sm: Node, geo: GeoOrigin, data: TerrainData) -> ConstructionTerrain:
	var root := EditorInterface.get_edited_scene_root()
	var container := _container(sm)
	var terrain := _terrain_node(sm)
	if not terrain:
		terrain = ConstructionTerrain.new()
		terrain.name = "Terrain"
		sm.add_child(terrain, true)
		terrain.owner = root
	terrain.use_near_textures = _near_check.button_pressed
	terrain.geo_origin = geo
	terrain.anchor_path = terrain.get_path_to(container) if container else NodePath()
	terrain.data = data
	terrain.rebuild()
	return terrain

## Raises/lowers the origin so the deepest part just touches the ground.
func _sit(sm: Node, geo: GeoOrigin, data: TerrainData) -> float:
	var check := TerrainBuilder.position_check(data, _samples(sm, geo))
	if check.count == 0:
		return NAN
	geo.height += check.lift
	geo.height_known = true
	return check.lift

func _on_sit() -> void:
	var sm := _sequence_manager()
	var terrain := _terrain_node(sm)
	var geo := _geo(sm)
	if not terrain or not terrain.data or not geo:
		_set_status("No hay terreno en la escena.")
		return
	var lift := _sit(sm, geo, terrain.data)
	if is_nan(lift):
		_set_status("El modelo queda fuera del terreno descargado.")
		return
	EditorInterface.mark_scene_as_unsaved()
	_set_status("Origen %+.2f m: ahora a %.2f m. %s" % [lift, geo.height, TerrainBuilder.position_check(terrain.data, _samples(sm, geo)).text])
	refresh()

func _on_level_toggled(on: bool) -> void:
	var sm := _sequence_manager()
	var terrain := _terrain_node(sm)
	if not terrain or not terrain.data:
		_set_status("Primero hace falta el terreno (Descargar terreno).")
		refresh()
		return
	if on:
		var text := _level(sm, terrain, false)
		_set_status(text if text != "" else "El modelo no tiene piezas con geometría.")
	elif not terrain.platforms.is_empty():
		terrain.platforms = []
		terrain.rebuild()
		EditorInterface.mark_scene_as_unsaved()
		_set_status("Plataformas quitadas: terreno natural.")
	refresh()

## Levels the ground for a building: a pad at the level the model stands on
## and a pit down to the footings, tied to the schedule's earthworks. With
## `only_with_earthworks`, does nothing unless some platform found an earthwork
## activity to follow -- the automatic case, where a schedule with no
## earthworks says nothing about whether the site is levelled. Returns the
## status text, or "" when nothing was done.
func _level(sm: Node, terrain: ConstructionTerrain, only_with_earthworks: bool) -> String:
	var container := _container(sm)
	if not container:
		return ""
	var list := TerrainGrading.platforms_from_model(container, _schedule_actions(sm), terrain.level_margin, terrain.level_slope)
	if list.is_empty():
		return ""
	if only_with_earthworks and not list.any(func(p): return not p.activities.is_empty()):
		return ""
	terrain.platforms = list
	terrain.rebuild()
	EditorInterface.mark_scene_as_unsaved()
	var geo := _geo(sm)
	var lines: Array = []
	for p in list:
		var ext := Rect2(p.footprint[0], Vector2.ZERO)
		for q in p.footprint:
			ext = ext.expand(q)
		var when := ", con %s" % ", ".join(p.activities) if not p.activities.is_empty() else ", desde el día 0"
		var abs_level := " (%.2f m)" % geo.local_to_map(Vector3(0.0, p.level, 0.0))[2] if geo and geo.height_known else ""
		lines.append("%s %.0f x %.0f m a cota %.2f%s%s" % [p.name, ext.size.x, ext.size.y, p.level, abs_level, when])
	var g := terrain.grading()
	var volumes := " Desmonte %.0f m³, terraplén %.0f m³." % [g.cut_m3, g.fill_m3] if g else ""
	return "Nivelado: " + "; ".join(lines) + "." + volumes + " Ajusta las plataformas en el inspector del nodo Terrain."

## [{id, prefix, text}] for every action in the scene's construction JSON.
func _schedule_actions(sm: Node) -> Array:
	var out: Array = []
	var path: String = sm.get("construction_json_path") if sm else ""
	if path == "" or not FileAccess.file_exists(path):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return out
	for step in parsed.get("steps", []):
		for a in step.get("actions", []):
			var id := ConstructionSchedule._action_id(a)
			if id != "":
				out.append({"id": id, "prefix": a.get("target_prefix", ""), "text": "%s %s %s" % [id, a.get("name", ""), a.get("comment", "")]})
	return out

## Adds a GeoSun -- the sun over the site on the timeline's date -- when the
## scene has no directional light at all; an authored light always wins.
## Returns the status text, or "" when nothing was added.
func _ensure_sun() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if not root or not root.find_children("*", "DirectionalLight3D", true, false).is_empty():
		return ""
	var sun := GeoSun.new()
	sun.name = "GeoSun"
	sun.shadow_enabled = true
	root.add_child(sun, true)
	sun.owner = root
	var sm := _sequence_manager()
	if sm:
		sun.sequence_manager_path = sun.get_path_to(sm)
	sun.set_date_from_unix(Time.get_unix_time_from_system())
	EditorInterface.mark_scene_as_unsaved()
	return "Sol de la fecha añadido (GeoSun, a las %.2f h locales)." % sun.time_of_day

func _on_files() -> void:
	var sm := _sequence_manager()
	var geo := _geo(sm)
	if not geo or not geo.is_located():
		_set_status("Para usar archivos propios hace falta el origen con huso (Aplicar origen).")
		return
	if not _files_dialog:
		_files_dialog = EditorFileDialog.new()
		_files_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
		_files_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_files_dialog.add_filter("*.asc", "Elevación ASC")
		_files_dialog.add_filter("*.jpg, *.jpeg, *.png", "Ortofoto con world file")
		_files_dialog.title = "Elige un .asc y, opcionalmente, ortofotos"
		_files_dialog.files_selected.connect(_on_files_selected)
		add_child(_files_dialog)
	_files_dialog.popup_file_dialog()

func _on_files_selected(paths: PackedStringArray) -> void:
	if _busy:
		return
	var asc := ""
	var images: Array = []
	for p in paths:
		if p.get_extension().to_lower() == "asc":
			asc = p
		else:
			images.append(p)
	if asc == "":
		_set_status("Falta el archivo de elevación .asc.")
		return
	var sm := _sequence_manager()
	var geo := _geo(sm)
	var spec := TerrainSpec.create(geo.utm_zone, geo.easting, geo.northing, _preset.get_item_metadata(_preset.selected), geo.south)
	_set_busy(true)
	var result := await _service.build_from_files(spec, asc, images, CACHE_ROOT)
	if result.error == "":
		await _finish(sm, geo, result)
	_set_busy(false)
	refresh()

## Called by the dock once an IFC import has finished and SequenceManager has
## its GeoOrigin.
func on_ifc_imported() -> void:
	refresh()
	var sm := _sequence_manager()
	var geo := _geo(sm)
	if not geo or not geo.has_position():
		_set_status("El IFC no trae georreferencia: para el terreno, indica lat/lon del centro del modelo y pulsa Aplicar origen.")
		return
	# A terrain that already covers every model (e.g. the second model of the
	# same site) is kept: rebuilding it would give the same ground.
	var terrain := _terrain_node(sm)
	if terrain and terrain.data and not _busy and _covers(terrain.data, geo, _samples(sm, geo)):
		_set_status("El terreno actual ya cubre todos los modelos. " + TerrainBuilder.position_check(terrain.data, _samples(sm, geo)).text)
		return
	if _auto_check.button_pressed and not _busy:
		_on_download()

## Whether `data` is this origin's map grid and holds every sample.
func _covers(data: TerrainData, geo: GeoOrigin, samples: Array) -> bool:
	if samples.is_empty() or data.zone != geo.utm_zone or data.south != geo.south:
		return false
	for s in samples:
		if not data.contains(s.e, s.n):
			return false
	return true
