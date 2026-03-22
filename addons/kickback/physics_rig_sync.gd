## Synchronizes physics ragdoll body transforms back to the visible Skeleton3D.
## Runs every frame when active, writing bone pose overrides from RigidBody3D positions.
class_name PhysicsRigSync
extends Node

## Path to the Skeleton3D whose bone poses are overridden by physics bodies.
@export var skeleton_path: NodePath
## Path to the PhysicsRigBuilder that provides the physics body transforms.
@export var rig_builder_path: NodePath

var _skeleton: Skeleton3D
var _rig_builder: PhysicsRigBuilder
var _active: bool = false
var _profile: RagdollProfile

var _bone_cache: Array[Dictionary] = []  # [{body: RigidBody3D, bone_idx: int}, ...]
var _intermediate_cache: Array[Dictionary] = []  # [{bone_idx, body_a, body_b, weight, use_a_basis}]
var _cache_built: bool = false


func configure(profile: RagdollProfile) -> void:
	_profile = profile


func _ready() -> void:
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder


## Enables or disables skeleton sync. When the rig is always-simulated,
## sync should stay on permanently — bodies always drive the visible skeleton.
func set_active(value: bool) -> void:
	_active = value
	if not value and _skeleton:
		for bone_idx in _skeleton.get_bone_count():
			_skeleton.set_bone_global_pose_override(bone_idx, Transform3D(), 0.0, false)


func is_active() -> bool:
	return _active


## Forces an immediate skeleton sync outside the normal _process() cycle.
## Call after teleporting the character root and restoring body transforms
## to prevent a 1-frame visual pop.
func sync_now() -> void:
	if not _active or not _rig_builder or not _skeleton:
		return
	if not _cache_built:
		_build_cache()
	_do_sync()


func _build_cache() -> void:
	if not _profile:
		_profile = RagdollProfile.create_mixamo_default()

	_bone_cache.clear()
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var bone_name: String = _rig_builder.get_bone_name_for_body(rig_name)
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			_bone_cache.append({"body": bodies[rig_name], "bone_idx": bone_idx})

	_intermediate_cache.clear()
	for entry: IntermediateBoneEntry in _profile.intermediate_bones:
		var bone_idx := _skeleton.find_bone(entry.skeleton_bone)
		if bone_idx >= 0 and entry.rig_body_a in bodies and entry.rig_body_b in bodies:
			_intermediate_cache.append({
				"bone_idx": bone_idx,
				"body_a": entry.rig_body_a,
				"body_b": entry.rig_body_b,
				"weight": entry.blend_weight,
				"use_a_basis": entry.use_a_basis,
			})

	_cache_built = true


func _process(_delta: float) -> void:
	if not _active or not _rig_builder or not _skeleton:
		return
	if not _cache_built:
		_build_cache()
	_do_sync()


func _do_sync() -> void:
	var skel_global_inv := _skeleton.global_transform.affine_inverse()

	# Direct sync: body transform IS the bone transform
	for entry: Dictionary in _bone_cache:
		var body: RigidBody3D = entry.body
		var local_pose: Transform3D = skel_global_inv * body.global_transform
		_safe_set_bone_override(entry.bone_idx, local_pose)

	# Interpolate intermediate bones
	var bodies := _rig_builder.get_bodies()
	for entry: Dictionary in _intermediate_cache:
		var body_a: RigidBody3D = bodies.get(entry.body_a)
		var body_b: RigidBody3D = bodies.get(entry.body_b)
		if not body_a or not body_b:
			continue
		var pos_a: Vector3 = body_a.global_position
		var pos_b: Vector3 = body_b.global_position
		var mid := pos_a.lerp(pos_b, entry.weight)
		var basis_source: Basis = body_a.global_basis if entry.use_a_basis else body_b.global_basis
		var local_pose := skel_global_inv * Transform3D(basis_source, mid)
		_safe_set_bone_override(entry.bone_idx, local_pose)


func _safe_set_bone_override(bone_idx: int, xform: Transform3D) -> void:
	var det := xform.basis.determinant()
	if det < 0.001 and det > -0.001:
		return
	_skeleton.set_bone_global_pose_override(bone_idx, xform, 1.0, true)
