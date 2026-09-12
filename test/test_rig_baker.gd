extends GutTest

# ── RigBaker / baked-rig adoption ───────────────────────────────────────────
# The editor RigBaker and the runtime PhysicsRigBuilder must build IDENTICAL
# bodies (PhysicsRigBuilder.build_body is the single construction path), and a
# baked rig adopted at runtime must run with the CURRENT RagdollTuning — not
# the layer/mask/gravity/damping/limits it happened to be baked with.
# RigBaker.build_rig_nodes is the editor-free half of bake(), so it is exercised
# here without an EditorUndoRedoManager (the undo action wrapping is editor-only).

const RigHarness := preload("res://test/helpers/rig_harness.gd")

const BAKE_LAYER := 8
const BAKE_MASK := 15


func _skeleton_in_tree() -> Skeleton3D:
	var skel := RigHarness.build_mixamo_skeleton()
	add_child_autoqfree(skel)
	return skel


func _runtime_tuning() -> RagdollTuning:
	# Every body/joint property the runtime path takes from the tuning, set to
	# values that differ from the defaults the nodes were baked with.
	var t := RagdollTuning.create_default()
	t.collision_layer = 16
	t.collision_mask = 3
	t.gravity_scale = 0.35
	t.angular_damp = 3.25
	t.linear_damp = 0.75
	t.joint_limit_scale = 0.5
	t.foot_ik_enabled = false
	return t


func _bone_def(profile: RagdollProfile, rig_name: String) -> BoneDefinition:
	for bone_def: BoneDefinition in profile.bones:
		if bone_def.rig_name == rig_name:
			return bone_def
	return null


func _joint_def(profile: RagdollProfile, child_rig: String) -> JointDefinition:
	for joint_def: JointDefinition in profile.joints:
		if joint_def.child_rig == child_rig:
			return joint_def
	return null


# ── build_rig_nodes: same construction as the runtime rig ───────────────────

func test_build_rig_nodes_emits_bodies_then_joints():
	var skel := _skeleton_in_tree()
	var profile := RagdollProfile.create_mixamo_default()
	var nodes := RigBaker.build_rig_nodes(skel, profile, RagdollTuning.create_default(), Transform3D.IDENTITY)
	for n: Node in nodes:
		autofree(n)
	assert_eq(nodes.size(), 16 + 15, "16 bodies + 15 joints for the Mixamo profile")
	var seen_joint := false
	for n: Node in nodes:
		if n is Generic6DOFJoint3D:
			seen_joint = true
		else:
			assert_true(n is RigidBody3D, "non-joint node is a body")
			assert_false(seen_joint, "every body precedes every joint (joints need their bodies in the tree first)")
			assert_true(n.has_meta("kickback_baked") and n.has_meta("kickback_rig_name") and n.has_meta("kickback_skeleton_bone"),
				"body '%s' carries the adopt metadata" % n.name)
			assert_true((n as RigidBody3D).freeze, "baked body starts frozen (unfrozen on first enable)")
			assert_true((n as RigidBody3D).top_level, "baked body is world-space like the runtime rig")


func test_baked_shape_honours_bone_definition_shape_offset():
	# Regression: the baker used a hardcoded 0.65 (box) / 0.5 (else) ratio and
	# its own shape factory; the runtime builder used BoneDefinition.shape_offset.
	var skel := _skeleton_in_tree()
	var profile := RagdollProfile.create_mixamo_default()
	var tuning := RagdollTuning.create_default()
	# Force offsets that no hardcoded ratio would reproduce.
	_bone_def(profile, "Spine").shape_offset = 0.2      # box
	_bone_def(profile, "UpperArm_L").shape_offset = 0.9  # capsule
	var nodes := RigBaker.build_rig_nodes(skel, profile, tuning, Transform3D.IDENTITY)
	for n: Node in nodes:
		autofree(n)

	for rig_name: String in ["Spine", "UpperArm_L", "Head", "Hips"]:
		var bone_def := _bone_def(profile, rig_name)
		var baked: RigidBody3D = null
		for n: Node in nodes:
			if n.name == rig_name:
				baked = n
		assert_not_null(baked, "baked body '%s' exists" % rig_name)
		# The runtime construction, from the same rest transforms.
		var bone_global := skel.global_transform * skel.get_bone_global_rest(skel.find_bone(bone_def.skeleton_bone))
		var child_global := PhysicsRigBuilder.NO_CHILD_BONE
		if bone_def.child_bone != "":
			child_global = skel.global_transform * skel.get_bone_global_rest(skel.find_bone(bone_def.child_bone))
		var runtime := PhysicsRigBuilder.build_body(bone_def, bone_global, child_global, tuning)
		autofree(runtime)

		var baked_shape := baked.get_child(0) as CollisionShape3D
		var runtime_shape := runtime.get_child(0) as CollisionShape3D
		assert_not_null(baked_shape, "%s: baked body has a CollisionShape3D" % rig_name)
		assert_eq(baked_shape.shape.get_class(), runtime_shape.shape.get_class(), "%s: same shape class" % rig_name)
		assert_almost_eq(baked_shape.position, runtime_shape.position, Vector3.ONE * 1e-5,
			"%s: shape offset matches the runtime builder" % rig_name)
		assert_almost_eq(baked_shape.rotation, runtime_shape.rotation, Vector3.ONE * 1e-5,
			"%s: shape rotation matches the runtime builder" % rig_name)
		if bone_def.child_bone != "":
			var expected := (bone_global.affine_inverse() * child_global).origin * bone_def.shape_offset
			assert_almost_eq(baked_shape.position, expected, Vector3.ONE * 1e-5,
				"%s: offset is bone->child * BoneDefinition.shape_offset (%.2f)" % [rig_name, bone_def.shape_offset])
		assert_almost_eq(baked.transform.origin, bone_global.origin, Vector3.ONE * 1e-5,
			"%s: baked body sits on the bone rest origin" % rig_name)
		assert_almost_eq(baked.mass, runtime.mass, 1e-6, "%s: same mass" % rig_name)


func test_build_body_without_child_bone_leaves_shape_at_origin():
	var bone_def := BoneDefinition.new()
	bone_def.rig_name = "Lonely"
	bone_def.skeleton_bone = "x"
	bone_def.shape_type = "sphere"
	bone_def.shape_offset = 0.8
	var body := PhysicsRigBuilder.build_body(bone_def, Transform3D(Basis(), Vector3(1, 2, 3)),
		PhysicsRigBuilder.NO_CHILD_BONE, RagdollTuning.create_default())
	autofree(body)
	assert_eq((body.get_child(0) as CollisionShape3D).position, Vector3.ZERO,
		"no child bone -> no offset (not an offset toward the world origin)")
	assert_eq(body.transform.origin, Vector3(1, 2, 3))


# ── Adoption re-applies the runtime tuning ─────────────────────────────────

func test_adopted_baked_rig_takes_layer_mask_gravity_damping_from_tuning():
	# Bake-like nodes carry stale values (a different tuning at bake time,
	# top_level unset as older bakes were saved); adoption must overwrite all
	# of them from the builder's configured tuning.
	var skel := _skeleton_in_tree()
	var profile := RagdollProfile.create_mixamo_default()
	var bake_tuning := RagdollTuning.create_default()
	bake_tuning.collision_layer = BAKE_LAYER
	bake_tuning.collision_mask = BAKE_MASK
	var nodes := RigBaker.build_rig_nodes(skel, profile, bake_tuning, Transform3D.IDENTITY)

	var builder := PhysicsRigBuilder.new()
	builder.name = "PhysicsRigBuilder"
	builder.skeleton_path = NodePath("../Skeleton3D")
	for n: Node in nodes:
		if n is RigidBody3D:
			n.collision_layer = 1
			n.collision_mask = 1
			n.gravity_scale = 2.0
			n.angular_damp = 0.0
			n.linear_damp = 0.0
			n.can_sleep = true
			n.top_level = false
		builder.add_child(n)
	var runtime_tuning := _runtime_tuning()
	builder.configure(profile, runtime_tuning)
	add_child_autoqfree(builder)

	var bodies: Dictionary = await builder.await_bodies()
	assert_eq(bodies.size(), 16, "baked rig adopted (16 bodies)")
	assert_eq(builder.get_joints().size(), 15, "all 15 baked joints registered")
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		assert_true(body.has_meta("kickback_baked"), "%s is the baked node, not a regenerated one" % rig_name)
		assert_eq(body.collision_layer, runtime_tuning.collision_layer, "%s: collision_layer from tuning" % rig_name)
		assert_eq(body.collision_mask, runtime_tuning.collision_mask, "%s: collision_mask from tuning" % rig_name)
		assert_almost_eq(body.gravity_scale, runtime_tuning.gravity_scale, 1e-6, "%s: gravity_scale from tuning" % rig_name)
		assert_almost_eq(body.angular_damp, runtime_tuning.angular_damp, 1e-6, "%s: angular_damp from tuning" % rig_name)
		assert_almost_eq(body.linear_damp, runtime_tuning.linear_damp, 1e-6, "%s: linear_damp from tuning" % rig_name)
		assert_false(body.can_sleep, "%s: can_sleep off" % rig_name)
		assert_true(body.top_level, "%s: top_level enforced on adopt" % rig_name)


func test_adopted_baked_joints_take_limits_from_profile_and_tuning_scale():
	var skel := _skeleton_in_tree()
	var profile := RagdollProfile.create_mixamo_default()
	var nodes := RigBaker.build_rig_nodes(skel, profile, RagdollTuning.create_default(), Transform3D.IDENTITY)

	var builder := PhysicsRigBuilder.new()
	builder.name = "PhysicsRigBuilder"
	builder.skeleton_path = NodePath("../Skeleton3D")
	for n: Node in nodes:
		if n is Generic6DOFJoint3D:
			# Stale, unscaled bake: limits that match no JointDefinition.
			var j := n as Generic6DOFJoint3D
			j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -3.0)
			j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 3.0)
			j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -3.0)
			j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 3.0)
			j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -3.0)
			j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 3.0)
		builder.add_child(n)
	var runtime_tuning := _runtime_tuning()  # joint_limit_scale = 0.5
	builder.configure(profile, runtime_tuning)
	add_child_autoqfree(builder)
	await builder.await_bodies()

	var joints: Dictionary = builder.get_joints()
	assert_eq(joints.size(), 15)
	var s := runtime_tuning.joint_limit_scale
	for child_rig: String in joints:
		var joint_def := _joint_def(profile, child_rig)
		assert_not_null(joint_def, "%s: matched to a JointDefinition" % child_rig)
		assert_eq(joints[child_rig]["parent"], joint_def.parent_rig, "%s: parent recovered from node_a" % child_rig)
		var joint: Generic6DOFJoint3D = joints[child_rig]["joint"]
		# JointDefinition.apply_to mirrors the sign (see its doc); reproduce
		# the expected bounds the same way, scaled by the RUNTIME tuning.
		assert_almost_eq(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), deg_to_rad(-joint_def.limit_x.y * s), 1e-5,
			"%s: X lower limit = profile limit x runtime joint_limit_scale" % child_rig)
		assert_almost_eq(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(-joint_def.limit_x.x * s), 1e-5,
			"%s: X upper limit" % child_rig)
		assert_almost_eq(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), deg_to_rad(-joint_def.limit_y.y * s), 1e-5,
			"%s: Y lower limit" % child_rig)
		assert_almost_eq(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(-joint_def.limit_z.x * s), 1e-5,
			"%s: Z upper limit" % child_rig)
		assert_true(joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "%s: linear axes locked" % child_rig)
