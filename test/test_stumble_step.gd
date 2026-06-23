extends GutTest

# ── Stumble-step execution (0.4.0 Self-Preservation) ────────────────────────
# End-to-end wiring on a live physics rig (res://test/helpers/rig_harness.gd). The
# pure foot-selection / target / gating math (band, cooldown, step cap) is covered
# by test_stumble_planner.gd; here we let the REAL controller + REAL FootIKSolver
# run and verify the wiring: a staggering character pushed off balance fires a
# recovery step through the foot IK solver and emits the signal — and doesn't when
# disabled.
#
# We push the character deterministically rather than waiting for it to topple on
# its own: with the hardened substrate (foot-IK orientation fix + spring settle
# deadband) a staggering rig holds its balance well, so we drive the centre-of-mass
# off the (IK-pinned) feet by forcing the upper body laterally.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _stumble_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = true
	t.foot_ik_stagger_pin = true
	t.stumble_enabled = true
	# Wide trigger band so this WIRING test fires on any real imbalance rather than
	# depending on hitting a narrow window (the exact band/cooldown/cap thresholds are
	# covered precisely by the pure StumblePlanner.can_step tests).
	t.stumble_step_threshold = 0.15
	t.balance_ragdoll_threshold = 0.95
	t.stumble_step_cooldown = 0.2
	t.stumble_max_steps = 2
	t.stumble_step_duration = 0.25
	# Hold the stagger open and don't early-recover, so the push can drive the CoM
	# off the feet rather than the stagger ending first.
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


# Pushes the upper body (everything but the IK-pinned feet) laterally each physics
# frame, shifting the CoM off the support polygon. Returns true as soon as a stumble
# step fires (caller must watch_signals first), else false after max_frames.
func _push_until_step(h, max_frames: int = 180) -> bool:
	# Force the torso column laterally. The legs/feet are pinned by foot IK, so this
	# shifts the centre-of-mass off the support polygon (the imbalance stumble reacts
	# to) instead of just sliding the whole rig.
	var bodies: Dictionary = h.rig_builder.get_bodies()
	var column := ["Hips", "Spine", "Chest", "Head"]
	for _i in max_frames:
		for rn: String in column:
			var b: RigidBody3D = bodies.get(rn)
			if b:
				b.apply_central_force(Vector3.RIGHT * b.mass * 20.0)
		if get_signal_emit_count(h.controller, "stumble_step_started") > 0:
			return true
		await wait_physics_frames(1)
	return get_signal_emit_count(h.controller, "stumble_step_started") > 0


func test_stumble_fires_when_pushed_off_balance():
	var h = await _spawn_ready(_stumble_tuning())
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.RIGHT)
	var fired: bool = await _push_until_step(h)
	assert_true(fired, "a stumble step fires when the staggering character is pushed off balance")
	assert_true(h.controller._stumble_step_count >= 1, "at least one step recorded")


func test_no_stumble_when_disabled():
	var t = _stumble_tuning()
	t.stumble_enabled = false
	var h = await _spawn_ready(t)
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.RIGHT)
	var fired: bool = await _push_until_step(h, 120)
	assert_false(fired, "no stumble step while stumble is disabled")
	assert_eq(h.controller._stumble_step_count, 0)
	assert_false(h.controller._foot_ik.is_stepping(), "no step in flight when disabled")
