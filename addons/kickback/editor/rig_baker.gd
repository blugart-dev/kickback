## Editor utility that bakes the physics rig (RigidBody3D + Generic6DOFJoint3D)
## as persistent scene-tree nodes under PhysicsRigBuilder. At runtime, the builder
## detects these baked nodes and adopts them instead of generating new ones.
@tool
class_name RigBaker


## Bakes the physics rig as persistent scene nodes under [param rig_builder].
## Returns true on success. Uses undo/redo so the operation is reversible.
static func bake(rig_builder: PhysicsRigBuilder, undo_redo: EditorUndoRedoManager, scene_owner: Node) -> bool:
	var skeleton := rig_builder.get_node_or_null(rig_builder.skeleton_path) as Skeleton3D
	if not skeleton:
		push_error("RigBaker: skeleton_path is invalid — cannot bake")
		return false

	var config := _resolve_config(rig_builder)
	var profile: RagdollProfile = config[0]
	var tuning: RagdollTuning = config[1]

	if profile.bones.is_empty():
		push_error("RigBaker: RagdollProfile has no bones — cannot bake")
		return false

	# Clean re-bake if already baked
	if is_baked(rig_builder):
		_unbake_immediate(rig_builder)

	undo_redo.create_action("Bake Kickback Physics Rig")

	var body_nodes: Dictionary = {}  # rig_name → RigidBody3D (for joint wiring)

	# --- Create bodies ---
	for bone_def: BoneDefinition in profile.bones:
		var bone_idx := skeleton.find_bone(bone_def.skeleton_bone)
		if bone_idx < 0:
			push_warning("RigBaker: bone '%s' not found in skeleton — skipping" % bone_def.skeleton_bone)
			continue

		var bone_global := skeleton.global_transform * skeleton.get_bone_global_rest(bone_idx)

		var body := RigidBody3D.new()
		body.name = bone_def.rig_name
		body.mass = bone_def.mass
		body.collision_layer = tuning.collision_layer
		body.collision_mask = tuning.collision_mask
		body.can_sleep = false
		body.gravity_scale = tuning.gravity_scale
		body.angular_damp = tuning.angular_damp
		body.linear_damp = tuning.linear_damp
		body.freeze = true

		body.set_meta("kickback_baked", true)
		body.set_meta("kickback_rig_name", bone_def.rig_name)
		body.set_meta("kickback_skeleton_bone", bone_def.skeleton_bone)

		# Collision shape with offset toward child bone
		var col_shape := _create_collision_shape(bone_def)
		if bone_def.child_bone != "":
			var child_idx := skeleton.find_bone(bone_def.child_bone)
			if child_idx >= 0:
				var child_global := skeleton.global_transform * skeleton.get_bone_global_rest(child_idx)
				var bone_to_child_local := bone_global.affine_inverse() * child_global
				var offset_ratio := 0.65 if bone_def.shape_type == "box" else 0.5
				col_shape.position = bone_to_child_local.origin * offset_ratio
		if bone_def.shape_type == "box":
			col_shape.rotation.x = PI / 2.0
		body.add_child(col_shape)

		# Undo/redo: add body to rig_builder
		undo_redo.add_do_method(rig_builder, "add_child", body)
		undo_redo.add_do_method(body, "set_owner", scene_owner)
		undo_redo.add_do_method(col_shape, "set_owner", scene_owner)
		undo_redo.add_do_method(body, "set", "global_transform", bone_global)
		undo_redo.add_undo_method(rig_builder, "remove_child", body)
		undo_redo.add_do_reference(body)

		body_nodes[bone_def.rig_name] = body

	# --- Create joints ---
	for joint_def: JointDefinition in profile.joints:
		if joint_def.parent_rig not in body_nodes or joint_def.child_rig not in body_nodes:
			push_warning("RigBaker: joint '%s→%s' references missing body — skipping" % [joint_def.parent_rig, joint_def.child_rig])
			continue

		var child_body: RigidBody3D = body_nodes[joint_def.child_rig]
		var child_bone_name: String = child_body.get_meta("kickback_skeleton_bone")
		var child_bone_idx := skeleton.find_bone(child_bone_name)
		if child_bone_idx < 0:
			continue
		var joint_global := skeleton.global_transform * skeleton.get_bone_global_rest(child_bone_idx)

		var joint := Generic6DOFJoint3D.new()
		joint.name = "%s_to_%s" % [joint_def.parent_rig, joint_def.child_rig]
		joint.set_meta("kickback_baked", true)

		# node_a/node_b as relative paths (deterministic, no tree required)
		joint.node_a = NodePath("../%s" % joint_def.parent_rig)
		joint.node_b = NodePath("../%s" % joint_def.child_rig)

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

		undo_redo.add_do_method(rig_builder, "add_child", joint)
		undo_redo.add_do_method(joint, "set_owner", scene_owner)
		undo_redo.add_do_method(joint, "set", "global_transform", joint_global)
		undo_redo.add_undo_method(rig_builder, "remove_child", joint)
		undo_redo.add_do_reference(joint)

	undo_redo.commit_action()
	print("RigBaker: Baked %d bodies + %d joints" % [body_nodes.size(), profile.joints.size()])
	return true


## Removes all baked nodes from [param rig_builder] with undo/redo support.
static func unbake(rig_builder: PhysicsRigBuilder, undo_redo: EditorUndoRedoManager) -> void:
	var baked_nodes: Array[Node] = _get_baked_children(rig_builder)
	if baked_nodes.is_empty():
		return

	var scene_owner: Node = rig_builder.owner if rig_builder.owner else rig_builder
	undo_redo.create_action("Unbake Kickback Physics Rig")

	for node: Node in baked_nodes:
		undo_redo.add_do_method(rig_builder, "remove_child", node)
		undo_redo.add_undo_method(rig_builder, "add_child", node)
		undo_redo.add_undo_method(node, "set_owner", scene_owner)
		# Re-set owner on collision shape children during undo
		for child in node.get_children():
			undo_redo.add_undo_method(child, "set_owner", scene_owner)
		undo_redo.add_undo_reference(node)

	undo_redo.commit_action()
	print("RigBaker: Unbaked %d nodes" % baked_nodes.size())


## Returns true if [param rig_builder] has any baked children.
static func is_baked(rig_builder: PhysicsRigBuilder) -> bool:
	for child in rig_builder.get_children():
		if child.has_meta("kickback_baked"):
			return true
	return false


## Returns the number of baked RigidBody3D children.
static func get_baked_body_count(rig_builder: PhysicsRigBuilder) -> int:
	var count := 0
	for child in rig_builder.get_children():
		if child is RigidBody3D and child.has_meta("kickback_baked"):
			count += 1
	return count


# --- Private helpers ---


## Returns [RagdollProfile, RagdollTuning] from the sibling KickbackCharacter,
## falling back to defaults if not found.
static func _resolve_config(rig_builder: Node) -> Array:
	var profile: RagdollProfile = null
	var tuning: RagdollTuning = null
	var parent := rig_builder.get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling is KickbackCharacter:
				profile = sibling.ragdoll_profile
				tuning = sibling.ragdoll_tuning
				break
	if not profile:
		profile = RagdollProfile.create_mixamo_default()
	if not tuning:
		tuning = RagdollTuning.create_default()
	return [profile, tuning]


static func _create_collision_shape(bone_def: BoneDefinition) -> CollisionShape3D:
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


static func _get_baked_children(rig_builder: PhysicsRigBuilder) -> Array[Node]:
	var result: Array[Node] = []
	for child in rig_builder.get_children():
		if child.has_meta("kickback_baked"):
			result.append(child)
	return result


## Immediate unbake without undo/redo (used internally before re-bake).
static func _unbake_immediate(rig_builder: PhysicsRigBuilder) -> void:
	var to_remove: Array[Node] = _get_baked_children(rig_builder)
	for node: Node in to_remove:
		rig_builder.remove_child(node)
		node.queue_free()
