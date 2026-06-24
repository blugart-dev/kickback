extends GutTest


# ── Protective fall-reach tests ─────────────────────────────────────────────
# Drives the REAL ActiveRagdollController on a live harness rig: a hit that
# commits to a fall should keep the leading arm active and reaching for the
# ground while the rest goes limp, gated to forward/side falls. The reach MOTION
# is validated visually; these assert the state-machine wiring (which arm stays
# alive, the facing gate, the release).

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _spawn():
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(RagdollTuning.create_default(), null, true)  # foot IK + arm bracing on
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	# Step physics so the controller lazily creates the foot + arm IK solvers.
	await wait_physics_frames(15)
	return h


# A profile that always ragdolls, so apply_hit commits straight to a fall.
func _fall_profile() -> ImpactProfile:
	var p := ImpactProfile.create_bullet()
	p.ragdoll_probability = 1.0
	return p


func _chest(h) -> RigidBody3D:
	return h.rig_builder.get_bodies().get("Chest")


# The harness character root faces +Z, so a +Z hit is a forward fall.
func test_forward_fall_braces_leading_arm():
	var h = await _spawn()
	var ctrl = h.controller
	var chest := _chest(h)
	ctrl.apply_hit(chest, Vector3(0, 0, 1), chest.global_position, _fall_profile())

	assert_eq(ctrl.get_state(), ActiveRagdollController.State.RAGDOLL, "hit committed to a fall")
	assert_true(ctrl._fall_bracing, "forward fall engages the protective reach")

	var arm_rigs: PackedStringArray = ctrl._fall_brace_arm_rigs
	assert_eq(arm_rigs.size(), 3, "a full arm chain is bracing")
	# The bracing arm keeps spring strength; the rest of the body goes limp.
	assert_gt(h.spring.get_bone_strength(arm_rigs[0]), 0.01, "bracing shoulder stays active")
	assert_gt(h.spring.get_bone_strength(arm_rigs[2]), 0.01, "bracing hand stays active")
	assert_lt(h.spring.get_bone_strength("UpperLeg_L"), 0.01, "non-bracing bones go limp")
	assert_lt(h.spring.get_bone_strength("UpperLeg_R"), 0.01, "non-bracing bones go limp")


# A backward fall can't be broken by a hands-forward plant — the reach is skipped.
func test_backward_fall_does_not_brace():
	var h = await _spawn()
	var ctrl = h.controller
	var chest := _chest(h)
	ctrl.apply_hit(chest, Vector3(0, 0, -1), chest.global_position, _fall_profile())

	assert_eq(ctrl.get_state(), ActiveRagdollController.State.RAGDOLL, "hit committed to a fall")
	assert_false(ctrl._fall_bracing, "a backward fall skips the hands-forward reach")
	# Everything is limp on a backward fall (no arm kept alive).
	assert_lt(h.spring.get_bone_strength("UpperArm_L"), 0.01, "arms limp on a backward fall")
	assert_lt(h.spring.get_bone_strength("UpperArm_R"), 0.01, "arms limp on a backward fall")


# The min-facing gate is configurable: -1 means always reach (even backward).
func test_min_facing_can_force_reach():
	var h = await _spawn()
	h.tuning.arm_fall_reach_min_facing = -1.0
	var ctrl = h.controller
	var chest := _chest(h)
	ctrl.apply_hit(chest, Vector3(0, 0, -1), chest.global_position, _fall_profile())
	assert_true(ctrl._fall_bracing, "min_facing = -1 reaches even on a backward fall")


# The brace is a brief window; after it the arm releases and joins the full ragdoll.
func test_fall_brace_releases_after_window():
	var h = await _spawn()
	var ctrl = h.controller
	var chest := _chest(h)
	ctrl.apply_hit(chest, Vector3(0, 0, 1), chest.global_position, _fall_profile())
	assert_true(ctrl._fall_bracing, "brace engaged")

	# Well past arm_fall_reach_duration (0.55 s ≈ 33 frames).
	await wait_physics_frames(70)
	assert_false(ctrl._fall_bracing, "brace releases after its window")
