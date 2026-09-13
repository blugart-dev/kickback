extends GutTest

# ── Feet load-bearing (0.6.0, docs/PLAN.md) ─────────────────────────────────
# The foot collider is a sole-aligned box (level with the character, bottom face
# on the foot IK sole), the feet collide by default, and the root anchor carries
# only `muscle_root_support` of the body's weight — the legs carry the rest.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _tuning(support: float = 0.0) -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.muscle_mode = RagdollTuning.MuscleMode.JOINT_MOTOR
	t.muscle_root_support = support
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


func _hips_sag(h) -> float:
	var hips: RigidBody3D = h.get_body("Hips")
	return h.spring.get_bone_target_global("Hips").origin.y - hips.global_position.y


# ── Sole-aligned box geometry (pure math) ───────────────────────────────────

func test_sole_shape_is_level_with_its_bottom_on_the_sole():
	# An ankle bone pitched 30 deg nose-down (like the Mixamo foot), toes ahead and
	# below it. The pre-0.6.0 bone-aligned box followed that pitch and its corner
	# sat several cm under the floor; the sole box must be level, bottom face exactly
	# `sole_depth` below the ankle, and reach behind the ankle by the heel share.
	var bd := BoneDefinition.new()
	bd.shape_type = "box"
	bd.sole_aligned = true
	bd.box_size = Vector3(0.12, 0.065, 0.325)
	bd.shape_offset = SkeletonDetector.FOOT_SOLE_OFFSET
	var ankle := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(0.3, 0.105, -0.2))
	var toe := Transform3D(Basis.IDENTITY, ankle.origin + Vector3(0.0, -0.07, 0.15))
	var local := PhysicsRigBuilder.sole_shape_transform(bd, ankle, toe, 0.065, Vector3.UP)
	var world := ankle * local
	assert_almost_eq(world.basis.y.normalized(), Vector3.UP, Vector3.ONE * 1e-4, "box up axis is world up (level)")
	assert_almost_eq(world.basis.z.normalized(), Vector3.BACK, Vector3.ONE * 1e-4, "box length runs along the flattened ankle->toe direction")
	var half := bd.box_size * 0.5
	var lo := INF
	var front := -INF
	var back := INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var c: Vector3 = world * Vector3(sx * half.x, sy * half.y, sz * half.z)
				lo = minf(lo, c.y)
				front = maxf(front, c.z)
				back = minf(back, c.z)
	assert_almost_eq(lo, ankle.origin.y - 0.065, 1e-4, "bottom face is exactly sole_depth below the ankle")
	assert_almost_eq(front - ankle.origin.z, 0.325 * SkeletonDetector.FOOT_SOLE_OFFSET, 1e-4, "toes: shape_offset of the length ahead of the ankle")
	assert_almost_eq(ankle.origin.z - back, 0.325 * (1.0 - SkeletonDetector.FOOT_SOLE_OFFSET), 1e-4, "heel: the rest behind it")


func test_build_body_uses_the_sole_transform_for_sole_aligned_feet_only():
	var bd := BoneDefinition.new()
	bd.rig_name = "Foot_L"
	bd.shape_type = "box"
	bd.sole_aligned = true
	bd.box_size = Vector3(0.12, 0.065, 0.325)
	bd.shape_offset = SkeletonDetector.FOOT_SOLE_OFFSET
	var t := RagdollTuning.create_default()
	var ankle := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(0.0, 0.105, 0.0))
	var toe := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.035, 0.15))
	var body := PhysicsRigBuilder.build_body(bd, ankle, toe, t)
	autofree(body)
	var shape := body.get_child(0) as CollisionShape3D
	assert_almost_eq((ankle * shape.transform).basis.y.normalized(), Vector3.UP, Vector3.ONE * 1e-4, "sole-aligned foot box is level")
	bd.sole_aligned = false
	var legacy := PhysicsRigBuilder.build_body(bd, ankle, toe, t)
	autofree(legacy)
	var lshape := legacy.get_child(0) as CollisionShape3D
	assert_almost_eq(lshape.rotation.x, PI / 2.0, 1e-6, "a plain box keeps the bone-aligned 90 deg convention")


func test_mixamo_profiles_mark_the_feet_sole_aligned():
	var skel := RigHarness.build_mixamo_skeleton()
	autofree(skel)
	var profiles: Array[RagdollProfile] = [RagdollProfile.create_mixamo_default(), SkeletonDetector.create_profile_from_skeleton(skel, SkeletonDetector.detect_humanoid_bones(skel))]
	for profile: RagdollProfile in profiles:
		for bd: BoneDefinition in profile.bones:
			var is_foot := bd.rig_name in SkeletonDetector.SOLE_ALIGNED_SLOTS
			assert_eq(bd.sole_aligned, is_foot, "%s sole_aligned=%s" % [bd.rig_name, str(is_foot)])
			if is_foot:
				assert_almost_eq(bd.shape_offset, SkeletonDetector.FOOT_SOLE_OFFSET, 1e-6, "%s: ankle sits FOOT_SOLE_OFFSET of the length from the heel" % bd.rig_name)


func test_detected_foot_box_includes_the_heel():
	var skel := RigHarness.build_mixamo_skeleton()
	autofree(skel)
	var profile := SkeletonDetector.create_profile_from_skeleton(skel, SkeletonDetector.detect_humanoid_bones(skel))
	var ankle_idx := skel.find_bone("mixamorig_LeftFoot")
	var extent := 0.0
	for child_idx: int in skel.get_bone_children(ankle_idx):
		extent = maxf(extent, skel.get_bone_global_rest(child_idx).origin.distance_to(skel.get_bone_global_rest(ankle_idx).origin))
	# The detector floors every box dimension at a ratio of the Hips→Head height.
	var skel_height := absf(skel.get_bone_global_rest(skel.find_bone("mixamorig_Head")).origin.y
		- skel.get_bone_global_rest(skel.find_bone("mixamorig_Hips")).origin.y)
	var min_z: float = (SkeletonDetector.BONE_PROPORTIONS["Foot_L"]["min_ratio"] as Vector3).z * skel_height
	for bd: BoneDefinition in profile.bones:
		if bd.rig_name == "Foot_L":
			var expected := maxf(extent * (1.0 + SkeletonDetector.FOOT_HEEL_RATIO), min_z)
			assert_almost_eq(bd.box_size.z, expected, 1e-3, "foot length = ankle->toe extent + heel (or the height-scaled minimum)")
			assert_gt(bd.box_size.z, extent, "the box is longer than the ankle->toe extent (heel added)")


# ── The built rig ───────────────────────────────────────────────────────────

func test_feet_collide_and_report_contacts_by_default():
	var h = await _spawn(_tuning())
	await wait_physics_frames(60)
	for foot in ["Foot_L", "Foot_R"]:
		var body: RigidBody3D = h.get_body(foot)
		assert_true(body.contact_monitor, "%s reports contacts (balance layer input)" % foot)
		assert_gte(body.max_contacts_reported, PhysicsRigBuilder.FOOT_CONTACTS_REPORTED)
		assert_ne(body.collision_mask, 0, "%s collides while standing (feet are load-bearing)" % foot)
		assert_gt(body.get_contact_count(), 0, "%s touches the ground" % foot)


func test_legs_carry_the_body_when_the_anchor_carries_none():
	# muscle_root_support = 0: the root anchor has no vertical authority. With the
	# feet on the ground the pelvis stays at its (foot-IK-shifted) target through the
	# hip / knee motors alone...
	var h = await _spawn(_tuning(0.0))
	await wait_physics_frames(120)
	var sag := _hips_sag(h)
	assert_lt(absf(sag), 0.02, "pelvis within 2 cm of its target on load-bearing legs (sag %.1f mm)" % (sag * 1000.0))
	var hips: RigidBody3D = h.get_body("Hips")
	var ymin := INF
	var ymax := -INF
	for i in 60:
		await wait_physics_frames(1)
		ymin = minf(ymin, hips.global_position.y)
		ymax = maxf(ymax, hips.global_position.y)
	assert_lt(ymax - ymin, 0.01, "no pelvis bounce on the legs (%.1f mm peak-to-peak over 1 s)" % ((ymax - ymin) * 1000.0))


func test_masked_feet_sink_when_the_anchor_carries_none():
	# ...and with the feet masked out of collision (the pre-0.6.0 default) the same
	# body has nothing to stand on and sinks — proof the anchor is not holding it up.
	var t := _tuning(0.0)
	t.foot_ik_disable_foot_collision = true
	var h = await _spawn(t)
	await wait_physics_frames(120)
	var sag := _hips_sag(h)
	assert_gt(sag, 0.05, "pelvis sinks past 5 cm with no feet to stand on (sag %.1f mm)" % (sag * 1000.0))


func test_full_support_holds_the_pelvis_without_feet():
	# muscle_root_support = 1 restores the 0.5.0 stand-in: the anchor may carry the
	# whole weight, so masked feet no longer matter for the pelvis height.
	var t := _tuning(1.0)
	t.foot_ik_disable_foot_collision = true
	var h = await _spawn(t)
	await wait_physics_frames(120)
	var sag := _hips_sag(h)
	assert_lt(absf(sag), 0.01, "anchor at full support holds the pelvis within 1 cm (sag %.1f mm)" % (sag * 1000.0))


func test_legacy_mode_ignores_the_support_knob():
	var t := _tuning(0.0)
	t.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
	t.foot_ik_disable_foot_collision = true
	var h = await _spawn(t)
	await wait_physics_frames(90)
	var sag := _hips_sag(h)
	assert_lt(absf(sag), 0.01, "the velocity pin holds the pelvis regardless of muscle_root_support (sag %.1f mm)" % (sag * 1000.0))
