## Tests for StumblePlanner — the pure decision logic behind stumble-step recovery
## (0.4.0 Self-Preservation). No live rig: balance snapshots and foot positions in,
## stepping foot and step target out. The stateful gating (cooldown, step count) and
## execution live elsewhere and are covered by the integration tests.
extends GutTest


# ── select_step_foot ────────────────────────────────────────────────────────

func test_picks_trailing_foot():
	# Feet straddle the support centre on X; CoM falls toward +X (right foot leads).
	# The trailing (left, -X) foot should step.
	var feet := {
		"Foot_L": Vector3(-0.15, 0.0, 0.0),
		"Foot_R": Vector3(0.15, 0.0, 0.0),
	}
	var step := StumblePlanner.select_step_foot(Vector2(1, 0), feet, Vector3.ZERO)
	assert_eq(step, "Foot_L", "trailing foot (away from fall direction) steps")


func test_picks_trailing_foot_other_direction():
	var feet := {
		"Foot_L": Vector3(-0.15, 0.0, 0.0),
		"Foot_R": Vector3(0.15, 0.0, 0.0),
	}
	var step := StumblePlanner.select_step_foot(Vector2(-1, 0), feet, Vector3.ZERO)
	assert_eq(step, "Foot_R", "fall toward -X → right foot is trailing and steps")


func test_no_step_without_imbalance():
	var feet := {
		"Foot_L": Vector3(-0.15, 0.0, 0.0),
		"Foot_R": Vector3(0.15, 0.0, 0.0),
	}
	assert_eq(StumblePlanner.select_step_foot(Vector2.ZERO, feet, Vector3.ZERO), "",
		"no fall direction → no step decision")


func test_no_step_with_single_foot():
	var feet := {"Foot_L": Vector3(-0.15, 0.0, 0.0)}
	assert_eq(StumblePlanner.select_step_foot(Vector2(1, 0), feet, Vector3.ZERO), "",
		"need two feet to choose a stepping foot")


func test_step_foot_uses_support_center_offset():
	# Both feet share +X sign but differ relative to a shifted support centre.
	var feet := {
		"Foot_L": Vector3(0.0, 0.0, 0.0),
		"Foot_R": Vector3(0.30, 0.0, 0.0),
	}
	var support := Vector3(0.15, 0.0, 0.0)
	var step := StumblePlanner.select_step_foot(Vector2(1, 0), feet, support)
	assert_eq(step, "Foot_L", "trailing relative to support centre, not world origin")


# ── compute_step_target ─────────────────────────────────────────────────────

func test_target_offsets_along_fall_direction():
	var t := StumblePlanner.compute_step_target(
		Vector3(0, 0.5, 0), Vector2(1, 0), 1.0, 0.4, 0.6)
	assert_almost_eq(t.x, 0.4, 0.0001, "x advances by step_length * balance_ratio")
	assert_almost_eq(t.z, 0.0, 0.0001)


func test_target_keeps_foot_height():
	var t := StumblePlanner.compute_step_target(
		Vector3(0, 0.73, 0), Vector2(0, 1), 1.0, 0.4, 0.6)
	assert_almost_eq(t.y, 0.73, 0.0001, "Y unchanged — caller ground-snaps it")
	assert_almost_eq(t.z, 0.4, 0.0001)


func test_target_scales_with_balance_ratio():
	var t := StumblePlanner.compute_step_target(
		Vector3.ZERO, Vector2(1, 0), 0.5, 0.4, 0.6)
	assert_almost_eq(t.x, 0.2, 0.0001, "half the imbalance → half the step")


func test_target_clamped_to_reach_max():
	var t := StumblePlanner.compute_step_target(
		Vector3.ZERO, Vector2(1, 0), 1.5, 0.6, 0.6)
	assert_almost_eq(t.x, 0.6, 0.0001, "step clamped to reach_max")


func test_target_unchanged_without_imbalance():
	var origin := Vector3(1, 0.5, 2)
	var t := StumblePlanner.compute_step_target(origin, Vector2.ZERO, 1.0, 0.4, 0.6)
	assert_eq(t, origin, "no fall direction → target is the foot's current position")
