extends Node3D
## Test scene for validating the "Add Kickback to Selected" plugin tool.
## Usage:
##   1. Open this scene
##   2. Select the "Character" node in the tree
##   3. Project → Tools → "Add Kickback to Selected"
##   4. Save and run (F5/F6)
##
## Controls: LMB = shoot, RMB = orbit, E = force ragdoll, 1-5 = weapon, F3 = debug

@onready var _state_label: Label = %StateLabel
@onready var _hit_label: Label = %HitLabel

var _character: Node3D
var _kickback: KickbackCharacter
var _rig_builder: PhysicsRigBuilder
var _rig_sync: PhysicsRigSync
var _spring: SpringResolver
var _active_controller: ActiveRagdollController

var _profiles: Array[ImpactProfile] = []
var _current_weapon: int = 0


func _ready() -> void:
	_profiles = [
		load("res://test/resources/bullet.tres"),
		load("res://test/resources/shotgun.tres"),
		load("res://test/resources/explosion.tres"),
		load("res://test/resources/melee.tres"),
		load("res://test/resources/arrow.tres"),
	]

	# Find the character node (first child that has a Skeleton3D)
	for child in get_children():
		if child is Node3D and child.get_node_or_null("Skeleton3D"):
			_character = child
			break

	if not _character:
		_state_label.text = "ERROR: No character found. Drag ybot.tscn into this scene."
		return

	# Auto-discover Kickback controllers from character's children
	for child in _character.get_children():
		if child is KickbackCharacter:
			_kickback = child
		elif child is PhysicsRigBuilder:
			_rig_builder = child
		elif child is PhysicsRigSync:
			_rig_sync = child
		elif child is SpringResolver:
			_spring = child
		elif child is ActiveRagdollController:
			_active_controller = child

	if not _kickback:
		_state_label.text = "No KickbackCharacter found. Select Character → Project → Tools → Add Kickback to Selected"
		return

	# Remove PhysicalBoneSimulator3D (conflicts with active ragdoll rig sync)
	var simulator := _character.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D")
	if simulator:
		simulator.queue_free()

	# Wait for physics rig to initialize, then activate
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if _rig_builder:
		_rig_builder.set_enabled(true)
	if _rig_sync:
		_rig_sync.set_active(true)
	if _spring:
		_spring.set_active(true)

	# Wire orbit camera to discovered character
	var cam := get_node_or_null("Camera3D")
	if cam:
		cam.set("target", _character)

	# Wire strength debug HUD to discovered controllers
	var hud: StrengthDebugHUD = get_node_or_null("CanvasLayer/StrengthHUD")
	if hud and _spring and _rig_builder:
		hud._spring = _spring
		hud._rig_builder = _rig_builder

	_state_label.text = "Ready! LMB = shoot | RMB = orbit | E = ragdoll | 1-5 = weapon | F3 = debug"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				if _active_controller:
					_active_controller.trigger_ragdoll()
					_hit_label.text = "RAGDOLL triggered!"
			KEY_1: _current_weapon = 0
			KEY_2: _current_weapon = 1
			KEY_3: _current_weapon = 2
			KEY_4: _current_weapon = 3
			KEY_5: _current_weapon = 4

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
	var hit_pos: Vector3 = result["position"]
	var profile: ImpactProfile = _profiles[_current_weapon]

	# Route through ActiveRagdollController directly (since we're testing close-range)
	if collider is RigidBody3D and _active_controller:
		_active_controller.apply_hit(collider, direction.normalized(), hit_pos, profile)
		_hit_label.text = "Hit: %s with %s" % [collider.name, profile.profile_name]


func _process(_delta: float) -> void:
	if not _spring:
		return

	var profile: ImpactProfile = _profiles[_current_weapon]
	var state_name := _active_controller.get_state_name() if _active_controller else "N/A"
	var max_err := _spring.get_max_rotation_error()
	_state_label.text = "[%d] %s  |  State: %s  |  Error: %.2f  |  FPS: %d  |  E = ragdoll  |  F3 = debug" % [
		_current_weapon + 1, profile.profile_name, state_name, max_err, Engine.get_frames_per_second()]

	if _active_controller and _active_controller.get_state() == ActiveRagdollController.State.GETTING_UP:
		var hip_str := _spring.get_bone_strength("Hips")
		var arm_str := _spring.get_bone_strength("UpperArm_L")
		var head_str := _spring.get_bone_strength("Head")
		_hit_label.text = "Recovery: Hips=%.2f  Arm=%.2f  Head=%.2f" % [hip_str, arm_str, head_str]
