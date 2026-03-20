class_name RaycastWeapon
extends Node3D

const PHYS_BONE_LAYER := 4   # 0-indexed bit, layer 5 in UI (PhysicalBone3D)
const RIGID_BODY_LAYER := 3  # 0-indexed bit, layer 4 in UI (RigidBody3D rig)

@export var impulse_magnitude: float = 8.0
@export var ray_length: float = 100.0

signal hit_reported(bone_name: String)
signal hit_fired(event: HitEvent)

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
	query.collision_mask = (1 << PHYS_BONE_LAYER) | (1 << RIGID_BODY_LAYER)
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		hit_reported.emit("Miss")
		return

	var collider: CollisionObject3D = result["collider"]
	var hit_pos: Vector3 = result["position"]

	if collider is PhysicalBone3D:
		var bone: PhysicalBone3D = collider
		var ev := HitEvent.new()
		ev.hit_position = hit_pos
		ev.hit_direction = direction.normalized()
		ev.hit_bone_name = bone.bone_name
		ev.impulse_magnitude = impulse_magnitude
		ev.hit_bone = bone
		ev.hit_bone_region = HitEvent.classify_region(bone.bone_name)
		hit_reported.emit(bone.bone_name)
		hit_fired.emit(ev)
	elif collider is RigidBody3D:
		# Dual-skeleton rig body — apply impulse directly
		var body: RigidBody3D = collider
		var local_offset := body.to_local(hit_pos)
		body.apply_impulse(direction.normalized() * impulse_magnitude, local_offset)
		hit_reported.emit(body.name)
	else:
		hit_reported.emit("Non-bone: %s" % collider.name)
