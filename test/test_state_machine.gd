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
