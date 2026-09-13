extends GutTest

# ── Self-collision (0.6.0, docs/PLAN.md "ragdoll look") ─────────────────────
# On by default: the bodies of one rig collide with each other except jointed pairs
# (excluded by the joint) and pairs already overlapping in the build pose (excluded
# by the builder's safety net, listed by get_self_collision_exclusions()).

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.muscle_mode = RagdollTuning.MuscleMode.JOINT_MOTOR
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning, profile: RagdollProfile = null):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, profile, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	await wait_physics_frames(3)  # the safety net runs one physics tick after the build
	return h


func _excluded(a: RigidBody3D, b: RigidBody3D) -> bool:
	return b in a.get_collision_exceptions() or a in b.get_collision_exceptions()


func test_self_collision_is_on_by_default():
	assert_true(RagdollTuning.create_default().self_collision, "self_collision defaults to true since 0.6.0")


func test_non_adjacent_pairs_collide_and_jointed_pairs_do_not():
	var h = await _spawn(_tuning())
	# Non-adjacent, not overlapping in the harness pose: they collide.
	for pair in [["Hand_R", "UpperLeg_R"], ["LowerArm_L", "Chest"], ["Foot_L", "Foot_R"], ["Head", "Spine"]]:
		assert_false(_excluded(h.get_body(pair[0]), h.get_body(pair[1])), "%s / %s collide" % [pair[0], pair[1]])
	# Jointed pairs: the joint itself excludes them.
	var joints: Dictionary = h.rig_builder.get_joints()
	for child_rig: String in joints:
		var joint: Generic6DOFJoint3D = joints[child_rig].joint
		assert_true(joint.exclude_nodes_from_collision, "%s joint excludes its two bodies" % child_rig)
	assert_eq(h.rig_builder.get_self_collision_exclusions().size(), 0, "nothing overlaps in the harness build pose, so the safety net excluded nothing")


func test_no_body_pair_overlaps_in_the_standing_pose():
	var h = await _spawn(_tuning())
	await wait_physics_frames(30)
	var pairs: Array = h.rig_builder.find_overlapping_pairs()
	assert_eq(pairs.size(), 0, "standing rig has no non-adjacent overlaps: %s" % str(pairs))


func test_build_pose_overlaps_are_excluded_by_the_safety_net():
	# An absurd Hips box (1.2 m wide, 1.2 m tall) swallows the chest, arms and thighs in
	# the build pose: those pairs must be excluded for good, everything else still collides.
	var profile := RagdollProfile.create_mixamo_default()
	for bd: BoneDefinition in profile.bones:
		if bd.rig_name == "Hips":
			bd.box_size = Vector3(1.2, 1.2, 0.6)
	var h = await _spawn(_tuning(), profile)
	var excluded: Array = h.rig_builder.get_self_collision_exclusions()
	var names := PackedStringArray()
	for pair: Array in excluded:
		names.append("%s+%s" % [pair[0], pair[1]])
	assert_true("Chest+Hips" in names, "Hips swallowing the Chest in the build pose is excluded (%s)" % ", ".join(names))
	assert_true(_excluded(h.get_body("Hips"), h.get_body("Chest")), "the exclusion is applied to the bodies")
	assert_false(_excluded(h.get_body("Hand_L"), h.get_body("Foot_L")), "a pair that does not overlap still collides")


func test_self_collision_off_excludes_everything_and_reports_nothing():
	var t := _tuning()
	t.self_collision = false
	var h = await _spawn(t)
	assert_true(_excluded(h.get_body("Hand_R"), h.get_body("UpperLeg_R")), "opt-out: every pair excluded")
	assert_eq(h.rig_builder.get_self_collision_exclusions().size(), 0, "no safety-net list when self-collision is off")


func _hand_inside_chest(h) -> bool:
	var chest: RigidBody3D = h.get_body("Chest")
	var shape := chest.get_child(0) as CollisionShape3D
	var box := shape.shape as BoxShape3D
	var local: Vector3 = shape.global_transform.affine_inverse() * (h.get_body("Hand_L") as RigidBody3D).global_position
	var half := box.size * 0.5
	return absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z


func test_the_torso_blocks_a_limp_arm():
	# Limp rig (persistent ragdoll) lying on the ground; shove the left hand hard toward
	# the chest. With self-collision the chest box stops it; without, it passes inside.
	for self_col in [true, false]:
		var t := _tuning()
		t.self_collision = self_col
		var h = await _spawn(t)
		h.controller.set_persistent(true)
		await wait_physics_frames(90)  # down and settled
		var hand: RigidBody3D = h.get_body("Hand_L")
		var chest: RigidBody3D = h.get_body("Chest")
		var inside_before := _hand_inside_chest(h)
		var dir := (chest.global_position - hand.global_position).normalized()
		hand.apply_central_impulse(dir * 6.0)  # 1 kg hand → 6 m/s at the chest
		var ever_inside := false
		for i in 30:
			await wait_physics_frames(1)
			if _hand_inside_chest(h):
				ever_inside = true
		if self_col:
			assert_false(ever_inside, "self-collision on: the hand never enters the chest box (inside before: %s)" % str(inside_before))
		else:
			assert_true(ever_inside, "self-collision off: the same shove puts the hand inside the chest box")
