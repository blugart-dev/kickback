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


## Solves a two-bone chain anchored at [param root_pos] reaching toward
## [param target]. Returns an empty dictionary if the target is unreachable
## (degenerate length), else
## [code]{"upper": Transform3D, "lower": Transform3D, "knee": Vector3}[/code]:
## [code]upper[/code]/[code]lower[/code] are the world-space segment transforms
## (swung animation basis at the solved positions); [code]knee[/code] is the solved
## mid-joint position. The caller owns the end-effector (foot/hand) transform — it
## sits at [param target] with a caller-chosen orientation (e.g. slope-corrected
## for a planted foot, animation-preserving for a reaching hand).
##
## [param upper_len]/[param lower_len] are the two segment lengths.
## [param root_pos] is the chain anchor (hip/shoulder), already including any shift.
## [param target] is the end-effector goal in world space.
## [param knee_hint] is the animation mid-joint position (same shift as root_pos);
## it defines which way the joint bends.
## [param upper_anim]/[param lower_anim]/[param end_anim] are the world-space
## animation globals of the two segments and the end bone; their bases are swung for
## the output and their origins give the animation segment directions.
## [param fallback_axis] seeds the bend plane when [param target] and
## [param knee_hint] are colinear (the cross product degenerates).
static func solve(upper_len: float, lower_len: float, root_pos: Vector3,
		target: Vector3, knee_hint: Vector3, upper_anim: Transform3D,
		lower_anim: Transform3D, end_anim: Transform3D,
		fallback_axis: Vector3) -> Dictionary:
	var cv := target - root_pos
	var cl := cv.length()
	var mx := upper_len + lower_len - 0.01
	var mn := absf(upper_len - lower_len) + 0.01
	if cl < mn or cl > mx + 0.1:
		return {}
	cl = clampf(cl, mn, mx)

	# Law of cosines: angle at the root between the chain line and the upper segment.
	var ch := (upper_len * upper_len + cl * cl - lower_len * lower_len) / (2.0 * upper_len * cl)
	ch = clampf(ch, -1.0, 1.0)
	var ho := acos(ch)

	# Bend plane from the animation mid-joint direction (keeps the joint bending the
	# way the animation already does).
	var cd := cv.normalized()
	var kf := (knee_hint - root_pos).normalized()
	var side := cd.cross(kf).normalized()
	if side.length_squared() < 0.001:
		side = cd.cross(fallback_axis).normalized()
	if side.length_squared() < 0.001:
		side = cd.cross(Vector3.RIGHT).normalized()
	var bd := side.cross(cd).normalized()

	# Upper/lower segment directions and the mid-joint between them.
	var ud := (cd * cos(ho) + bd * sin(ho)).normalized()
	var kp := root_pos + ud * upper_len
	var ld := (target - kp).normalized()

	# Orientation as a swing of each animation basis onto its new bone direction.
	var anim_upper_dir := (lower_anim.origin - upper_anim.origin).normalized()
	var anim_lower_dir := (end_anim.origin - lower_anim.origin).normalized()
	var ux := Transform3D(Basis(swing(anim_upper_dir, ud)) * upper_anim.basis, root_pos)
	var lx := Transform3D(Basis(swing(anim_lower_dir, ld)) * lower_anim.basis, kp)

	return {"upper": ux, "lower": lx, "knee": kp}


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
