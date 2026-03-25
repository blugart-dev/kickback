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
var _built: bool = false
var _profile: RagdollProfile
var _tuning: RagdollTuning


func configure(profile: RagdollProfile, tuning: RagdollTuning) -> void:
	_profile = profile
	_tuning = tuning


func _ready() -> void:
	_skeleton = get_node(skeleton_path) as Skeleton3D
	await get_tree().process_frame
	await get_tree().process_frame
	_build_rig()
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

	_bodies = baked_bodies
	_rig_to_bone = baked_bones
	return true


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

	# Shape is offset locally along the bone direction (toward child bone)
	var col_shape := _create_collision_shape(bone_def)
	if bone_def.child_bone != "":
		var child_global := _get_bone_global(bone_def.child_bone)
		var bone_to_child_local := bone_global.affine_inverse() * child_global
		# Foot boxes need more forward offset (mesh extends past midpoint toward toes)
		var offset_ratio := 0.65 if bone_def.shape_type == "box" else 0.5
		col_shape.position = bone_to_child_local.origin * offset_ratio
	# Box shapes on bones need rotation: bone Y points along bone direction,
	# but box Y should be height (thin). Rotate 90° on X so box Z (length)
	# aligns with bone Y (forward) and box Y (height) aligns with bone Z (up).
	if bone_def.shape_type == "box":
		col_shape.rotation.x = PI / 2.0
	body.add_child(col_shape)

	return body


func _create_collision_shape(bone_def: BoneDefinition) -> CollisionShape3D:
	var col := CollisionShape3D.new()
	match bone_def.shape_type:
		"box":
			var box := BoxShape3D.new()
			box.size = bone_def.box_size
			col.shape = box
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = bone_def.capsule_radius
			capsule.height = bone_def.capsule_height
			col.shape = capsule
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = bone_def.sphere_radius
			col.shape = sphere
	return col


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

	# Lock linear axes
	for axis in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)

	# Angular limits
	for axis in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(joint_def.limit_x.x))
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(joint_def.limit_x.y))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(joint_def.limit_y.x))
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(joint_def.limit_y.y))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, deg_to_rad(joint_def.limit_z.x))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, deg_to_rad(joint_def.limit_z.y))


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


func get_bone_name_for_body(rig_name: String) -> String:
	return _rig_to_bone.get(rig_name, "")


func get_profile() -> RagdollProfile:
	_ensure_config()
	return _profile


func get_tuning() -> RagdollTuning:
	_ensure_config()
	return _tuning
