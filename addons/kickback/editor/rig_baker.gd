## Editor utility that bakes the physics rig (RigidBody3D + Generic6DOFJoint3D)
## as persistent scene-tree nodes under PhysicsRigBuilder. At runtime, the builder
## detects these baked nodes and adopts them instead of generating new ones.
@tool
class_name RigBaker


## Bakes the physics rig as persistent scene nodes under [param rig_builder].
## Returns true on success. The whole operation — removing a previous bake and
## adding the new nodes — is ONE undo/redo action, so undoing a re-bake restores
## the previous bake and redoing it re-applies the new one.
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

	var new_nodes := build_rig_nodes(skeleton, profile, tuning, rig_builder.global_transform)
	if new_nodes.is_empty():
		push_error("RigBaker: no profile bone matched the skeleton — cannot bake")
		return false
	var previous: Array[Node] = _get_baked_children(rig_builder)

	undo_redo.create_action("Bake Kickback Physics Rig")

	# Do: drop the previous bake (if any), then add the new nodes. Undo runs the
	# undo methods in reverse registration order: the new nodes come out first,
	# then the previous bake goes back in with its ownership restored.
	for node: Node in previous:
		undo_redo.add_do_method(rig_builder, "remove_child", node)
		undo_redo.add_undo_method(rig_builder, "add_child", node)
		undo_redo.add_undo_method(node, "set_owner", scene_owner)
		for child in node.get_children():
			undo_redo.add_undo_method(child, "set_owner", scene_owner)
		undo_redo.add_undo_reference(node)

	# Bodies precede joints in new_nodes, so a joint's node_a/node_b ("../Rig")
	# resolve the moment it enters the tree.
	for node: Node in new_nodes:
		undo_redo.add_do_method(rig_builder, "add_child", node)
		undo_redo.add_do_method(node, "set_owner", scene_owner)
		for child in node.get_children():
			undo_redo.add_do_method(child, "set_owner", scene_owner)
		undo_redo.add_undo_method(rig_builder, "remove_child", node)
		undo_redo.add_do_reference(node)

	undo_redo.commit_action()
	return true


## Builds the baked node set for [param skeleton] at its REST pose: one
## RigidBody3D per profile bone found in the skeleton (built by
## [method PhysicsRigBuilder.build_body] — the same construction as the runtime
## rig, tuning included), then one Generic6DOFJoint3D per profile joint whose
## bodies exist. Bodies carry the [code]kickback_baked[/code] /
## [code]kickback_rig_name[/code] / [code]kickback_skeleton_bone[/code] metadata
## the runtime adopt path reads and start frozen (the builder snaps and unfreezes
## them on first enable); joints reference their bodies by sibling path
## ([code]../Rig[/code]) and are placed local to a parent at
## [param rig_builder_global]. Nothing is added to the tree, so this is usable
## without the editor. Returns bodies first, then joints — the order they must
## be parented in.
static func build_rig_nodes(skeleton: Skeleton3D, profile: RagdollProfile, tuning: RagdollTuning, rig_builder_global: Transform3D) -> Array[Node]:
	var nodes: Array[Node] = []
	var body_nodes: Dictionary = {}  # rig_name → RigidBody3D (for joint wiring)

	# --- Create bodies ---
	for bone_def: BoneDefinition in profile.bones:
		var bone_idx := skeleton.find_bone(bone_def.skeleton_bone)
		if bone_idx < 0:
			push_warning("RigBaker: bone '%s' not found in skeleton — skipping" % bone_def.skeleton_bone)
			continue

		var bone_global := skeleton.global_transform * skeleton.get_bone_global_rest(bone_idx)
		var child_global := PhysicsRigBuilder.NO_CHILD_BONE
		if bone_def.child_bone != "":
			var child_idx := skeleton.find_bone(bone_def.child_bone)
			if child_idx >= 0:
				child_global = skeleton.global_transform * skeleton.get_bone_global_rest(child_idx)

		var body := PhysicsRigBuilder.build_body(bone_def, bone_global, child_global, tuning)
		body.freeze = true
		body.set_meta("kickback_baked", true)
		body.set_meta("kickback_rig_name", bone_def.rig_name)
		body.set_meta("kickback_skeleton_bone", bone_def.skeleton_bone)

		body_nodes[bone_def.rig_name] = body
		nodes.append(body)

	# --- Create joints ---
	var to_local := rig_builder_global.affine_inverse()
	for joint_def: JointDefinition in profile.joints:
		if joint_def.parent_rig not in body_nodes or joint_def.child_rig not in body_nodes:
			push_warning("RigBaker: joint '%s→%s' references missing body — skipping" % [joint_def.parent_rig, joint_def.child_rig])
			continue

		var child_body: RigidBody3D = body_nodes[joint_def.child_rig]
		var child_bone_name: String = child_body.get_meta("kickback_skeleton_bone")
		var child_bone_idx := skeleton.find_bone(child_bone_name)
		if child_bone_idx < 0:
			continue
		# Same limit frame as the runtime builder (rest-centred; ANATOMICAL by
		# default — see RagdollProfile.joint_frame). Bodies are baked at rest, so
		# the frames captured on scene load are centred on the rest pose too.
		var frame_rest := skeleton.get_bone_global_rest(child_bone_idx)
		if profile.joint_frame == RagdollProfile.JointFrame.ANATOMICAL:
			frame_rest = PhysicsRigBuilder.compute_rest_joint_frame(skeleton, profile, joint_def)
		var joint_global := skeleton.global_transform * frame_rest

		var joint := Generic6DOFJoint3D.new()
		joint.name = "%s_to_%s" % [joint_def.parent_rig, joint_def.child_rig]
		joint.set_meta("kickback_baked", true)
		joint.transform = to_local * joint_global

		# node_a/node_b as relative paths (deterministic, no tree required)
		joint.node_a = NodePath("../%s" % joint_def.parent_rig)
		joint.node_b = NodePath("../%s" % joint_def.child_rig)

		# Lock linear axes + apply angular limits/compliance (typed, shared with PhysicsRigBuilder)
		joint_def.apply_to(joint, tuning.joint_limit_scale)
		nodes.append(joint)

	return nodes


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


static func _get_baked_children(rig_builder: PhysicsRigBuilder) -> Array[Node]:
	var result: Array[Node] = []
	for child in rig_builder.get_children():
		if child.has_meta("kickback_baked"):
			result.append(child)
	return result
