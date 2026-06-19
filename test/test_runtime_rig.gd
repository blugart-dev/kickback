extends GutTest

# ── Runtime / physics smoke tests ──────────────────────────────────────────
# Builds a REAL Kickback rig (synthetic skeleton + PhysicsRigBuilder +
# SpringResolver + PhysicsRigSync + ActiveRagdollController, coordinated by
# KickbackCharacter) inside the headless SceneTree, steps Jolt physics, and
# asserts the rig builds, the springs track the animation pose, hits land, and
# the sync writes physics back onto the skeleton. State-machine transitions
# (ragdoll / recovery / stagger) live in test_state_machine.gd; foot IK lives in
# test_foot_ik.gd. All three share res://test/helpers/rig_harness.gd.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _core_tuning() -> RagdollTuning:
	# Foot IK off so the solver's per-frame target overrides don't perturb the
	# rest pose these tests assert against.
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	return t


func _spawn(tuning: RagdollTuning = null, with_ground: bool = true):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning if tuning else _core_tuning(), null, with_ground)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


# ── Setup / construction ────────────────────────────────────────────────────

func test_setup_enters_active_mode():
	var h = await _spawn()
	assert_eq(h.character.get_mode(), KickbackCharacter.Mode.ACTIVE, "active ragdoll mode detected")
	assert_eq(h.character.get_active_state(), ActiveRagdollController.State.NORMAL)


func test_rig_builds_all_bodies():
	var h = await _spawn()
	var bodies: Dictionary = h.rig_builder.get_bodies()
	assert_eq(bodies.size(), 16, "16 RigidBody3D bodies built from the Mixamo profile")
	for rig_name: String in RigHarness.RIG_NAMES:
		assert_true(bodies.has(rig_name), "body '%s' present" % rig_name)
		assert_true(bodies[rig_name] is RigidBody3D, "body '%s' is a RigidBody3D" % rig_name)


func test_rig_builds_all_joints():
	var h = await _spawn()
	var joints := 0
	for child in h.rig_builder.get_children():
		if child is Generic6DOFJoint3D:
			joints += 1
	assert_eq(joints, 15, "15 Generic6DOFJoint3D joints connect the 16 bodies")


func test_bodies_snap_to_bone_globals():
	# Groundless — this asserts the builder's placement, before any ground contact
	# can nudge a foot off its bone.
	var h = await _spawn(null, false)
	# Each body should be created at its skeleton bone's world pose.
	for pair in [["Hips", "mixamorig_Hips"], ["Head", "mixamorig_Head"], ["Foot_L", "mixamorig_LeftFoot"]]:
		var body: RigidBody3D = h.get_body(pair[0])
		var bone_origin: Vector3 = h.skeleton_bone_world_origin(pair[1])
		assert_lt(body.global_position.distance_to(bone_origin), 0.06,
			"%s body sits on its bone" % pair[0])


func test_spring_registers_all_bones_with_base_strengths():
	var h = await _spawn()
	var names: PackedStringArray = h.spring.get_all_bone_names()
	assert_eq(names.size(), 16, "spring resolver registered all 16 bodies")
	# Base strengths come straight from the tuning strength_map.
	assert_almost_eq(h.spring.get_base_strength("Hips"), 0.65, 0.001)
	assert_almost_eq(h.spring.get_base_strength("Head"), 0.35, 0.001)
	assert_almost_eq(h.spring.get_base_strength("Hand_L"), 0.25, 0.001)


# ── Spring tracking ─────────────────────────────────────────────────────────

func test_springs_hold_pose_against_gravity():
	# Groundless: the springs alone must counter gravity — nothing holds the rig
	# up from below.
	var h = await _spawn(null, false)
	var hips: RigidBody3D = h.get_body("Hips")
	var start_y := hips.global_position.y
	assert_almost_eq(start_y, 0.9, 0.1, "hips start near the rest height")

	await wait_physics_frames(45)

	# At full spring strength gravity is cancelled and the pin holds the hips up.
	# Without working springs the body would collapse toward the ground (~0).
	assert_gt(hips.global_position.y, 0.7, "springs hold the hips up against gravity")
	assert_lt(hips.global_position.y, 1.1, "hips do not launch upward")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL, "stays NORMAL with no hits")
	# Core orientation tracks the (upright) animation pose rather than toppling.
	assert_gt(hips.global_transform.basis.y.dot(Vector3.UP), 0.9,
		"hips stay upright — springs track the animation orientation")


# ── Hit handling (apply_hit) ────────────────────────────────────────────────

func test_apply_hit_reduces_bone_strength():
	var h = await _spawn()
	var head: RigidBody3D = h.get_body("Head")
	var before: float = h.spring.get_bone_strength("Head")

	var impact := ImpactProfile.new()
	impact.base_impulse = 5.0
	impact.impulse_transfer_ratio = 0.3
	impact.ragdoll_probability = 0.0   # deterministic: never random-ragdoll
	impact.strength_reduction = 0.5
	impact.strength_spread = 0
	impact.recovery_rate = 1.0

	watch_signals(h.controller)
	h.controller.apply_hit(head, Vector3.FORWARD, head.global_position, impact)

	assert_lt(h.spring.get_bone_strength("Head"), before, "hit reduced the head spring strength")
	assert_ne(h.controller.get_state(), ActiveRagdollController.State.RAGDOLL,
		"a single weak hit with 0 ragdoll chance does not ragdoll")
	assert_signal_emitted(h.controller, "hit_absorbed", "a sub-stagger hit emits hit_absorbed")


# ── Skeleton sync (physics → Skeleton3D) ────────────────────────────────────

func test_skeleton_sync_follows_physics_during_ragdoll():
	var h = await _spawn()
	var hips: RigidBody3D = h.get_body("Hips")
	var start := hips.global_position

	h.controller.trigger_ragdoll()
	# Let the now-limp rig fall and collapse under gravity.
	await wait_physics_frames(30)

	assert_gt(start.distance_to(hips.global_position), 0.1,
		"with springs zeroed, physics moves the hips body")

	# PhysicsRigSync is a SkeletonModifier3D: its output is applied to the skin then rolled
	# back, so the modified pose is only live during the skeleton_updated signal — capture
	# it there. Bones span the hierarchy (incl. the deep foot) to also verify the
	# parent-first write order.
	var skel: Skeleton3D = h.skeleton
	var checks := [["Hips", "mixamorig_Hips"], ["Chest", "mixamorig_Spine2"], ["Foot_L", "mixamorig_LeftFoot"]]
	var diffs := {}
	var on_updated := func() -> void:
		for pair in checks:
			var idx: int = skel.find_bone(pair[1])
			var body: RigidBody3D = h.get_body(pair[0])
			var bone_world: Vector3 = (skel.global_transform * skel.get_bone_global_pose(idx)).origin
			diffs[pair[0]] = bone_world.distance_to(body.global_position)
	skel.skeleton_updated.connect(on_updated)
	await wait_physics_frames(3)
	skel.skeleton_updated.disconnect(on_updated)

	assert_eq(diffs.size(), checks.size(), "modifier ran (skeleton_updated fired during ragdoll)")
	for pair in checks:
		assert_lt(float(diffs.get(pair[0], 999.0)), 0.06,
			"skeleton bone '%s' follows its physics body via the modifier" % pair[0])

	# Roll-back invariant: OUTSIDE the skeleton_updated callback, the skeleton's
	# queryable pose is the clean (rolled-back) animation pose — NOT the fallen
	# physics body. This is exactly what keeps the spring's get_bone_pose() target
	# uncontaminated (no feedback loop).
	var hips_idx := skel.find_bone("mixamorig_Hips")
	var hips_bone_world := (skel.global_transform * skel.get_bone_global_pose(hips_idx)).origin
	assert_gt(hips_bone_world.y, 0.7,
		"outside skeleton_updated the hips bone reads the rolled-back animation pose (~rest height)")
	assert_gt(hips_bone_world.distance_to(hips.global_position), 0.1,
		"the rolled-back pose differs from the fallen physics body — modifier rollback is working")


# ── Coordinator facade + balance ────────────────────────────────────────────

func test_kickback_character_ragdoll_facade():
	var h = await _spawn()
	assert_false(h.character.is_ragdolled(), "starts on its feet")
	h.character.trigger_ragdoll()
	assert_true(h.character.is_ragdolled(), "KickbackCharacter.is_ragdolled() tracks the controller")
	assert_eq(h.character.get_active_state(), ActiveRagdollController.State.RAGDOLL)


func test_balance_state_reports_support_when_standing():
	var h = await _spawn()
	var bs: Dictionary = h.controller.get_balance_state()
	assert_true(bs.has_support, "two foot bodies → balance has a support polygon")
	assert_lt(float(bs.balance_ratio), 0.5, "a centered standing pose reads as roughly balanced")


func test_anticipate_threat_emits_signal():
	var h = await _spawn()
	watch_signals(h.controller)
	h.character.anticipate_threat(Vector3.FORWARD, 0.8)
	assert_signal_emitted(h.controller, "threat_anticipated",
		"anticipate_threat routes through to the controller signal")


# ── Spawn-time queue API (deferral until setup_complete) ─────────────────────

func test_queue_ragdoll_before_setup_defers():
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(_core_tuning(), null, true)
	assert_false(h.character.is_setup_complete(), "not yet set up immediately after setup()")
	h.character.queue_ragdoll()  # queued before the physics rig exists
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "setup completed")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.RAGDOLL,
		"queue_ragdoll fired on setup_complete")


func test_queue_persistent_before_setup_defers():
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(_core_tuning(), null, true)
	h.character.queue_persistent()
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "setup completed")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"queue_persistent fired on setup_complete")


# ── apply_hit per-frame debounce ─────────────────────────────────────────────

func test_apply_hit_debounces_same_body_same_frame():
	var h = await _spawn()
	var head: RigidBody3D = h.get_body("Head")
	var impact := ImpactProfile.new()
	impact.base_impulse = 5.0
	impact.impulse_transfer_ratio = 0.3
	impact.ragdoll_probability = 0.0   # deterministic — never random-ragdoll
	impact.strength_reduction = 0.5
	impact.strength_spread = 0
	impact.recovery_rate = 1.0
	# Two hits on the same body with NO frame advance between them.
	h.controller.apply_hit(head, Vector3.FORWARD, head.global_position, impact)
	var after_first: float = h.spring.get_bone_strength("Head")
	h.controller.apply_hit(head, Vector3.FORWARD, head.global_position, impact)
	var after_second: float = h.spring.get_bone_strength("Head")
	assert_lt(after_first, h.spring.get_base_strength("Head"),
		"first hit reduced strength (guards against a trivially-passing test)")
	assert_almost_eq(after_second, after_first, 0.0001,
		"a second same-frame hit on the same body is debounced — no extra reduction")
