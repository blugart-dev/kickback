extends GutTest

# ── BalanceState (0.6.0) ─────────────────────────────────────────────────────
# CoM, XCoM, the support polygon from foot contact, the margin and the ratio.
# Pure geometry first, then the live harness rig.

const RigHarness := preload("res://test/helpers/rig_harness.gd")

var SQUARE := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])


func _tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.muscle_mode = RagdollTuning.MuscleMode.JOINT_MOTOR
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


# ── Geometry ────────────────────────────────────────────────────────────────

func test_convex_hull_drops_interior_and_duplicate_points():
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2), Vector2(1, 1), Vector2(2, 0), Vector2(0.5, 0.5)])
	var hull := BalanceState.convex_hull(pts)
	assert_eq(hull.size(), 4, "square hull has 4 vertices (%s)" % str(hull))
	# Counter-clockwise: positive signed area.
	var area := 0.0
	for i in hull.size():
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		area += a.x * b.y - b.x * a.y
	assert_gt(area, 0.0, "hull is counter-clockwise")


func test_signed_margin_is_distance_to_the_nearest_edge():
	assert_almost_eq(BalanceState.signed_margin(SQUARE, Vector2.ZERO), 1.0, 1e-6, "centre of a 2x2 square is 1 m inside")
	assert_almost_eq(BalanceState.signed_margin(SQUARE, Vector2(0.7, 0.0)), 0.3, 1e-6, "0.3 m from the right edge")
	assert_almost_eq(BalanceState.signed_margin(SQUARE, Vector2(1.5, 0.0)), -0.5, 1e-6, "0.5 m outside is negative")
	assert_almost_eq(BalanceState.signed_margin(SQUARE, Vector2(2.0, 2.0)), -sqrt(2.0), 1e-6, "outside past a corner: distance to the corner")


func test_edge_distance_along_a_direction():
	assert_almost_eq(BalanceState.edge_distance_along(SQUARE, Vector2.ZERO, Vector2.RIGHT), 1.0, 1e-6)
	assert_almost_eq(BalanceState.edge_distance_along(SQUARE, Vector2.ZERO, Vector2(1, 1).normalized()), sqrt(2.0), 1e-6, "toward a corner")
	assert_almost_eq(BalanceState.edge_distance_along(SQUARE, Vector2(0.5, 0.0), Vector2.RIGHT), 0.5, 1e-6, "from an off-centre origin")


func test_xcom_extrapolates_the_com_by_its_velocity_over_omega0():
	# Two static "feet" and a "torso" moving at 1 m/s: one update with no velocity, one
	# with; XCoM must move by v / sqrt(g / h).
	var world := Node3D.new()
	add_child_autoqfree(world)
	var bodies: Dictionary = {}
	for spec in [["Foot_L", Vector3(0.1, 0.0325, 0.0), 2.0], ["Foot_R", Vector3(-0.1, 0.0325, 0.0), 2.0], ["Hips", Vector3(0.0, 1.0, 0.0), 60.0]]:
		var b := RigidBody3D.new()
		b.name = spec[0]
		b.mass = spec[2]
		b.freeze = true
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.12, 0.065, 0.325) if spec[0] != "Hips" else Vector3(0.3, 0.2, 0.2)
		cs.shape = box
		b.add_child(cs)
		world.add_child(b)
		b.global_position = spec[1]
		bodies[spec[0]] = b
	var bs := BalanceState.new()
	var feet := PackedStringArray(["Foot_L", "Foot_R"])
	bs.update(bodies, feet, 1.0 / 60.0, 9.8)
	assert_true(bs.has_support, "two foot boxes on the ground give a support polygon (contact_monitor off → assumed in contact)")
	assert_almost_eq(bs.xcom, Vector3(bs.com.x, bs.support_y, bs.com.z), Vector3.ONE * 1e-5, "at rest the XCoM is the CoM projection")
	assert_gt(bs.margin, 0.03, "standing CoM is inside the feet by a few cm (margin %.3f)" % bs.margin)
	# Move the torso 1/60 m in +X per tick for 12 ticks: CoM velocity ≈ 1 m/s × (60 / 64)
	# mass share, converged through the exponential smoothing (3-tick constant).
	var com_before := bs.com
	for i in 12:
		(bodies["Hips"] as RigidBody3D).global_position += Vector3(1.0 / 60.0, 0.0, 0.0)
		com_before = bs.com
		bs.update(bodies, feet, 1.0 / 60.0, 9.8)
	var v := bs.com_velocity.x
	assert_almost_eq(v, (bs.com.x - com_before.x) * 60.0, 0.03, "CoM velocity from the CoM step (smoothed, converged)")
	var expected_x := bs.com.x + v / sqrt(9.8 / bs.height)
	assert_almost_eq(bs.xcom.x, expected_x, 1e-5, "XCoM = CoM + v / omega0")
	assert_gt(bs.ratio, 1.0, "a 1 m/s CoM velocity puts the XCoM outside a 0.3 m stance (ratio %.2f)" % bs.ratio)
	assert_lt(bs.margin, 0.0, "…and the margin goes negative")
	assert_eq(bs.imbalance_dir.x, 1.0, "imbalance points +X")
	assert_eq(bs.loaded_foot, "Foot_L", "the foot on the +X side carries the load")


# ── Live rig ────────────────────────────────────────────────────────────────

func test_standing_rig_is_balanced_inside_its_feet():
	var h = await _spawn(_tuning())
	await wait_physics_frames(60)
	var bs: BalanceState = h.controller.get_balance()
	assert_true(bs.has_support, "both feet in contact → support polygon")
	assert_gte(bs.support.size(), 4, "hull of two sole footprints has at least 4 vertices (%d)" % bs.support.size())
	assert_eq(bs.contacts.get("Foot_L", 0) > 0 and bs.contacts.get("Foot_R", 0) > 0, true, "both feet report contact")
	assert_gt(bs.margin, 0.02, "standing XCoM is inside the polygon by more than 2 cm (margin %.3f m)" % bs.margin)
	# The synthetic rig's CoM sits over its ankles, i.e. over the heels of the sole boxes
	# (a real idle stands mid-foot: 0.42 on the ybot), so ~0.5 here.
	assert_lt(bs.ratio, 0.7, "standing ratio below the 0.8 stagger threshold (%.2f)" % bs.ratio)
	assert_almost_eq(bs.foot_load.get("Foot_L", 0.0) + bs.foot_load.get("Foot_R", 0.0), 1.0, 1e-6, "load shares sum to 1")
	var d: Dictionary = h.controller.get_balance_state()
	assert_true(d.has("support_polygon") and d.has("xcom") and d.has("margin"), "dictionary API carries the new fields")
	assert_almost_eq(float(d.balance_ratio), bs.ratio, 1e-6)


func test_airborne_rig_has_no_support():
	var t := _tuning()
	t.muscle_root_support = 1.0
	var h = await _spawn(t)
	# Lift the character (skeleton + bodies, NOT the harness node, which also owns the
	# ground) 0.5 m: the feet leave the ground and the anchor holds it there.
	h.skeleton.position.y += 0.5
	for body: RigidBody3D in h.rig_builder.get_bodies().values():
		body.global_position += Vector3(0.0, 0.5, 0.0)
	await wait_physics_frames(10)
	var bs: BalanceState = h.controller.get_balance()
	assert_false(bs.has_support, "no foot in contact → no support polygon")
	assert_eq(bs.loaded_foot, "", "no loaded foot without support")


func test_a_shove_moves_the_xcom_outside_the_polygon():
	var t := _tuning()
	t.muscle_root_hold = 0.0  # let the body actually move
	var h = await _spawn(t)
	await wait_physics_frames(60)
	for body: RigidBody3D in h.rig_builder.get_bodies().values():
		body.linear_velocity += Vector3(1.5, 0.0, 0.0)
	await wait_physics_frames(4)  # the smoothed CoM velocity needs a few ticks to register
	var bs: BalanceState = h.controller.get_balance()
	assert_gt(bs.ratio, 1.0, "1.5 m/s sideways puts the XCoM outside the stance (ratio %.2f, margin %.3f)" % [bs.ratio, bs.margin])
	assert_gt(bs.imbalance_dir.x, 0.9, "imbalance points along the shove")
