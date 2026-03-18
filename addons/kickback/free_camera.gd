class_name FreeCamera
extends Camera3D

@export var move_speed: float = 5.0
@export var fast_speed: float = 15.0
@export var sensitivity: float = 0.002

var _yaw: float = 0.0
var _pitch: float = 0.0
var _looking: bool = false


func _ready() -> void:
	_yaw = global_rotation.y
	_pitch = global_rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * sensitivity
		_pitch -= event.relative.y * sensitivity
		_pitch = clampf(_pitch, -PI * 0.45, PI * 0.45)
		global_rotation = Vector3(_pitch, _yaw, 0)


func _process(delta: float) -> void:
	if not _looking:
		return

	var speed := fast_speed if Input.is_key_pressed(KEY_SHIFT) else move_speed
	var input := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		input.z -= 1
	if Input.is_key_pressed(KEY_S):
		input.z += 1
	if Input.is_key_pressed(KEY_A):
		input.x -= 1
	if Input.is_key_pressed(KEY_D):
		input.x += 1
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		input.y += 1
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
		input.y -= 1

	if input.length_squared() > 0:
		input = input.normalized()
		global_translate(global_basis * input * speed * delta)
