extends GutTest


# ── TwoBoneIK tests ─────────────────────────────────────────────────────────
# Pure, stateless math — the shared two-bone solver used by both FootIKSolver and
# ArmIKSolver. Tests assert geometric invariants (segment lengths, anchor
# positions, reachability) that hold regardless of bone convention, plus the
# hardened swing() degeneracy handling.


# ── swing(): shortest-arc rotation, hardened ───────────────────────────────

func test_swing_parallel_is_identity():
	var q := TwoBoneIK.swing(Vector3(1, 0, 0), Vector3(2, 0, 0))
	assert_almost_eq(q.x, 0.0, 0.0001)
	assert_almost_eq(q.y, 0.0, 0.0001)
	assert_almost_eq(q.z, 0.0, 0.0001)
	assert_almost_eq(absf(q.w), 1.0, 0.0001, "parallel vectors → identity rotation")


func test_swing_zero_input_is_identity():
	assert_eq(TwoBoneIK.swing(Vector3.ZERO, Vector3(1, 0, 0)), Quaternion.IDENTITY)
	assert_eq(TwoBoneIK.swing(Vector3(1, 0, 0), Vector3.ZERO), Quaternion.IDENTITY)


func test_swing_rotates_from_onto_to():
	var q := TwoBoneIK.swing(Vector3(1, 0, 0), Vector3(0, 1, 0))
	var rotated := (q * Vector3(1, 0, 0)).normalized()
	assert_almost_eq(rotated.x, 0.0, 0.0001)
	assert_almost_eq(rotated.y, 1.0, 0.0001)
	assert_almost_eq(rotated.z, 0.0, 0.0001)


func test_swing_antiparallel_is_180():
	# Antiparallel is the degeneracy the bare Quaternion(from, to) constructor
	# asserts on; swing() must return a valid 180° rotation onto the target.
	var q := TwoBoneIK.swing(Vector3(1, 0, 0), Vector3(-1, 0, 0))
	var rotated := (q * Vector3(1, 0, 0)).normalized()
	assert_almost_eq(rotated.x, -1.0, 0.001, "antiparallel → flips the vector")
	assert_almost_eq(q.get_axis().length(), 1.0, 0.001, "valid (non-NaN) rotation axis")


# ── solve(): two-bone IK invariants ────────────────────────────────────────

# A bent, reachable target. Equal-length segments anchored at (0,1,0), animation
# pose straight down, target pulled forward so the joint must bend.
func _bent_solve() -> Dictionary:
	var upper_anim := Transform3D(Basis(), Vector3(0, 1.0, 0))
	var lower_anim := Transform3D(Basis(), Vector3(0, 0.6, 0))
	var end_anim := Transform3D(Basis(), Vector3(0, 0.2, 0))
	var target := Vector3(0.2, 0.3, 0.0)
	return TwoBoneIK.solve(0.4, 0.4, upper_anim.origin, target, lower_anim.origin,
		upper_anim, lower_anim, end_anim, Vector3(0, 0, -1))


func test_solve_reachable_returns_chain():
	var ik := _bent_solve()
	assert_false(ik.is_empty(), "reachable target solves")
	assert_true(ik.has("upper") and ik.has("lower") and ik.has("knee"))


func test_solve_anchors_upper_at_root():
	var ik := _bent_solve()
	var upper: Transform3D = ik["upper"]
	assert_almost_eq(upper.origin.distance_to(Vector3(0, 1.0, 0)), 0.0, 0.0001,
		"upper segment is anchored at the root position")


func test_solve_segment_lengths_preserved():
	var ik := _bent_solve()
	var knee: Vector3 = ik["knee"]
	var lower: Transform3D = ik["lower"]
	# Knee sits one upper-length from the root and one lower-length from the target.
	assert_almost_eq(knee.distance_to(Vector3(0, 1.0, 0)), 0.4, 0.001,
		"root→knee equals the upper segment length")
	assert_almost_eq(knee.distance_to(Vector3(0.2, 0.3, 0.0)), 0.4, 0.001,
		"knee→target equals the lower segment length")
	# The lower segment transform is anchored at the knee.
	assert_almost_eq(lower.origin.distance_to(knee), 0.0, 0.0001,
		"lower segment is anchored at the knee")


func test_solve_unreachable_returns_empty():
	var upper_anim := Transform3D(Basis(), Vector3(0, 1.0, 0))
	var lower_anim := Transform3D(Basis(), Vector3(0, 0.6, 0))
	var end_anim := Transform3D(Basis(), Vector3(0, 0.2, 0))
	# Target far beyond the 0.8 m total reach.
	var ik := TwoBoneIK.solve(0.4, 0.4, upper_anim.origin, Vector3(5, 1, 0),
		lower_anim.origin, upper_anim, lower_anim, end_anim, Vector3(0, 0, -1))
	assert_true(ik.is_empty(), "target beyond reach returns empty")


# When the target sits exactly at the animation's own end position, the IK should
# reproduce the animation pose: both swings are identity, so each segment keeps its
# animation basis. This is what avoids spurious rotation error for the spring.
func test_solve_no_adjustment_keeps_anim_basis():
	# Right-angle bent pose: upper along +X, lower along -Y (each 0.4 m).
	var rot := Basis(Vector3(1, 0, 0), deg_to_rad(30.0))  # arbitrary non-identity basis
	var upper_anim := Transform3D(rot, Vector3(0.0, 1.0, 0))
	var lower_anim := Transform3D(rot, Vector3(0.4, 1.0, 0))  # knee
	var end_anim := Transform3D(rot, Vector3(0.4, 0.6, 0))   # end effector
	# Target == the animation's own end position → no adjustment needed.
	var ik := TwoBoneIK.solve(0.4, 0.4, upper_anim.origin, end_anim.origin,
		lower_anim.origin, upper_anim, lower_anim, end_anim, Vector3(0, 0, -1))
	assert_false(ik.is_empty())
	var upper: Transform3D = ik["upper"]
	var lower: Transform3D = ik["lower"]
	# Bases unchanged (swing ≈ identity) → no rotation error for the spring to chase.
	assert_true(upper.basis.is_equal_approx(rot),
		"upper segment stays at its animation basis when no adjustment is needed")
	assert_true(lower.basis.is_equal_approx(rot),
		"lower segment stays at its animation basis when no adjustment is needed")
	# And the solved knee lands on the animation knee.
	assert_almost_eq((ik["knee"] as Vector3).distance_to(Vector3(0.4, 1.0, 0)), 0.0, 0.001)
