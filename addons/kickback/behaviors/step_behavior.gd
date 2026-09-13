## Stepping, driven by balance (docs/PLAN.md 0.6.0). Replaces the 0.4.0 directed stumble,
## which teleported the character root along the hit direction and paced steps by the
## distance travelled. Two reasons to step, both read from [BalanceState]:
##
## 1. **Balance step** — the extrapolated CoM is at or past the edge of the feet
##    ([member RagdollTuning.step_trigger_ratio]): the foot on the fall side swings to the
##    capture point (XCoM plus a small margin), where planting it stops the fall. The
##    body moves because the loaded leg pushes and the swing foot lands under the CoM;
##    nothing is teleported.
## 2. **Re-plant** — the character is calm ([member RagdollTuning.step_calm_ratio]) but a
##    loaded foot stands far from where the animation wants it (a foot friction planted
##    during a violent clip, or after a get-up): the less loaded foot is lifted and swung
##    to its animation spot. A load-bearing foot cannot be dragged into place by the
##    animation; it has to be unloaded and stepped.
##
## Foot LOCKS make both possible: a foot in contact whose animation spot has drifted is
## locked to the ground where it stands (its IK target = its own position) so the leg
## does not fight friction, and released when the animation spot comes back to it or
## the foot leaves the ground. The swing itself is a lifted arc the foot IK solver
## animates as the foot's target ([method FootIKSolver.begin_step]); the joint motors
## execute it. Stiffness: the leg chains are asked to full base strength while a foot
## is in flight (a stagger's 10 % floor cannot step).
@icon("res://addons/kickback/icons/active_ragdoll_controller.svg")
class_name StepBehavior
extends KickbackBehavior

## Seconds between two steps.
const STEP_COOLDOWN := 0.1
## The balance ratio must stay at or past the trigger for this many consecutive ticks
## before a balance step fires: a shove the root anchor arrests within a few ticks
## (muscle_root_hold = 1) spikes the XCoM for 2–3 ticks and would otherwise fire a
## phantom step the body never follows.
const STEP_TRIGGER_TICKS := 4
## The balance step lands this far (m) beyond the capture point, in the fall direction.
const STEP_MARGIN := 0.05
## A locked foot within this (m) of its animation spot is released; a contacting foot
## further than this from its animation spot is locked where it stands. (A physical foot
## settles 2–4 cm from its spot on friction alone; locking it there is the point.)
const LOCK_RELEASE := 0.05

## Diagnostics: the last step's foot, target and the total count since reset.
var last_step_foot: String = ""
var last_step_target: Vector3 = Vector3.ZERO
var steps_taken: int = 0
## Why the last step happened: "balance" or "replant".
var last_step_reason: String = ""

var _cooldown: float = 0.0
var _trigger_ticks: int = 0


func tick(ctx: BehaviorContext, balance: BalanceState, delta: float) -> Dictionary:
	var ik := ctx.foot_ik
	if not enabled or ik == null or not ik.is_initialized() or not ctx.tuning.steps_enabled:
		return {}
	# The legacy velocity-overwrite resolver drags feet with unbounded force and never
	# needs a step or a lock; locks would only degrade its tracking.
	if not ctx.spring.is_motor_mode():
		return {}
	var feet := ctx.profile.get_foot_rigs()
	if feet.size() != 2:
		return {}
	if ik.is_stepping():
		_cooldown = STEP_COOLDOWN
		return _leg_stiffness(ctx)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not balance.has_support:
		return {}
	_maintain_locks(ctx, balance, feet)
	if _cooldown > 0.0:
		return {}
	var t := ctx.tuning

	# 1. Balance step: the capture point has reached the edge of the feet and stays there.
	if balance.ratio >= t.step_trigger_ratio and balance.imbalance_dir.length_squared() > 0.0:
		_trigger_ticks += 1
	else:
		_trigger_ticks = 0
	if _trigger_ticks >= STEP_TRIGGER_TICKS:
		_trigger_ticks = 0
		var swing := _fall_side_foot(ctx, balance, feet)
		var stance: String = feet[0] if swing == feet[1] else feet[1]
		var dest := Vector2(balance.xcom.x, balance.xcom.z) + balance.imbalance_dir * STEP_MARGIN
		dest = _keep_stance(dest, ctx.body(stance), balance.imbalance_dir, t.step_min_stance)
		if _step(ctx, swing, stance, dest, "balance"):
			return _leg_stiffness(ctx)
		return {}

	# 2. Re-plant: calm, but a loaded foot stands far from its animation spot.
	if balance.ratio <= t.step_calm_ratio:
		var best := ""
		var best_load := INF
		for foot: String in feet:
			if balance.contacts.get(foot, 0) <= 0:
				continue
			var mismatch := _mismatch(ctx, foot)
			var load: float = balance.foot_load.get(foot, 1.0)
			if mismatch > t.step_replant_distance and load < best_load:
				best = foot
				best_load = load
		if best != "":
			var stance: String = feet[0] if best == feet[1] else feet[1]
			var a := ctx.animation_global(best).origin
			if _step(ctx, best, stance, Vector2(a.x, a.z), "replant"):
				return _leg_stiffness(ctx)
	return {}


func reset(ctx: BehaviorContext) -> void:
	_cooldown = 0.0
	_trigger_ticks = 0
	if ctx.foot_ik:
		for foot: String in ctx.profile.get_foot_rigs():
			ctx.foot_ik.clear_foot_lock(foot)


## Horizontal distance (m) between a foot body and its animation spot.
func _mismatch(ctx: BehaviorContext, foot: String) -> float:
	var b := ctx.body(foot)
	if not b:
		return 0.0
	var a := ctx.animation_global(foot).origin
	return Vector2(a.x - b.global_position.x, a.z - b.global_position.z).length()


## Foot locks: a contacting foot far from its animation spot is locked where it stands;
## a lock is released when the spot comes back to it or the foot leaves the ground.
## In STAGGER the solver has locked both feet already (anti-slide); this keeps that.
func _maintain_locks(ctx: BehaviorContext, balance: BalanceState, feet: PackedStringArray) -> void:
	var ik := ctx.foot_ik
	for foot: String in feet:
		var b := ctx.body(foot)
		if not b:
			continue
		var in_contact: bool = balance.contacts.get(foot, 0) > 0
		var mismatch := _mismatch(ctx, foot)
		if ik.is_foot_locked(foot):
			if not in_contact and not ik.is_foot_stepping(foot):
				ik.clear_foot_lock(foot)  # the animation lifted it: let it swing
			elif mismatch < LOCK_RELEASE and ctx.state == ActiveRagdollController.State.NORMAL:
				ik.clear_foot_lock(foot)  # back where the animation wants it
		elif in_contact and mismatch > LOCK_RELEASE:
			ik.set_foot_lock(foot, b.global_position)


## The foot on the fall side: largest offset from the support centre along the
## imbalance direction.
func _fall_side_foot(ctx: BehaviorContext, balance: BalanceState, feet: PackedStringArray) -> String:
	var best := feet[0]
	var best_dot := -INF
	var c := Vector2(balance.support_center.x, balance.support_center.z)
	for foot: String in feet:
		var b := ctx.body(foot)
		if not b:
			continue
		var d := (Vector2(b.global_position.x, b.global_position.z) - c).dot(balance.imbalance_dir)
		if d > best_dot:
			best_dot = d
			best = foot
	return best


## Keeps the landing spot at least [param min_stance] from the stance foot so the legs
## do not cross: pushes it out along the direction from the stance foot (or sideways to
## the fall when the two coincide).
static func _keep_stance(dest: Vector2, stance_body: RigidBody3D, fall_dir: Vector2, min_stance: float) -> Vector2:
	if not stance_body:
		return dest
	var s := Vector2(stance_body.global_position.x, stance_body.global_position.z)
	var off := dest - s
	if off.length() >= min_stance:
		return dest
	var away := off.normalized() if off.length_squared() > 1e-8 else Vector2(-fall_dir.y, fall_dir.x)
	return s + away * min_stance


## Starts the step: locks the stance foot where it is, swings [param swing] to
## [param dest] (ground plane; the solver ground-snaps and lifts), clamped to
## step_max_length from where the foot stands.
func _step(ctx: BehaviorContext, swing: String, stance: String, dest: Vector2, reason: String) -> bool:
	var ik := ctx.foot_ik
	var t := ctx.tuning
	var sb := ctx.body(swing)
	var stb := ctx.body(stance)
	if not sb or not stb:
		return false
	var from := Vector2(sb.global_position.x, sb.global_position.z)
	var step := dest - from
	if step.length() > t.step_max_length:
		step = step.normalized() * t.step_max_length
	dest = from + step
	if not ik.is_foot_locked(stance):
		ik.set_foot_lock(stance, stb.global_position)
	var target := Vector3(dest.x, sb.global_position.y, dest.y)
	if not ik.begin_step(swing, target, t.step_duration, t.step_lift):
		return false
	_cooldown = STEP_COOLDOWN
	steps_taken += 1
	last_step_foot = swing
	last_step_target = target
	last_step_reason = reason
	if ctx.on_step_started.is_valid():
		ctx.on_step_started.call(swing, target)
	return true


## Both leg chains and the pelvis at full base strength — a step needs muscles.
func _leg_stiffness(ctx: BehaviorContext) -> Dictionary:
	var stiff: Dictionary = {}
	for rig: String in ctx.profile.get_all_leg_rigs():
		stiff[rig] = 1.0
	stiff[ctx.profile.get_root_rig()] = 1.0
	return {"stiffness": stiff}
