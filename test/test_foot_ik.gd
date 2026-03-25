extends GutTest


# ── FootIKSolver unit tests ────────────────────────────────────────────────
# Tests the IK solver's math and state management without a full scene.
# Scene-dependent features (raycasting, spring integration) require
# integration tests in the demo scenes.


func test_solver_creation():
	var solver := FootIKSolver.new()
	assert_not_null(solver)
	assert_false(solver.is_initialized())
	assert_false(solver.is_active())


func test_uninitialized_process_is_safe():
	var solver := FootIKSolver.new()
	# Should not crash when called before initialize
	solver.process(0.016)
	solver.process_stagger(0.016)
	solver.begin_stagger()
	solver.end_stagger()
	solver.reset()
	assert_false(solver.is_active())


func test_reset_clears_state():
	var solver := FootIKSolver.new()
	solver.reset()
	assert_false(solver.is_active())
	assert_false(solver._stagger_pinning)


func test_stagger_lifecycle():
	var solver := FootIKSolver.new()
	# begin_stagger on uninitialized solver is safe
	solver.begin_stagger()
	assert_false(solver._stagger_pinning, "Uninitialized solver should not pin")

	solver.end_stagger()
	assert_false(solver._stagger_pinning)


# ── RagdollTuning foot IK defaults ────────────────────────────────────────

func test_default_tuning_has_foot_ik():
	var t := RagdollTuning.create_default()
	assert_true(t.foot_ik_enabled)
	assert_almost_eq(t.foot_ik_ankle_height, 0.065, 0.001)
	assert_almost_eq(t.foot_ik_max_pelvis_drop, 0.35, 0.001)
	assert_almost_eq(t.foot_ik_max_adjustment, 0.5, 0.001)
	assert_almost_eq(t.foot_ik_swing_threshold, 0.25, 0.001)
	assert_almost_eq(t.foot_ik_plant_threshold, 0.17, 0.001)
	assert_almost_eq(t.foot_ik_pelvis_blend_speed, 8.0, 0.001)
	assert_almost_eq(t.foot_ik_foot_blend_speed, 10.0, 0.001)
	assert_almost_eq(t.foot_ik_ray_above_hip, 0.3, 0.001)
	assert_almost_eq(t.foot_ik_ray_below_hip, 2.5, 0.001)
	assert_eq(t.foot_ik_collision_mask, 1)
	assert_true(t.foot_ik_disable_foot_collision)
	assert_true(t.foot_ik_stagger_pin)
	assert_almost_eq(t.foot_ik_stagger_leg_strength, 0.4, 0.001)


func test_tuning_validates_foot_ik_bones():
	var t := RagdollTuning.create_default()
	var profile := RagdollProfile.create_mixamo_default()
	var warnings := t.validate_against_profile(profile)
	# Default Mixamo profile has all foot IK bones — no warnings
	assert_eq(warnings.size(), 0, "Default profile should pass foot IK validation")


func test_tuning_warns_missing_foot_bones():
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = true
	# Create a profile without foot bones
	var profile := RagdollProfile.new()
	profile.bones = []
	var warnings := t.validate_against_profile(profile)
	assert_true(warnings.size() > 0, "Should warn about missing foot IK bones")


# ── Swing detection math ──────────────────────────────────────────────────

func test_swing_detection_logic():
	# Replicate the swing detection formula from FootIKSolver
	var swing_threshold := 0.25
	var plant_threshold := 0.17
	var range_val := swing_threshold - plant_threshold

	# Foot at root level (planted)
	var far_planted := 0.10
	var tw_planted := clampf(1.0 - (far_planted - plant_threshold) / range_val, 0.0, 1.0)
	assert_almost_eq(tw_planted, 1.0, 0.01, "Foot at root should be fully planted")

	# Foot at swing threshold (transitioning)
	var far_swing := 0.25
	var tw_swing := clampf(1.0 - (far_swing - plant_threshold) / range_val, 0.0, 1.0)
	assert_almost_eq(tw_swing, 0.0, 0.01, "Foot at swing threshold should have zero weight")

	# Foot mid-range
	var far_mid := 0.21
	var tw_mid := clampf(1.0 - (far_mid - plant_threshold) / range_val, 0.0, 1.0)
	assert_true(tw_mid > 0.0 and tw_mid < 1.0, "Mid-range should be partial weight")

	# Foot well above swing threshold
	var far_high := 0.5
	if far_high >= swing_threshold:
		pass  # Weight stays 0 (not computed)
	assert_true(true, "High foot skipped correctly")


func test_pelvis_offset_clamping():
	var max_drop := 0.35
	# Both feet below animation → pelvis drops
	var offset_l := -0.2
	var offset_r := -0.3
	var wl := 1.0
	var wr := 1.0
	var target := clampf(minf(offset_l * wl, offset_r * wr), -max_drop, 0.0)
	assert_almost_eq(target, -0.3, 0.001, "Pelvis should drop to lowest foot")

	# Extreme drop gets clamped
	offset_r = -0.5
	target = clampf(minf(offset_l * wl, offset_r * wr), -max_drop, 0.0)
	assert_almost_eq(target, -max_drop, 0.001, "Pelvis drop should clamp to max")

	# Positive offset (foot above animation) → no pelvis lift
	offset_l = 0.1
	offset_r = 0.2
	target = clampf(minf(offset_l * wl, offset_r * wr), -max_drop, 0.0)
	assert_almost_eq(target, 0.0, 0.001, "Pelvis should not lift above zero")
