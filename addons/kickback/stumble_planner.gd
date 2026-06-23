## Pure decision logic for stumble-step recovery (0.4.0 Self-Preservation).
##
## Stateless and side-effect-free: given a balance snapshot and the current foot
## positions, it decides WHICH foot should step and WHERE the step target sits.
## It deliberately owns none of the timing — the [ActiveRagdollController] owns the
## stateful gating (trigger band, per-step cooldown, step count) and the
## [FootIKSolver] owns execution (moving the foot to the target). Keeping the
## decision pure means it is unit-testable without a live rig or physics step.
##
## A stumble step is the trailing foot swinging in the fall direction to catch a
## loss of balance — the first *active* survival behavior. See
## docs/SELF_PRESERVATION.md.
class_name StumblePlanner
extends RefCounted

## Selects the foot that should step to catch a fall: the trailing foot, i.e. the
## one the centre-of-mass is falling AWAY from. The load-bearing foot is the one
## furthest in the fall ([param imbalance_dir]) direction and stays planted; the
## other foot is free to swing. [param foot_positions] maps foot rig name → world
## position. Returns "" when it cannot decide (no imbalance, fewer than two feet,
## or degenerate positions coincident with the support centre).
static func select_step_foot(imbalance_dir: Vector2, foot_positions: Dictionary,
		support_center: Vector3) -> String:
	if imbalance_dir.length_squared() < 0.0001 or foot_positions.size() < 2:
		return ""
	var dir := imbalance_dir.normalized()
	var support_xz := Vector2(support_center.x, support_center.z)
	var step_foot := ""
	var lowest_dot := INF
	for foot_rig: String in foot_positions:
		var fp: Vector3 = foot_positions[foot_rig]
		var off := Vector2(fp.x, fp.z) - support_xz
		if off.length_squared() <= 0.0001:
			continue
		var d := off.normalized().dot(dir)
		if d < lowest_dot:
			lowest_dot = d
			step_foot = foot_rig
	return step_foot


## Computes the world-space step target on the ground plane (pre ground-snap) for a
## foot at [param foot_pos]: an offset from the foot's current position along the
## fall direction ([param imbalance_dir]), with distance scaled by how far
## off-balance the character is ([param balance_ratio]) and clamped to
## [param reach_max]. The Y is left at the foot's current height — the caller
## ground-snaps it via raycast during execution. Returns [param foot_pos]
## unchanged when there is no fall direction to step along.
static func compute_step_target(foot_pos: Vector3, imbalance_dir: Vector2,
		balance_ratio: float, step_length: float, reach_max: float) -> Vector3:
	if imbalance_dir.length_squared() < 0.0001:
		return foot_pos
	var dir := imbalance_dir.normalized()
	var dist := clampf(step_length * maxf(balance_ratio, 0.0), 0.0, maxf(reach_max, 0.0))
	return foot_pos + Vector3(dir.x, 0.0, dir.y) * dist


## Pure gate deciding whether a stumble step should be attempted this frame, given
## the current [param balance_ratio] and gating state. A step fires only in the band
## between "wobbling" ([param step_threshold]) and "tipping over"
## ([param ragdoll_threshold] — past it the character ragdolls instead), while not in
## the per-step cooldown ([param cooldown_remaining] <= 0) and under the
## [param max_steps] cap. Kept pure so the gating is unit-testable without a live rig.
static func can_step(balance_ratio: float, step_threshold: float, ragdoll_threshold: float,
		cooldown_remaining: float, step_count: int, max_steps: int) -> bool:
	if cooldown_remaining > 0.0:
		return false
	if step_count >= max_steps:
		return false
	if balance_ratio < step_threshold or balance_ratio > ragdoll_threshold:
		return false
	return true
