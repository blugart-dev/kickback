## One balance measurement per physics tick (docs/PLAN.md 0.6.0): centre of mass, its
## velocity, the extrapolated centre of mass (XCoM = CoM + v / ω₀, ω₀ = √(g / h), the
## capture-point estimate of where the body is heading), the support polygon from the
## feet that are actually in contact with the ground (the convex hull of their sole
## footprints), which foot carries the load, and how far the XCoM is from the edge of
## that polygon. Every balance decision (stagger, step, fall) reads this one struct;
## nothing else measures balance.
##
## Replaces the 0.4.x static ratio (CoM offset from the ankle midpoint over half the
## stance width), which read 0.5–0.6 for a perfectly standing character on load-bearing
## feet: a standing CoM sits ahead of the ankles, inside the feet.
@icon("res://addons/kickback/icons/physics_rig_builder.svg")
class_name BalanceState
extends RefCounted

## Mass-weighted centre of mass of the rig (world).
var com: Vector3 = Vector3.ZERO
## CoM velocity (world, m/s) from the previous tick's CoM.
var com_velocity: Vector3 = Vector3.ZERO
## Extrapolated CoM on the support plane (world; y = [member support_y]).
var xcom: Vector3 = Vector3.ZERO
## CoM height above the support plane (m) and the inverted-pendulum frequency √(g / h).
var height: float = 1.0
var omega0: float = 3.1
## Convex hull (XZ, counter-clockwise) of the sole footprints of the feet in contact.
var support: PackedVector2Array = PackedVector2Array()
## Height of the support plane (mean of the contacting soles' bottoms).
var support_y: float = 0.0
## Centroid of the support polygon (world, on the support plane).
var support_center: Vector3 = Vector3.ZERO
## False when no foot touches the ground (airborne, lying) — the polygon is empty.
var has_support: bool = false
## Signed distance (m) from the XCoM to the polygon edge: positive inside, negative
## outside. The balance margin.
var margin: float = 0.0
## XCoM offset from the support centre over the polygon's radius in that direction:
## 0 = centred, 1 = at the edge, > 1 = outside (clamped to the tuning's max). The
## 0.4.x `balance_ratio`, now on the real polygon.
var ratio: float = 0.0
## Unit XZ direction from the support centre toward the XCoM (zero when centred).
var imbalance_dir: Vector2 = Vector2.ZERO
## Per foot rig: contact count this tick, and the estimated share of the load (0..1, sums
## to 1 over the feet in contact; the foot nearest the XCoM carries most of it).
var contacts: Dictionary = {}
var foot_load: Dictionary = {}
## The foot with the largest load share ("" without support).
var loaded_foot: String = ""

var _prev_com: Vector3 = Vector3.ZERO
var _has_prev: bool = false

## Footprint half-size (m) used for a foot body whose shape is not a box.
const FALLBACK_FOOT_HALF := 0.05
## Minimum CoM height (m) for the pendulum frequency (a body lying on the floor).
const MIN_HEIGHT := 0.1


## Recomputes everything from the rig's bodies. [param bodies] is rig name → RigidBody3D,
## [param foot_rigs] the profile's foot rig names, [param radius_min] the smallest
## polygon radius the ratio divides by, [param max_ratio] its clamp.
func update(bodies: Dictionary, foot_rigs: PackedStringArray, delta: float, gravity: float,
		radius_min: float = 0.1, max_ratio: float = 1.5) -> void:
	# Centre of mass and its velocity.
	var sum := Vector3.ZERO
	var total_mass := 0.0
	for body: RigidBody3D in bodies.values():
		sum += body.global_position * body.mass
		total_mass += body.mass
	if total_mass <= 0.001:
		has_support = false
		return
	com = sum / total_mass
	if _has_prev and delta > 0.0:
		com_velocity = (com - _prev_com) / delta
	else:
		com_velocity = Vector3.ZERO
	_prev_com = com
	_has_prev = true

	# Support polygon from the feet in contact.
	var points := PackedVector2Array()
	var y_sum := 0.0
	var y_n := 0
	var centers: Dictionary = {}
	contacts.clear()
	for foot_rig: String in foot_rigs:
		var foot: RigidBody3D = bodies.get(foot_rig)
		if not foot:
			continue
		var n := foot.get_contact_count() if foot.contact_monitor else 1
		contacts[foot_rig] = n
		if n <= 0:
			continue
		var fp := footprint(foot)
		var c := Vector2.ZERO
		for p: Vector3 in fp:
			points.append(Vector2(p.x, p.z))
			c += Vector2(p.x, p.z)
			y_sum += p.y
			y_n += 1
		centers[foot_rig] = c / maxf(fp.size(), 1)
	support = convex_hull(points)
	has_support = support.size() >= 3
	foot_load.clear()
	loaded_foot = ""
	if not has_support:
		xcom = com
		margin = 0.0
		ratio = 0.0
		imbalance_dir = Vector2.ZERO
		support_center = com
		return
	support_y = y_sum / maxf(y_n, 1)
	var c2 := Vector2.ZERO
	for p: Vector2 in support:
		c2 += p
	c2 /= support.size()
	support_center = Vector3(c2.x, support_y, c2.y)

	# Extrapolated CoM (capture point of the linear inverted pendulum).
	height = maxf(com.y - support_y, MIN_HEIGHT)
	omega0 = sqrt(maxf(gravity, 0.01) / height)
	var x2 := Vector2(com.x, com.z) + Vector2(com_velocity.x, com_velocity.z) / omega0
	xcom = Vector3(x2.x, support_y, x2.y)

	# Margin, direction, ratio.
	margin = signed_margin(support, x2)
	var d := x2 - c2
	if d.length_squared() > 1e-8:
		imbalance_dir = d.normalized()
		var edge := edge_distance_along(support, c2, imbalance_dir)
		ratio = clampf(d.length() / maxf(edge, radius_min), 0.0, max_ratio)
	else:
		imbalance_dir = Vector2.ZERO
		ratio = 0.0

	# Load share: the foot nearest the XCoM carries most of it.
	var w_sum := 0.0
	for foot_rig: String in centers:
		var w := 1.0 / maxf((centers[foot_rig] as Vector2).distance_to(x2), 0.02)
		foot_load[foot_rig] = w
		w_sum += w
	var best := -1.0
	for foot_rig: String in foot_load:
		foot_load[foot_rig] = foot_load[foot_rig] / w_sum
		if foot_load[foot_rig] > best:
			best = foot_load[foot_rig]
			loaded_foot = foot_rig


## Forgets the previous CoM (the next update reports zero velocity) — call after a
## teleport such as the recovery re-base, so the jump is not read as a velocity.
func reset_velocity() -> void:
	_has_prev = false
	com_velocity = Vector3.ZERO


## The four bottom corners (world) of a foot's collision box — its sole footprint — or a
## small square around the body origin for a non-box shape.
static func footprint(foot: RigidBody3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var shape := foot.get_child(0) as CollisionShape3D if foot.get_child_count() > 0 else null
	if shape and shape.shape is BoxShape3D:
		var half: Vector3 = (shape.shape as BoxShape3D).size * 0.5
		var xf := shape.global_transform
		# The bottom face is the one facing down in world space.
		var down_local: Vector3 = xf.basis.inverse() * Vector3.DOWN
		var axis := 0
		var best := -1.0
		for k in 3:
			if absf(down_local[k]) > best:
				best = absf(down_local[k])
				axis = k
		var sign := 1.0 if down_local[axis] > 0.0 else -1.0
		var a := (axis + 1) % 3
		var b := (axis + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var c := Vector3.ZERO
				c[axis] = sign * half[axis]
				c[a] = sa * half[a]
				c[b] = sb * half[b]
				out.append(xf * c)
		return out
	var o := foot.global_position
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(o + Vector3(sx * FALLBACK_FOOT_HALF, 0.0, sz * FALLBACK_FOOT_HALF))
	return out


## Convex hull of 2D points (Andrew's monotone chain), counter-clockwise, no duplicate
## end point. Fewer than 3 distinct points yield what was given.
static func convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for p: Vector2 in points:
		pts.append(p)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x if not is_equal_approx(a.x, b.x) else a.y < b.y)
	# Drop duplicates.
	var uniq: Array[Vector2] = []
	for p: Vector2 in pts:
		if uniq.is_empty() or not uniq[-1].is_equal_approx(p):
			uniq.append(p)
	if uniq.size() < 3:
		return PackedVector2Array(uniq)
	var lower: Array[Vector2] = []
	for p: Vector2 in uniq:
		while lower.size() >= 2 and _cross(lower[-2], lower[-1], p) <= 0.0:
			lower.pop_back()
		lower.append(p)
	var upper: Array[Vector2] = []
	for i in range(uniq.size() - 1, -1, -1):
		var p: Vector2 = uniq[i]
		while upper.size() >= 2 and _cross(upper[-2], upper[-1], p) <= 0.0:
			upper.pop_back()
		upper.append(p)
	lower.pop_back()
	upper.pop_back()
	return PackedVector2Array(lower + upper)


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


## Signed distance from [param p] to the edge of the convex polygon (CCW): positive
## inside, negative outside, 0 on the edge. Zero for a degenerate polygon.
static func signed_margin(poly: PackedVector2Array, p: Vector2) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var inside := true
	var min_edge := INF
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		if _cross(a, b, p) < 0.0:
			inside = false
		min_edge = minf(min_edge, _segment_distance(a, b, p))
	return min_edge if inside else -min_edge


static func _segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-12:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## Distance from [param origin] (inside the CCW polygon) to its edge along the unit
## direction [param dir]; INF when the ray never leaves (degenerate input).
static func edge_distance_along(poly: PackedVector2Array, origin: Vector2, dir: Vector2) -> float:
	var n := poly.size()
	var best := INF
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var e := b - a
		var denom := dir.x * e.y - dir.y * e.x
		if absf(denom) < 1e-9:
			continue
		var ao := a - origin
		var t := (ao.x * e.y - ao.y * e.x) / denom      # along the ray
		var u := (ao.x * dir.y - ao.y * dir.x) / denom  # along the edge
		if t >= 0.0 and u >= -1e-6 and u <= 1.0 + 1e-6:
			best = minf(best, t)
	return best


## The 0.4.x dictionary shape every consumer reads (controller, HUD, trace recorder,
## demos), extended with the new fields.
func to_dictionary() -> Dictionary:
	return {
		"com": com,
		"com_velocity": com_velocity,
		"xcom": xcom,
		"support_center": support_center,
		"support_polygon": support,
		"support_y": support_y,
		"balance_ratio": ratio,
		"margin": margin,
		"imbalance_dir": imbalance_dir,
		"has_support": has_support,
		"loaded_foot": loaded_foot,
		"foot_load": foot_load,
		"contacts": contacts,
	}
