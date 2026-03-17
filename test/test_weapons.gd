extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _rig_builder: PhysicsRigBuilder = %PhysicsRigBuilder
@onready var _rig_sync: PhysicsRigSync = %PhysicsRigSync
@onready var _spring: SpringResolver = %SpringResolver
@onready var _controller: ActiveRagdollController = %ActiveRagdollController

var _profiles: Array[WeaponProfile] = []
var _current_profile_idx: int = 0


func _ready() -> void:
	var simulator := %Character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()

	_profiles = [
		load("res://addons/kickback/resources/bullet.tres"),
		load("res://addons/kickback/resources/shotgun.tres"),
		load("res://addons/kickback/resources/explosion.tres"),
		load("res://addons/kickback/resources/melee.tres"),
		load("res://addons/kickback/resources/arrow.tres"),
	]

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_rig_builder.set_enabled(true)
	_rig_sync.set_active(true)
	_spring.set_active(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var prev := _current_profile_idx
		match event.keycode:
			KEY_1: _current_profile_idx = 0
			KEY_2: _current_profile_idx = 1
			KEY_3: _current_profile_idx = 2
			KEY_4: _current_profile_idx = 3
			KEY_5: _current_profile_idx = 4
		if prev != _current_profile_idx:
			_hit_label.text = "Switched to: %s" % _profiles[_current_profile_idx].weapon_name

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
		_hit_label.text = "Miss"
		return

	var collider: CollisionObject3D = result["collider"]
	if collider is RigidBody3D:
		var profile: WeaponProfile = _profiles[_current_profile_idx]
		_controller.apply_hit(collider, direction.normalized(), result["position"], profile)
		_hit_label.text = "Hit: %s with %s" % [collider.name, profile.weapon_name]


func _process(_delta: float) -> void:
	var profile: WeaponProfile = _profiles[_current_profile_idx]
	var wname: String = profile.weapon_name if profile else "NONE"
	_state_label.text = "[%d] %s  |  Impulse: %.0f  |  Reduction: %.0f%%  |  Spread: %d  |  FPS: %d  |  1-5 = switch" % [
		_current_profile_idx + 1, wname, profile.base_impulse * profile.impulse_transfer_ratio,
		profile.strength_reduction * 100, profile.strength_spread, Engine.get_frames_per_second()]
