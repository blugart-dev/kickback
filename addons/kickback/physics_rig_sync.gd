## Synchronizes physics ragdoll body transforms back to the visible Skeleton3D.
## Runs every frame when active, writing bone pose overrides from RigidBody3D positions.
class_name PhysicsRigSync
extends Node

@export var skeleton_path: NodePath
@export var rig_builder_path: NodePath

var _skeleton: Skeleton3D
var _rig_builder: PhysicsRigBuilder
var _active: bool = false

var _spine1_idx: int = -1
var _neck_idx: int = -1
var _bone_cache: Array = []  # [{body: RigidBody3D, bone_idx: int}, ...]
var _cache_built: bool = false


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	_spine1_idx = _skeleton.find_bone("mixamorig_Spine1")
	_neck_idx = _skeleton.find_bone("mixamorig_Neck")


func set_active(value: bool) -> void:
	_active = value
	if not value:
		for bone_idx in _skeleton.get_bone_count():
			_skeleton.set_bone_global_pose_override(bone_idx, Transform3D(), 0.0, false)


func is_active() -> bool:
	return _active


func _build_cache() -> void:
	_bone_cache.clear()
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var bone_name: String = _rig_builder.get_bone_name_for_body(rig_name)
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			_bone_cache.append({"body": bodies[rig_name], "bone_idx": bone_idx})
	_cache_built = true


func _process(_delta: float) -> void:
	if not _active or not _rig_builder or not _skeleton:
		return

	if not _cache_built:
		_build_cache()

	var skel_global_inv := _skeleton.global_transform.affine_inverse()

	# Direct sync: body transform IS the bone transform
	for entry: Dictionary in _bone_cache:
		var body: RigidBody3D = entry.body
		var local_pose: Transform3D = skel_global_inv * body.global_transform
		_safe_set_bone_override(entry.bone_idx, local_pose)

	# Interpolate skipped bones (Spine1, Neck)
	var bodies := _rig_builder.get_bodies()
	if _spine1_idx >= 0 and "Spine" in bodies and "Chest" in bodies:
		var spine_pos: Vector3 = bodies["Spine"].global_position
		var chest_pos: Vector3 = bodies["Chest"].global_position
		var mid := (spine_pos + chest_pos) * 0.5
		var local_pose := skel_global_inv * Transform3D(bodies["Spine"].global_basis, mid)
		_safe_set_bone_override(_spine1_idx, local_pose)

	if _neck_idx >= 0 and "Chest" in bodies and "Head" in bodies:
		var chest_pos: Vector3 = bodies["Chest"].global_position
		var head_pos: Vector3 = bodies["Head"].global_position
		var mid := (chest_pos + head_pos) * 0.5
		var local_pose := skel_global_inv * Transform3D(bodies["Chest"].global_basis, mid)
		_safe_set_bone_override(_neck_idx, local_pose)


func _safe_set_bone_override(bone_idx: int, xform: Transform3D) -> void:
	var det := xform.basis.determinant()
	if det < 0.001 and det > -0.001:
		return
	_skeleton.set_bone_global_pose_override(bone_idx, xform, 1.0, true)
