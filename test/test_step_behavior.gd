extends GutTest

# ── Behavior layer + StepBehavior (0.6.0) ───────────────────────────────────
# The controller runs a fixed list of behaviors every NORMAL / STAGGER tick; each reads
# the BalanceState and answers with stiffness / targets. StepBehavior locks loaded feet
# that drift from their animation spot, re-plants them with a lifted step when calm, and
# steps to the capture point when the XCoM reaches the edge of the feet. Nothing here
# moves the character root.

const RigHarness := preload("res://test/helpers/rig_harness.gd")


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
	await wait_physics_frames(10)  # foot IK initialises lazily
	assert_not_null(h.controller._foot_ik, "foot IK initialised during NORMAL")
	# The synthetic skeleton stands with its legs fully extended (hip joint 0.82 m above
	# the ankle = the leg length), so no foot could reach anywhere but straight down.
	# Lower the animation pelvis 6 cm: the knees bend and a step has somewhere to go.
	var hips_idx: int = h.skeleton.find_bone("mixamorig_Hips")
	h.skeleton.set_bone_pose_position(hips_idx, h.skeleton.get_bone_pose_position(hips_idx) - Vector3(0.0, 0.06, 0.0))
	await wait_physics_frames(45)  # settle on bent knees
	return h


func _step_behavior(h) -> StepBehavior:
	for b in h.controller.get_behaviors():
		if b is StepBehavior:
			return b
	return null


# ── Wiring ──────────────────────────────────────────────────────────────────

func test_controller_runs_a_step_behavior_by_default():
	var h = await _spawn(_tuning())
	assert_not_null(_step_behavior(h), "the default behavior list contains a StepBehavior")
	assert_eq(h.controller.get_balance().has_support, true)


func test_standing_still_takes_no_step():
	var h = await _spawn(_tuning())
	var sb := _step_behavior(h)
	await wait_physics_frames(90)
	assert_eq(sb.steps_taken, 0, "a quiet stance never steps (ratio %.2f)" % h.controller.get_balance().ratio)
	for foot in ["Foot_L", "Foot_R"]:
		assert_lt(sb._mismatch(h.controller._behavior_ctx, foot), h.tuning.step_replant_distance,
			"%s stands within the re-plant distance of its animation spot" % foot)


# ── Re-plant ────────────────────────────────────────────────────────────────

func test_a_displaced_animation_replants_the_feet_with_lifted_steps():
	# The gameplay root (and with it the whole animation) moves 20 cm forward while the
	# physical feet stay where friction planted them — the situation after a violent
	# clip or a get-up. The anchor drags the pelvis forward; the feet must not be dragged
	# but lifted and re-planted under the new spots, one at a time.
	var h = await _spawn(_tuning())
	var sb := _step_behavior(h)
	watch_signals(h.controller)
	var foot_l: RigidBody3D = h.get_body("Foot_L")
	var foot_r: RigidBody3D = h.get_body("Foot_R")
	var start_l := foot_l.global_position
	var start_r := foot_r.global_position
	h.skeleton.position.z += 0.2  # the harness node owns the ground; move only the skeleton
	var max_lift := 0.0
	for i in 150:
		await wait_physics_frames(1)
		max_lift = maxf(max_lift, maxf(foot_l.global_position.y - start_l.y, foot_r.global_position.y - start_r.y))
	assert_gte(sb.steps_taken, 2, "both feet were re-planted (%d steps, last reason %s)" % [sb.steps_taken, sb.last_step_reason])
	assert_eq(sb.last_step_reason, "replant")
	assert_signal_emitted(h.controller, "step_started")
	assert_gt(max_lift, 0.02, "a foot lifted off the ground during a step (%.3f m)" % max_lift)
	var moved_l := foot_l.global_position.z - start_l.z
	var moved_r := foot_r.global_position.z - start_r.z
	assert_gt(moved_l, 0.10, "left foot re-planted forward (%.3f m of 0.2)" % moved_l)
	assert_gt(moved_r, 0.10, "right foot re-planted forward (%.3f m of 0.2)" % moved_r)
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL, "a re-plant is not a stagger")


func test_no_step_when_disabled():
	var t := _tuning()
	t.steps_enabled = false
	var h = await _spawn(t)
	var sb := _step_behavior(h)
	h.skeleton.position.z += 0.2
	await wait_physics_frames(60)
	assert_eq(sb.steps_taken, 0, "steps_enabled = false: no step")


# ── Balance step ────────────────────────────────────────────────────────────

func test_a_shove_past_the_edge_of_the_feet_steps_to_the_fall_side():
	# Push the whole body sideways (+X): the XCoM leaves the polygon, the +X foot swings
	# out toward the capture point. The root is never written — check it. The anchor's
	# sideways hold is released here so the body can actually move (with the hold the
	# shove is arrested within 3 ticks and the trigger persistence filters it out).
	var t := _tuning()
	t.muscle_root_hold = 0.0
	var h = await _spawn(t)
	var sb := _step_behavior(h)
	var root_before: Vector3 = h.controller._character_root.global_position
	var foot_l: RigidBody3D = h.get_body("Foot_L")  # +X side in the harness
	var xl_before := foot_l.global_position.x
	# Capture the FIRST step (a balance step is followed by a re-plant back to the
	# animation spot once the character is calm again).
	var first: Dictionary = {}
	h.controller.step_started.connect(func(foot_rig: String, target: Vector3) -> void:
		if first.is_empty():
			first["foot"] = foot_rig
			first["target"] = target
			first["reason"] = sb.last_step_reason)
	for body: RigidBody3D in h.rig_builder.get_bodies().values():
		body.linear_velocity += Vector3(1.6, 0.0, 0.0)
	for i in 40:
		await wait_physics_frames(1)
	assert_false(first.is_empty(), "the shove triggered a step")
	if not first.is_empty():
		assert_eq(first["reason"], "balance", "the first step is a balance step")
		assert_eq(first["foot"], "Foot_L", "the foot on the fall side (+X) is the one that steps")
		assert_gt((first["target"] as Vector3).x - xl_before, 0.05, "the step lands further out on the fall side")
	assert_eq(h.controller._character_root.global_position, root_before, "no root teleport anywhere in a step")


func test_stagger_steps_instead_of_shuffling_in_place():
	# trigger_stagger locks both feet (anti-slide); the behavior may still step them
	# if balance asks. Without a shove the stagger just wobbles and recovers to NORMAL.
	var t := _tuning()
	t.stagger_duration = 1.0
	var h = await _spawn(t)
	var root_before: Vector3 = h.controller._character_root.global_position
	h.controller.trigger_stagger(Vector3.FORWARD)
	var recovered: bool = await wait_for_signal(h.controller.stagger_finished, 4.0)
	assert_true(recovered, "stagger recovers")
	assert_eq(h.controller._character_root.global_position, root_before, "a stagger never moves the character root by itself")
