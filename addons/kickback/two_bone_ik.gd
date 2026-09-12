## Shared two-bone IK math, used by both [FootIKSolver] (leg: hip→knee→foot) and
## [ArmIKSolver] (arm: shoulder→elbow→hand). Pure, stateless static functions —
## no scene, no spring, no per-instance state.
##
## Solves the chain as a CORRECTION OF the animation pose: the mid-joint position
## and the two segment directions come from the law of cosines, but each segment's
## ORIENTATION is expressed as a SWING of that segment's animation basis onto its
## new direction. This is convention-agnostic — when the IK direction equals the
## animation direction (no adjustment needed) the swing is identity and the target
## equals the animation pose, so there is no spurious rotation error for the spring
## to chase. (Building bases from scratch with an assumed local-axis convention
## produced ~130° steady orientation errors against Mixamo bones → idle leg buzz;
## see the foot-IK orientation fix.)
class_name TwoBoneIK
extends RefCounted

## Sine of the hint angle below which the animation mid-joint is too close to the
## chain line to define a bend plane on its own (≈ 5.7°). Below it the plane blends
## from the hint toward [code]fallback_axis[/code], reaching pure fallback at 0°, so
## a near-straight idle knee cannot flip its plane between frames (the raw cross
## product of two nearly parallel unit vectors is tiny AND noisy; normalising it
## first, as the old test did, amplified that noise into a full 180° flip).
const COLINEAR_HINT_SIN: float = 0.1

## Margins keeping the chain strictly inside its reach band so the law of cosines
## never has to produce an exactly straight or exactly folded joint.
const REACH_MARGIN: float = 0.01


## Solves a two-bone chain anchored at [param root_pos] reaching toward
## [param target]. The target is first clamped onto the chain's reachable band —
## no further than full extension, no closer than full fold — and the chain is ALWAYS
## solved: an out-of-reach target yields a fully extended chain pointing at it, a
## too-close target a maximally folded one. (Returning nothing for such targets made
## callers write no override, so the limb snapped back to the animation pose — a
## visible pop on every windmill cycle and on an over-stretched pinned foot.)
##
## Returns an empty dictionary only for degenerate input (a zero-length segment, a
## non-finite position, or a target whose direction from the root cannot be
## determined), else
## [code]{"upper": Transform3D, "lower": Transform3D, "knee": Vector3, "end": Vector3}[/code]:
## [code]upper[/code]/[code]lower[/code] are the world-space segment transforms
## (swung animation basis at the solved positions); [code]knee[/code] is the solved
## mid-joint position; [code]end[/code] is the effective end-effector position — the
## clamped target, which callers must use in place of [param target] when placing
## the foot/hand so it stays attached to the lower segment. The caller owns the
## end-effector (foot/hand) transform — it sits at [code]end[/code] with a
## caller-chosen orientation (e.g. slope-corrected for a planted foot,
## animation-preserving for a reaching hand).
##
## [param upper_len]/[param lower_len] are the two segment lengths.
## [param root_pos] is the chain anchor (hip/shoulder), already including any shift.
## [param target] is the end-effector goal in world space.
## [param knee_hint] is the animation mid-joint position (same shift as root_pos);
## it defines which way the joint bends.
## [param upper_anim]/[param lower_anim]/[param end_anim] are the world-space
## animation globals of the two segments and the end bone; their bases are swung for
## the output and their origins give the animation segment directions.
## [param fallback_axis] is the direction the mid-joint bends toward when
## [param target] and [param knee_hint] are (nearly) colinear — see
## [constant COLINEAR_HINT_SIN].
static func solve(upper_len: float, lower_len: float, root_pos: Vector3,
		target: Vector3, knee_hint: Vector3, upper_anim: Transform3D,
		lower_anim: Transform3D, end_anim: Transform3D,
		fallback_axis: Vector3) -> Dictionary:
	if not (is_finite(upper_len) and is_finite(lower_len)
			and root_pos.is_finite() and target.is_finite() and knee_hint.is_finite()):
		return {}
	var mx := upper_len + lower_len - REACH_MARGIN
	var mn := absf(upper_len - lower_len) + REACH_MARGIN
	if upper_len <= 0.0 or lower_len <= 0.0 or mx <= mn:
		return {}

	# Chain direction. A target sitting on the root has no direction of its own, so
	# take the animation chain's (end_anim - root) and, failing that, the fallback.
	var cv := target - root_pos
	var cl := cv.length()
	var cd := cv / cl if cl > 0.0001 else Vector3.ZERO
	if cd == Vector3.ZERO:
		cd = (end_anim.origin - upper_anim.origin).normalized()
	if cd.length_squared() < 0.5:
		cd = fallback_axis.normalized()
	if cd.length_squared() < 0.5:
		return {}

	# Clamp the target onto the reachable band along the chain direction.
	cl = clampf(cl, mn, mx)
	var end := root_pos + cd * cl

	# Law of cosines: angle at the root between the chain line and the upper segment.
	var ch := (upper_len * upper_len + cl * cl - lower_len * lower_len) / (2.0 * upper_len * cl)
	ch = clampf(ch, -1.0, 1.0)
	var ho := acos(ch)

	# Bend plane from the animation mid-joint direction (keeps the joint bending the
	# way the animation already does), blended toward the fallback axis as the hint
	# approaches the chain line. The RAW cross product's length is sin(hint angle);
	# it is tested BEFORE normalising so a near-straight hint is recognised as such.
	var side := _bend_plane_normal(cd, knee_hint - root_pos, fallback_axis)
	var bd := side.cross(cd).normalized()

	# Upper/lower segment directions and the mid-joint between them.
	var ud := (cd * cos(ho) + bd * sin(ho)).normalized()
	var kp := root_pos + ud * upper_len
	var ld := (end - kp).normalized()

	# Orientation as a swing of each animation basis onto its new bone direction.
	var anim_upper_dir := (lower_anim.origin - upper_anim.origin).normalized()
	var anim_lower_dir := (end_anim.origin - lower_anim.origin).normalized()
	var ux := Transform3D(Basis(swing(anim_upper_dir, ud)) * upper_anim.basis, root_pos)
	var lx := Transform3D(Basis(swing(anim_lower_dir, ld)) * lower_anim.basis, kp)

	return {"upper": ux, "lower": lx, "knee": kp, "end": end}


## Unit normal of the bend plane for chain direction [param cd] (unit) and the
## root→hint vector [param hint_vec]. Pure hint above [constant COLINEAR_HINT_SIN],
## pure fallback at 0°, a continuous blend between — so the plane cannot flip from
## one frame to the next as an idle joint wobbles about straight. The fallback normal
## itself is guarded: an axis parallel to the chain degrades to world RIGHT, then UP.
static func _bend_plane_normal(cd: Vector3, hint_vec: Vector3, fallback_axis: Vector3) -> Vector3:
	var side_fb := cd.cross(fallback_axis)
	if side_fb.length_squared() < 0.000001:
		side_fb = cd.cross(Vector3.RIGHT)
	if side_fb.length_squared() < 0.000001:
		side_fb = cd.cross(Vector3.UP)
	side_fb = side_fb.normalized()

	var hint_len := hint_vec.length()
	if hint_len < 0.0001:
		return side_fb
	var side_hint := cd.cross(hint_vec / hint_len)  # |side_hint| == sin(hint angle)
	var hint_sin := side_hint.length()
	if hint_sin >= COLINEAR_HINT_SIN:
		return side_hint / hint_sin
	if hint_sin < 0.000001:
		return side_fb
	var t := hint_sin / COLINEAR_HINT_SIN
	var side := side_fb * (1.0 - t) + (side_hint / hint_sin) * t
	# Hint and fallback exactly opposed at the blend midpoint cancel out; the
	# fallback owns that single point rather than a NaN plane.
	if side.length_squared() < 0.000001:
		return side_fb
	return side.normalized()


## Shortest-arc rotation from [param from] to [param to], hardened against the zero
## and antiparallel degeneracies that the bare [code]Quaternion(from, to)[/code]
## constructor asserts on.
static func swing(from: Vector3, to: Vector3) -> Quaternion:
	if from.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return Quaternion.IDENTITY
	var f := from.normalized()
	var t := to.normalized()
	var d := f.dot(t)
	if d > 0.9999:
		return Quaternion.IDENTITY
	if d < -0.9999:
		var axis := f.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = f.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(f, t)
