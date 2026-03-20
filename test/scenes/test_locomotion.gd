extends Node3D

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel
@onready var _rig_builder: PhysicsRigBuilder = %PhysicsRigBuilder
@onready var _rig_sync: PhysicsRigSync = %PhysicsRigSync
@onready var _spring: SpringResolver = %SpringResolver
@onready var _controller: ActiveRagdollController = %ActiveRagdollController
@onready var _character: Node3D = %Character
@onready var _anim_player: AnimationPlayer

var _bullet_profile: ImpactProfile
var _walking: bool = true
var _walk_speed: float = 1.2
var _walk_speed_run: float = 2.5


func _ready() -> void:
	var simulator := _character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()

	_anim_player = _character.get_node("AnimationPlayer")
	_bullet_profile = load("res://test/resources/heavy_bullet.tres")

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_rig_builder.set_enabled(true)
	_rig_sync.set_active(true)
	_spring.set_active(true)

	# Start walking
	if _anim_player.has_animation("walk"):
		_anim_player.play("walk")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_W:
				_walking = true
				_walk_speed = 1.2
				_anim_player.play("walk", 0.3)
			KEY_R:
				_walking = true
				_anim_player.play("run", 0.3)
				_walk_speed = _walk_speed_run
			KEY_S:
				_walking = false
				_anim_player.play("idle", 0.3)
				_walk_speed = 0.0
			KEY_E:
				_controller.trigger_ragdoll()
				_walking = false

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot(event.position)


func _physics_process(delta: float) -> void:
	if not _walking or _controller.get_state() != ActiveRagdollController.State.NORMAL:
		return
	_character.global_position += -_character.global_basis.z * _walk_speed * delta


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
		_controller.apply_hit(collider, direction.normalized(), result["position"], _bullet_profile)
		_hit_label.text = "Hit: %s" % collider.name


func _process(_delta: float) -> void:
	var state := _controller.get_state_name()
	var anim: String = _anim_player.current_animation if _anim_player else "none"
	_state_label.text = "State: %s  |  Anim: %s  |  FPS: %d  |  W=walk R=run S=stop E=ragdoll  |  LMB=shoot  |  RMB=orbit" % [
		state, anim, Engine.get_frames_per_second()]
