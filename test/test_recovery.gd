extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _rig_builder: PhysicsRigBuilder = %PhysicsRigBuilder
@onready var _rig_sync: PhysicsRigSync = %PhysicsRigSync
@onready var _spring: SpringResolver = %SpringResolver
@onready var _controller: ActiveRagdollController = %ActiveRagdollController

var _explosion_profile: WeaponProfile
var _bullet_profile: WeaponProfile


func _ready() -> void:
	var simulator := %Character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()

	_explosion_profile = load("res://addons/kickback/resources/explosion.tres")
	_bullet_profile = load("res://addons/kickback/resources/bullet.tres")

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_rig_builder.set_enabled(true)
	_rig_sync.set_active(true)
	_spring.set_active(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E:
			_controller.trigger_ragdoll()
			_hit_label.text = "RAGDOLL triggered!"

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _shoot(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var from := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to := from + direction * 100.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = (1 << 3) | (1 << 4)
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider: CollisionObject3D = result["collider"]
	if collider is RigidBody3D:
		_controller.apply_hit(collider, direction.normalized(), result["position"], _bullet_profile)
		_hit_label.text = "Hit: %s" % collider.name


func _process(_delta: float) -> void:
	var state_name := _controller.get_state_name()
	var max_err := _spring.get_max_rotation_error()
	_state_label.text = "State: %s  |  Error: %.2f  |  FPS: %d  |  E = ragdoll  |  LMB = shoot  |  RMB = orbit" % [
		state_name, max_err, Engine.get_frames_per_second()]

	if _controller.get_state() == ActiveRagdollController.State.GETTING_UP:
		var hip_str := _spring.get_bone_strength("Hips")
		var arm_str := _spring.get_bone_strength("UpperArm_L")
		var head_str := _spring.get_bone_strength("Head")
		_hit_label.text = "Recovery: Hips=%.2f  Arm=%.2f  Head=%.2f" % [hip_str, arm_str, head_str]
