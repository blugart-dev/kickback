## Right-mouse orbit + scroll-zoom camera rig shared by the Kickback DEMO scenes.
## NOT part of the plugin — it lives under demo/ and is preloaded by the demo
## scripts so the drag / wheel / motion input block isn't re-typed per scene.
## Per-demo differences (start distance and pitch, zoom step and range, pitch
## clamp) are constructor arguments; drag sensitivity is shared.
##
## Usage:
##   const OrbitCamera := preload("res://demo/orbit_camera.gd")
##   var _orbit: OrbitCamera
##   func _ready() -> void:
##       _orbit = OrbitCamera.new($Camera3D, 5.0, -15.0, 1.0, 2.0, 20.0)
##   func _unhandled_input(event: InputEvent) -> void:
##       if _orbit.handle_input(event):
##           return
##       ...
##   func _physics_process(_delta: float) -> void:
##       _orbit.update(pivot)
extends RefCounted

## Degrees of yaw / pitch per pixel of right-mouse drag.
const DRAG_SENSITIVITY := 0.3

var camera: Camera3D
var distance: float
var yaw: float = 0.0
var pitch: float
var zoom_step: float
var min_distance: float
var max_distance: float
var min_pitch: float
var max_pitch: float
var dragging: bool = false


func _init(cam: Camera3D, start_distance: float, start_pitch: float, step: float,
		near: float, far: float, pitch_min: float = -80.0, pitch_max: float = 80.0) -> void:
	camera = cam
	distance = start_distance
	pitch = start_pitch
	zoom_step = step
	min_distance = near
	max_distance = far
	min_pitch = pitch_min
	max_pitch = pitch_max


## Consumes the orbit inputs: right mouse button (drag on/off), mouse wheel
## (zoom) and mouse motion while dragging. Returns true when [param event] was
## one of those so the caller can skip its own handling.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				dragging = mb.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = maxf(distance - zoom_step, min_distance)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = minf(distance + zoom_step, max_distance)
				return true
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * DRAG_SENSITIVITY
		pitch = clampf(pitch - mm.relative.y * DRAG_SENSITIVITY, min_pitch, max_pitch)
		return true
	return false


## Positions the camera at the current yaw / pitch / distance around
## [param pivot] and looks at it. Call from _physics_process (root motion and
## camera updates belong in the physics tick alongside the spring resolver).
func update(pivot: Vector3 = Vector3(0.0, 1.0, 0.0)) -> void:
	if not camera:
		return
	var yaw_rad := deg_to_rad(yaw)
	var pitch_rad := deg_to_rad(pitch)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad),
	) * distance
	camera.global_position = pivot + offset
	camera.look_at(pivot)
