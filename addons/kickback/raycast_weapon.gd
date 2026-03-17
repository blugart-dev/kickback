class_name RaycastWeapon
extends Node3D

@export var impulse_magnitude: float = 8.0
@export var ray_length: float = 100.0

signal hit_reported(bone_name: String)

var _camera: Camera3D


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_camera = get_viewport().get_camera_3d()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _shoot(screen_pos: Vector2) -> void:
	if not _camera:
		return
	var from := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	var to := from + direction * ray_length

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 << 4  # Layer 5 (0-indexed bit 4)
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		hit_reported.emit("Miss")
		return

	var collider: CollisionObject3D = result["collider"]
	if collider is PhysicalBone3D:
		var hit_pos: Vector3 = result["position"]
		var local_offset := collider.to_local(hit_pos)
		collider.apply_impulse(direction * impulse_magnitude, local_offset)
		hit_reported.emit(collider.name)
	else:
		hit_reported.emit("Non-bone: %s" % collider.name)
