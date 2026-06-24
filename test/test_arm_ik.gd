extends GutTest


# ── ArmIKSolver tests ───────────────────────────────────────────────────────
# Two layers, mirroring test_foot_ik.gd:
#   1. Lifecycle tests that exercise the real solver with no scene.
#   2. Runtime tests that drive the REAL ArmIKSolver on a live rig built by
#      res://test/helpers/rig_harness.gd. Foot IK is disabled so the arm solver
#      owns the spring's override channel (co-running both is the B3 wiring step).
#
# The solver reads ANIMATION globals (static at idle in the harness), so the reach
# blend is driven deterministically by calling process() in a loop and asserting on
# the override buffer — no coupling to physics-tick ordering.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _spawn(extra_frames: int = 10):
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false  # free the override channel for the arm solver
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(t, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	await wait_physics_frames(extra_frames)
	return h


# Builds + initializes the real ArmIKSolver against the harness rig.
func _make_solver(h) -> ArmIKSolver:
	var solver := ArmIKSolver.new()
	var ok := solver.initialize(h.spring, h.tuning, h, h.rig_builder, h.profile)
	assert_true(ok, "ArmIKSolver initialized against the rig")
	return solver


# World-space animation origin of a rig bone (the solver's reach anchor space).
func _bone_world(h, rig_name: String) -> Vector3:
	var idx: int = h.spring.get_bone_idx(rig_name)
	return (h.skeleton.global_transform * h.spring.get_animation_bone_global(idx)).origin


# Runs the solver's solve loop for [param frames] fixed 60 Hz steps.
func _pump(solver: ArmIKSolver, frames: int) -> void:
	for i in frames:
		solver.process(1.0 / 60.0)


# ── Lifecycle (real class, no scene) ───────────────────────────────────────

func test_solver_creation():
	var solver := ArmIKSolver.new()
	assert_not_null(solver)
	assert_false(solver.is_initialized())
	assert_false(solver.is_active())
	assert_false(solver.is_reaching())


func test_uninitialized_calls_are_safe():
	var solver := ArmIKSolver.new()
	solver.process(0.016)
	solver.begin_reach("L", Vector3(1, 1, 1))
	solver.update_reach("L", Vector3(2, 2, 2))
	solver.end_reach("L")
	solver.reset()
	# begin_reach sets state flags even before init, but process() is a no-op, so the
	# solver never becomes active without an initialized rig.
	assert_false(solver.is_active())


func test_reset_clears_reach_state():
	var solver := ArmIKSolver.new()
	solver.begin_reach("L", Vector3(1, 0, 0))
	solver.begin_reach("R", Vector3(-1, 0, 0))
	assert_true(solver.is_reaching())
	solver.reset()
	assert_false(solver.is_reaching())
	assert_false(solver.is_active())


# ── Real ArmIKSolver on a live rig ─────────────────────────────────────────

func test_initializes_and_reads_arm_lengths():
	var h = await _spawn()
	var solver = _make_solver(h)
	assert_true(solver.is_initialized())
	# Lengths derived from the synthetic skeleton's rest poses (0.28 m + 0.25 m).
	assert_almost_eq(solver._upper_arm_len, 0.28, 0.02, "upper arm length read from rest")
	assert_almost_eq(solver._lower_arm_len, 0.25, 0.02, "lower arm length read from rest")
	# Full reach = the two segments summed.
	assert_almost_eq(solver.get_reach(), 0.53, 0.03, "reach sums the arm segments")


func test_reach_drives_hand_to_target():
	var h = await _spawn()
	var solver = _make_solver(h)
	# A target within reach of the left shoulder (total arm reach ≈ 0.53 m).
	var shoulder := _bone_world(h, "UpperArm_L")
	var target := shoulder + Vector3(0.25, -0.15, 0.15)
	solver.begin_reach("L", target)
	_pump(solver, 50)

	assert_gt(solver._weight_l, 0.9, "left arm IK weight blended in")
	assert_true(solver._overrides_buf.has("Hand_L"), "left hand override written")
	var hand_t: Transform3D = solver._overrides_buf["Hand_L"]
	assert_almost_eq(hand_t.origin.distance_to(target), 0.0, 0.02,
		"left hand reaches the target")
	assert_true(solver._overrides_buf.has("UpperArm_L") and solver._overrides_buf.has("LowerArm_L"),
		"shoulder and elbow overrides written")
	# The other arm is untouched.
	assert_false(solver._overrides_buf.has("Hand_R"), "right arm not driven")
	assert_true(solver.is_active())


func test_unreachable_target_leaves_arm_at_anim():
	var h = await _spawn()
	var solver = _make_solver(h)
	var shoulder := _bone_world(h, "UpperArm_R")
	# Far beyond arm reach — the solve degenerates, so no override is written.
	solver.begin_reach("R", shoulder + Vector3(5.0, 0, 0))
	_pump(solver, 30)
	assert_gt(solver._weight_r, 0.9, "weight still ramps even when unreachable")
	assert_false(solver._overrides_buf.has("Hand_R"),
		"unreachable target writes no override (arm stays at animation pose)")


# Physics-anchored mode (used by the fall reach) solves from the arm's physical body
# pose rather than the animation pose. At rest the bodies sit on the animation pose, so
# the hand still reaches the target — but the solve now tracks the body, not the anim.
func test_physics_anchored_reach_drives_hand():
	var h = await _spawn()
	var solver = _make_solver(h)
	solver.set_physics_anchored(true)
	var shoulder_body: RigidBody3D = h.rig_builder.get_bodies().get("UpperArm_R")
	assert_not_null(shoulder_body)
	var target := shoulder_body.global_position + Vector3(-0.2, -0.2, 0.15)
	solver.begin_reach("R", target, 1.0)
	_pump(solver, 50)
	assert_gt(solver._weight_r, 0.9, "physics-anchored arm blended in")
	assert_true(solver._overrides_buf.has("Hand_R"), "physics-anchored hand override written")
	var hand_t: Transform3D = solver._overrides_buf["Hand_R"]
	assert_almost_eq(hand_t.origin.distance_to(target), 0.0, 0.03,
		"physics-anchored hand reaches the target")


func test_end_reach_blends_weight_out():
	var h = await _spawn()
	var solver = _make_solver(h)
	var shoulder := _bone_world(h, "UpperArm_L")
	solver.begin_reach("L", shoulder + Vector3(0.2, -0.1, 0.1))
	_pump(solver, 40)
	assert_gt(solver._weight_l, 0.9, "weight blended in")
	solver.end_reach("L")
	assert_false(solver.is_reaching(), "reach released")
	_pump(solver, 40)
	assert_lt(solver._weight_l, 0.05, "weight blended back out after release")
