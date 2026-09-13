extends GutTest

# ── JOINT_MOTOR muscle layer (0.5.0) ────────────────────────────────────────
# Drives the REAL resolver in RagdollTuning.MuscleMode.JOINT_MOTOR on the live
# harness rig (res://test/helpers/rig_harness.gd): motors enabled, force limit =
# torque × strength ratio, limp = zero limit, axis sign end to end on identity and
# anatomical joint frames, hold under real gravity, a physical hit reaction, and
# 30 / 120 Hz holds. Legacy mode stays the default and is regression-guarded by
# test_rig_fidelity.gd / test_runtime_rig.gd.

const RigHarness := preload("res://test/helpers/rig_harness.gd")

var _saved_hz: int = 60


func before_each():
	_saved_hz = Engine.physics_ticks_per_second


func after_each():
	Engine.physics_ticks_per_second = _saved_hz


func _tuning(motor: bool = true) -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	t.stagger_sway_strength = 0.0
	t.steps_enabled = false
	t.arm_brace_enabled = false
	t.muscle_mode = RagdollTuning.MuscleMode.JOINT_MOTOR if motor else RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
	# These tests characterise the MUSCLES, mostly on a groundless rig: the root anchor
	# carries the body (the 0.5.0 stand-in). Since 0.6.0 the default is 0 (the legs
	# carry the body through the feet) — covered by test_feet_load_bearing.gd.
	t.muscle_root_support = 1.0
	return t


func _spawn(tuning: RagdollTuning, with_ground: bool):
	var h = RigHarness.new()
	add_child_autoqfree(h)
	h.setup(tuning, null, with_ground)
	var ok: bool = await h.await_ready(60)
	assert_true(ok, "Kickback setup completed within frame budget")
	return h


## Angle (deg) between a body's basis and its animation bone's world basis.
func _error_deg(h, rig: String) -> float:
	var idx: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(rig))
	var target: Basis = (h.skeleton.global_transform * h.spring.get_animation_bone_global(idx)).basis.orthonormalized()
	var body: RigidBody3D = h.get_body(rig)
	var q := (target * body.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	return rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))


# ── Wiring ──────────────────────────────────────────────────────────────────

func test_default_mode_is_joint_motor():
	assert_eq(RagdollTuning.create_default().muscle_mode, RagdollTuning.MuscleMode.JOINT_MOTOR,
		"JOINT_MOTOR is the shipped default since 0.5.0")


func test_legacy_mode_keeps_motors_off():
	var h = await _spawn(_tuning(false), false)
	await wait_physics_frames(2)
	assert_false(h.spring.is_motor_mode())
	var cmd: Dictionary = h.spring.get_motor_command("Chest")
	assert_false(bool(cmd.enabled), "legacy mode never enables a joint motor")


func test_motor_mode_enables_every_joint_motor_with_profile_torque():
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(2)
	assert_true(h.spring.is_motor_mode())
	for rig_name: String in RigHarness.RIG_NAMES:
		if rig_name == "Hips":
			var root_cmd: Dictionary = h.spring.get_motor_command("Hips")
			assert_true(bool(root_cmd.enabled), "root world-joint motor enabled")
			assert_almost_eq(float(root_cmd.limit), RagdollTuning.create_default().muscle_root_torque, 0.001,
				"root force limit = muscle_root_torque")
			continue
		var cmd: Dictionary = h.spring.get_motor_command(rig_name)
		assert_true(bool(cmd.enabled), "%s motor enabled" % rig_name)
		var torque: float = h.spring.get_muscle_torque(rig_name)
		assert_eq(torque, float(SkeletonDetector.MUSCLE_TORQUE_TABLE[rig_name]), "%s torque from the profile" % rig_name)
		assert_almost_eq(float(cmd.limit), torque, 0.001, "%s force limit = torque at full strength" % rig_name)


func test_force_limit_scales_with_strength_and_scale():
	var t := _tuning()
	t.muscle_strength_scale = 0.5
	var h = await _spawn(t, false)
	await wait_physics_frames(2)
	h.spring.set_bone_strength("LowerArm_L", h.spring.get_base_strength("LowerArm_L") * 0.4)
	await wait_physics_frames(1)
	var cmd: Dictionary = h.spring.get_motor_command("LowerArm_L")
	# torque 40 × scale 0.5 × ratio 0.4 ^ curve 0.5 (before the next tick's recovery nudge)
	var expected := 40.0 * 0.5 * pow(0.4, t.muscle_strength_curve)
	assert_almost_eq(float(cmd.limit), expected, 0.5, "limit = torque × scale × ratio^curve")


func test_limp_bone_has_zero_force_limit():
	var h = await _spawn(_tuning(), true)
	await wait_physics_frames(2)
	h.controller.trigger_ragdoll()
	await wait_physics_frames(2)
	for rig_name: String in ["Chest", "Head", "LowerArm_L", "Foot_R"]:
		var cmd: Dictionary = h.spring.get_motor_command(rig_name)
		assert_almost_eq(float(cmd.limit), 0.0, 0.001, "%s limp: motor lets go" % rig_name)
		assert_almost_eq((cmd.target as Vector3).length(), 0.0, 0.001, "%s limp: no target" % rig_name)


func test_gravity_stays_on_in_motor_mode():
	var t := _tuning()
	t.gravity_scale = 1.0
	var h = await _spawn(t, false)
	await wait_physics_frames(3)
	var chest: RigidBody3D = h.get_body("Chest")
	assert_almost_eq(chest.gravity_scale, 1.0, 0.001, "jointed bodies carry full gravity at full strength")


# ── Axis sign end to end ────────────────────────────────────────────────────

func test_motor_follows_an_animated_head_nod():
	# Identity-ish joint frame: a 30 deg nod must be reproduced with the RIGHT
	# sign (a wrong mirror would drive the head 30 deg the other way = 60 off).
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(5)
	var idx: int = h.skeleton.find_bone("mixamorig_Head")
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(30.0)))
	await wait_physics_frames(60)
	assert_lt(_error_deg(h, "Head"), 6.0, "head reaches the nodded target (%.1f deg off)" % _error_deg(h, "Head"))


func test_motor_follows_an_animated_elbow_fold():
	# Anatomical elbow frame (non-identity): a 60 deg fold inside the limits.
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(5)
	var idx: int = h.skeleton.find_bone("mixamorig_LeftForeArm")
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.DOWN, deg_to_rad(60.0)))
	await wait_physics_frames(60)
	var e := _error_deg(h, "LowerArm_L")
	# 7.x deg with the single-joint root of 0.5.0; 8.3 once the root became two
	# constraints (orientation in the pelvis frame, position in world axes, 0.6.0).
	assert_lt(e, 10.0, "forearm reaches the folded target (%.1f deg off)" % e)


func test_root_motor_follows_an_animated_pelvis_yaw():
	# The pelvis has no parent joint; its world-joint motor must turn it (and the
	# body hanging off it) to a yawed animation root within a few degrees.
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(5)
	var idx: int = h.skeleton.find_bone("mixamorig_Hips")
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.UP, deg_to_rad(25.0)))
	await wait_physics_frames(60)
	var e := _error_deg(h, "Hips")
	assert_lt(e, 4.0, "pelvis reaches the yawed target (%.1f deg off)" % e)
	assert_lt(_error_deg(h, "Chest"), 8.0, "chest follows the yawed pelvis (chain lag)")


func test_leaving_motor_mode_frees_the_root_anchor():
	var t := _tuning()
	var h = await _spawn(t, false)
	await wait_physics_frames(3)
	assert_not_null(h.rig_builder.find_child("Hips_anchor_motor", false, false), "root anchor joint created")
	t.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
	h.character.refresh_tuning()
	await wait_physics_frames(3)
	assert_null(h.rig_builder.find_child("Hips_anchor_motor", false, false), "root anchor joint freed on leaving motor mode")


func test_motor_pushing_into_a_limit_yields_a_bounded_amount():
	# An unreachable target (elbow hyperextension -60 vs the -10 bound): the motor
	# pushes with its full 40 N.m and Jolt's limit yields some degrees under that
	# sustained torque. It must stay bounded (measured ~16 deg past the bound).
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(5)
	var idx: int = h.skeleton.find_bone("mixamorig_LeftForeArm")
	h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.DOWN, deg_to_rad(-60.0)))
	await wait_physics_frames(120)
	var a: Vector3 = h.rig_builder.get_joint_angles("LowerArm_L")
	assert_gt(a.x, -35.0, "limit yields at most ~25 deg under a 40 N.m push (%.1f)" % a.x)
	assert_lt(a.x, 0.0, "...on the hyperextension side")


# ── Hold under real gravity ─────────────────────────────────────────────────

func test_motors_hold_the_pose_under_gravity():
	# Groundless T-pose: the muscles alone must carry the arms and legs; the root
	# anchor holds the body up (muscle_root_support = 1: since 0.6.0 the default is 0,
	# the legs carry the body, and there is no ground here). (Spike: ~1 deg at gain
	# 0.17-0.25.)
	var t := _tuning()
	t.muscle_root_support = 1.0
	var h = await _spawn(t, false)
	await wait_physics_frames(90)
	var hips: RigidBody3D = h.get_body("Hips")
	assert_gt(hips.global_position.y, 0.7, "pelvis pin holds the body up")
	for rig_name: String in ["Spine", "Chest", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperLeg_L", "LowerLeg_L"]:
		var e := _error_deg(h, rig_name)
		assert_lt(e, 4.0, "%s holds within 4 deg under gravity (%.2f)" % [rig_name, e])


func test_pelvis_stands_at_its_target_height():
	# The root is held by the world joint's LINEAR motor (a bounded force inside the
	# solver): the standing pelvis sits within the settle deadband of its target and
	# does not bounce. A velocity pin written to the pelvis alone was diluted by the
	# joint solve across the ~55 kg hanging from it (3.5 cm low, bouncing at ~3 Hz on
	# the demo idle — the user-visible whole-body wobble). Groundless, so the anchor
	# carries the weight here (muscle_root_support = 1).
	var t := _tuning()
	t.muscle_root_support = 1.0
	var h = await _spawn(t, false)
	await wait_physics_frames(90)
	var hips: RigidBody3D = h.get_body("Hips")
	var st: Dictionary = h.spring._bones["Hips"]
	var target_y: float = (st.target_xform as Transform3D).origin.y
	var sag := target_y - hips.global_position.y
	assert_lt(absf(sag), 0.006, "pelvis within 6 mm of its target (sag %.1f mm)" % (sag * 1000.0))
	var ymin := INF
	var ymax := -INF
	for i in 60:
		await wait_physics_frames(1)
		ymin = minf(ymin, hips.global_position.y)
		ymax = maxf(ymax, hips.global_position.y)
	assert_lt(ymax - ymin, 0.004, "no pelvis bounce (%.1f mm peak-to-peak over 1 s)" % ((ymax - ymin) * 1000.0))


func test_weak_muscle_cannot_hold_a_horizontal_arm():
	# Physical honesty: a 3 N.m shoulder (60 × 0.05) is far below what a straight
	# horizontal arm needs, so it sags where a 60 N.m one holds within 4 deg (test
	# above). At 15 N.m (×0.25) it still sags, just slowly (~2 deg in 1.5 s).
	var t := _tuning()
	t.muscle_strength_scale = 0.05
	t.muscle_root_support = 1.0  # groundless
	var h = await _spawn(t, false)
	await wait_physics_frames(90)
	var e := _error_deg(h, "UpperArm_L")
	assert_gt(e, 20.0, "under-powered shoulder sags (%.1f deg)" % e)


# ── Hit response ────────────────────────────────────────────────────────────

func test_hit_deflects_the_hand_and_the_muscle_recovers():
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(30)
	var hand: RigidBody3D = h.get_body("Hand_L")
	hand.apply_impulse(Vector3(0.0, 0.0, -8.0))
	var peak := 0.0
	var recovered_at := -1
	for i in 90:
		await wait_physics_frames(1)
		var e := _error_deg(h, "Hand_L")
		peak = maxf(peak, e)
		if recovered_at < 0 and i > 3 and e < 5.0:
			recovered_at = i
	assert_gt(peak, 10.0, "an 8 N.s hit visibly deflects the hand (peak %.1f deg)" % peak)
	assert_true(recovered_at >= 0, "the wrist muscle brings the hand back under 5 deg within 1.5 s (peak %.1f)" % peak)


# ── Tick rates ──────────────────────────────────────────────────────────────

func test_hold_at_30hz_does_not_diverge():
	Engine.physics_ticks_per_second = 30
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(90)  # 3 s
	for rig_name: String in ["Chest", "UpperArm_L", "LowerArm_L", "UpperLeg_L"]:
		var e := _error_deg(h, rig_name)
		assert_lt(e, 8.0, "%s holds at 30 Hz (%.2f deg)" % [rig_name, e])


func test_hold_at_120hz():
	Engine.physics_ticks_per_second = 120
	var h = await _spawn(_tuning(), false)
	await wait_physics_frames(180)  # 1.5 s
	for rig_name: String in ["Chest", "UpperArm_L", "LowerArm_L", "UpperLeg_L"]:
		var e := _error_deg(h, rig_name)
		assert_lt(e, 4.0, "%s holds at 120 Hz (%.2f deg)" % [rig_name, e])


# ── State machine still works on motors ─────────────────────────────────────

func test_ragdoll_and_recovery_cycle_in_motor_mode():
	var t := _tuning()
	t.ragdoll_force_recovery_time = 0.4
	t.recovery_duration = 0.6
	t.safety_timeout = 0.8
	t.pose_blend_duration = 0.2
	t.settle_duration = 0.15
	var h = await _spawn(t, true)
	await wait_physics_frames(5)
	watch_signals(h.controller)
	h.controller.trigger_ragdoll()
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 8.0)
	assert_true(recovered, "recovery completes with motors")
	assert_eq(h.controller.get_state(), ActiveRagdollController.State.NORMAL)
	await wait_physics_frames(60)
	var cmd: Dictionary = h.spring.get_motor_command("Chest")
	assert_gt(float(cmd.limit), 100.0, "muscles are back at full torque after recovery")


func test_stagger_stays_on_its_feet_and_recovers_in_motor_mode():
	# The stagger floor (10 % strength) is 32 % torque through the strength curve:
	# weak but standing. Linear torque collapsed the character into a ragdoll.
	var t := _tuning()
	t.stagger_duration = 1.0
	t.steps_enabled = false
	var h = await _spawn(t, true)
	await wait_physics_frames(5)
	watch_signals(h.controller)
	h.controller.trigger_stagger(Vector3.FORWARD)
	var finished: bool = await wait_for_signal(h.controller.stagger_finished, 5.0)
	assert_true(finished, "stagger recovers to NORMAL")
	assert_signal_not_emitted(h.controller, "ragdoll_started")
	assert_gt(h.get_body("Hips").global_position.y, 0.6, "still standing")


func test_knocked_down_character_gets_up_upright():
	# Regression: after a ragdoll on the ground the pelvis lies 90 deg+ from the
	# orientation its world joint was anchored in; Jolt's swing-twist motor axes
	# degenerate there and the get-up drove the character to the wrong stable
	# point — it stood up UPSIDE DOWN (seen in shooting_range.tscn). The root joint
	# is re-anchored on large relative rotations and at recovery start.
	var t := _tuning()
	t.foot_ik_enabled = true  # the shipped configuration: feet planted by IK, not colliding in NORMAL
	t.ragdoll_force_recovery_time = 1.0
	t.settle_duration = 0.3
	t.recovery_duration = 1.5
	t.safety_timeout = 2.5
	var h = await _spawn(t, true)
	await wait_physics_frames(10)
	var hips: RigidBody3D = h.get_body("Hips")
	hips.apply_impulse(Vector3(90.0, 0.0, 30.0))  # knock it over so it lands lying
	h.controller.trigger_ragdoll()
	await wait_physics_frames(60)
	assert_lt(hips.global_basis.y.dot(Vector3.UP), 0.8, "the character actually went down")
	var recovered: bool = await wait_for_signal(h.controller.recovery_finished, 12.0)
	assert_true(recovered, "recovery finished")
	await wait_physics_frames(90)
	assert_gt(hips.global_basis.y.dot(Vector3.UP), 0.9, "pelvis upright after getting up (up.dot = %.2f)" % hips.global_basis.y.dot(Vector3.UP))
	assert_lt(_error_deg(h, "Hips"), 15.0, "pelvis near its animation orientation")
	assert_gt(hips.global_position.y, 0.6, "standing height")


func test_switching_mode_at_runtime_disables_motors():
	var t := _tuning()
	var h = await _spawn(t, false)
	await wait_physics_frames(3)
	assert_true(bool(h.spring.get_motor_command("Chest").enabled))
	t.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
	h.character.refresh_tuning()
	await wait_physics_frames(2)
	assert_false(h.spring.is_motor_mode())
	assert_false(bool(h.spring.get_motor_command("Chest").enabled), "motors disabled after switching back")
