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
##   anchor_parent: Vector3, anchor_child: Vector3} — the joint anchor expressed
## in each body's local frame at build time (see [method get_joints]).
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
		add_child(body)
		body.global_transform = bone_global
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

	# Baked rigs predate (or may have been saved without) the world-space
	# flag — enforce it on adopt, same rationale as _create_body.
	for body: RigidBody3D in baked_bodies.values():
		body.top_level = true

	_bodies = baked_bodies
	_rig_to_bone = baked_bones

	# Baked joints: recover the parent→child topology from node_a/node_b.
	var body_to_rig: Dictionary = {}
	for rig_name: String in _bodies:
		body_to_rig[_bodies[rig_name]] = rig_name
	for child in get_children():
		if child is Generic6DOFJoint3D:
			var a := child.get_node_or_null(child.node_a)
			var b := child.get_node_or_null(child.node_b)
			if a in body_to_rig and b in body_to_rig:
				_register_joint(body_to_rig[a], body_to_rig[b], child)
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
	var body := RigidBody3D.new()
	body.name = bone_def.rig_name
	body.mass = bone_def.mass
	body.collision_layer = _tuning.collision_layer
	body.collision_mask = _tuning.collision_mask
	body.can_sleep = false
	body.gravity_scale = _tuning.gravity_scale
	body.angular_damp = _tuning.angular_damp
	body.linear_damp = _tuning.linear_damp
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

	# Shape is offset locally along the bone direction (toward child bone)
	var col_shape := SkeletonDetector.create_collision_shape(bone_def)
	if bone_def.child_bone != "":
		var child_global := _get_bone_global(bone_def.child_bone)
		var bone_to_child_local := bone_global.affine_inverse() * child_global
		col_shape.position = bone_to_child_local.origin * bone_def.shape_offset
	# Box shapes on bones need rotation: bone Y points along bone direction,
	# but box Y should be height (thin). Rotate 90° on X so box Z (length)
	# aligns with bone Y (forward) and box Y (height) aligns with bone Z (up).
	if bone_def.shape_type == "box":
		col_shape.rotation.x = PI / 2.0
	body.add_child(col_shape)

	return body


func _create_joint(joint_def: JointDefinition) -> void:
	if joint_def.parent_rig not in _bodies or joint_def.child_rig not in _bodies:
		push_warning("PhysicsRigBuilder: joint '%s→%s' references missing body" % [joint_def.parent_rig, joint_def.child_rig])
		return

	var parent_body: RigidBody3D = _bodies[joint_def.parent_rig]
	var child_body: RigidBody3D = _bodies[joint_def.child_rig]
	var child_bone: String = _rig_to_bone[joint_def.child_rig]
	var joint_global := _get_bone_global(child_bone)

	var joint := Generic6DOFJoint3D.new()
	joint.name = "%s_to_%s" % [joint_def.parent_rig, joint_def.child_rig]
	add_child(joint)

	joint.global_transform = joint_global
	joint.node_a = joint.get_path_to(parent_body)
	joint.node_b = joint.get_path_to(child_body)

	# Lock linear axes + apply angular limits/compliance (typed, shared with RigBaker)
	joint_def.apply_to(joint)
	_register_joint(joint_def.parent_rig, joint_def.child_rig, joint)


## Records a joint's topology and its anchor in both bodies' local frames (from
## the transforms at registration — the bone poses the rig was built on), so the
## SpringResolver can command kinematically consistent linear velocities down
## the chain.
func _register_joint(parent_rig: String, child_rig: String, joint: Generic6DOFJoint3D) -> void:
	var parent_body: RigidBody3D = _bodies[parent_rig]
	var child_body: RigidBody3D = _bodies[child_rig]
	var anchor := joint.global_position
	_joints[child_rig] = {
		"parent": parent_rig,
		"joint": joint,
		"anchor_parent": parent_body.global_transform.affine_inverse() * anchor,
		"anchor_child": child_body.global_transform.affine_inverse() * anchor,
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
## Generic6DOFJoint3D, anchor_parent: Vector3, anchor_child: Vector3}. The anchor
## vectors are the joint pivot in the parent's / child's local frame as built
## (for the runtime rig the pivot sits at the child bone origin, so anchor_child
## is ~zero). Empty until the rig is built.
func get_joints() -> Dictionary:
	return _joints


func get_profile() -> RagdollProfile:
	_ensure_config()
	return _profile


func get_tuning() -> RagdollTuning:
	_ensure_config()
	return _tuning
