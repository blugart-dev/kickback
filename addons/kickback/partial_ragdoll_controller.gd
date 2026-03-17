class_name PartialRagdollController
extends Node

@export var simulator_path: NodePath
@export var skeleton_path: NodePath
@export var animation_player_path: NodePath
@export var hold_time: float = 0.12
@export var blend_duration: float = 0.4

var _simulator: PhysicalBoneSimulator3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _bone_map: Dictionary  # bone_name (String) → PhysicalBone3D
var _physical_bone_names: PackedStringArray
var _active_tween: Tween
var _is_reacting: bool = false


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_simulator = get_node(simulator_path) as PhysicalBoneSimulator3D
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_anim_player = get_node(animation_player_path) as AnimationPlayer
	if _anim_player and _anim_player.has_animation("idle"):
		_anim_player.play("idle")
	_build_bone_map()


func _build_bone_map() -> void:
	_bone_map = {}
	_physical_bone_names = PackedStringArray()
	for child in _simulator.get_children():
		if child is PhysicalBone3D:
			var pb: PhysicalBone3D = child
			_bone_map[pb.bone_name] = pb
			_physical_bone_names.append(pb.bone_name)


func apply_hit(event: HitEvent) -> void:
	var chain := _get_bone_chain(event.hit_bone_name)
	if chain.is_empty():
		return
	# Cancel any active reaction
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_simulator.physical_bones_stop_simulation()
	_simulator.influence = 1.0
	_run_reaction(event, chain)


func _get_bone_chain(bone_name: String) -> PackedStringArray:
	var chain := PackedStringArray()
	var hit_idx := _skeleton.find_bone(bone_name)
	if hit_idx < 0:
		return chain

	# Hit bone
	if bone_name in _bone_map:
		chain.append(bone_name)

	# Children (recursive)
	_collect_children(hit_idx, chain)

	# 1 parent (stop at Hips)
	var parent_idx := _skeleton.get_bone_parent(hit_idx)
	if parent_idx >= 0:
		var parent_name := _skeleton.get_bone_name(parent_idx)
		if parent_name in _bone_map and parent_name != "mixamorig_Hips":
			chain.append(parent_name)

	return chain


func _collect_children(bone_idx: int, chain: PackedStringArray) -> void:
	for child_idx in _skeleton.get_bone_children(bone_idx):
		var child_name := _skeleton.get_bone_name(child_idx)
		if child_name in _bone_map:
			chain.append(child_name)
		_collect_children(child_idx, chain)


func _run_reaction(event: HitEvent, chain: PackedStringArray) -> void:
	_is_reacting = true

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

	# Blend out: tween influence from 1.0 → 0.0
	_active_tween = create_tween()
	_active_tween.tween_property(_simulator, "influence", 0.0, blend_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await _active_tween.finished

	# Reset
	_simulator.physical_bones_stop_simulation()
	_simulator.influence = 1.0
	_is_reacting = false


func is_reacting() -> bool:
	return _is_reacting
