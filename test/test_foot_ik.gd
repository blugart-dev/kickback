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
func _spawn_with_foot_ik(extra_frames: int = 20, tuning: RagdollTuning = null):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning if tuning else RagdollTuning.create_default(), null, true)  # foot_ik_enabled is on by default
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
	assert_false(t.foot_ik_disable_foot_collision, "feet are load-bearing by default since 0.6.0")
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
	# Lengths are derived from the skeleton's rest poses (0.42 m + 0.40 m), per side.
	assert_almost_eq(solver._upper_leg_len_l, 0.42, 0.02, "left upper leg length read from rest")
	assert_almost_eq(solver._lower_leg_len_l, 0.40, 0.02, "left lower leg length read from rest")
	assert_almost_eq(solver._upper_leg_len_r, 0.42, 0.02, "right upper leg length read from rest")
	assert_almost_eq(solver._lower_leg_len_r, 0.40, 0.02, "right lower leg length read from rest")


# Skeletons are not guaranteed symmetric: each leg must be measured on its own bones.
func test_solver_measures_each_leg_separately():
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false  # keep the controller from building its own solver
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(t, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	# Lengthen the RIGHT thigh only (rest pose), then initialise a fresh solver.
	var knee_r := h.bone_idx("mixamorig_RightLeg")
	h.skeleton.set_bone_rest(knee_r, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.52, 0.0)))
	var solver := FootIKSolver.new()
	assert_true(solver.initialize(h.spring, h.tuning, h, h.rig_builder, h.profile),
		"solver initialised against the asymmetric rig")
	assert_almost_eq(solver._upper_leg_len_l, 0.42, 0.005, "left thigh keeps its own length")
	assert_almost_eq(solver._upper_leg_len_r, 0.52, 0.005, "right thigh measured on the right bones")
	assert_almost_eq(solver._lower_leg_len_r, 0.40, 0.005, "right shin unchanged")


# ── Fallback bend direction honours character_forward_sign ─────────────────

# The harness legs are perfectly straight, so the animation knee gives no bend plane
# and the solver must fall back to "knee bends forward". On flat ground the target
# foot sits ankle_height above the animation foot, forcing a real bend, so the knee
# override is displaced along the character's forward — whichever way that is.
func _knee_forward_displacement(sign: int) -> float:
	var t := RagdollTuning.create_default()
	t.character_forward_sign = sign
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(t, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	await wait_physics_frames(35)
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	assert_gt(solver._ik_weight_l, 0.4, "left foot planted (leg bending)")
	assert_true(solver._overrides_buf.has("LowerLeg_L"), "knee override written")
	var knee_override: Transform3D = solver._overrides_buf["LowerLeg_L"]
	var knee_idx: int = h.spring.get_bone_idx("LowerLeg_L")
	var knee_anim: Vector3 = (h.skeleton.global_transform * h.spring.get_animation_bone_global(knee_idx)).origin
	# The harness root has an identity basis, so forward = +Z * sign.
	var forward := Vector3(0, 0, 1) * float(sign)
	return (knee_override.origin - knee_anim).dot(forward)


func test_straight_leg_knee_bends_forward_plus_z_model():
	var along_forward: float = await _knee_forward_displacement(1)
	assert_gt(along_forward, 0.02,
		"+Z model: straight-leg knee bends toward +Z (got %.3f m)" % along_forward)


func test_straight_leg_knee_bends_forward_minus_z_model():
	var along_forward: float = await _knee_forward_displacement(-1)
	assert_gt(along_forward, 0.02,
		"-Z model: straight-leg knee bends toward -Z (got %.3f m)" % along_forward)


# ── Slope correction hardened against degenerate ground normals ────────────

# Leg chain in the harness layout: hip 0.85, knee 0.43, foot 0.03 (x = 0.1).
const _UPPER_L := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.85, 0.0))
const _LOWER_L := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.43, 0.0))
const _FOOT_L := Transform3D(Basis.IDENTITY, Vector3(0.1, 0.03, 0.0))


func test_zero_ground_normal_is_no_correction_and_no_engine_error():
	var h = await _spawn_with_foot_ik()
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	var ik: Dictionary = solver._solve_two_bone_ik(0.42, 0.40, _UPPER_L, _LOWER_L, _FOOT_L,
		Vector3(0.1, 0.065, 0.0), Vector3.ZERO, Vector3.ZERO)
	assert_false(ik.is_empty(), "solve succeeds with a zero normal")
	var foot: Transform3D = ik["foot"]
	assert_true(foot.basis.is_finite(), "foot basis is finite")
	assert_true(foot.basis.is_equal_approx(_FOOT_L.basis),
		"a zero normal applies no slope correction")
	# The bare Quaternion(UP, normal) constructor raises "The vectors must not be zero".
	assert_engine_error_count(0, "no engine error from the slope correction")


func test_downward_ground_normal_gives_valid_flip():
	var h = await _spawn_with_foot_ik()
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	var ik: Dictionary = solver._solve_two_bone_ik(0.42, 0.40, _UPPER_L, _LOWER_L, _FOOT_L,
		Vector3(0.1, 0.065, 0.0), Vector3.DOWN, Vector3.ZERO)
	assert_false(ik.is_empty(), "solve succeeds with a downward normal")
	var foot: Transform3D = ik["foot"]
	assert_true(foot.basis.is_finite(), "foot basis is finite for an antiparallel normal")
	var up_after: Vector3 = foot.basis * Vector3.UP
	assert_almost_eq(up_after.y, -1.0, 0.001, "foot up is rotated onto the downward normal")
	assert_engine_error_count(0, "no engine error from the slope correction")


# ── Over-stretched pin keeps the foot attached (clamped solve) ─────────────

func test_overstretched_target_keeps_foot_on_shin():
	var h = await _spawn_with_foot_ik()
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	# A target 1.5 m below the hip: beyond the 0.82 m leg.
	var ik: Dictionary = solver._solve_two_bone_ik(0.42, 0.40, _UPPER_L, _LOWER_L, _FOOT_L,
		Vector3(0.1, 0.85 - 1.5, 0.0), Vector3.UP, Vector3.ZERO)
	assert_false(ik.is_empty(), "over-stretched target still solves")
	var foot: Transform3D = ik["foot"]
	var knee: Vector3 = ik["knee"]
	assert_almost_eq(foot.origin.distance_to(knee), 0.40, 0.001,
		"foot stays one shin length from the knee (leg fully extended toward the target)")


# ── Runtime toggle-off restores foot collision masks ───────────────────────

func test_disabling_foot_ik_at_runtime_restores_foot_masks():
	# Opt-in masking (off by default since 0.6.0: the feet are load-bearing).
	var t := RagdollTuning.create_default()
	t.foot_ik_disable_foot_collision = true
	var h = await _spawn_with_foot_ik(35, t)
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	var foot_l: RigidBody3D = h.get_body("Foot_L")
	var foot_r: RigidBody3D = h.get_body("Foot_R")
	assert_not_null(foot_l)
	assert_ne(solver._foot_mask_l, 0, "sanity: the rig gave the foot a real mask to restore")
	# While foot IK solves with masking on, the feet are out of collision.
	assert_eq(foot_l.collision_mask, 0, "foot mask cleared while foot IK is solving")
	# Toggle off at runtime: the next NORMAL tick must hand the masks back.
	h.tuning.foot_ik_enabled = false
	await wait_physics_frames(2)
	assert_eq(foot_l.collision_mask, solver._foot_mask_l, "left foot mask restored")
	assert_eq(foot_r.collision_mask, solver._foot_mask_r, "right foot mask restored")
	assert_false(solver.is_active(), "IK influence dropped on toggle-off")


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


# A foot over a drop-off (ground beyond pelvis reach) must NOT drag the whole
# pelvis down and break the other, planted foot. Regression for the pelvis-drop
# support gate: only feet on reachable ground inform the drop.
func test_pelvis_ignores_foot_over_dropoff():
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(RagdollTuning.create_default(), null, false)  # no default ground
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	# Solid ground under the LEFT foot (x > 0), top flush with the feet (y ≈ 0).
	h.add_child(_platform(Vector3(5.0, -0.2, 0.0), Vector3(10.0, 0.4, 20.0)))
	# A deep drop-off under the RIGHT foot (x < 0): ground ~1 m below the feet,
	# far beyond foot_ik_max_pelvis_drop (0.35 m).
	h.add_child(_platform(Vector3(-5.0, -1.2, 0.0), Vector3(10.0, 0.4, 20.0)))
	await wait_physics_frames(35)
	var solver = h.controller._foot_ik
	assert_not_null(solver)
	assert_gt(solver._ik_weight_l, 0.4, "left foot plants on the solid ground")
	# The right foot's drop-off is excluded, so the pelvis stays near neutral
	# instead of being yanked to -foot_ik_max_pelvis_drop by the deep ground.
	assert_gt(solver._pelvis_offset, -0.1,
		"pelvis is not dragged into the drop-off (got %f)" % solver._pelvis_offset)


# Builds a layer-1 StaticBody3D box platform at [param pos] with [param size].
func _platform(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	return body
