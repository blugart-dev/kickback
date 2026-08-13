extends GutTest

# ── ActiveRagdollController state machine ──────────────────────────────────
# Drives the REAL controller through its NORMAL → RAGDOLL → GETTING_UP → NORMAL,
# stagger, and persistent transitions on a live physics rig (built via
# res://test/helpers/rig_harness.gd), rather than re-implementing its formulas.
# The remaining pure tests assert tuning/enum invariants the controller relies
# on (threshold ordering, enum values), which are not re-implementations.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


# Fast, deterministic tuning: short ragdoll/recovery windows keep the wall-clock
# low, foot IK off and sway off so a balanced stance can't tip mid-test.
func _fast_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	t.ragdoll_force_recovery_time = 0.4
	t.recovery_duration = 0.4
	t.safety_timeout = 0.6
	t.pose_blend_duration = 0.2
	t.settle_duration = 0.15
	t.stagger_duration = 0.3
	t.stagger_sway_strength = 0.0
	return t


func _spawn(tuning: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, true)
	var ok: bool = await h.await_ready(40)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


# ── Real state-machine transitions ──────────────────────────────────────────

func test_trigger_ragdoll_zeroes_springs():
	var h = await _spawn(_fast_tuning())
	watch_signals(h.controller)
	h.controller.trigger_ragdoll()

	assert_eq(h.controller.get_state(), ActiveRagdollController.State.RAGDOLL)
	assert_signal_emitted(h.controller, "ragdoll_started")
	assert_signal_emitted(h.controller, "state_changed")
	for rig_name: String in RigHarness.RIG_NAMES:
		assert_almost_eq(h.spring.get_bone_strength(rig_name), 0.0, 0.001,
			"%s spring zeroed on ragdoll" % rig_name)


func test_ragdoll_recovers_to_normal():
	var h = await _spawn(_fast_tuning())
	watch_signals(h.controller)
	h.controller.trigger_ragdoll()
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.RAGDOLL)

	# Force-recovery + safety timeout guarantee the cycle completes quickly.
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 8.0)
	assert_true(recovered, "recovery_finished fired within the timeout")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL, "returned to NORMAL")
	assert_signal_emitted(h.controller, "recovery_started")
	# Springs ramp back to their base strength after recovery.
	assert_almost_eq(h.spring.get_bone_strength("Hips"), 0.65, 0.02, "hips spring restored to base")


func test_trigger_stagger_reduces_strength_and_recovers():
	var h = await _spawn(_fast_tuning())
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.FORWARD)

	assert_eq(h.controller.get_state(), ActiveRagdollController.State.STAGGER)
	assert_signal_emitted(h.controller, "stagger_started")
	assert_lt(h.spring.get_bone_strength("Hips"), 0.2,
		"stagger drops spring strength toward the floor")

	var finished: bool = await wait_for_signal(h.controller.stagger_finished, 5.0)
	assert_true(finished, "stagger auto-recovers to NORMAL")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL)


func test_persistent_holds_until_released():
	var h = await _spawn(_fast_tuning())
	h.controller.set_persistent(true)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT)

	# Persistent ragdoll must NOT auto-recover while it is held.
	await wait_physics_frames(20)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"persistent ragdoll stays down")

	watch_signals(h.controller)
	h.controller.set_persistent(false)
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 8.0)
	assert_true(recovered, "releasing persistent starts recovery")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL)


func test_persistent_survives_hits():
	var h = await _spawn(_fast_tuning())
	h.controller.set_persistent(true)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT)

	# Worst-case profile: guaranteed ragdoll dice + full-body strength wipe.
	# A hit on a held-down body must stay pure impulse — transitioning back
	# to RAGDOLL lets settle→recovery stand a corpse up (regression:
	# shooting a persistent ragdoll resurrected it).
	var smash := ImpactProfile.new()
	smash.ragdoll_probability = 1.0
	smash.strength_reduction = 1.0
	smash.strength_spread = 99
	var chest := h.get_body("Chest")
	h.controller.apply_hit(chest, Vector3.FORWARD, chest.global_position, smash)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"hit does not knock a persistent body out of PERSISTENT")

	# ...and the hit must not have armed a recovery either.
	await wait_physics_frames(30)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"persistent body stays down after being hit")


func test_knockdown_disabled_downgrades_ragdoll_to_stagger():
	# Death-only-ragdoll games: with knockdown_enabled=false a hit that WOULD
	# fell the character (guaranteed dice roll) staggers it instead, and only
	# explicit calls (deaths, scripts) still ragdoll.
	var t := _fast_tuning()
	t.knockdown_enabled = false
	var h = await _spawn(t)
	watch_signals(h.controller)

	var smash := ImpactProfile.new()
	smash.ragdoll_probability = 1.0
	smash.strength_reduction = 0.5
	var chest := h.get_body("Chest")
	h.controller.apply_hit(chest, Vector3.FORWARD, chest.global_position, smash)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.STAGGER,
		"guaranteed-ragdoll hit downgrades to stagger")
	assert_signal_not_emitted(h.controller, "ragdoll_started")

	# Explicit persistent ragdoll (death) bypasses the gate.
	h.controller.set_persistent(true)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.PERSISTENT,
		"death ragdoll bypasses knockdown_enabled")


func test_recovery_facing_honors_forward_sign():
	# The get-up teleport yaws the root so the MODEL faces the way the body lies:
	# the same landing pose under a flipped forward convention must yaw 180° apart
	# (a -Z-forward Godot character otherwise stands up facing backwards).
	var t := _fast_tuning()
	t.ragdoll_force_recovery_time = 10.0  # recovery is driven manually below
	t.settle_duration = 10.0
	var h = await _spawn(t)
	h.controller.trigger_ragdoll()
	await wait_physics_frames(2)

	# Lay the head a clear metre forward (+Z) of the hips so the landing pose has
	# an unambiguous facing for the head-hip computation.
	var hips: RigidBody3D = h.get_body("Hips")
	h.get_body("Head").global_position = hips.global_position + Vector3(0.0, -0.4, 1.0)

	t.character_forward_sign = 1
	h.controller._start_recovery()
	var yaw_plus_z: float = h.global_rotation.y

	t.character_forward_sign = -1
	h.controller._start_recovery()
	var yaw_minus_z: float = h.global_rotation.y

	assert_almost_eq(absf(wrapf(yaw_plus_z - yaw_minus_z, -PI, PI)), PI, 0.01,
		"flipping the forward convention flips the recovered yaw 180 degrees")


# ── Enum / tuning invariants (not re-implemented formulas) ──────────────────

func test_state_enum():
	assert_eq(ActiveRagdollController.State.NORMAL, 0)
	assert_eq(ActiveRagdollController.State.STAGGER, 1)
	assert_eq(ActiveRagdollController.State.RAGDOLL, 2)
	assert_eq(ActiveRagdollController.State.GETTING_UP, 3)
	assert_eq(ActiveRagdollController.State.PERSISTENT, 4)


func test_pain_thresholds_ordered():
	var t := RagdollTuning.create_default()
	assert_eq(t.pain_stagger_threshold, 0.5)
	assert_eq(t.pain_ragdoll_threshold, 0.9)
	assert_true(t.pain_stagger_threshold < t.pain_ragdoll_threshold,
		"pain must cross stagger before ragdoll")


func test_balance_thresholds_ordered():
	var t := RagdollTuning.create_default()
	assert_true(t.balance_recovery_threshold < t.balance_stagger_threshold)
	assert_true(t.balance_stagger_threshold < t.balance_ragdoll_threshold)


func test_injury_threshold_default():
	var t := RagdollTuning.create_default()
	assert_eq(t.injury_threshold, 0.3)
