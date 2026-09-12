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


func test_solve_reachable_end_is_target():
	var ik := _bent_solve()
	assert_almost_eq((ik["end"] as Vector3).distance_to(Vector3(0.2, 0.3, 0.0)), 0.0, 0.0001,
		"a reachable target is the effective end position, unclamped")


# Straight-down animation chain (upper 1.0→0.6, lower 0.6→0.2) with 0.4 m segments.
const _ROOT := Vector3(0, 1.0, 0)
const _UPPER_ANIM := Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0))
const _LOWER_ANIM := Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))
const _END_ANIM := Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0))


func _straight_solve(target: Vector3, knee_hint: Vector3 = Vector3(0, 0.6, 0),
		fallback: Vector3 = Vector3(0, 0, -1)) -> Dictionary:
	return TwoBoneIK.solve(0.4, 0.4, _ROOT, target, knee_hint,
		_UPPER_ANIM, _LOWER_ANIM, _END_ANIM, fallback)


# An out-of-reach target no longer aborts the solve (which made callers drop the
# override and pop the limb to the animation pose): the chain extends fully toward it.
func test_solve_out_of_reach_extends_toward_target():
	var target := Vector3(5, 1, 0)  # far beyond the 0.8 m total reach, along +X
	var ik := _straight_solve(target)
	assert_false(ik.is_empty(), "out-of-reach target still solves")
	var knee: Vector3 = ik["knee"]
	var end: Vector3 = ik["end"]
	var to_target := (target - _ROOT).normalized()
	# End effector sits at the far edge of the reach band, on the root→target ray.
	assert_almost_eq(end.distance_to(_ROOT), 0.8 - TwoBoneIK.REACH_MARGIN, 0.001,
		"end is clamped to full extension")
	assert_almost_eq((end - _ROOT).normalized().dot(to_target), 1.0, 0.0001,
		"end lies on the root→target ray")
	# Fully extended: the knee sits on that ray up to the residual bend REACH_MARGIN
	# leaves in the joint (1 cm short of 0.8 m ≈ 9° at the hip for 0.4 m segments), and
	# the lengths still hold.
	assert_gt((knee - _ROOT).normalized().dot(to_target), cos(deg_to_rad(10.0)),
		"knee points at the target (chain straight up to the reach margin)")
	assert_almost_eq(knee.distance_to(_ROOT), 0.4, 0.001)
	assert_almost_eq(knee.distance_to(end), 0.4, 0.001)
	assert_almost_eq((ik["lower"] as Transform3D).origin.distance_to(knee), 0.0, 0.0001)


# A too-close target folds the chain as far as it goes instead of aborting.
func test_solve_too_close_folds_chain():
	var target := _ROOT + Vector3(0, -0.002, 0)  # 2 mm from the root
	var ik := _straight_solve(target)
	assert_false(ik.is_empty(), "too-close target still solves")
	var knee: Vector3 = ik["knee"]
	var end: Vector3 = ik["end"]
	assert_almost_eq(end.distance_to(_ROOT), TwoBoneIK.REACH_MARGIN, 0.0001,
		"end is clamped to the minimum reach")
	assert_almost_eq(knee.distance_to(_ROOT), 0.4, 0.001)
	assert_almost_eq(knee.distance_to(end), 0.4, 0.001)
	# Maximally bent: upper and lower segments run antiparallel.
	var upper_dir := (knee - _ROOT).normalized()
	var lower_dir := (end - knee).normalized()
	assert_lt(upper_dir.dot(lower_dir), -0.99, "segments fold back on each other")


func test_solve_degenerate_input_returns_empty():
	assert_true(_straight_solve(Vector3(0, 0.3, 0)).size() > 0, "sanity: normal solve works")
	var zero_seg := TwoBoneIK.solve(0.0, 0.4, _ROOT, Vector3(0, 0.3, 0), Vector3(0, 0.6, 0),
		_UPPER_ANIM, _LOWER_ANIM, _END_ANIM, Vector3(0, 0, -1))
	assert_true(zero_seg.is_empty(), "zero-length segment returns empty")
	var nan_target := _straight_solve(Vector3(NAN, 0.3, 0))
	assert_true(nan_target.is_empty(), "non-finite target returns empty")


# ── Bend-plane continuity near a straight hint ─────────────────────────────

# Root→hint direction tilted [param deg] degrees off straight-down toward
# [param toward] (a unit axis perpendicular to the chain).
func _tilted_hint(deg: float, toward: Vector3) -> Vector3:
	var dir := (Vector3.DOWN * cos(deg_to_rad(deg)) + toward * sin(deg_to_rad(deg))).normalized()
	return _ROOT + dir * 0.4


func _knee_bend_dir(ik: Dictionary, chain_dir: Vector3) -> Vector3:
	var v: Vector3 = (ik["knee"] as Vector3) - _ROOT
	return (v - chain_dir * v.dot(chain_dir)).normalized()


# The animation knee of an idle leg wobbles about straight. The old solver tested
# colinearity AFTER normalising the cross product, so anything but an exactly straight
# hint took the hint's (noisy) plane — a 1° hint opposed to the fallback flipped the
# knee 180° from where the 0° hint put it. The plane must now vary continuously.
func test_solve_near_straight_hint_does_not_flip_bend_plane():
	var target := Vector3(0, 0.3, 0)  # 0.7 m: a real bend (~29° at the knee)
	var fallback := Vector3(0, 0, 1)
	var chain_dir := (target - _ROOT).normalized()
	var straight := _straight_solve(target, _tilted_hint(0.0, fallback), fallback)
	var opposed_1deg := _straight_solve(target, _tilted_hint(1.0, -fallback), fallback)
	var agreeing_1deg := _straight_solve(target, _tilted_hint(1.0, fallback), fallback)
	var dir0 := _knee_bend_dir(straight, chain_dir)
	assert_almost_eq(dir0.dot(fallback), 1.0, 0.001, "0° hint bends along the fallback axis")
	var angle_opposed := rad_to_deg(acos(clampf(dir0.dot(_knee_bend_dir(opposed_1deg, chain_dir)), -1.0, 1.0)))
	var angle_agreeing := rad_to_deg(acos(clampf(dir0.dot(_knee_bend_dir(agreeing_1deg, chain_dir)), -1.0, 1.0)))
	assert_lt(angle_opposed, 5.0,
		"1° hint opposed to the fallback stays within a few degrees of the 0° plane (got %.1f°)" % angle_opposed)
	assert_lt(angle_agreeing, 5.0,
		"1° hint along the fallback stays within a few degrees of the 0° plane (got %.1f°)" % angle_agreeing)


# Well above the colinearity band the hint owns the plane outright, as before.
func test_solve_clear_hint_owns_bend_plane():
	var target := Vector3(0, 0.3, 0)
	var fallback := Vector3(0, 0, 1)
	var chain_dir := (target - _ROOT).normalized()
	var ik := _straight_solve(target, _tilted_hint(20.0, -fallback), fallback)
	var dir := _knee_bend_dir(ik, chain_dir)
	assert_almost_eq(dir.dot(-fallback), 1.0, 0.001, "a 20° hint bends the knee its own way")


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
