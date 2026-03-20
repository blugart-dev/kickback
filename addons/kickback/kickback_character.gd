## Central coordinator for a Kickback-enabled character. Manages LOD tier switching
## based on camera distance and routes incoming hits to the appropriate controller
## (active ragdoll, partial ragdoll, or flinch animation).
@icon("res://addons/kickback/icons/kickback_character.svg")
class_name KickbackCharacter
extends Node

## Detail level for hit-reaction simulation, ordered from most expensive to cheapest.
enum Tier {
	ACTIVE_RAGDOLL,   ## Full physics rig with spring-driven joints (< 10m).
	PARTIAL_RAGDOLL,  ## PhysicalBoneSimulator3D on hit bones only (10-25m).
	FLINCH,           ## Additive animation blending, no physics (25-50m).
	NONE,             ## No reactions (> 50m or no controller available).
}

@export_group("References")
## Path to the Skeleton3D node that drives this character's mesh.
@export var skeleton_path: NodePath
## Path to the AnimationPlayer that plays animations for this character.
@export var animation_player_path: NodePath
## Path to the character's root Node3D, used for camera distance LOD calculations.
@export var character_root_path: NodePath

@export_group("Configuration")
## Skeleton-dependent ragdoll config (bone mapping, joints, shapes).
## If null, defaults to Mixamo humanoid.
@export var ragdoll_profile: RagdollProfile
## Physics tuning (spring strengths, animation names, collision layers).
## If null, uses built-in defaults.
@export var ragdoll_tuning: RagdollTuning

var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _character_root: Node3D
var _manager: KickbackManager
var _simulator: PhysicalBoneSimulator3D

var _rig_builder: PhysicsRigBuilder
var _rig_sync: PhysicsRigSync
var _spring: SpringResolver
var _active_controller: ActiveRagdollController
var _partial_controller: PartialRagdollController
var _flinch_controller: FlinchController
var _animator: RagdollAnimator

var _current_tier: int = Tier.NONE
var _active_ragdoll_enabled: bool = false
var _ready_complete: bool = false
var _forced_tier: int = -1

## Emitted when the character transitions to a different LOD tier.
signal tier_changed(new_tier: int)


func _ready() -> void:
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not _skeleton:
		push_error("KickbackCharacter: skeleton_path is invalid or missing — cannot initialize.")
		return

	_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if not _anim_player:
		push_error("KickbackCharacter: animation_player_path is invalid or missing — cannot initialize.")
		return

	if not character_root_path.is_empty():
		_character_root = get_node_or_null(character_root_path) as Node3D

	_manager = get_node_or_null("/root/KickbackManager") as KickbackManager
	if not _manager:
		var root := get_tree().current_scene
		if root:
			_manager = _find_manager(root)

	# Find simulator and controllers in siblings
	if _skeleton:
		_simulator = _skeleton.get_node_or_null("PhysicalBoneSimulator3D")

	for sibling in get_parent().get_children():
		if sibling is PhysicsRigBuilder:
			_rig_builder = sibling
		elif sibling is PhysicsRigSync:
			_rig_sync = sibling
		elif sibling is SpringResolver:
			_spring = sibling
		elif sibling is ActiveRagdollController:
			_active_controller = sibling
		elif sibling is PartialRagdollController:
			_partial_controller = sibling
		elif sibling is FlinchController:
			_flinch_controller = sibling
		elif sibling is RagdollAnimator:
			_animator = sibling

	# Distribute configuration to all controllers
	if _rig_builder:
		_rig_builder.configure(ragdoll_profile, ragdoll_tuning)
	if _rig_sync:
		_rig_sync.configure(ragdoll_profile)
	if _spring:
		_spring.configure(ragdoll_tuning)
	if _active_controller:
		_active_controller.configure(ragdoll_profile, ragdoll_tuning)
	if _partial_controller:
		_partial_controller.configure(ragdoll_profile, ragdoll_tuning)
	if _flinch_controller:
		_flinch_controller.configure(ragdoll_tuning)

	# Validate setup and print consolidated warnings
	_validate_setup()

	# Disable simulator initially (will enable when PARTIAL tier is set)
	if _simulator:
		_simulator.active = false

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_ready_complete = true


func _find_manager(node: Node) -> KickbackManager:
	if node is KickbackManager:
		return node
	for child in node.get_children():
		var found := _find_manager(child)
		if found:
			return found
	return null


func _process(_delta: float) -> void:
	if not _ready_complete:
		return

	var camera := get_viewport().get_camera_3d()
	if not camera or not _character_root:
		return

	var distance := camera.global_position.distance_to(_character_root.global_position)
	var target_tier: int = Tier.NONE

	if _forced_tier >= 0:
		target_tier = _forced_tier
	elif _manager:
		var tier_idx := _manager.get_tier(distance)
		target_tier = clampi(tier_idx, 0, Tier.NONE)
	else:
		if distance < 10.0:
			target_tier = Tier.ACTIVE_RAGDOLL
		elif distance < 25.0:
			target_tier = Tier.PARTIAL_RAGDOLL
		elif distance < 50.0:
			target_tier = Tier.FLINCH
		else:
			target_tier = Tier.NONE

	# Fallback if controller for target tier doesn't exist
	if target_tier == Tier.ACTIVE_RAGDOLL and not _rig_builder:
		target_tier = Tier.PARTIAL_RAGDOLL
	if target_tier == Tier.PARTIAL_RAGDOLL and (not _partial_controller or not _simulator):
		target_tier = Tier.FLINCH
	if target_tier == Tier.FLINCH and not _flinch_controller:
		target_tier = Tier.NONE

	if target_tier != _current_tier:
		_set_tier(target_tier)


## Routes an incoming hit to the controller for the current LOD tier.
## [param body_or_bone] should be a RigidBody3D (active) or PhysicalBone3D (partial).
func receive_hit(body_or_bone: CollisionObject3D, hit_dir: Vector3, hit_pos: Vector3, profile: ImpactProfile) -> void:
	match _current_tier:
		Tier.ACTIVE_RAGDOLL:
			if _active_controller and body_or_bone is RigidBody3D:
				_active_controller.apply_hit(body_or_bone, hit_dir, hit_pos, profile)
		Tier.PARTIAL_RAGDOLL:
			if _partial_controller and body_or_bone is PhysicalBone3D:
				var event := HitEvent.new()
				event.hit_position = hit_pos
				event.hit_direction = hit_dir
				event.hit_bone_name = body_or_bone.bone_name
				event.impulse_magnitude = profile.base_impulse * profile.impulse_transfer_ratio
				event.hit_bone = body_or_bone
				event.hit_bone_region = HitEvent.classify_region(body_or_bone.bone_name)
				_partial_controller.apply_hit(event)
		Tier.FLINCH:
			if _flinch_controller:
				var event := HitEvent.new()
				event.hit_position = hit_pos
				event.hit_direction = hit_dir
				event.hit_bone_region = "torso"
				_flinch_controller.on_hit(event)


func _set_tier(new_tier: int) -> void:
	# --- Deactivate old tier ---
	if _current_tier == Tier.ACTIVE_RAGDOLL:
		if _spring:
			_spring.set_active(false)
		if _rig_sync:
			_rig_sync.set_active(false)
		if _rig_builder:
			_rig_builder.set_enabled(false)
		if _active_ragdoll_enabled and _manager:
			_manager.release_active_ragdoll()
			_active_ragdoll_enabled = false
	elif _current_tier == Tier.PARTIAL_RAGDOLL:
		if _simulator:
			_simulator.active = false
			_simulator.physical_bones_stop_simulation()

	_current_tier = new_tier
	tier_changed.emit(new_tier)

	# --- Activate new tier ---
	match new_tier:
		Tier.ACTIVE_RAGDOLL:
			# Disable simulator (conflicts with rig sync)
			if _simulator:
				_simulator.active = false
				_simulator.physical_bones_stop_simulation()
			var allowed := true
			if _manager:
				allowed = _manager.request_active_ragdoll()
			if allowed and _rig_builder and _spring and _rig_sync:
				_rig_builder.set_enabled(true)
				_rig_sync.set_active(true)
				_spring.set_active(true)
				_active_ragdoll_enabled = true
			else:
				_current_tier = Tier.PARTIAL_RAGDOLL
				if _simulator:
					_simulator.active = true

		Tier.PARTIAL_RAGDOLL:
			# Enable simulator for partial ragdoll hits
			if _simulator:
				_simulator.active = true


## Returns the current LOD tier as a [enum Tier] value.
func get_current_tier() -> int:
	return _current_tier


## Returns a human-readable label for the current tier (e.g. "ACTIVE", "PARTIAL").
func get_tier_name() -> String:
	match _current_tier:
		Tier.ACTIVE_RAGDOLL: return "ACTIVE"
		Tier.PARTIAL_RAGDOLL: return "PARTIAL"
		Tier.FLINCH: return "FLINCH"
		Tier.NONE: return "NONE"
	return "UNKNOWN"


## Returns true if the active ragdoll controller is not in NORMAL state
## (i.e., RAGDOLL, GETTING_UP, or PERSISTENT).
func is_ragdolled() -> bool:
	if _active_controller:
		var state: int = _active_controller.get_state()
		return state != ActiveRagdollController.State.NORMAL
	return false


## Returns the active ragdoll state name ("NORMAL", "RAGDOLL", "GETTING UP", "PERSISTENT"),
## or "N/A" if no active ragdoll controller is present.
func get_active_state_name() -> String:
	if _active_controller:
		return _active_controller.get_state_name()
	return "N/A"


## Forces the character to ragdoll immediately. The character will recover automatically.
func trigger_ragdoll() -> void:
	if _active_controller:
		_active_controller.trigger_ragdoll()
	else:
		push_warning("KickbackCharacter: no ActiveRagdollController available for trigger_ragdoll()")


## Enables or disables persistent ragdoll. When enabled, the character stays
## ragdolled until set_persistent(false) is called, which triggers recovery.
func set_persistent(enabled: bool) -> void:
	if _active_controller:
		_active_controller.set_persistent(enabled)
	else:
		push_warning("KickbackCharacter: no ActiveRagdollController available for set_persistent()")


## Forces a specific LOD tier, bypassing distance-based selection.
## Controller fallback still applies (e.g., forcing ACTIVE_RAGDOLL without a rig builder
## will degrade to PARTIAL_RAGDOLL).
func force_tier(tier: int) -> void:
	_forced_tier = tier
	if _ready_complete:
		_set_tier(tier)


## Returns to automatic distance-based LOD tier selection.
func clear_forced_tier() -> void:
	_forced_tier = -1


## Returns the list of animation names that RagdollAnimator expects by default.
static func get_expected_animations() -> Array[StringName]:
	return [
		&"idle",
		&"get_up_face_up",
		&"get_up_face_down",
		&"flinch_front",
		&"flinch_back",
		&"flinch_left",
		&"flinch_right",
	]


## Returns the character root Node3D used for distance calculations, or null.
func get_character_root() -> Node3D:
	return _character_root


## Recursively finds all KickbackCharacter nodes under [param root].
static func find_all(root: Node) -> Array[KickbackCharacter]:
	var result: Array[KickbackCharacter] = []
	_find_all_recursive(root, result)
	return result


static func _find_all_recursive(node: Node, result: Array[KickbackCharacter]) -> void:
	if node is KickbackCharacter:
		result.append(node)
	for child in node.get_children():
		_find_all_recursive(child, result)


func _validate_setup() -> void:
	var warnings := PackedStringArray()

	# Jolt check (once, not per-controller)
	if not JoltCheck.is_jolt_active():
		warnings.append("Jolt Physics is not active — enable in Project Settings > Physics > 3D > Physics Engine")

	# Simulator check
	if not _simulator:
		warnings.append("No PhysicalBoneSimulator3D on Skeleton3D — partial ragdoll tier disabled")

	# Tuning/profile cross-validation
	var tuning := ragdoll_tuning if ragdoll_tuning else RagdollTuning.create_default()
	var profile := ragdoll_profile if ragdoll_profile else RagdollProfile.create_mixamo_default()
	var tuning_warnings := tuning.validate_against_profile(profile)
	for w: String in tuning_warnings:
		warnings.append(w)

	# Print consolidated
	if warnings.is_empty():
		print("Kickback [%s]: setup OK" % get_parent().name)
	else:
		var msg := "Kickback [%s]: %d issue(s):" % [get_parent().name, warnings.size()]
		for w: String in warnings:
			msg += "\n  - " + w
		push_warning(msg)
