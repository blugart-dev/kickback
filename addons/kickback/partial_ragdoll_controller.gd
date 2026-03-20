## Mid-range hit reaction using PhysicalBoneSimulator3D. On hit, selectively
## simulates the struck bone and its neighbors, applies impulse, then blends
## back to animation over a short duration.
@icon("res://addons/kickback/icons/partial_ragdoll_controller.svg")
class_name PartialRagdollController
extends Node

@export_group("References")
## Path to the PhysicalBoneSimulator3D used for selective bone simulation.
@export var simulator_path: NodePath
## Path to the Skeleton3D for bone hierarchy traversal.
@export var skeleton_path: NodePath
@export_group("Timing")
## How long the hit bone stays in physics simulation before blend-back.
@export var hold_time: float = 0.18
## Duration in seconds for blending from physics simulation back to animation.
@export var blend_duration: float = 0.4

## Emitted when the controller starts or finishes reacting to a hit.
## [param is_reacting] is true when a reaction begins, false when blend-out completes.
## Unlike ActiveRagdollController.state_changed (which emits a State enum int),
## this emits a bool since partial ragdoll has only two states.
signal state_changed(is_reacting: bool)

var _simulator: PhysicalBoneSimulator3D
var _skeleton: Skeleton3D
var _bone_map: Dictionary  # bone_name (String) → PhysicalBone3D
var _active_tween: Tween
var _is_reacting: bool = false
var _profile: RagdollProfile
var _tuning: RagdollTuning


func configure(profile: RagdollProfile, tuning: RagdollTuning) -> void:
	_profile = profile
	_tuning = tuning


func _ready() -> void:
	_simulator = get_node_or_null(simulator_path) as PhysicalBoneSimulator3D
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not _simulator:
		push_warning("PartialRagdollController: No PhysicalBoneSimulator3D found at '%s' — partial ragdoll disabled" % simulator_path)
		return
	_ensure_config()
	_build_bone_map()


func _ensure_config() -> void:
	if not _profile:
		_profile = RagdollProfile.create_mixamo_default()
	if not _tuning:
		_tuning = RagdollTuning.create_default()


func _build_bone_map() -> void:
	_bone_map = {}
	for child in _simulator.get_children():
		if child is PhysicalBone3D:
			var pb: PhysicalBone3D = child
			_bone_map[pb.bone_name] = pb


func apply_hit(event: HitEvent) -> void:
	var chain := _get_bone_chain(event.hit_bone_name)
	if chain.is_empty():
		push_warning("PartialRagdollController: bone '%s' not part of PhysicalBoneSimulator3D — partial ragdoll hit ignored" % event.hit_bone_name)
		return

	# If already reacting during blend-out, extend instead of full restart.
	# Killing the tween abandons the old _blend_out() coroutine's await — this is
	# safe because _is_reacting stays true throughout, and a new blend-out takes over.
	if _is_reacting and _active_tween and _active_tween.is_valid():
		_active_tween.kill()
		# Apply additional impulse to the already-simulating bones
		if event.hit_bone:
			var local_offset := event.hit_bone.to_local(event.hit_position)
			event.hit_bone.apply_impulse(event.hit_direction * event.impulse_magnitude, local_offset)
		# Restart blend-out from current influence
		_blend_out()
		return

	# Fresh reaction
	_simulator.physical_bones_stop_simulation()
	_simulator.influence = 1.0
	_run_reaction(event, chain)


func _get_bone_chain(bone_name: String) -> PackedStringArray:
	var chain := PackedStringArray()
	var hit_idx := _skeleton.find_bone(bone_name)
	if hit_idx < 0:
		return chain

	if bone_name in _bone_map:
		chain.append(bone_name)

	_collect_children(hit_idx, chain)

	var parent_idx := _skeleton.get_bone_parent(hit_idx)
	if parent_idx >= 0:
		var parent_name := _skeleton.get_bone_name(parent_idx)
		if parent_name in _bone_map and parent_name != _profile.root_bone:
			chain.append(parent_name)

	return chain


func _collect_children(bone_idx: int, chain: PackedStringArray) -> void:
	for child_idx in _skeleton.get_bone_children(bone_idx):
		var child_name := _skeleton.get_bone_name(child_idx)
		if child_name in _bone_map:
			chain.append(child_name)
		_collect_children(child_idx, chain)


func _run_reaction(event: HitEvent, chain: PackedStringArray) -> void:
	_set_reacting(true)

	# Start partial simulation (deferred)
	await get_tree().physics_frame
	_simulator.physical_bones_start_simulation(chain)

	# Apply impulse now that the bone is simulating
	await get_tree().physics_frame
	if event.hit_bone:
		var local_offset := event.hit_bone.to_local(event.hit_position)
		event.hit_bone.apply_impulse(event.hit_direction * event.impulse_magnitude, local_offset)

	# Hold — let physics play out
	await get_tree().create_timer(hold_time).timeout

	_blend_out()


func _blend_out() -> void:
	_active_tween = create_tween()
	_active_tween.tween_property(_simulator, "influence", 0.0, blend_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await _active_tween.finished

	_simulator.physical_bones_stop_simulation()
	_simulator.influence = 1.0
	_set_reacting(false)


func _set_reacting(value: bool) -> void:
	if _is_reacting != value:
		_is_reacting = value
		state_changed.emit(_is_reacting)


func is_reacting() -> bool:
	return _is_reacting
