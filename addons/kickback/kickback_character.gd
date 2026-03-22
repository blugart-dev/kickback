## Central coordinator for a Kickback-enabled character. Detects available
## sibling controllers and routes incoming hits to the appropriate one.
## If ActiveRagdollController is present, it takes priority over partial.
@icon("res://addons/kickback/icons/kickback_character.svg")
class_name KickbackCharacter
extends Node

## Which controller mode is active for this character.
enum Mode {
	ACTIVE,   ## Full physics rig with spring-driven joints.
	PARTIAL,  ## PhysicalBoneSimulator3D on hit bones only.
	NONE,     ## No controllers available.
}

@export_group("References")
## Path to the Skeleton3D node that drives this character's mesh.
@export var skeleton_path: NodePath
## Path to the AnimationPlayer (optional — only needed if using RagdollAnimator).
@export var animation_player_path: NodePath
## Path to the character's root Node3D (gameplay root, not model sub-node).
## This node is teleported during ragdoll recovery. The setup tool defaults to
## ".." assuming Kickback nodes are direct children of the character root. If
## nodes are inside a model sub-scene, override to reach the actual gameplay root.
@export var character_root_path: NodePath

@export_group("Configuration")
## Skeleton-dependent ragdoll config (bone mapping, joints, shapes).
## If null, defaults to Mixamo humanoid.
@export var ragdoll_profile: RagdollProfile
## Physics tuning (spring strengths, recovery, collision layers).
## If null, uses built-in defaults.
@export var ragdoll_tuning: RagdollTuning

var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _character_root: Node3D
var _simulator: PhysicalBoneSimulator3D

var _rig_builder: PhysicsRigBuilder
var _rig_sync: PhysicsRigSync
var _spring: SpringResolver
var _active_controller: ActiveRagdollController
var _partial_controller: PartialRagdollController

var _mode: int = Mode.NONE
var _ready_complete: bool = false

## Emitted when all controllers are initialized and the character is ready for use.
signal setup_complete()


func _ready() -> void:
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not _skeleton:
		push_error("KickbackCharacter: skeleton_path is invalid or missing — cannot initialize.")
		return

	if not animation_player_path.is_empty():
		_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer

	if not character_root_path.is_empty():
		_character_root = get_node_or_null(character_root_path) as Node3D

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

	# Determine mode: active ragdoll takes priority if all its nodes are present
	if _rig_builder and _spring and _rig_sync and _active_controller:
		_mode = Mode.ACTIVE
	elif _partial_controller and _simulator:
		_mode = Mode.PARTIAL

	_validate_setup()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# Enable the chosen mode
	if _mode == Mode.ACTIVE:
		_rig_builder.set_enabled(true)
		_rig_sync.set_active(true)
		_spring.set_active(true)
		# Disable simulator so its PhysicalBone3D colliders don't intercept raycasts
		if _simulator:
			_simulator.active = false
	elif _mode == Mode.PARTIAL:
		_simulator.active = true

	_ready_complete = true
	setup_complete.emit()


## Routes an incoming hit to the active controller.
## [param body_or_bone] should be a RigidBody3D (active) or PhysicalBone3D (partial).
func receive_hit(body_or_bone: CollisionObject3D, hit_dir: Vector3, hit_pos: Vector3, profile: ImpactProfile) -> void:
	match _mode:
		Mode.ACTIVE:
			if _active_controller and body_or_bone is RigidBody3D:
				_active_controller.apply_hit(body_or_bone, hit_dir, hit_pos, profile)
		Mode.PARTIAL:
			if _partial_controller and body_or_bone is PhysicalBone3D:
				var event := HitEvent.new()
				event.hit_position = hit_pos
				event.hit_direction = hit_dir
				event.hit_bone_name = body_or_bone.bone_name
				event.impulse_magnitude = profile.base_impulse * profile.impulse_transfer_ratio
				event.hit_bone = body_or_bone
				event.hit_bone_region = HitEvent.classify_region(body_or_bone.bone_name)
				_partial_controller.apply_hit(event)


## Returns the current mode as a [enum Mode] value.
func get_mode() -> int:
	return _mode


## Returns a human-readable label for the current mode.
func get_mode_name() -> String:
	match _mode:
		Mode.ACTIVE: return "ACTIVE"
		Mode.PARTIAL: return "PARTIAL"
		Mode.NONE: return "NONE"
	return "UNKNOWN"


## Returns true if the character is in full ragdoll, getting up, or persistent ragdoll.
## Does NOT return true during stagger — use [method is_staggering] for that.
func is_ragdolled() -> bool:
	if _active_controller:
		var s := _active_controller.get_state()
		return s == ActiveRagdollController.State.RAGDOLL \
			or s == ActiveRagdollController.State.GETTING_UP \
			or s == ActiveRagdollController.State.PERSISTENT
	return false


## Returns true if the character is currently staggering (hit-reactive but on feet).
func is_staggering() -> bool:
	if _active_controller:
		return _active_controller.get_state() == ActiveRagdollController.State.STAGGER
	return false


## Forces the character into a stagger. Recovers automatically after stagger_duration.
func trigger_stagger(hit_dir: Vector3 = Vector3.FORWARD) -> void:
	if _active_controller:
		_active_controller.trigger_stagger(hit_dir)
	else:
		push_warning("KickbackCharacter: no ActiveRagdollController available for trigger_stagger()")


## Causes a brief defensive flinch toward the threat direction.
## Call when the character detects incoming danger (nearby gunfire, melee wind-up).
func anticipate_threat(threat_dir: Vector3, urgency: float = 0.5) -> void:
	if _active_controller:
		_active_controller.anticipate_threat(threat_dir, urgency)


## Returns the active ragdoll state name, or "N/A" if no active controller.
func get_active_state_name() -> String:
	if _active_controller:
		return _active_controller.get_state_name()
	return "N/A"


## Returns the active ragdoll state as an [enum ActiveRagdollController.State] int.
## Returns -1 if no active controller is present.
func get_active_state() -> int:
	if _active_controller:
		return _active_controller.get_state()
	return -1


## Returns true if the Kickback system has finished initializing.
func is_setup_complete() -> bool:
	return _ready_complete


## Forces the character to ragdoll immediately. Recovers automatically.
func trigger_ragdoll() -> void:
	if _active_controller:
		_active_controller.trigger_ragdoll()
	else:
		push_warning("KickbackCharacter: no ActiveRagdollController available for trigger_ragdoll()")


## Enables or disables persistent ragdoll (death/knockdown).
func set_persistent(enabled: bool) -> void:
	if _active_controller:
		_active_controller.set_persistent(enabled)
	else:
		push_warning("KickbackCharacter: no ActiveRagdollController available for set_persistent()")


## Returns the character root Node3D.
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

	if not JoltCheck.is_jolt_active():
		warnings.append("Jolt Physics is not active — enable in Project Settings > Physics > 3D > Physics Engine")

	if not _simulator and _partial_controller:
		warnings.append("No PhysicalBoneSimulator3D on Skeleton3D — partial ragdoll disabled")

	var tuning := ragdoll_tuning if ragdoll_tuning else RagdollTuning.create_default()
	var profile := ragdoll_profile if ragdoll_profile else RagdollProfile.create_mixamo_default()
	var tuning_warnings := tuning.validate_against_profile(profile)
	for w: String in tuning_warnings:
		warnings.append(w)

	if _mode == Mode.NONE:
		warnings.append("No physics controllers found — add ActiveRagdollController or PartialRagdollController as siblings")

	if warnings.is_empty():
		print("Kickback [%s]: setup OK (mode: %s)" % [get_parent().name, get_mode_name()])
	else:
		var msg := "Kickback [%s]: %d issue(s):" % [get_parent().name, warnings.size()]
		for w: String in warnings:
			msg += "\n  - " + w
		push_warning(msg)
