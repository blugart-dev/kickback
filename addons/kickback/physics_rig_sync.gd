## Drives the visible Skeleton3D from the physics ragdoll rig, as a SkeletonModifier3D.
## Each modification pass it writes every rig body's transform onto its bone (plus the
## interpolated intermediate bones).
##
## Being a modifier — a child of the Skeleton3D — is what makes this correct: the engine
## applies the modified pose to the skin and then ROLLS IT BACK, so get_bone_pose() outside
## the modification callback stays the clean animation pose that SpringResolver reads as its
## target. No feedback loop, and no deprecated set_bone_global_pose_override. (See
## docs/SKELETON_MODIFIER_MIGRATION.md.)
##
## A SkeletonModifier3D must live under its Skeleton3D. This node is typically created next
## to the other Kickback nodes (a sibling), so it resolves its skeleton from [member
## skeleton_path] and then promotes itself under it on the next idle frame. Deferring the
## reparent lets siblings that resolve it by NodePath at _ready (the controller,
## KickbackCharacter) still find it first; their references survive the move.
##
## NOTE: writes use Skeleton3D.set_bone_global_pose() in parent-first bone order — unlike the
## old global override layer, that setter composes a child's pose through its parent's
## already-written pose, so order matters here.
class_name PhysicsRigSync
extends SkeletonModifier3D

## Path to the Skeleton3D whose bone poses are driven by the physics bodies.
@export var skeleton_path: NodePath
## Path to the PhysicsRigBuilder that provides the physics body transforms.
@export var rig_builder_path: NodePath

var _skeleton: Skeleton3D
var _rig_builder: PhysicsRigBuilder
var _profile: RagdollProfile

## Modified bones, sorted parent-first (ascending skeleton depth). Each entry is one of:
##   {kind="body",         bone_idx, depth, body}
##   {kind="intermediate", bone_idx, depth, body_a, body_b, weight, use_a_basis}
var _ordered: Array[Dictionary] = []
var _cache_built: bool = false


func configure(profile: RagdollProfile) -> void:
	_profile = profile


func _ready() -> void:
	# SkeletonModifier3D defaults to active; stay dormant until the rig is enabled.
	active = false
	if not skeleton_path.is_empty():
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not rig_builder_path.is_empty():
		_rig_builder = get_node_or_null(rig_builder_path) as PhysicsRigBuilder
	# Promote ourselves under the Skeleton3D so the engine processes us as a modifier.
	# Deferred so NodePath-based lookups at _ready resolve us as a sibling first.
	if _skeleton and get_parent() != _skeleton:
		reparent.call_deferred(_skeleton, false)


## Enables or disables physics→skeleton sync. While disabled the modifier contributes
## nothing and the engine renders the plain animation pose.
func set_active(value: bool) -> void:
	active = value


func is_active() -> bool:
	return active


## Forces an immediate modification pass (used after a recovery teleport to avoid a
## one-frame visual pop). No-op until the rig is available and active.
func sync_now() -> void:
	if not active or not _skeleton or not _rig_builder:
		return
	_skeleton.advance(0.0)


func _process_modification_with_delta(_delta: float) -> void:
	if not _rig_builder or not _skeleton:
		return
	if not _cache_built:
		_build_cache()
	if _ordered.is_empty():
		return

	var skel_inv := _skeleton.global_transform.affine_inverse()
	var bodies := _rig_builder.get_bodies()
	for entry: Dictionary in _ordered:
		match entry.kind:
			"body":
				var body: RigidBody3D = entry.body
				_set_bone(entry.bone_idx, skel_inv * body.global_transform)
			"intermediate":
				var body_a: RigidBody3D = bodies.get(entry.body_a)
				var body_b: RigidBody3D = bodies.get(entry.body_b)
				if not body_a or not body_b:
					continue
				var mid := body_a.global_position.lerp(body_b.global_position, entry.weight)
				var basis_src: Basis = body_a.global_basis if entry.use_a_basis else body_b.global_basis
				_set_bone(entry.bone_idx, skel_inv * Transform3D(basis_src, mid))


func _set_bone(bone_idx: int, skel_pose: Transform3D) -> void:
	var det := skel_pose.basis.determinant()
	if det < 0.001 and det > -0.001:
		return
	_skeleton.set_bone_global_pose(bone_idx, skel_pose)


func _build_cache() -> void:
	if not _profile:
		_profile = RagdollProfile.create_mixamo_default()

	var entries: Array[Dictionary] = []
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var bone_name: String = _rig_builder.get_bone_name_for_body(rig_name)
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			entries.append({
				"kind": "body", "bone_idx": bone_idx,
				"depth": _bone_depth(bone_idx), "body": bodies[rig_name],
			})

	for entry: IntermediateBoneEntry in _profile.intermediate_bones:
		var bone_idx := _skeleton.find_bone(entry.skeleton_bone)
		if bone_idx >= 0 and entry.rig_body_a in bodies and entry.rig_body_b in bodies:
			entries.append({
				"kind": "intermediate", "bone_idx": bone_idx, "depth": _bone_depth(bone_idx),
				"body_a": entry.rig_body_a, "body_b": entry.rig_body_b,
				"weight": entry.blend_weight, "use_a_basis": entry.use_a_basis,
			})

	# Parent-first: set_bone_global_pose composes a child through its parent's current pose.
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.depth < b.depth)
	_ordered = entries
	_cache_built = true


func _bone_depth(bone_idx: int) -> int:
	var depth := 0
	var parent := _skeleton.get_bone_parent(bone_idx)
	while parent >= 0:
		depth += 1
		parent = _skeleton.get_bone_parent(parent)
	return depth
