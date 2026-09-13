## Foot-contact probe (docs/PLAN.md 0.6.0 "feet load-bearing"). Loads the ybot with the
## idle clip in JOINT_MOTOR mode, once with the feet colliding and once without, and
## after a settle prints for each foot: body height, collision-box bottom vs the floor,
## animation target height, joint angles (body vs animation), contact count, and the
## pelvis height vs its target. Standalone; not part of the plugin or the suite.
##
##   godot --headless --path . -s tools/bench/foot_probe.gd
##   PROBE_SECONDS=4 godot --headless --path . -s tools/bench/foot_probe.gd
extends SceneTree

const YBOT := "res://assets/characters/ybot/ybot.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 32
	var secs := 2.0
	var env := OS.get_environment("PROBE_SECONDS")
	if env != "":
		secs = float(env)
	for feet_collide in [false, true]:
		await _run_case(feet_collide, secs)
	quit()


func _run_case(feet_collide: bool, secs: float) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.collision_layer = KickbackLayers.ENVIRONMENT_LAYER
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(40.0, 1.0, 40.0)
	gshape.shape = gbox
	ground.add_child(gshape)
	ground.position.y = -0.5
	world.add_child(ground)

	var char_root := Node3D.new()
	world.add_child(char_root)
	var model: Node = (load(YBOT) as PackedScene).instantiate()
	char_root.add_child(model)
	var sim := model.find_child("PhysicalBoneSimulator3D", true, false)
	if sim:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
	var skeleton := KickbackSetup.find_skeleton(char_root)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	var tuning := RagdollTuning.create_default()
	tuning.muscle_mode = RagdollTuning.MuscleMode.JOINT_MOTOR
	tuning.foot_ik_disable_foot_collision = not feet_collide
	var nodes := KickbackSetup.add_active_rig(char_root, skeleton, null, tuning)
	var kc: KickbackCharacter = nodes[nodes.size() - 1]
	var spring: SpringResolver = nodes[2]
	var builder: PhysicsRigBuilder = nodes[0]
	anim.play("idle")
	if not kc.is_setup_complete():
		await kc.setup_complete
	var bodies := builder.get_bodies()
	for b: RigidBody3D in bodies.values():
		b.contact_monitor = true
		b.max_contacts_reported = 8
	for i in int(secs * 60.0):
		await physics_frame

	print("\n=== feet %s (ankle_height=%.3f, ground y=0) ===" % ["COLLIDING" if feet_collide else "NOT colliding", tuning.foot_ik_ankle_height])
	var sg := skeleton.global_transform
	for rig in ["Hips", "Foot_L", "Foot_R", "LowerLeg_L", "LowerLeg_R"]:
		var body: RigidBody3D = bodies[rig]
		var idx: int = skeleton.find_bone(builder.get_bone_name_for_body(rig))
		var target: Transform3D = sg * spring.get_animation_bone_global(idx)
		var line := "%-10s body y=%.3f target y=%.3f dy=%+.3f" % [rig, body.global_position.y, target.origin.y, body.global_position.y - target.origin.y]
		var shape: CollisionShape3D = body.get_child(0) as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			var box := shape.shape as BoxShape3D
			var half := box.size * 0.5
			var lo := INF
			var lo_t := INF
			var xf := shape.global_transform
			var xf_t := target * shape.transform
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var corner := Vector3(sx * half.x, sy * half.y, sz * half.z)
						lo = minf(lo, (xf * corner).y)
						lo_t = minf(lo_t, (xf_t * corner).y)
			line += "  box=%s bottom(body)=%+.3f bottom(anim target)=%+.3f" % [box.size, lo, lo_t]
		if body.contact_monitor:
			line += "  contacts=%d" % body.get_contact_count()
		if rig.begins_with("Foot"):
			var pi: int = skeleton.find_bone(builder.get_bone_name_for_body("LowerLeg_" + rig.substr(5)))
			var ang: Vector3 = builder.get_joint_angles(rig)
			var ang_t: Vector3 = builder.get_joint_angles(rig, sg * spring.get_animation_bone_global(pi), target)
			line += "  ankle body=(%.1f %.1f %.1f) anim=(%.1f %.1f %.1f)" % [ang.x, ang.y, ang.z, ang_t.x, ang_t.y, ang_t.z]
		print(line)
	var profile := builder.get_profile()
	var total_mass := 0.0
	for b: RigidBody3D in bodies.values():
		total_mass += b.mass
	print("total mass=%.1f kg (weight %.0f N)" % [total_mass, total_mass * 9.81])
	for bd: BoneDefinition in profile.bones:
		if bd.rig_name == "Foot_L":
			var fb: RigidBody3D = bodies["Foot_L"]
			var shape: CollisionShape3D = fb.get_child(0)
			var ankle_idx: int = skeleton.find_bone(bd.skeleton_bone)
			var toe_idx: int = skeleton.find_bone(bd.child_bone)
			var ankle: Transform3D = sg * skeleton.get_bone_global_pose(ankle_idx)
			var toe: Transform3D = sg * skeleton.get_bone_global_pose(toe_idx)
			print("Foot_L def: shape=%s box=%s offset=%.2f mass=%.1f bone=%s child=%s" % [bd.shape_type, bd.box_size, bd.shape_offset, bd.mass, bd.skeleton_bone, bd.child_bone])
			print("  ankle world=%s  toe world=%s  ankle->toe=%s (len %.3f)" % [ankle.origin, toe.origin, toe.origin - ankle.origin, ankle.origin.distance_to(toe.origin)])
			print("  ankle bone axes: X=%s Y=%s Z=%s" % [ankle.basis.x, ankle.basis.y, ankle.basis.z])
			print("  shape local pos=%s rot(deg)=%s  body basis Y=%s" % [shape.position, shape.rotation_degrees, fb.global_basis.y])
	var total_vertical := 0.0
	for rig: String in bodies:
		var b: RigidBody3D = bodies[rig]
		var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
		var imp := Vector3.ZERO
		var n := st.get_contact_count() if st else 0
		for k in n:
			imp += st.get_contact_impulse(k)
		if n > 0:
			print("%s contacts=%d impulse sum=%s (~force %s N)" % [rig, n, imp, imp * 60.0])
		total_vertical += imp.y * 60.0
	print("ground carries %.0f N of %.0f N (%.0f %%); the rest is the root anchor" % [total_vertical, total_mass * 9.81, 100.0 * total_vertical / (total_mass * 9.81)])
	var controller: ActiveRagdollController = nodes[3]
	var bs: Dictionary = controller.get_balance_state()
	print("balance: ratio=%.2f com_xz=(%.3f %.3f) support_center_xz=(%.3f %.3f)" % [bs.balance_ratio, bs.com.x, bs.com.z, bs.support_center.x, bs.support_center.z])
	for foot in ["Foot_L", "Foot_R"]:
		var fb: RigidBody3D = bodies[foot]
		var tgt: Transform3D = spring.get_bone_target_global(foot)
		var e := fb.global_position - tgt.origin
		print("%s xz error vs target: (%+.3f %+.3f) y %+.3f  body xz=(%.3f %.3f)" % [foot, e.x, e.z, e.y, fb.global_position.x, fb.global_position.z])
	world.queue_free()
	for i in 3:
		await physics_frame
