extends GutTest

# ── Joint limits that don't fight the animation (2026-08-18) ─────────────────
# Coverage for the rest-centred, geometry-derived (ANATOMICAL) joint frames:
# frames independent of the pose the rig is built in, limits containing the
# rest pose, no bend axis pinched, one-sided flexion limits with the right
# sense (elbow folds forward, knee folds backward, hyperextension blocked),
# RagdollTuning.joint_limit_scale, and the get_joint_angles helper. Uses the
# shared runtime harness (synthetic Mixamo skeleton, identity bone bases, T-pose
# along X, character facing +Z = left x up).

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	return t


## Spawns the harness. [param pre_build_pose] is applied to the skeleton BEFORE
## the rig builds (2 frames after setup) — the "pose the rig happens to be built
## in". Callable(skeleton).
func _spawn(profile: RagdollProfile = null, tuning: RagdollTuning = null, pre_build_pose: Callable = Callable(), with_ground: bool = true):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning if tuning else _tuning(), profile, with_ground)
	if pre_build_pose.is_valid():
		pre_build_pose.call(h.skeleton)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


## Signed rotation (deg) of [param child]'s body relative to [param parent]'s
## about world [param axis].
func _rel_deg(h, parent: String, child: String, axis: Vector3) -> float:
	var pb: RigidBody3D = h.get_body(parent)
	var cb: RigidBody3D = h.get_body(child)
	var q := (pb.global_basis.orthonormalized().inverse() * cb.global_basis.orthonormalized()).get_rotation_quaternion()
	return rad_to_deg(q.get_angle()) * signf(q.get_axis().dot(axis))


static func _bent_pose(skeleton: Skeleton3D) -> void:
	# A deliberately odd build pose: torso yawed, head tilted, elbows and knees
	# folded, feet turned — every joint away from rest.
	skeleton.set_bone_pose_rotation(skeleton.find_bone("mixamorig_Spine"), Quaternion(Vector3.UP, deg_to_rad(20.0)))
	skeleton.set_bone_pose_rotation(skeleton.find_bone("mixamorig_Head"), Quaternion(Vector3.RIGHT, deg_to_rad(30.0)))
	skeleton.set_bone_pose_rotation(skeleton.find_bone("mixamorig_LeftForeArm"), Quaternion(Vector3.DOWN, deg_to_rad(70.0)))
	skeleton.set_bone_pose_rotation(skeleton.find_bone("mixamorig_RightForeArm"), Quaternion(Vector3.UP, deg_to_rad(70.0)))
	skeleton.set_bone_pose_rotation(skeleton.find_bone("mixamorig_LeftLeg"), Quaternion(Vector3.RIGHT, deg_to_rad(50.0)))
	skeleton.set_bone_pose_rotation(skeleton.find_bone("mixamorig_RightFoot"), Quaternion(Vector3.UP, deg_to_rad(25.0)))


# ── Frames: rest-centred, pose-independent ──────────────────────────────────

func test_joint_frames_do_not_depend_on_the_build_pose():
	var h_rest = await _spawn()
	var h_bent = await _spawn(null, null, Callable(self, "_bent_pose"))
	var jr: Dictionary = h_rest.rig_builder.get_joints()
	var jb: Dictionary = h_bent.rig_builder.get_joints()
	assert_eq(jr.size(), 15)
	assert_eq(jb.size(), 15)
	for child_rig: String in jr:
		var a: Transform3D = jr[child_rig].frame_parent
		var b: Transform3D = jb[child_rig].frame_parent
		assert_true(a.is_equal_approx(b) or (a.origin.is_equal_approx(b.origin) and (a.basis.inverse() * b.basis).get_rotation_quaternion().get_angle() < 0.001),
			"%s: parent-side limit frame identical whatever pose the rig was built in" % child_rig)
		var c: Transform3D = jr[child_rig].frame_child
		var d: Transform3D = jb[child_rig].frame_child
		assert_true(c.origin.is_equal_approx(d.origin) and (c.basis.inverse() * d.basis).get_rotation_quaternion().get_angle() < 0.001,
			"%s: child-side limit frame identical whatever pose the rig was built in" % child_rig)
	# and the anchors too (the SpringResolver's chain consistency reads them)
	assert_almost_eq((jb["Spine"].anchor_parent as Vector3).length(), 0.12, 0.01, "anchor is the rest bone offset even when built bent")


func test_build_pose_frame_mode_is_the_legacy_behaviour():
	var prof := RagdollProfile.create_mixamo_default()
	prof.joint_frame = RagdollProfile.JointFrame.BUILD_POSE
	var h_rest = await _spawn(prof)
	var prof2 := RagdollProfile.create_mixamo_default()
	prof2.joint_frame = RagdollProfile.JointFrame.BUILD_POSE
	var h_bent = await _spawn(prof2, null, Callable(self, "_bent_pose"))
	var a: Transform3D = h_rest.rig_builder.get_joints()["LowerArm_L"].frame_parent
	var b: Transform3D = h_bent.rig_builder.get_joints()["LowerArm_L"].frame_parent
	assert_gt((a.basis.inverse() * b.basis).get_rotation_quaternion().get_angle(), deg_to_rad(30.0),
		"BUILD_POSE: the elbow's limit frame follows the pose the rig was built in (legacy)")
	# built at rest, BUILD_POSE centres on rest and reads zero
	var ang: Vector3 = h_rest.rig_builder.get_joint_angles("LowerArm_L")
	assert_lt(ang.length(), 3.0, "BUILD_POSE built at rest: elbow reads ~0 (%s)" % ang)


func test_bone_rest_frame_mode_uses_the_bone_basis():
	var prof := RagdollProfile.create_mixamo_default()
	prof.joint_frame = RagdollProfile.JointFrame.BONE_REST
	var h = await _spawn(prof, null, Callable(self, "_bent_pose"))
	# harness bones have identity bases -> the joint frame basis is identity in
	# the parent's frame regardless of the (bent) build pose
	var fp: Transform3D = h.rig_builder.get_joints()["LowerArm_L"].frame_parent
	assert_lt(fp.basis.get_rotation_quaternion().get_angle(), 0.001, "BONE_REST: elbow frame = the forearm's rest basis (identity here)")


func test_anatomical_frame_axes_on_the_t_pose_harness():
	# Left forearm runs along +X, character forward is +Z (left x up): the
	# elbow's twist axis is the bone (+X), its flexion axis is bone x forward =
	# -Y (down; +rotation folds the forearm toward the front), lateral = +Z.
	var h = await _spawn()
	var elbow: Generic6DOFJoint3D = h.rig_builder.get_joints()["LowerArm_L"].joint
	var b := elbow.global_basis.orthonormalized()
	assert_almost_eq(b.y.dot(Vector3.RIGHT), 1.0, 0.01, "elbow frame +Y along the forearm")
	assert_almost_eq(b.x.dot(Vector3.DOWN), 1.0, 0.01, "elbow frame +X = flexion axis (down)")
	assert_almost_eq(b.z.dot(Vector3.BACK), 1.0, 0.01, "elbow frame +Z lateral (forward)")
	# knee (shin along -Y, folds BACKWARD): X = +X world so +rotation swings the
	# foot toward the back
	var knee: Generic6DOFJoint3D = h.rig_builder.get_joints()["LowerLeg_L"].joint
	var kb := knee.global_basis.orthonormalized()
	assert_almost_eq(kb.y.dot(Vector3.DOWN), 1.0, 0.01, "knee frame +Y along the shin")
	assert_almost_eq(kb.x.dot(Vector3.RIGHT), 1.0, 0.01, "knee frame +X = flexion axis, sense = backward")
	# right side mirrors: the right elbow folds forward about +Y (up)
	var relbow: Generic6DOFJoint3D = h.rig_builder.get_joints()["LowerArm_R"].joint
	assert_almost_eq(relbow.global_basis.orthonormalized().x.dot(Vector3.UP), 1.0, 0.01, "right elbow flexion axis is up")


func test_compute_rest_joint_frame_is_static_and_skeleton_local():
	var skel := RigHarness.build_mixamo_skeleton()
	add_child_autoqfree(skel)
	var prof := RagdollProfile.create_mixamo_default()
	var jd: JointDefinition
	for j: JointDefinition in prof.joints:
		if j.child_rig == "Head":
			jd = j
	var f := PhysicsRigBuilder.compute_rest_joint_frame(skel, prof, jd)
	assert_true(f.origin.is_equal_approx(skel.get_bone_global_rest(skel.find_bone("mixamorig_Head")).origin), "frame origin = child bone rest origin")
	assert_almost_eq(f.basis.y.dot(Vector3.UP), 1.0, 0.01, "head frame +Y up the head")
	assert_almost_eq(absf(f.basis.x.dot(Vector3.RIGHT)), 1.0, 0.01, "head nod axis is lateral")


# ── Limits: contain rest, no pinched bend axis, tables ──────────────────────

func test_limits_contain_the_rest_pose_and_the_rig_reads_zero_at_rest():
	# no ground: the harness feet's toe box sits below y=0 and the floor would
	# push the feet up (a contact, not a limit)
	var h = await _spawn(null, null, Callable(), false)
	await wait_physics_frames(30)
	var prof: RagdollProfile = h.rig_builder.get_profile()
	for jd: JointDefinition in prof.joints:
		assert_true(jd.limit_x.x < 0.0 and jd.limit_x.y > 0.0, "%s X limits contain 0" % jd.child_rig)
		assert_true(jd.limit_y.x < 0.0 and jd.limit_y.y > 0.0, "%s Y limits contain 0" % jd.child_rig)
		assert_true(jd.limit_z.x < 0.0 and jd.limit_z.y > 0.0, "%s Z limits contain 0" % jd.child_rig)
		var a: Vector3 = h.rig_builder.get_joint_angles(jd.child_rig)
		assert_lt(a.length(), 4.0, "%s at rest reads ~0 in its limit frame (%s)" % [jd.child_rig, a])


func test_no_bend_axis_is_pinched_and_hinges_are_wide():
	var detected_skel: Skeleton3D = autofree(RigHarness.build_mixamo_skeleton())
	for prof: RagdollProfile in [RagdollProfile.create_mixamo_default(),
			SkeletonDetector.create_profile_from_skeleton(detected_skel, _harness_mapping())]:
		assert_eq(prof.joint_frame, RagdollProfile.JointFrame.ANATOMICAL, "profiles default to the ANATOMICAL frame")
		for jd: JointDefinition in prof.joints:
			for lim: Vector2 in [jd.limit_x, jd.limit_y, jd.limit_z]:
				assert_true(absf(lim.x) >= 10.0 and lim.y >= 10.0, "%s: no axis narrower than +-10 deg (%s)" % [jd.child_rig, lim])
			match jd.child_rig:
				"LowerArm_L", "LowerArm_R", "LowerLeg_L", "LowerLeg_R":
					assert_gte(jd.limit_x.y, 120.0, "%s flexion at least 120 deg" % jd.child_rig)
					assert_true(jd.flex_direction != JointDefinition.Flex.NONE, "%s carries a flexion sense" % jd.child_rig)
					assert_gte(jd.limit_y.y, 25.0, "%s twist not pinched (%s)" % [jd.child_rig, jd.limit_y])
				"UpperLeg_L", "UpperLeg_R":
					assert_gte(jd.limit_x.y, 90.0, "hip flexes forward at least 90")
					assert_eq(jd.flex_direction, JointDefinition.Flex.FORWARD)
				"Head":
					assert_gte(jd.limit_x.y, 60.0)
					assert_gte(jd.limit_y.y, 70.0)


func _harness_mapping() -> Dictionary:
	var m := {}
	for bd: BoneDefinition in RagdollProfile.create_mixamo_default().bones:
		m[bd.rig_name] = bd.skeleton_bone
	return m


func test_detector_and_mixamo_default_share_one_joint_table():
	var a := RagdollProfile.create_mixamo_default().joints
	var b := SkeletonDetector.default_joints_for(PackedStringArray(RigHarness.RIG_NAMES))
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].child_rig, b[i].child_rig)
		assert_eq(a[i].limit_x, b[i].limit_x, "%s X" % a[i].child_rig)
		assert_eq(a[i].limit_y, b[i].limit_y, "%s Y" % a[i].child_rig)
		assert_eq(a[i].limit_z, b[i].limit_z, "%s Z" % a[i].child_rig)
		assert_eq(a[i].flex_direction, b[i].flex_direction, "%s flex" % a[i].child_rig)


# ── One-sided limits: sense + hyperextension block (Jolt) ───────────────────

func test_elbow_folds_forward_150_but_hyperextends_only_10():
	# +rotation about the elbow's flexion axis (down, for the left arm) swings
	# the forearm toward the character's front. 100 deg of that must be reached;
	# 60 deg the other way (hyperextension) must stop near the -10 bound.
	var h = await _spawn()
	var idx: int = h.skeleton.find_bone("mixamorig_LeftForeArm")
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.DOWN, deg_to_rad(100.0)))
	await wait_physics_frames(90)
	var fold := _rel_deg(h, "UpperArm_L", "LowerArm_L", Vector3.DOWN)
	assert_almost_eq(fold, 100.0, 8.0, "forearm folds 100 deg forward (got %.1f)" % fold)
	var a: Vector3 = h.rig_builder.get_joint_angles("LowerArm_L")
	assert_almost_eq(a.x, 100.0, 8.0, "get_joint_angles reads the fold on X (%s)" % a)
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.DOWN, deg_to_rad(-60.0)))
	await wait_physics_frames(120)
	var hyper := _rel_deg(h, "UpperArm_L", "LowerArm_L", Vector3.DOWN)
	assert_gt(hyper, -22.0, "hyperextension blocked near the -10 deg bound (got %.1f)" % hyper)
	assert_lt(hyper, 0.0, "...on the hyperextension side")


func test_knee_folds_backward_and_blocks_forward():
	var h = await _spawn()
	var idx: int = h.skeleton.find_bone("mixamorig_LeftLeg")
	# shin points down; rotating about +X swings the foot toward -Z (back)
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(100.0)))
	await wait_physics_frames(90)
	var fold := _rel_deg(h, "UpperLeg_L", "LowerLeg_L", Vector3.RIGHT)
	assert_almost_eq(fold, 100.0, 8.0, "shin folds 100 deg backward (got %.1f)" % fold)
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(-60.0)))
	await wait_physics_frames(120)
	var hyper := _rel_deg(h, "UpperLeg_L", "LowerLeg_L", Vector3.RIGHT)
	assert_gt(hyper, -22.0, "knee does not bend forward past ~-10 (got %.1f)" % hyper)


func test_symmetric_limit_holds_both_ways():
	# the head nod (X +-70): a 60 deg nod either way is reached, 100 is not
	var h = await _spawn()
	var idx: int = h.skeleton.find_bone("mixamorig_Head")
	for sgn in [1.0, -1.0]:
		h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(60.0 * sgn)))
		await wait_physics_frames(90)
		var got := _rel_deg(h, "Chest", "Head", Vector3.RIGHT)
		assert_almost_eq(got, 60.0 * sgn, 10.0, "head nods %.0f (got %.1f)" % [60.0 * sgn, got])
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(110.0)))
	await wait_physics_frames(120)
	assert_lt(_rel_deg(h, "Chest", "Head", Vector3.RIGHT), 90.0, "110 deg nod is held back by the +-70 limit")


# ── Tuning knob + apply_to ──────────────────────────────────────────────────

func test_joint_limit_scale_multiplies_the_authored_bounds():
	var t := _tuning()
	t.joint_limit_scale = 1.5
	var h = await _spawn(null, t)
	var elbow: Generic6DOFJoint3D = h.rig_builder.get_joints()["LowerArm_L"].joint
	# authored (-10, 150) x 1.5 = (-15, 225); Godot's 6DOF stores the mirrored
	# range (see JointDefinition.apply_to)
	assert_almost_eq(elbow.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(15.0), 0.001)
	assert_almost_eq(elbow.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), deg_to_rad(-225.0), 0.001)
	assert_almost_eq(RagdollTuning.create_default().joint_limit_scale, 1.0, 0.001, "default scale 1")


func test_apply_to_mirrors_the_bounds_for_godot():
	var jd := JointDefinition.new()
	jd.limit_x = Vector2(-10, 150)
	jd.limit_y = Vector2(-80, 80)
	jd.limit_z = Vector2(-20, 20)
	var joint := Generic6DOFJoint3D.new()
	add_child_autoqfree(joint)
	jd.apply_to(joint)
	assert_almost_eq(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), deg_to_rad(-150.0), 0.0001)
	assert_almost_eq(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(10.0), 0.0001)
	assert_almost_eq(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT), deg_to_rad(-80.0), 0.0001)
	assert_almost_eq(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(20.0), 0.0001)
	assert_true(joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT))
	assert_true(joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT))


func test_get_joint_angles_unknown_joint_is_inf():
	var h = await _spawn()
	assert_eq(h.rig_builder.get_joint_angles("Nope"), Vector3.INF)
	assert_eq(h.rig_builder.get_joint_angles("Hips"), Vector3.INF, "root has no joint")


func test_bent_build_pose_tracks_the_animation_where_build_centred_limits_would_block():
	# Build the rig in the odd pose, then animate the head back to rest and 30
	# deg the OTHER way: with rest-centred limits (+-70) that is a 30 deg nod
	# and must be reached; build-centred limits would have measured it as 60
	# from centre. Both modes should reach it here (60 < 70), so assert the
	# tracking itself: rendered head follows within 6 deg.
	var h = await _spawn(null, null, Callable(self, "_bent_pose"))
	var idx: int = h.skeleton.find_bone("mixamorig_Head")
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(-30.0)))
	await wait_physics_frames(90)
	var got := _rel_deg(h, "Chest", "Head", Vector3.RIGHT)
	assert_almost_eq(got, -30.0, 6.0, "head follows the animation to -30 (got %.1f)" % got)
	var a: Vector3 = h.rig_builder.get_joint_angles("Head")
	assert_almost_eq(a.x, -30.0, 6.0, "limit-frame angle is rest-relative (%s)" % a)
