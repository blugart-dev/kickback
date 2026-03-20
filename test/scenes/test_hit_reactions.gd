extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _rig_builder: PhysicsRigBuilder = %PhysicsRigBuilder
@onready var _rig_sync: PhysicsRigSync = %PhysicsRigSync
@onready var _spring: SpringResolver = %SpringResolver
@onready var _controller: ActiveRagdollController = %ActiveRagdollController


func _ready() -> void:
	var simulator := %Character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()

	# Auto-enable after rig is built
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_rig_builder.set_enabled(true)
	_rig_sync.set_active(true)
	_spring.set_active(true)


func _unhandled_input(event: InputEvent) -> void:
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
	query.collision_mask = (1 << 3) | (1 << 4)  # Layers 4 + 5
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		_hit_label.text = "Miss"
		return

	var collider: CollisionObject3D = result["collider"]
	if collider is RigidBody3D:
		var body: RigidBody3D = collider
		var profile: ImpactProfile = load("res://test/resources/bullet.tres")
		_controller.apply_hit(body, direction.normalized(), result["position"], profile)
		_hit_label.text = "Hit: %s (str: %.2f)" % [body.name, _spring.get_bone_strength(body.name)]


func _process(_delta: float) -> void:
	# Show a few key bone strengths
	var hips_str := _spring.get_bone_strength("Hips")
	var chest_str := _spring.get_bone_strength("Chest")
	var head_str := _spring.get_bone_strength("Head")
	_state_label.text = "FPS: %d  |  Hips: %.2f  Chest: %.2f  Head: %.2f  |  LMB = shoot  |  RMB = orbit" % [
		Engine.get_frames_per_second(), hips_str, chest_str, head_str]
