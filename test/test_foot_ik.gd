extends GutTest


# ── FootIKSolver tests ──────────────────────────────────────────────────────
# Two layers:
#   1. Lifecycle / config tests that exercise the real solver and the real
#      RagdollTuning validation with no scene.
#   2. Runtime tests that drive the REAL FootIKSolver — the one the
#      ActiveRagdollController lazily creates — on a live rig standing over a
#      ground plane (built via res://test/helpers/rig_harness.gd), replacing the
#      old re-implemented swing/pelvis formula tests.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


# Builds a rig with foot IK ENABLED over a ground plane, then steps physics so
# the controller's lazy FootIKSolver initializes and solves a few NORMAL frames.
func _spawn_with_foot_ik(extra_frames: int = 20):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(RagdollTuning.create_default(), null, true)  # foot_ik_enabled is on by default
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	await wait_physics_frames(extra_frames)
	return h


# ── Solver lifecycle (real class, no scene) ────────────────────────────────

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


# ── RagdollTuning foot IK defaults / validation ────────────────────────────

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


# ── Real FootIKSolver on a live rig ────────────────────────────────────────

func test_controller_creates_foot_ik_solver():
	var h = await _spawn_with_foot_ik()
	assert_not_null(h.controller._foot_ik, "controller lazily created a FootIKSolver")
	assert_true(h.controller._foot_ik.is_initialized(), "solver initialized against the rig")


func test_solver_reads_leg_lengths_from_rest():
	var h = await _spawn_with_foot_ik()
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	# Lengths are derived from the skeleton's rest poses (0.42 m + 0.40 m).
	assert_almost_eq(solver._upper_leg_len, 0.42, 0.02, "upper leg length read from rest")
	assert_almost_eq(solver._lower_leg_len, 0.40, 0.02, "lower leg length read from rest")


func test_feet_plant_over_ground():
	# Extra frames so the exponential weight blend has time to ramp toward 1.
	var h = await _spawn_with_foot_ik(35)
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	assert_gt(solver._ik_weight_l, 0.4, "left foot plants over the ground")
	assert_gt(solver._ik_weight_r, 0.4, "right foot plants over the ground")
	assert_true(solver.is_active(), "foot IK reports active")


func test_pelvis_never_lifts_on_flat_ground():
	var h = await _spawn_with_foot_ik(35)
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	# Feet rest on flat ground level with the root, so the pelvis must not rise.
	assert_true(solver._pelvis_offset <= 0.001,
		"pelvis offset never lifts above zero (got %f)" % solver._pelvis_offset)
