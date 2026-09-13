extends GutTest

# ── Balance control defaults, the physical fall detector, the upright experiment ──
# (0.6.0). The root anchor's sideways hold is a bounded ASSIST (muscle_root_hold 0.25),
# the ankles are 150 N·m, the legs run a faster motor loop, and physics decides a fall:
# a pelvis that has dropped or tilted while "standing" commits to RAGDOLL.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.muscle_mode = RagdollTuning.MuscleMode.JOINT_MOTOR
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	await wait_physics_frames(45)
	return h


func test_defaults_are_the_measured_balance_configuration():
	var t := RagdollTuning.create_default()
	assert_almost_eq(t.muscle_root_hold, 0.25, 1e-6, "sideways assist at a quarter of the anchor force")
	assert_almost_eq(t.muscle_root_support, 0.0, 1e-6, "no vertical hold: the legs carry the body")
	assert_almost_eq(t.muscle_leg_gain, 0.2, 1e-6, "legs run a faster motor loop than the arms")
	assert_almost_eq(t.step_trigger_ratio, 1.0, 1e-6, "a balance step fires once the capture point leaves the feet")
	assert_false(t.upright_enabled, "the IK-shift upright behavior is experimental and off")
	assert_almost_eq(SkeletonDetector.MUSCLE_TORQUE_TABLE["Foot_L"], 150.0, 1e-6, "ankle torque 150 N·m")
	for bd: BoneDefinition in RagdollProfile.create_mixamo_default().bones:
		if bd.rig_name in SkeletonDetector.SOLE_ALIGNED_SLOTS:
			assert_almost_eq(bd.muscle_torque, 150.0, 1e-6, "%s carries the ankle torque" % bd.rig_name)


func test_leg_gain_is_applied_to_the_leg_chains_only():
	var h = await _spawn(_tuning())
	var legs: Dictionary = h.spring._leg_set
	for rig in ["UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R", "Hips"]:
		assert_true(legs.has(rig), "%s takes muscle_leg_gain" % rig)
	for rig in ["Spine", "Chest", "Head", "UpperArm_L", "Hand_R"]:
		assert_false(legs.has(rig), "%s keeps muscle_gain" % rig)


func test_standing_with_the_assist_holds_within_the_stagger_threshold():
	var h = await _spawn(_tuning())
	var worst := 0.0
	for i in 90:
		await wait_physics_frames(1)
		worst = maxf(worst, h.controller.get_balance().ratio)
	assert_lt(worst, h.tuning.balance_stagger_threshold, "a quiet stance never crosses the stagger threshold (worst ratio %.2f)" % worst)
	var hips: RigidBody3D = h.get_body("Hips")
	var sag: float = h.spring.get_bone_target_global("Hips").origin.y - hips.global_position.y
	assert_lt(absf(sag), 0.02, "pelvis within 2 cm of its target on the legs (sag %.1f mm)" % (sag * 1000.0))


func test_physics_decides_the_fall():
	# No dice, no pain: a 400 N·s shove at the chest with the assist released. The body
	# topples; when the pelvis has dropped / tilted for FALL_HOLD_SECONDS the controller
	# commits to RAGDOLL and the get-up follows on its own.
	var t := _tuning()
	t.muscle_root_hold = 0.0
	t.steps_enabled = false
	var h = await _spawn(t)
	watch_signals(h.controller)
	var chest: RigidBody3D = h.get_body("Chest")
	chest.apply_central_impulse(Vector3(400.0, 0.0, 0.0))
	var fell := false
	for i in 120:
		await wait_physics_frames(1)
		if h.controller.get_state() == ActiveRagdollController.State.RAGDOLL:
			fell = true
			break
	assert_true(fell, "the fall was detected and committed to RAGDOLL within 2 s")
	assert_signal_emitted(h.controller, "ragdoll_started")


func test_no_fall_detected_while_standing_or_getting_up():
	var h = await _spawn(_tuning())
	watch_signals(h.controller)
	await wait_physics_frames(60)
	assert_signal_not_emitted(h.controller, "ragdoll_started", "a quiet stance never trips the fall detector")
	# During the canned get-up the pelvis IS low and tilted: the detector must stay out.
	h.controller.trigger_ragdoll()
	await wait_for_signal(h.controller.recovery_started, 6.0)
	var state_during: int = h.controller.get_state()
	assert_eq(state_during, ActiveRagdollController.State.GETTING_UP)
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 8.0)
	assert_true(recovered, "the get-up completes without the detector re-dropping the character")


func test_upright_behavior_shifts_the_body_target_against_the_error_when_enabled():
	var t := _tuning()
	t.upright_enabled = true
	var h = await _spawn(t)
	var ub: UprightBehavior = null
	for b in h.controller.get_behaviors():
		if b is UprightBehavior:
			ub = b
	assert_not_null(ub, "the default behavior list contains the (disabled by default) UprightBehavior")
	# Push the body +X: the error goes +X, the target shift goes -X.
	for body: RigidBody3D in h.rig_builder.get_bodies().values():
		body.linear_velocity += Vector3(1.0, 0.0, 0.0)
	await wait_physics_frames(3)
	assert_gt(ub.last_error.x, 0.0, "error follows the body's drift (+X)")
	assert_lt(ub.last_shift.x, 0.0, "the whole-body target is shifted the other way (%.3f m)" % ub.last_shift.x)
	assert_almost_eq(h.controller._foot_ik.get_body_shift().x, ub.last_shift.x, 1e-6, "the shift reaches the foot IK solver")
