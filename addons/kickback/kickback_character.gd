class_name KickbackCharacter
extends Node

## Coordinator that routes hit events to the appropriate reaction tier
## based on camera distance and the KickbackManager's LOD config.

enum Tier { ACTIVE_RAGDOLL, PARTIAL_RAGDOLL, FLINCH, NONE }

@export var skeleton_path: NodePath
@export var animation_player_path: NodePath
@export var character_root_path: NodePath

var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _character_root: Node3D
var _manager: KickbackManager

var _rig_builder: PhysicsRigBuilder
var _rig_sync: PhysicsRigSync
var _spring: SpringResolver
var _active_controller: ActiveRagdollController
var _partial_controller: PartialRagdollController
var _flinch_controller: FlinchController

var _current_tier: int = Tier.NONE
var _active_ragdoll_enabled: bool = false
var _ready_complete: bool = false

signal tier_changed(new_tier: int)


func _ready() -> void:
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_anim_player = get_node(animation_player_path) as AnimationPlayer
	if not character_root_path.is_empty():
		_character_root = get_node(character_root_path) as Node3D

	# Find manager — check autoload first, then search scene tree
	_manager = get_node_or_null("/root/KickbackManager") as KickbackManager
	if not _manager:
		var root := get_tree().current_scene
		if root:
			_manager = _find_node_of_type(root)

	# Find existing controllers in siblings
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

	# Remove PhysicalBoneSimulator3D if active ragdoll is available
	if _rig_builder and _skeleton:
		var sim := _skeleton.get_node_or_null("PhysicalBoneSimulator3D")
		if sim:
			sim.queue_free()

	# Wait for rig to be built before enabling tiers
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_ready_complete = true


func _find_node_of_type(node: Node) -> KickbackManager:
	if node is KickbackManager:
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child)
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

	if _manager:
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

	# Only use active ragdoll if the rig builder exists
	if target_tier == Tier.ACTIVE_RAGDOLL and not _rig_builder:
		target_tier = Tier.PARTIAL_RAGDOLL
	if target_tier == Tier.PARTIAL_RAGDOLL and not _partial_controller:
		target_tier = Tier.FLINCH
	if target_tier == Tier.FLINCH and not _flinch_controller:
		target_tier = Tier.NONE

	if target_tier != _current_tier:
		_set_tier(target_tier)


func receive_hit(body_or_bone: CollisionObject3D, hit_dir: Vector3, hit_pos: Vector3, profile: WeaponProfile) -> void:
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
	# Deactivate old tier
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

	_current_tier = new_tier
	tier_changed.emit(new_tier)

	# Activate new tier
	if new_tier == Tier.ACTIVE_RAGDOLL:
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


func get_current_tier() -> int:
	return _current_tier


func get_tier_name() -> String:
	match _current_tier:
		Tier.ACTIVE_RAGDOLL: return "ACTIVE"
		Tier.PARTIAL_RAGDOLL: return "PARTIAL"
		Tier.FLINCH: return "FLINCH"
		Tier.NONE: return "NONE"
	return "UNKNOWN"
