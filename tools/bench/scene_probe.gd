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
