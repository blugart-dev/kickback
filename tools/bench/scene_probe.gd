## Loads a demo scene as-is and logs what each Kickback character does with NO input:
## state, pelvis height, lowest body point (ground clipping), worst body error,
## balance ratio, foot-IK pelvis offset, root motor command.
##   godot --headless --path . -s tools/bench/scene_probe.gd
##   PROBE_SCENE=res://demo/shooting_range.tscn PROBE_MODE=legacy PROBE_SECONDS=8
extends SceneTree

var _scene_path := "res://demo/shooting_range.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var env := OS.get_environment("PROBE_SCENE")
	if env != "":
		_scene_path = env
	var seconds := 8.0
	if OS.get_environment("PROBE_SECONDS") != "":
		seconds = float(OS.get_environment("PROBE_SECONDS"))
	var scene: Node = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var chars: Array = scene.find_children("*", "KickbackCharacter", true, false)
	print("=== probe %s: %d characters ===" % [_scene_path, chars.size()])
	for kc: KickbackCharacter in chars:
		if not kc.is_setup_complete():
			await kc.setup_complete
	if OS.get_environment("PROBE_MODE") == "legacy":
		for kc: KickbackCharacter in chars:
			kc.ragdoll_tuning.muscle_mode = RagdollTuning.MuscleMode.VELOCITY_OVERWRITE
			kc.refresh_tuning()
		print("  mode forced: VELOCITY_OVERWRITE")
	var kc0: KickbackCharacter = chars[0]
	var ctrl: ActiveRagdollController = kc0.get_active_controller()
	var builder: PhysicsRigBuilder = kc0.get_parent().find_child("PhysicsRigBuilder", false, false)
	var spring: SpringResolver = kc0.get_parent().find_child("SpringResolver", false, false)
	var skel: Skeleton3D = KickbackSetup.find_skeleton(kc0.get_parent())
	var anim: AnimationPlayer = kc0.get_parent().find_child("AnimationPlayer", true, false)
	print("  tuning: mode=%s gain=%.2f root_torque=%.0f root_pin=%.2f foot_ik=%s foot_col_off=%s" % [
		"JOINT_MOTOR" if spring.is_motor_mode() else "legacy", kc0.ragdoll_tuning.muscle_gain,
		kc0.ragdoll_tuning.muscle_root_torque, kc0.ragdoll_tuning.muscle_root_pin,
		kc0.ragdoll_tuning.foot_ik_enabled, kc0.ragdoll_tuning.foot_ik_disable_foot_collision])
	if anim:
		print("  anim: current='%s' playing=%s callback=%s" % [anim.current_animation, anim.is_playing(), anim.callback_mode_process])
	var sim := kc0.get_parent().find_child("PhysicalBoneSimulator3D", true, false)
	print("  PhysicalBoneSimulator3D present: %s%s" % [sim != null, (" active=%s" % sim.active) if sim else ""])
	print("  root: %s at %s" % [kc0.get_parent().name, kc0.get_parent().global_position])
	var hz := Engine.physics_ticks_per_second
	var ticks := int(seconds * hz)
	var line := ""
	var worst_dip := INF
	for i in ticks:
		await physics_frame
		if i % (hz / 4) == 0:
			var bodies: Dictionary = builder.get_bodies()
			var low := INF
			var low_name := ""
			var worst := 0.0
			var worst_name := ""
			for rig: String in bodies:
				var b: RigidBody3D = bodies[rig]
				if b.global_position.y < low:
					low = b.global_position.y
					low_name = rig
				var e := _err(spring, builder, skel, rig)
				if e > worst:
					worst = e
					worst_name = rig
			worst_dip = minf(worst_dip, low)
			var hips: RigidBody3D = bodies[ctrl.get_root_rig()]
			var cmd: Dictionary = spring.get_motor_command(ctrl.get_root_rig())
			var po := 0.0
			if ctrl._foot_ik:
				po = ctrl._foot_ik._pelvis_offset
			var st: Dictionary = spring._bones[ctrl.get_root_rig()]
			var tgt_y: float = (st.target_xform as Transform3D).origin.y
			var anim_y: float = (skel.global_transform * spring.get_animation_bone_global(st.bone_idx)).origin.y
			line += "   hips: tgtY=%.3f animY=%.3f vY=%.3f strength=%.2f base=%.2f pinOverride=%s\n" % [
				tgt_y, anim_y, hips.linear_velocity.y, st.strength, st.base_strength, str(spring._target_overrides.has(ctrl.get_root_rig()))]
			line += "t=%.2f %s bal=%.2f hipsY=%.3f low=%s@%.3f worst=%s@%.0f pelvisOff=%.3f rootCmd=%.2f\n" % [
				float(i) / hz, ctrl.get_state_name(), ctrl.get_balance_ratio(), hips.global_position.y,
				low_name, low, worst_name, worst, po, (cmd.get("target", Vector3.ZERO) as Vector3).length()]
	print(line)
	print("  lowest body point over the run: %.3f (ground is y=0)" % worst_dip)
	if OS.get_environment("PROBE_TRACE") != "":
		# Per-tick pelvis trace: y and vertical velocity, to see any bounce.
		var hips_b: RigidBody3D = builder.get_bodies()[ctrl.get_root_rig()]
		var tr := "  pelvis per tick (y|vY): "
		var ymin := INF
		var ymax := -INF
		for i in 90:
			await physics_frame
			ymin = minf(ymin, hips_b.global_position.y)
			ymax = maxf(ymax, hips_b.global_position.y)
			if i % 3 == 0:
				tr += "%.3f|%+.2f " % [hips_b.global_position.y, hips_b.linear_velocity.y]
		print(tr)
		print("  pelvis y range over 1.5 s: %.3f .. %.3f (%.1f mm peak-to-peak)" % [ymin, ymax, (ymax - ymin) * 1000.0])
	# PROBE_ACTION=ragdoll: knock every character down at 1 s, let them recover, and
	# report the recovered pose (pelvis upright? joint-space errors? lowest point?).
	if OS.get_environment("PROBE_ACTION") == "ragdoll":
		for i in hz:
			await physics_frame
		for kc: KickbackCharacter in chars:
			var c: ActiveRagdollController = kc.get_active_controller()
			var b: PhysicsRigBuilder = kc.get_parent().find_child("PhysicsRigBuilder", false, false)
			var hips_b: RigidBody3D = b.get_bodies()[c.get_root_rig()]
			hips_b.apply_impulse(Vector3(40.0, 0.0, 30.0))
			c.trigger_ragdoll()
		print("  --- ragdoll triggered on all characters; waiting for recovery ---")
		var deadline := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < deadline:
			await physics_frame
			var all_normal := true
			for kc: KickbackCharacter in chars:
				if kc.get_active_controller().get_state() != ActiveRagdollController.State.NORMAL:
					all_normal = false
			if all_normal:
				break
		# Get-up timeline: the pose the blend delivered (t=0), then 1 s and 3 s later —
		# does a standing character on load-bearing feet hold or degrade?
		for label in ["at recovery_finished", "+1 s", "+3 s"]:
			print("  --- %s ---" % label)
			for kc: KickbackCharacter in chars:
				var c: ActiveRagdollController = kc.get_active_controller()
				var b: PhysicsRigBuilder = kc.get_parent().find_child("PhysicsRigBuilder", false, false)
				var sp: SpringResolver = kc.get_parent().find_child("SpringResolver", false, false)
				var sk: Skeleton3D = KickbackSetup.find_skeleton(kc.get_parent())
				var hips_b: RigidBody3D = b.get_bodies()[c.get_root_rig()]
				var legs := ""
				for rig: String in ["UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]:
					legs += "%s=%.0f " % [rig, _err(sp, b, sk, rig)]
				var feet := ""
				for foot: String in ["Foot_L", "Foot_R"]:
					var fb: RigidBody3D = b.get_bodies()[foot]
					var e: Vector3 = fb.global_position - sp.get_bone_target_global(foot).origin
					feet += "%s xz=(%+.2f %+.2f) contacts=%d  " % [foot, e.x, e.z, fb.get_contact_count()]
					var tgt: Transform3D = sp.get_bone_target_global(foot)
				print("  %s: hipsY=%.2f (target %.2f) support_override=%.2f bal=%.2f | %s| %s" % [kc.get_parent().name, hips_b.global_position.y,
					sp.get_bone_target_global(c.get_root_rig()).origin.y, sp.get_root_support_override(), c.get_balance_ratio(), legs, feet])
			for i in (hz if label == "at recovery_finished" else hz * 2):
				await physics_frame
		if OS.get_environment("PROBE_REBUILD") != "":
			# Experiment: rebuild every rig joint constraint (reassign node_b) after recovery.
			for kc: KickbackCharacter in chars:
				var b2: PhysicsRigBuilder = kc.get_parent().find_child("PhysicsRigBuilder", false, false)
				for child_rig: String in b2.get_joints():
					var jj: Generic6DOFJoint3D = b2.get_joints()[child_rig].joint
					var pth := jj.node_b
					jj.node_b = NodePath()
					jj.node_b = pth
			print("  --- joints rebuilt; waiting 2 s ---")
			for i in hz * 2:
				await physics_frame
		for kc: KickbackCharacter in chars:
			var c: ActiveRagdollController = kc.get_active_controller()
			var b: PhysicsRigBuilder = kc.get_parent().find_child("PhysicsRigBuilder", false, false)
			var sp: SpringResolver = kc.get_parent().find_child("SpringResolver", false, false)
			var sk: Skeleton3D = KickbackSetup.find_skeleton(kc.get_parent())
			var hips_b: RigidBody3D = b.get_bodies()[c.get_root_rig()]
			var worst := 0.0
			var worst_name := ""
			var low := INF
			for rig: String in b.get_bodies():
				var e: float = _err(sp, b, sk, rig)
				if e > worst:
					worst = e
					worst_name = rig
				low = minf(low, (b.get_bodies()[rig] as RigidBody3D).global_position.y)
			print("  %s: state=%s pelvis up.dot(UP)=%.2f hipsY=%.2f worst=%s@%.0f deg lowest=%.3f" % [
				kc.get_parent().name, c.get_state_name(), hips_b.global_basis.y.dot(Vector3.UP), hips_b.global_position.y, worst_name, worst, low])
			if worst > 40.0:
				var sg := sk.global_transform
				var joints: Dictionary = b.get_joints()
				for jd: JointDefinition in b.get_profile().joints:
					var child := jd.child_rig
					var pi: int = sk.find_bone(b.get_bone_name_for_body(jd.parent_rig))
					var ci: int = sk.find_bone(b.get_bone_name_for_body(child))
					var body_ang: Vector3 = b.get_joint_angles(child)
					var anim_ang: Vector3 = b.get_joint_angles(child, sg * sp.get_animation_bone_global(pi), sg * sp.get_animation_bone_global(ci))
					var cmd: Dictionary = sp.get_motor_command(child)
					var pb: RigidBody3D = b.get_bodies()[jd.parent_rig]
					var cb: RigidBody3D = b.get_bodies()[child]
					var fp: Basis = (joints[child].frame_parent as Transform3D).basis
					var a: Basis = pb.global_basis.orthonormalized() * fp
					var relw: Vector3 = a.inverse() * (cb.angular_velocity - pb.angular_velocity)
					var e: float = _err(sp, b, sk, child)
					if e > 15.0:
						print("     %-11s err=%3.0f body=(%6.1f %6.1f %6.1f) anim=(%6.1f %6.1f %6.1f) cmd=%s force_limit=%.1f strength=%.2f/%.2f relwA=(%.2f %.2f %.2f)" % [
							child, e, body_ang.x, body_ang.y, body_ang.z, anim_ang.x, anim_ang.y, anim_ang.z,
							cmd.get("target"), float(cmd.get("limit", -1.0)), sp.get_bone_strength(child), sp.get_base_strength(child), relw.x, relw.y, relw.z])
				print("     fatigue=%.2f pain=%.2f injuries=%s state=%s" % [c.get_fatigue(), c.get_pain(), c.get_all_injuries(), c.get_state_name()])
	# All characters: a compact summary sampled every 2 s over a longer window.
	var long_s := 0.0
	if OS.get_environment("PROBE_ALL_SECONDS") != "":
		long_s = float(OS.get_environment("PROBE_ALL_SECONDS"))
	if long_s > 0.0:
		print("  --- all characters, every 2 s for %.0f s: state/hipsY/lowest/worstErr/balance ---" % long_s)
		var per_char: Array = []
		for kc: KickbackCharacter in chars:
			per_char.append({
				"ctrl": kc.get_active_controller(),
				"builder": kc.get_parent().find_child("PhysicsRigBuilder", false, false),
				"spring": kc.get_parent().find_child("SpringResolver", false, false),
				"skel": KickbackSetup.find_skeleton(kc.get_parent()),
				"name": kc.get_parent().name,
				"min_low": INF, "max_err": 0.0,
			})
		for i in int(long_s * hz):
			await physics_frame
			var sample := i % (hz * 2) == 0
			var row := "  t=%5.1f" % (float(i) / hz)
			for c: Dictionary in per_char:
				var b: PhysicsRigBuilder = c.builder
				var bodies: Dictionary = b.get_bodies()
				var low := INF
				var worst := 0.0
				for rig: String in bodies:
					low = minf(low, (bodies[rig] as RigidBody3D).global_position.y)
					worst = maxf(worst, _err(c.spring, b, c.skel, rig))
				c.min_low = minf(c.min_low, low)
				c.max_err = maxf(c.max_err, worst)
				if sample:
					var ctl: ActiveRagdollController = c.ctrl
					var hips: RigidBody3D = bodies[ctl.get_root_rig()]
					row += " | %s %s %.2f/%.2f/%.0f/%.2f" % [c.name, ctl.get_state_name().substr(0, 3), hips.global_position.y, low, worst, ctl.get_balance_ratio()]
			if sample:
				print(row)
		for c: Dictionary in per_char:
			print("  %s: lowest point %.3f, worst error %.0f deg" % [c.name, c.min_low, c.max_err])
	quit()


func _err(spring: SpringResolver, builder: PhysicsRigBuilder, skel: Skeleton3D, rig: String) -> float:
	var idx: int = skel.find_bone(builder.get_bone_name_for_body(rig))
	var target: Basis = (skel.global_transform * spring.get_animation_bone_global(idx)).basis.orthonormalized()
	var body: RigidBody3D = builder.get_bodies()[rig]
	var q := (target * body.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	return rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))
