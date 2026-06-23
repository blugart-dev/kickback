extends GutTest

# ── Directed stumble (0.4.0 Self-Preservation) ──────────────────────────────
# A staggering hit drives a DIRECTED stumble: the character root is knocked along
# the hit direction (visible displacement) with the feet stepping to follow, while
# the body stiffens to stay upright. End-to-end wiring on a live physics rig
# (res://test/helpers/rig_harness.gd) — we assert the controller actually displaces
# the character and fires steps, and respects the enable flag. The feel/quality of
# the motion is validated visually on the real asset, not asserted here.
#
# Note: in the harness the controller's character_root is the harness node, whose
# children include the rig — so its global_position moving IS the displacement under
# test (the ground is a sibling-ish child and moves with it, a harness quirk; on a
# real character the root excludes the ground).

const RigHarness := preload("res://test/helpers/rig_harness.gd")


func _stumble_tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = true
	t.foot_ik_stagger_pin = true
	t.stumble_enabled = true
	t.stagger_duration = 6.0          # keep the stagger open across the stumble
	t.stagger_sway_strength = 0.0     # deterministic (sway uses a random phase)
	return t


# Spawns the rig and lets foot IK lazily initialize during NORMAL (the directed
# stumble needs the foot IK solver to exist and pin). Returns in NORMAL state.
func _spawn_ready(t: RagdollTuning):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(t, null, true)
	assert_true(await h.await_ready(40), "Kickback setup completed")
	await wait_physics_frames(6)
	assert_not_null(h.controller._foot_ik, "foot IK initialized during NORMAL")
	return h


func test_directed_stumble_displaces_and_steps():
	var h = await _spawn_ready(_stumble_tuning())
	var start: Vector3 = h.controller._character_root.global_position
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.FORWARD)
	assert_true(h.controller._stumbling, "a directed stumble starts on the staggering hit")

	await wait_physics_frames(45)  # let the knockback drift play out
	var moved: Vector3 = h.controller._character_root.global_position - start
	assert_gt(moved.length(), 0.05, "the stumble visibly displaced the character")
	# Displacement is along the hit (forward) axis, not sideways.
	assert_gt(absf(moved.z), absf(moved.x), "displacement is along the hit direction")
	assert_signal_emitted(h.controller, "stumble_step_started")
	assert_true(h.controller._stumble_step_count >= 1, "at least one step fired")


func test_no_stumble_when_disabled():
	var t = _stumble_tuning()
	t.stumble_enabled = false
	var h = await _spawn_ready(t)
	var start: Vector3 = h.controller._character_root.global_position
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.FORWARD)
	assert_false(h.controller._stumbling, "no directed stumble when disabled")

	await wait_physics_frames(45)
	var moved: Vector3 = h.controller._character_root.global_position - start
	assert_lt(moved.length(), 0.02, "no knockback displacement when stumble disabled")
	assert_signal_not_emitted(h.controller, "stumble_step_started")


func test_stumble_ends_and_returns_to_normal():
	var h = await _spawn_ready(_stumble_tuning())
	h.controller.trigger_stagger(Vector3.FORWARD)
	assert_true(h.controller._stumbling)
	# The drift is spent within ~speed/decel seconds; the stumble flag clears and the
	# stagger then recovers to NORMAL on its own.
	var recovered: bool = await wait_for_signal(h.controller.stagger_finished, 8.0)
	assert_true(recovered, "stagger recovers after the stumble")
	assert_false(h.controller._stumbling, "stumble flag cleared")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL)
