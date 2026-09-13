extends GutTest
const RigHarness := preload("res://test/helpers/rig_harness.gd")
func test_dbg_zero_limit_latch():
	for variant in ["limit 0 then restore", "limit 0 then restore + flag toggle", "limit 0.01 then restore"]:
		var t := RagdollTuning.create_default()
		t.foot_ik_enabled = false
		t.stagger_sway_strength = 0.0
		var h = RigHarness.new()
		add_child_autoqfree(h)
		h.setup(t, null, false)
		assert_true(await h.await_ready(60))
		await wait_physics_frames(10)
		var j: Generic6DOFJoint3D = h.rig_builder.get_joints()["Head"].joint
		var idx: int = h.skeleton.find_bone("mixamorig_Head")
		# Bypass the resolver for 10 ticks: hold the head motor at zero (or tiny) limit.
		var zero := 0.01 if variant.begins_with("limit 0.01") else 0.0
		for i in 10:
			j.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, zero)
			j.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, zero)
			j.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, zero)
			await wait_physics_frames(1)
		if variant.ends_with("flag toggle"):
			for k in 2:
				j.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, k == 1)
				j.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, k == 1)
				j.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, k == 1)
		# The resolver restores the limit (30 N.m) each tick from now on. Command a nod.
		h.skeleton.set_bone_pose_rotation(idx, Quaternion(Vector3.RIGHT, deg_to_rad(30.0)))
		await wait_physics_frames(60)
		var ang: Vector3 = h.rig_builder.get_joint_angles("Head")
		print("DBG %-36s head joint after 30 deg nod command: X=%.1f (limit now %.1f, flag %s)" % [variant, ang.x, j.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT), j.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)])
		h.queue_free()
		await wait_physics_frames(2)
	pass_test("dbg")
