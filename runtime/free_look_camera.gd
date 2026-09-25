## Free-fly spectator camera: WASD to move, mouse to look, Shift to sprint,
## Q/E for down/up. Left-click captures the mouse and starts flying; Escape
## releases it back to the OS cursor so the TimelineUI buttons/slider are
## clickable again. Uses _unhandled_input (not _input) specifically so
## clicks already consumed by the TimelineUI Controls never trigger capture.
extends Camera3D

@export var move_speed: float = 8.0
@export var sprint_multiplier: float = 3.0
@export var vertical_speed: float = 8.0
@export var mouse_sensitivity: float = 0.003

const _PITCH_LIMIT := 1.5533  # ~89 degrees, avoids the gimbal flip at +/-90

var _mouse_captured: bool = false

func _ready() -> void:
	rotation.z = 0.0  # drop any roll baked into the authored transform

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_mouse_captured(true)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_set_mouse_captured(false)
	elif event is InputEventMouseMotion and _mouse_captured:
		rotation.y -= event.relative.x * mouse_sensitivity
		rotation.x = clampf(rotation.x - event.relative.y * mouse_sensitivity, -_PITCH_LIMIT, _PITCH_LIMIT)

func _process(delta: float) -> void:
	if not _mouse_captured:
		return

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0

	var vertical := 0.0
	if Input.is_key_pressed(KEY_E): vertical += 1.0
	if Input.is_key_pressed(KEY_Q): vertical -= 1.0

	var speed = move_speed * (sprint_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)

	var direction = transform.basis * input_dir
	if direction.length() > 0.0:
		global_position += direction.normalized() * speed * delta
	global_position.y += vertical * vertical_speed * delta

func _set_mouse_captured(captured: bool) -> void:
	_mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
