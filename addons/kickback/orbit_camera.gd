class_name OrbitCamera
extends Camera3D

@export var target: Node3D
@export var distance: float = 3.0
@export var min_distance: float = 1.0
@export var max_distance: float = 10.0
@export var sensitivity: float = 0.003
@export var zoom_speed: float = 0.3
@export var target_offset: Vector3 = Vector3(0, 1.0, 0)

var _yaw: float = 0.0
var _pitch: float = -0.2
var _dragging: bool = false


func _ready() -> void:
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance - zoom_speed)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance + zoom_speed)
			_update_transform()

	if event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * sensitivity
		_pitch -= event.relative.y * sensitivity
		_pitch = clampf(_pitch, -PI * 0.45, PI * 0.45)
		_update_transform()


func _update_transform() -> void:
	var pivot := target_offset
	if target:
		pivot = target.global_position + target_offset

	var offset := Vector3(
		distance * cos(_pitch) * sin(_yaw),
		distance * sin(_pitch),
		distance * cos(_pitch) * cos(_yaw)
	)
	global_position = pivot + offset
	look_at(pivot)
