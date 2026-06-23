extends GutTest

# ── Stumble-step execution (0.4.0 Self-Preservation) ────────────────────────
# End-to-end wiring on a live physics rig (res://test/helpers/rig_harness.gd). The
# pure foot-selection / target / gating math is covered by test_stumble_planner.gd;
# here we let the REAL controller + REAL FootIKSolver run: when a staggering rig
# tips into the stumble band it should fire a recovery step through the foot IK
# solver and emit the signal — and respect the enable flag and the step cap.
#
# We don't fabricate balance state: the synthetic rig, with springs at the stagger
# floor and sway off, naturally tips under gravity, which is exactly the condition
# stumble stepping reacts to.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _stumble_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = true
	t.foot_ik_stagger_pin = true
	t.stumble_enabled = true
	t.stumble_step_threshold = 0.6
	t.stumble_step_cooldown = 0.2
	t.stumble_max_steps = 2
	t.stumble_step_duration = 0.25
	# Hold the stagger open and don't let it early-recover, so tipping proceeds into
	# the stumble band rather than the stagger ending first.
	t.stagger_duration = 6.0
	t.balance_recovery_threshold = 0.0
	t.stagger_sway_strength = 0.0
	return t


# Spawns the rig and lets foot IK lazily initialize during NORMAL (begin_stagger
# only pins the feet if the solver already exists). Returns in NORMAL state.
func _spawn_ready(t: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(t, null, true)
	assert_true(await h.await_ready(40), "Kickback setup completed")
	await wait_physics_frames(6)
	assert_not_null(h.controller._foot_ik, "foot IK initialized during NORMAL")
	return h


func test_stumble_fires_when_tipping():
	var h = await _spawn_ready(_stumble_tuning())
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.FORWARD)
	var fired: bool = await wait_for_signal(h.controller.stumble_step_started, 5.0)
	assert_true(fired, "a stumble step fires as the staggering character tips")
	assert_true(h.controller._stumble_step_count >= 1, "at least one step recorded")


func test_no_stumble_when_disabled():
	var t = _stumble_tuning()
	t.stumble_enabled = false
	var h = await _spawn_ready(t)
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.FORWARD)
	await wait_physics_frames(90)  # ~1.5 s — ample time to tip
	assert_signal_not_emitted(h.controller, "stumble_step_started")
	assert_false(h.controller._foot_ik.is_stepping(), "no step while stumble disabled")
	assert_eq(h.controller._stumble_step_count, 0)


func test_stumble_capped_at_max_steps():
	var t = _stumble_tuning()
	t.stumble_max_steps = 1
	t.stumble_step_cooldown = 0.05
	var h = await _spawn_ready(t)
	h.controller.trigger_stagger(Vector3.FORWARD)
	await wait_physics_frames(150)  # 2.5 s of tipping — well past one cooldown
	assert_true(h.controller._stumble_step_count >= 1, "stepped at least once")
	assert_true(h.controller._stumble_step_count <= 1, "never exceeds stumble_max_steps")
