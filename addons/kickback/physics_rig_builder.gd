## Builds a physics ragdoll rig from RigidBody3D nodes connected by
## Generic6DOFJoint3D joints. Created at runtime when active ragdoll is enabled.
## Reads bone/joint configuration from a RagdollProfile resource.
@icon("res://addons/kickback/icons/physics_rig_builder.svg")
class_name PhysicsRigBuilder
extends Node3D

## Path to the Skeleton3D whose bones define the ragdoll rig layout.
@export var skeleton_path: NodePath

var _skeleton: Skeleton3D
var _bodies: Dictionary = {}         # rig_name → RigidBody3D
var _rig_to_bone: Dictionary = {}    # rig_name → skeleton bone name
## child rig_name → {parent: String, joint: Generic6DOFJoint3D,
##   anchor_parent: Vector3, anchor_child: Vector3, frame_parent: Transform3D,
##   frame_child: Transform3D} — the joint anchor / limit frame expressed in each
##   body's local frame at build time (see [method get_joints]).
var _joints: Dictionary = {}
var _built: bool = false
var _profile: RagdollProfile
var _tuning: RagdollTuning

## Emitted when all ragdoll bodies and joints have been created.
## After this signal, [method get_bodies] returns the full rig dictionary.
signal bodies_built()


func configure(profile: RagdollProfile, tuning: RagdollTuning) -> void:
	_profile = profile
	_tuning = tuning


func _ready() -> void:
	_skeleton = get_node(skeleton_path) as Skeleton3D
	await get_tree().process_frame
	await get_tree().process_frame
	_build_rig()
	bodies_built.emit()
	set_enabled(false)


func _ensure_config() -> void:
	if not _profile:
		_profile = RagdollProfile.create_mixamo_default()
	if not _tuning:
		_tuning = RagdollTuning.create_default()


func _build_rig() -> void:
	_ensure_config()

	# Check for pre-baked rig nodes from editor
	if _adopt_baked_rig():
		_built = true
		return

	for bone_def: BoneDefinition in _profile.bones:
		var bone_idx := _skeleton.find_bone(bone_def.skeleton_bone)
		if bone_idx < 0:
			push_warning("PhysicsRigBuilder: bone '%s' not found in skeleton (non-critical: rig will use fewer bones)" % bone_def.skeleton_bone)
			continue

		var bone_global := _get_bone_global(bone_def.skeleton_bone)
		var body := _create_body(bone_def, bone_global)
		add_child(body)  # top_level: the transform build_body set IS the world pose
		_bodies[bone_def.rig_name] = body
		_rig_to_bone[bone_def.rig_name] = bone_def.skeleton_bone

	for joint_def: JointDefinition in _profile.joints:
		_create_joint(joint_def)

	_apply_self_collision()
	_built = true


## Scans children for pre-baked RigidBody3D nodes (created by RigBaker in the editor).
## If found and valid, populates _bodies and _rig_to_bone from them. Returns true
## if the baked rig was adopted successfully, false to fall back to runtime generation.
func _adopt_baked_rig() -> bool:
	var baked_bodies: Dictionary = {}
	var baked_bones: Dictionary = {}

	for child in get_children():
		if child is RigidBody3D and child.has_meta("kickback_baked"):
			var rig_name: String = child.get_meta("kickback_rig_name", "")
			var skel_bone: String = child.get_meta("kickback_skeleton_bone", "")
			if rig_name != "" and skel_bone != "":
				baked_bodies[rig_name] = child
				baked_bones[rig_name] = skel_bone

	if baked_bodies.is_empty():
		return false

	# Validate: every bone in the profile should have a baked body
	var missing := PackedStringArray()
	for bone_def: BoneDefinition in _profile.bones:
		if bone_def.rig_name not in baked_bodies:
			missing.append(bone_def.rig_name)

	if not missing.is_empty():
		push_warning("PhysicsRigBuilder: Baked rig is missing %d bones (%s) — falling back to runtime generation" % [missing.size(), ", ".join(missing)])
		return false

	# The baked nodes carry the layer / mask / gravity / damping / limits of
	# whatever tuning was assigned WHEN THEY WERE BAKED. The tuning is the
	# source of truth at runtime, exactly as for a generated rig — re-apply
	# everything the runtime path sets from it, so a tuning change after the
	# bake is not silently ignored (top_level included: older bakes were saved
	# without it, same rationale as in apply_body_tuning).
	for body: RigidBody3D in baked_bodies.values():
		apply_body_tuning(body, _tuning)

	_bodies = baked_bodies
	_rig_to_bone = baked_bones

	# Baked joints: recover the parent→child topology from node_a/node_b, and
	# re-apply the matching JointDefinition (limits scaled by the CURRENT
	# tuning's joint_limit_scale) on top of the baked values.
	var body_to_rig: Dictionary = {}
	for rig_name: String in _bodies:
		body_to_rig[_bodies[rig_name]] = rig_name
	var joint_defs: Dictionary = {}  # "parent→child" → JointDefinition
	for joint_def: JointDefinition in _profile.joints:
		joint_defs["%s→%s" % [joint_def.parent_rig, joint_def.child_rig]] = joint_def
	var unmatched := PackedStringArray()
	for child in get_children():
		if child is Generic6DOFJoint3D:
			var a := child.get_node_or_null(child.node_a)
			var b := child.get_node_or_null(child.node_b)
			if a in body_to_rig and b in body_to_rig:
				var key := "%s→%s" % [body_to_rig[a], body_to_rig[b]]
				if key in joint_defs:
					(joint_defs[key] as JointDefinition).apply_to(child, _tuning.joint_limit_scale)
				else:
					unmatched.append(key)
				_register_joint(body_to_rig[a], body_to_rig[b], child)
	if not unmatched.is_empty():
		push_warning("PhysicsRigBuilder: %d baked joint(s) have no JointDefinition in the profile (%s) — keeping their baked limits; re-bake the rig to match the profile" % [unmatched.size(), ", ".join(unmatched)])
	_apply_self_collision()
	return true


## Excludes every body pair of this rig from colliding unless the tuning asks
## for self-collision (RagdollTuning.self_collision). Jointed pairs are already
## excluded by the joints; the non-adjacent pairs (Chest-Hips, forearm-chest,
## upper arm-spine, ...) overlap in ordinary poses and would otherwise fight
## the springs with contact impulses every tick.
func _apply_self_collision() -> void:
	if _tuning.self_collision:
		return
	var list: Array = _bodies.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			(list[i] as RigidBody3D).add_collision_exception_with(list[j])


func _get_bone_global(bone_name: String) -> Transform3D:
	var idx := _skeleton.find_bone(bone_name)
	if idx < 0:
		return Transform3D.IDENTITY
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx)


func _create_body(bone_def: BoneDefinition, bone_global: Transform3D) -> RigidBody3D:
	var child_global := NO_CHILD_BONE
	if bone_def.child_bone != "" and _skeleton.find_bone(bone_def.child_bone) >= 0:
		child_global = _get_bone_global(bone_def.child_bone)
	return build_body(bone_def, bone_global, child_global, _tuning)


## Sentinel for [method build_body]'s [code]child_global[/code]: the bone has no
## child bone to offset its collision shape toward (shape stays at the bone origin).
const NO_CHILD_BONE := Transform3D(Basis(), Vector3.INF)


## Builds the RigidBody3D (with its CollisionShape3D child) for [param bone_def],
## placed at [param bone_global] (world) with the shape offset toward
## [param child_global] (the child bone's world transform; [constant NO_CHILD_BONE]
## for none) by [member BoneDefinition.shape_offset], and every physics property
## taken from [param tuning] (see [method apply_body_tuning]). Single source of
## truth for body construction — the runtime rig and the editor RigBaker both
## build their bodies here, so they cannot diverge. The body is not yet in the
## tree; it is world-space ([code]top_level[/code]), so its transform is final
## wherever it is parented.
static func build_body(bone_def: BoneDefinition, bone_global: Transform3D, child_global: Transform3D, tuning: RagdollTuning) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = bone_def.rig_name
	body.mass = bone_def.mass
	apply_body_tuning(body, tuning)
	body.transform = bone_global

	# Shape is offset locally along the bone direction (toward child bone)
	var col_shape := SkeletonDetector.create_collision_shape(bone_def)
	if child_global.origin.is_finite():
		var bone_to_child_local := bone_global.affine_inverse() * child_global
		col_shape.position = bone_to_child_local.origin * bone_def.shape_offset
	# Box shapes on bones need rotation: bone Y points along bone direction,
	# but box Y should be height (thin). Rotate 90° on X so box Z (length)
	# aligns with bone Y (forward) and box Y (height) aligns with bone Z (up).
	if bone_def.shape_type == "box":
		col_shape.rotation.x = PI / 2.0
	body.add_child(col_shape)

	return body


## Applies every RigidBody3D property the rig takes from [param tuning] —
## collision layer / mask, gravity scale, damping, sleeping, and world-space
## placement. Called at build time and again when a baked rig is adopted, so the
## tuning (not the bake) is what the bodies run with.
static func apply_body_tuning(body: RigidBody3D, tuning: RagdollTuning) -> void:
	body.collision_layer = tuning.collision_layer
	body.collision_mask = tuning.collision_mask
	body.can_sleep = false
	body.gravity_scale = tuning.gravity_scale
	body.angular_damp = tuning.angular_damp
	body.linear_damp = tuning.linear_damp
	# World-space, immune to ancestor transform writes. Without this, a
	# character root that moves every physics frame (CharacterBody3D
	# move_and_slide, nav-driven NPCs) re-teleports each body to
	# parent_xform * local every frame, silently discarding that frame's
	# integration: the rig visibly freezes while springs pump clamp-level
	# velocities into it — which then release all at once the moment the
	# root stops (death), as an explosive ragdoll. The springs are what
	# carry the rig along with the character (their targets already move
	# with the skeleton); parent inheritance was never load-bearing.
	body.top_level = true


func _create_joint(joint_def: JointDefinition) -> void:
	if joint_def.parent_rig not in _bodies or joint_def.child_rig not in _bodies:
		push_warning("PhysicsRigBuilder: joint '%s→%s' references missing body" % [joint_def.parent_rig, joint_def.child_rig])
		return

	var parent_body: RigidBody3D = _bodies[joint_def.parent_rig]
	var child_body: RigidBody3D = _bodies[joint_def.child_rig]
	var child_bone: String = _rig_to_bone[joint_def.child_rig]
	var parent_bone: String = _rig_to_bone[joint_def.parent_rig]

	var joint := Generic6DOFJoint3D.new()
	joint.name = "%s_to_%s" % [joint_def.parent_rig, joint_def.child_rig]
	add_child(joint)

	# Godot captures a 6DOF joint's two local frames from the joint's and the
	# bodies' transforms at the moment node_a/node_b are assigned; the relative
	# rotation the limits are measured against is ZERO in that configuration.
	# For the rest-centred frames the child body is parked, for the assignment
	# only, where the REST pose would put it relative to the parent body's
	# current pose (parent_now * parent_rest^-1 * child_rest), and the joint at
	# the rest frame in the same parent-relative sense; then it is put back onto
	# its animation pose. Nothing has been simulated yet, so the teleport is free,
	# and frames already captured by this body's other joints are stored local
	# to the bodies (unaffected).
	var restore := false
	var saved_child_xform := child_body.global_transform
	if _profile.joint_frame == RagdollProfile.JointFrame.BUILD_POSE:
		joint.global_transform = _get_bone_global(child_bone)
	else:
		var parent_idx := _skeleton.find_bone(parent_bone)
		var child_idx := _skeleton.find_bone(child_bone)
		var parent_rest := _skeleton.get_bone_global_rest(parent_idx)
		var child_rest := _skeleton.get_bone_global_rest(child_idx)
		var frame_rest: Transform3D  # skeleton-local, at rest
		if _profile.joint_frame == RagdollProfile.JointFrame.BONE_REST:
			frame_rest = child_rest
		else:
			frame_rest = compute_rest_joint_frame(_skeleton, _profile, joint_def)
		# parent_now * parent_rest^-1 maps skeleton-local rest space onto the
		# parent body's current placement (world).
		var rest_to_now := parent_body.global_transform * parent_rest.affine_inverse()
		child_body.global_transform = rest_to_now * child_rest
		joint.global_transform = rest_to_now * frame_rest
		restore = true

	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child_body)

	# Lock linear axes + apply angular limits/compliance (typed, shared with RigBaker)
	joint_def.apply_to(joint, _tuning.joint_limit_scale)
	# Anchors are registered while the bodies sit in the rest-relative pose (a
	# rigid local offset either way — pose independent).
	_register_joint(joint_def.parent_rig, joint_def.child_rig, joint)
	if restore:
		child_body.global_transform = saved_child_xform


## The ANATOMICAL joint frame for [param joint_def], in SKELETON-LOCAL space at
## the rest pose (see [enum RagdollProfile.JointFrame]). Origin: the child bone's
## rest origin. Axes:
##   +Y  along the child bone — the bone's own local axis nearest the direction
##       toward its child (its BoneDefinition.child_bone; the bone's own local
##       +Y when it has none), or that raw direction if no local axis is within
##       35 deg of it (identity-basis rigs);
##   +X  the flexion / bend axis: if the rest pose already bends this joint by
##       3-45 deg (A-pose elbows/knees authored with a pole bend), the axis of
##       that bend (parent bone direction x child bone direction — +rotation
##       increases the bend), sign-corrected to [member JointDefinition.flex_direction]
##       when one is given; otherwise perpendicular to the bone in the character's
##       sagittal plane (bone x forward, +rotation folds the child toward the
##       front, or toward the back for Flex.BACKWARD), falling back to bone x up
##       / bone x lateral for bones that point forward;
##   +Z  = X x Y (lateral).
## "Forward" is the character's own: left x up, from the rest positions of the
## profile's leg (or arm) chains and root/head roles — rig-convention independent.
static func compute_rest_joint_frame(skeleton: Skeleton3D, profile: RagdollProfile, joint_def: JointDefinition) -> Transform3D:
	var parent_def := _find_bone_def(profile, joint_def.parent_rig)
	var child_def := _find_bone_def(profile, joint_def.child_rig)
	if parent_def == null or child_def == null:
		return Transform3D.IDENTITY
	var child_idx := skeleton.find_bone(child_def.skeleton_bone)
	var parent_idx := skeleton.find_bone(parent_def.skeleton_bone)
	if child_idx < 0 or parent_idx < 0:
		return Transform3D.IDENTITY
	var child_rest := skeleton.get_bone_global_rest(child_idx)
	var parent_rest := skeleton.get_bone_global_rest(parent_idx)
	var axes := _character_axes(skeleton, profile)  # {forward, up, lateral}

	var y := _bone_long_axis(skeleton, child_def, child_rest, parent_rest.origin)
	var parent_dir := _bone_long_axis(skeleton, parent_def, parent_rest, Vector3.INF)
	var fold: Vector3 = axes.forward
	if joint_def.flex_direction == JointDefinition.Flex.BACKWARD:
		fold = -axes.forward

	var x := Vector3.ZERO
	var bend := parent_dir.angle_to(y)
	if bend > deg_to_rad(3.0) and bend < deg_to_rad(45.0):
		x = parent_dir.cross(y).normalized()  # +rotation increases the authored bend
		if joint_def.flex_direction != JointDefinition.Flex.NONE:
			var hint := y.cross(fold)
			if hint.length_squared() > 0.04 and x.dot(hint) < 0.0:
				x = -x
	if x == Vector3.ZERO:
		for d: Vector3 in [fold, axes.up, axes.lateral, Vector3.UP, Vector3.RIGHT]:
			var c := y.cross(d)
			if c.length_squared() > 0.04:  # bone at least ~12 deg off that direction
				x = c.normalized()
				break
	x = (x - y * y.dot(x)).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), child_rest.origin)


static func _find_bone_def(profile: RagdollProfile, rig_name: String) -> BoneDefinition:
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == rig_name:
			return bone_def
	return null


## Skeleton-local rest direction of a rig bone: toward its BoneDefinition.child_bone,
## else away from [param from_origin] (its parent's rest origin; INF = none), else
## its own local +Y. Snapped to the bone's nearest local axis when one lies within
## 35 deg of it (keeps authored bone axes; identity-basis rigs get the raw direction).
static func _bone_long_axis(skeleton: Skeleton3D, bone_def: BoneDefinition, rest: Transform3D, from_origin: Vector3) -> Vector3:
	var basis := rest.basis.orthonormalized()
	var dir := Vector3.ZERO
	if bone_def.child_bone != "":
		var ci := skeleton.find_bone(bone_def.child_bone)
		if ci >= 0:
			dir = skeleton.get_bone_global_rest(ci).origin - rest.origin
	if dir.length_squared() < 1e-8 and from_origin.is_finite():
		dir = rest.origin - from_origin
	if dir.length_squared() < 1e-8:
		return basis.y
	dir = dir.normalized()
	var best := basis.y
	var best_dot := -2.0
	for axis: Vector3 in [basis.x, basis.y, basis.z, -basis.x, -basis.y, -basis.z]:
		var d := axis.dot(dir)
		if d > best_dot:
			best_dot = d
			best = axis
	return best if best_dot > cos(deg_to_rad(35.0)) else dir


## The character's rest-pose axes in skeleton-local space: up = root -> head,
## lateral = right leg (or arm) root -> left one, forward = left x up. Falls back
## to the skeleton's own axes when the roles are missing.
static func _character_axes(skeleton: Skeleton3D, profile: RagdollProfile) -> Dictionary:
	var up := Vector3.UP
	var root_def := _find_bone_def(profile, profile.get_root_rig())
	var head_def := _find_bone_def(profile, profile.get_head_rig())
	if root_def and head_def:
		var ri := skeleton.find_bone(root_def.skeleton_bone)
		var hi := skeleton.find_bone(head_def.skeleton_bone)
		if ri >= 0 and hi >= 0:
			var d := skeleton.get_bone_global_rest(hi).origin - skeleton.get_bone_global_rest(ri).origin
			if d.length_squared() > 1e-6:
				up = d.normalized()
	var left := Vector3.ZERO
	for pair in [[profile.get_leg_chain("L"), profile.get_leg_chain("R")], [profile.get_arm_chain("L"), profile.get_arm_chain("R")]]:
		var lc: PackedStringArray = pair[0]
		var rc: PackedStringArray = pair[1]
		if lc.is_empty() or rc.is_empty():
			continue
		var ld := _find_bone_def(profile, lc[0])
		var rd := _find_bone_def(profile, rc[0])
		if ld == null or rd == null:
			continue
		var li := skeleton.find_bone(ld.skeleton_bone)
		var rgi := skeleton.find_bone(rd.skeleton_bone)
		if li < 0 or rgi < 0:
			continue
		var d := skeleton.get_bone_global_rest(li).origin - skeleton.get_bone_global_rest(rgi).origin
		d -= up * up.dot(d)
		if d.length_squared() > 1e-6:
			left = d.normalized()
			break
	if left == Vector3.ZERO:
		left = Vector3.RIGHT - up * up.dot(Vector3.RIGHT)
		left = left.normalized() if left.length_squared() > 1e-6 else Vector3.FORWARD.cross(up).normalized()
	var forward := left.cross(up).normalized()
	return {"forward": forward, "up": up, "lateral": left}


## Records a joint's topology and its anchor in both bodies' local frames (from
## the transforms at registration — the bone poses the rig was built on), so the
## SpringResolver can command kinematically consistent linear velocities down
## the chain.
func _register_joint(parent_rig: String, child_rig: String, joint: Generic6DOFJoint3D) -> void:
	var parent_body: RigidBody3D = _bodies[parent_rig]
	var child_body: RigidBody3D = _bodies[child_rig]
	var anchor := joint.global_position
	var jg := joint.global_transform.orthonormalized()
	_joints[child_rig] = {
		"parent": parent_rig,
		"joint": joint,
		"anchor_parent": parent_body.global_transform.affine_inverse() * anchor,
		"anchor_child": child_body.global_transform.affine_inverse() * anchor,
		"frame_parent": parent_body.global_transform.orthonormalized().affine_inverse() * jg,
		"frame_child": child_body.global_transform.orthonormalized().affine_inverse() * jg,
	}


## Enables the physics rig. On first enable, snaps bodies to skeleton and unfreezes
## them permanently. Subsequent calls are no-ops — bodies stay always-simulated
## so tier transitions have zero visual snap.
func set_enabled(value: bool) -> void:
	if value and _built:
		# Only snap + unfreeze on first enable. After that, bodies stay alive.
		var any_frozen := false
		for body: RigidBody3D in _bodies.values():
			if body.freeze:
				any_frozen = true
				break
		if any_frozen:
			snap_to_skeleton()
			for body: RigidBody3D in _bodies.values():
				body.freeze = false


func snap_to_skeleton() -> void:
	for rig_name: String in _bodies:
		var body: RigidBody3D = _bodies[rig_name]
		var bone_name: String = _rig_to_bone[rig_name]
		var bone_global := _get_bone_global(bone_name)
		body.global_transform = bone_global
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


func get_bodies() -> Dictionary:
	return _bodies


## Returns the bodies dictionary, waiting for the rig to be built if needed.
func await_bodies() -> Dictionary:
	if not _built:
		await bodies_built
	return _bodies


func get_bone_name_for_body(rig_name: String) -> String:
	return _rig_to_bone.get(rig_name, "")


## Returns the joint registry: child rig_name → {parent: String, joint:
## Generic6DOFJoint3D, anchor_parent: Vector3, anchor_child: Vector3,
## frame_parent: Transform3D, frame_child: Transform3D}. The anchor vectors are
## the joint pivot in the parent's / child's local frame as built (for the
## runtime rig the pivot sits at the child bone origin, so anchor_child is
## ~zero); the frames are the joint's limit frame in each body's local space —
## `(parent.global * frame_parent)^-1 * (child.global * frame_child)` is the
## rotation the angular limits are measured on (identity = the rest pose for the
## rest-centred [enum RagdollProfile.JointFrame] modes), see
## [method get_joint_angles]. Empty until the rig is built.
func get_joints() -> Dictionary:
	return _joints


## Debug / tuning helper: the current rotation of [param child_rig] relative to
## its parent in the joint's limit frame, in DEGREES per axis, decomposed the way
## Jolt's 6DOF constraint measures it — twist about the frame's X first, then
## the remaining swing split per component about Y and Z (pyramid) — so the
## values are the ones [member JointDefinition.limit_x]/y/z bound (0 = the
## frame's centre, i.e. the rest pose for the rest-centred frames). Pass
## [param parent_xform] / [param child_xform] to evaluate other poses (e.g. the
## animation's bone globals) instead of the rig bodies. Returns Vector3.INF if
## the rig has no such joint.
func get_joint_angles(child_rig: String, parent_xform: Transform3D = Transform3D(Basis(), Vector3.INF), child_xform: Transform3D = Transform3D(Basis(), Vector3.INF)) -> Vector3:
	if child_rig not in _joints:
		return Vector3.INF
	var j: Dictionary = _joints[child_rig]
	var p_x: Transform3D = parent_xform if parent_xform.origin.is_finite() else (_bodies[j.parent] as RigidBody3D).global_transform
	var c_x: Transform3D = child_xform if child_xform.origin.is_finite() else (_bodies[child_rig] as RigidBody3D).global_transform
	var fa: Basis = (p_x.basis.orthonormalized() * (j.frame_parent as Transform3D).basis)
	var fb: Basis = (c_x.basis.orthonormalized() * (j.frame_child as Transform3D).basis)
	var q := (fa.inverse() * fb).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	# swing-twist split, twist axis X: q = swing * twist
	var twist := Quaternion(q.x, 0.0, 0.0, q.w)
	if twist.length_squared() < 1e-12:
		twist = Quaternion.IDENTITY
	twist = twist.normalized()
	var swing := q * twist.inverse()
	if swing.w < 0.0:
		swing = -swing
	return Vector3(
		rad_to_deg(2.0 * atan2(twist.x, twist.w)),
		rad_to_deg(2.0 * atan2(swing.y, swing.w)),
		rad_to_deg(2.0 * atan2(swing.z, swing.w)))


func get_profile() -> RagdollProfile:
	_ensure_config()
	return _profile


func get_tuning() -> RagdollTuning:
	_ensure_config()
	return _tuning
