extends GutTest

# ── Rig fidelity (2026-08-17) ───────────────────────────────────────────────
# Coverage for the tracking-fidelity pass: intra-rig self-collision exclusion,
# the builder's joint registry, the spring's parent-first chain-consistent
# linear commands, and target feed-forward. Uses the shared runtime harness
# (synthetic Mixamo skeleton + the real Kickback node graph, Jolt stepping).

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _tuning(legacy: bool = false) -> RagdollTuning:
	var t := RagdollTuning.create_default()
	# These tests characterise the VELOCITY_OVERWRITE resolver (chain consistency,
	# feed-forward, anchor mismatch); the shipped default is JOINT_MOTOR since 0.5.0.
	t.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
	t.foot_ik_enabled = false
	if legacy:
		t.self_collision = true
		t.spring_chain_consistency = 0.0
		t.spring_feed_forward = 0.0
		t.spring_angular_settle_deadband = 0.04
	return t


func _spawn(tuning: RagdollTuning = null):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning if tuning else _tuning(), null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


## Rotation error (radians) between a body and its skeleton bone's world pose.
func _bone_error(h, rig: String, skeleton_bone: String) -> float:
	var idx: int = h.skeleton.find_bone(skeleton_bone)
	var target: Basis = (h.skeleton.global_transform * h.spring.get_animation_bone_global(idx)).basis.orthonormalized()
	var body: RigidBody3D = h.get_body(rig)
	return (target * body.global_basis.orthonormalized().inverse()).get_rotation_quaternion().get_angle()


# ── Builder: joint registry + self-collision ────────────────────────────────

func test_builder_registers_joint_topology_and_anchors():
	var h = await _spawn()
	var joints: Dictionary = h.rig_builder.get_joints()
	assert_eq(joints.size(), 15, "one registry entry per joint (child rig -> parent)")
	assert_eq(joints["Spine"].parent, "Hips")
	assert_eq(joints["Chest"].parent, "Spine")
	assert_eq(joints["Head"].parent, "Chest")
	assert_eq(joints["LowerArm_L"].parent, "UpperArm_L")
	assert_eq(joints["Foot_R"].parent, "LowerLeg_R")
	# The runtime rig places every joint at the child bone origin = the child
	# body's origin, so the child-side anchor is ~zero and the parent-side anchor
	# is the bone offset (Spine sits 0.12 m above Hips in the harness skeleton).
	assert_lt((joints["Spine"].anchor_child as Vector3).length(), 0.001, "child-side anchor at the child origin")
	assert_almost_eq((joints["Spine"].anchor_parent as Vector3).length(), 0.12, 0.01, "parent-side anchor is the bone offset")
	assert_true(joints["Spine"].joint is Generic6DOFJoint3D)


func test_self_collision_off_excludes_every_body_pair():
	var h = await _spawn()
	var bodies: Dictionary = h.rig_builder.get_bodies()
	# Non-adjacent pairs (no joint between them) — exactly the ones that used to
	# collide in ordinary poses (Chest-Hips, forearm-chest, hand-thigh...).
	for pair in [["Chest", "Hips"], ["LowerArm_L", "Chest"], ["Hand_R", "UpperLeg_R"], ["Head", "Spine"]]:
		var a: RigidBody3D = bodies[pair[0]]
		var b: RigidBody3D = bodies[pair[1]]
		var excluded: bool = b in a.get_collision_exceptions() or a in b.get_collision_exceptions()
		assert_true(excluded, "%s / %s excluded from colliding" % [pair[0], pair[1]])


func test_self_collision_on_keeps_legacy_contacts():
	var t := _tuning()
	t.self_collision = true
	var h = await _spawn(t)
	var chest: RigidBody3D = h.get_body("Chest")
	var hips: RigidBody3D = h.get_body("Hips")
	# Jointed pairs are still excluded by the joints themselves; a non-adjacent
	# pair (Chest-Hips) is not — the legacy behaviour.
	assert_false(hips in chest.get_collision_exceptions() or chest in hips.get_collision_exceptions(),
		"self_collision=true leaves non-adjacent pairs colliding")


# ── Spring: order + chain-consistent commands ───────────────────────────────

func test_spring_updates_parent_first():
	var h = await _spawn()
	var order: PackedStringArray = h.spring._order
	assert_eq(order.size(), 16)
	assert_lt(order.find("Hips"), order.find("Spine"), "Hips before Spine")
	assert_lt(order.find("Spine"), order.find("Chest"), "Spine before Chest")
	assert_lt(order.find("Chest"), order.find("Head"), "Chest before Head")
	assert_lt(order.find("UpperArm_L"), order.find("LowerArm_L"), "UpperArm before LowerArm")
	assert_lt(order.find("LowerLeg_R"), order.find("Foot_R"), "LowerLeg before Foot")


func test_chain_consistent_commands_leave_no_anchor_velocity_mismatch():
	# Right after the spring's own _physics_process (before Jolt steps), every
	# joint anchor must move identically as seen from parent and child — that is
	# what keeps the solver from paying for the mismatch with impulses that spin
	# the light bodies (head/hands/feet). Sample inside the spring's tick via a
	# high-priority sibling.
	var h = await _spawn()
	var worst := {"v": 0.0}
	var joints: Dictionary = h.rig_builder.get_joints()
	var bodies: Dictionary = h.rig_builder.get_bodies()
	var on_tick := func(_d: float) -> void:
		for child_rig: String in joints:
			var j: Dictionary = joints[child_rig]
			var pb: RigidBody3D = bodies[j.parent]
			var cb: RigidBody3D = bodies[child_rig]
			var rp: Vector3 = pb.global_basis * j.anchor_parent
			var rc: Vector3 = cb.global_basis * j.anchor_child
			var mismatch: float = (pb.linear_velocity + pb.angular_velocity.cross(rp)
				- cb.linear_velocity - cb.angular_velocity.cross(rc)).length()
			worst.v = maxf(worst.v, mismatch)
	# process_physics_priority 1000: ticks after the SpringResolver wrote this
	# tick's commands, before Jolt steps (a sibling — a child would tick after its
	# parent regardless of priority).
	var sampler := _AnchorSampler.new()
	sampler.cb = on_tick
	sampler.process_physics_priority = 1000
	h.add_child(sampler)
	# Give the springs a live error to command against: rotate the animation
	# chest 15 deg so every torso body has something to chase.
	var chest_idx: int = h.skeleton.find_bone("mixamorig_Spine2")
	h.skeleton.set_bone_pose_rotation(chest_idx, Quaternion(Vector3.RIGHT, deg_to_rad(15.0)))
	await wait_physics_frames(20)
	assert_lt(worst.v, 0.02, "anchor velocity mismatch after the spring's writes stays ~0 (%.4f m/s)" % worst.v)


class _AnchorSampler extends Node:
	var cb: Callable
	func _physics_process(d: float) -> void:
		if cb.is_valid():
			cb.call(d)


# ── Tracking quality: settle + moving target ────────────────────────────────

func test_step_target_settles_without_oscillation_growth():
	# Displace the chest target 10 deg (inside the Spine>Chest joint limit) and
	# hold: the body must settle to a small residual and its error must not grow
	# again afterwards (no ringing).
	var h = await _spawn()
	var chest_idx: int = h.skeleton.find_bone("mixamorig_Spine2")
	h.skeleton.set_bone_pose_rotation(chest_idx, Quaternion(Vector3.RIGHT, deg_to_rad(10.0)))
	var err_hist: Array[float] = []
	for i in 40:
		await wait_physics_frames(1)
		err_hist.append(_bone_error(h, "Chest", "mixamorig_Spine2"))
	var late_max := 0.0
	for i in range(20, 40):
		late_max = maxf(late_max, err_hist[i])
	assert_lt(err_hist[-1], deg_to_rad(2.0), "chest settles within 2 deg of a 10 deg step (%.1f deg)" % rad_to_deg(err_hist[-1]))
	assert_lt(late_max, deg_to_rad(2.5), "no late ringing: frames 20-40 stay under 2.5 deg (max %.1f)" % rad_to_deg(late_max))


func test_feed_forward_tracks_a_moving_target_tighter_than_legacy():
	# Yaw the whole animation (root bone) at a constant 90 deg/s — every target
	# moves, no joint limit is involved. A pure error spring trails a moving target
	# by ~one tick's motion per tick of lag; feed-forward arrives where the target
	# IS. Compare the mean chest error over the sweep.
	var results := {}
	for legacy in [true, false]:
		var h = await _spawn(_tuning(legacy))
		var hips_idx: int = h.skeleton.find_bone("mixamorig_Hips")
		var sum := 0.0
		var n := 0
		for i in 45:
			var ang := deg_to_rad(90.0) * (i + 1) / 60.0  # 90 deg/s, up to 67 deg of yaw
			h.skeleton.set_bone_pose_rotation(hips_idx, Quaternion(Vector3.UP, ang))
			await wait_physics_frames(1)
			if i >= 15:  # past the initial transient
				sum += _bone_error(h, "Chest", "mixamorig_Spine2")
				n += 1
		results[legacy] = sum / n
		h.queue_free()
	assert_lt(results[false], results[true],
		"feed-forward tracks the sweep tighter (%.1f deg vs legacy %.1f deg)" % [rad_to_deg(results[false]), rad_to_deg(results[true])])
	assert_lt(results[false], deg_to_rad(4.0), "chest trails a 90 deg/s yaw sweep by under 4 deg (%.1f)" % rad_to_deg(results[false]))


func test_new_tuning_fields_default_to_the_fidelity_pass():
	var t := RagdollTuning.create_default()
	assert_false(t.self_collision, "self_collision off by default")
	assert_almost_eq(t.spring_chain_consistency, 1.0, 0.001)
	assert_almost_eq(t.spring_feed_forward, 1.0, 0.001)
	assert_almost_eq(t.spring_angular_settle_deadband, 0.01, 0.0001)
