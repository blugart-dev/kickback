extends GutTest

# ── Guided persistent ragdoll (set_persistent_guided) ──────────────────────
# Drives the REAL controller (live rig via res://test/helpers/rig_harness.gd)
# through an animation-guided death: the springs start at a scale of their base
# strength, ramp strictly down to zero over the guide window, and the body ends
# exactly as limp as a plain persistent ragdoll — then set_persistent(false)
# still recovers, and hits during the guide stay pure impulse.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _fast_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	t.ragdoll_force_recovery_time = 0.4
	t.recovery_duration = 0.4
	t.safety_timeout = 0.6
	t.pose_blend_duration = 0.2
	t.settle_duration = 0.15
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


func test_guided_ramps_strengths_down_to_persistent_limp():
	var h = await _spawn(_fast_tuning())
	watch_signals(h.controller)
	var base: float = h.spring.get_base_strength("Chest")
	assert_gt(base, 0.0, "harness chest has a base strength")

	# 0.5 s window at 60 Hz = 30 physics frames.
	h.controller.set_persistent_guided(0.5, 0.5)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"guided death is PERSISTENT from the first frame")
	assert_true(h.controller.is_guiding(), "guide is live right after the call")
	assert_signal_emitted(h.controller, "ragdoll_started")
	assert_false(h.controller._fall_bracing, "guided death does not arm the fall brace")
	assert_almost_eq(h.spring.get_bone_strength("Chest"), base * 0.5, 0.001,
		"frame-0 strength is base * strength_scale")
	assert_almost_eq(h.controller.get_guide_scale(), 0.5, 0.001)

	# Strictly decreasing samples across the ramp.
	var s0: float = h.spring.get_bone_strength("Chest")
	await wait_physics_frames(8)
	var s1: float = h.spring.get_bone_strength("Chest")
	await wait_physics_frames(8)
	var s2: float = h.spring.get_bone_strength("Chest")
	assert_lt(s1, s0, "chest strength drops over the ramp (sample 1)")
	assert_lt(s2, s1, "chest strength keeps dropping (sample 2)")
	assert_gt(s2, 0.0, "still guiding mid-ramp")
	assert_true(h.controller.is_guiding(), "still guiding mid-ramp")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"stays PERSISTENT while guiding")

	# Past the window: fully limp, still PERSISTENT, guide_finished fired.
	await wait_physics_frames(24)
	assert_false(h.controller.is_guiding(), "guide over after ramp_time")
	assert_signal_emitted(h.controller, "guide_finished")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"limp corpse stays PERSISTENT (no settle -> recovery)")
	for rig_name: String in RigHarness.RIG_NAMES:
		assert_almost_eq(h.spring.get_bone_strength(rig_name), 0.0, 0.001,
			"%s spring zeroed after the guide" % rig_name)
	assert_almost_eq(h.controller.get_guide_scale(), 0.0, 0.001)


func test_guided_hit_stays_pure_impulse():
	var h = await _spawn(_fast_tuning())
	h.controller.set_persistent_guided(0.5, 0.5)
	await wait_physics_frames(3)

	var smash := ImpactProfile.new()
	smash.ragdoll_probability = 1.0
	smash.strength_reduction = 1.0
	smash.strength_spread = 99
	var chest := h.get_body("Chest")
	h.controller.apply_hit(chest, Vector3.FORWARD, chest.global_position, smash)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"a hit during the guide does not leave PERSISTENT")
	assert_true(h.controller.is_guiding(), "a hit during the guide does not cancel it")
	assert_gt(h.spring.get_bone_strength("Chest"), 0.0,
		"the guide keeps its strengths through a hit (impulse only)")


func test_guided_releases_and_recovers():
	var h = await _spawn(_fast_tuning())
	h.controller.set_persistent_guided(0.5, 0.3)
	await wait_physics_frames(5)
	watch_signals(h.controller)
	# Release mid-ramp: the get-up owns the strengths from here on.
	h.controller.set_persistent(false)
	assert_false(h.controller.is_guiding(), "release cancels the guide")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.GETTING_UP)
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 8.0)
	assert_true(recovered, "released guided ragdoll recovers")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL)
	assert_almost_eq(h.spring.get_bone_strength("Hips"), h.spring.get_base_strength("Hips"),
		0.02, "hips spring restored to base")


func test_guided_zero_window_is_plain_persistent():
	var h = await _spawn(_fast_tuning())
	watch_signals(h.controller)
	h.controller.set_persistent_guided(0.5, 0.0)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT)
	assert_false(h.controller.is_guiding(), "no window = no guide")
	assert_signal_emitted(h.controller, "guide_finished")
	for rig_name: String in RigHarness.RIG_NAMES:
		assert_almost_eq(h.spring.get_bone_strength(rig_name), 0.0, 0.001,
			"%s spring zeroed immediately" % rig_name)


func test_guide_scale_curve():
	var h = await _spawn(_fast_tuning())
	# ease 2: at half the window the scale is a quarter of the start, not half.
	h.controller.set_persistent_guided(0.8, 1.0, 2.0)
	h.controller._guide_elapsed = 0.5
	assert_almost_eq(h.controller.get_guide_scale(), 0.8 * 0.25, 0.001,
		"ease exponent shapes the ramp")
	h.controller._guide_ease = 1.0
	assert_almost_eq(h.controller.get_guide_scale(), 0.4, 0.001, "linear at ease 1")


func test_queue_persistent_guided_before_setup():
	# The facade's queue_ variant is spawn-safe: called before the rig exists it
	# starts the guide on setup_complete.
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(_fast_tuning(), null, true)
	h.character.queue_persistent_guided(0.5, 0.5)
	assert_false(h.character.is_setup_complete(), "queued before setup")
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "setup completed")
	await wait_physics_frames(1)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"queued guided death applied on setup_complete")
	assert_true(h.controller.is_guiding(), "and it is guiding")
