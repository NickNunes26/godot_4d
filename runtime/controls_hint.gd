class_name ControlsHint
extends Control

## What the keys and the mouse do, drawn over the bottom-left corner of the
## view while playing (not in a recording): translucent keycaps for W A S D,
## Q E, Shift, Esc and H, and a mouse with its left button marked. A key lights
## up while it is held, so it is plain which one does what. One line says what
## to do next -- click to fly, or Esc to get the cursor back for the bar.
## H hides and shows it; it dims itself while you fly.
##
## The keys are FreeLookCamera's (runtime/free_look_camera.gd); the labels are
## Spanish, as the rest of the tool's interface.

const CAP := 34.0          # keycap size, px
const GAP := 5.0
const MARGIN := 16.0
const FILL := Color(0.08, 0.09, 0.10, 0.55)
const EDGE := Color(1, 1, 1, 0.35)
const LIT := Color(1.0, 0.78, 0.25, 0.85)
const TEXT := Color(1, 1, 1, 0.92)
const DIM := Color(1, 1, 1, 0.62)
const DIM_AFTER_SEC := 6.0 # flying this long, the panel fades to half

var _hidden := false
var _flying_for := 0.0
var _font: Font
var _box := StyleBoxFlat.new()

func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	size = Vector2(430, 196)
	position = Vector2(MARGIN, get_viewport_rect().size.y - size.y - MARGIN)
	get_viewport().size_changed.connect(func():
		position = Vector2(MARGIN, get_viewport_rect().size.y - size.y - MARGIN))
	_box.set_corner_radius_all(6)
	_box.set_border_width_all(1)

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_H:
		_hidden = not _hidden
		queue_redraw()

func _process(delta: float) -> void:
	var flying := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_flying_for = _flying_for + delta if flying else 0.0
	var target := 0.5 if _flying_for > DIM_AFTER_SEC else 1.0
	modulate.a = move_toward(modulate.a, target, delta * 2.0)
	queue_redraw()

func _draw() -> void:
	if _hidden:
		_cap(Vector2(0, size.y - CAP), "H", Input.is_key_pressed(KEY_H), 0.0)
		_label(Vector2(CAP + 8, size.y - CAP * 0.5), "Mostrar controles", DIM, 13)
		return
	# Panel.
	_box.bg_color = Color(0, 0, 0, 0.28)
	_box.border_color = Color(1, 1, 1, 0.12)
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var flying := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_label(Vector2(12, 18), "Esc: soltar el ratón para usar la barra" if flying else "Clic en la vista para volar con el ratón",
		LIT if not flying else TEXT, 14)
	# Movement block: Q W E / A S D, Shift under.
	var o := Vector2(12, 34)
	var step := CAP + GAP
	_cap(o + Vector2(0, 0), "Q", Input.is_key_pressed(KEY_Q))
	_cap(o + Vector2(step, 0), "W", Input.is_key_pressed(KEY_W))
	_cap(o + Vector2(step * 2, 0), "E", Input.is_key_pressed(KEY_E))
	_cap(o + Vector2(0, step), "A", Input.is_key_pressed(KEY_A))
	_cap(o + Vector2(step, step), "S", Input.is_key_pressed(KEY_S))
	_cap(o + Vector2(step * 2, step), "D", Input.is_key_pressed(KEY_D))
	_cap(o + Vector2(0, step * 2), "Shift", Input.is_key_pressed(KEY_SHIFT), step * 2)
	var tx := o.x + step * 3 + 4
	_label(Vector2(tx, o.y + CAP * 0.5), "W A S D  moverse", TEXT, 14)
	_label(Vector2(tx, o.y + step + CAP * 0.5), "Q / E  bajar / subir", TEXT, 14)
	_label(Vector2(tx, o.y + step * 2 + CAP * 0.5), "Shift  más rápido", TEXT, 14)
	# Mouse.
	var m := Vector2(size.x - 70, 40)
	_mouse(m, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	_label(Vector2(size.x - 92, m.y + 74), "mirar / volar", DIM, 12)
	# Bottom line: Esc, H, and the bar.
	var b := Vector2(12, size.y - CAP - 8)
	_cap(b, "Esc", Input.is_key_pressed(KEY_ESCAPE), 18.0)
	_label(b + Vector2(CAP + 18 + 8, CAP * 0.5), "soltar", DIM, 13)
	_cap(b + Vector2(118, 0), "H", Input.is_key_pressed(KEY_H))
	_label(b + Vector2(118 + CAP + 8, CAP * 0.5), "ocultar", DIM, 13)
	_label(b + Vector2(232, CAP * 0.5 - 8), "Barra superior:", DIM, 12)
	_label(b + Vector2(232, CAP * 0.5 + 8), "Play · fecha · velocidad · Reset", DIM, 12)

## A keycap at `at` (top-left), lit while held; `extra` widens it.
func _cap(at: Vector2, key: String, held: bool, extra: float = 0.0) -> void:
	_box.bg_color = LIT if held else FILL
	_box.border_color = LIT if held else EDGE
	var r := Rect2(at, Vector2(CAP + extra, CAP))
	draw_style_box(_box, r)
	var fs := 15 if key.length() == 1 else 12
	var w := _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + CAP * 0.5 + fs * 0.35),
		key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9) if held else TEXT)

## A mouse, its left button lit while pressed (and marked as the one to use).
func _mouse(at: Vector2, held: bool) -> void:
	var body := Rect2(at, Vector2(44, 64))
	_box.bg_color = FILL
	_box.border_color = EDGE
	_box.set_corner_radius_all(20)
	draw_style_box(_box, body)
	_box.set_corner_radius_all(6)
	var left := PackedVector2Array([at + Vector2(4, 22), at + Vector2(4, 14), at + Vector2(10, 5), at + Vector2(21, 2), at + Vector2(21, 22)])
	draw_colored_polygon(left, LIT if held else Color(LIT, 0.45))
	draw_line(at + Vector2(22, 1), at + Vector2(22, 24), EDGE, 1.0)
	draw_line(at + Vector2(2, 24), at + Vector2(42, 24), EDGE, 1.0)

func _label(at: Vector2, text: String, color: Color, fs: int) -> void:
	draw_string(_font, Vector2(at.x, at.y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
