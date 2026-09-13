## Step probe (docs/PLAN.md 0.6.0 StepBehavior). Loads the ybot idle, then moves the
## character root 0.25 m forward while the physical feet stay where friction planted
## them, and logs every tick-group: per-foot mismatch to the animation spot, contact,
## lock, step in flight, lift, the balance ratio and the step count — does the re-plant
## bring the feet under the body, how fast, and does it settle? Then a 150 N·s shove.
## Standalone; not part of the plugin or the suite.
##
##   godot --headless --path . -s tools/bench/step_probe.gd
##   PROBE_SCENARIO=react godot --headless --path . -s tools/bench/step_probe.gd
extends SceneTree

const YBOT := "res://assets/characters/ybot/ybot.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 32
	seed(20260913)
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
	var nodes := KickbackSetup.add_active_rig(char_root, skeleton, null, tuning)
	var kc: KickbackCharacter = nodes[nodes.size() - 1]
	var builder: PhysicsRigBuilder = nodes[0]
	var spring: SpringResolver = nodes[2]
	var controller: ActiveRagdollController = nodes[3]
	anim.play("idle")
	if not kc.is_setup_complete():
		await kc.setup_complete
	for i in 120:
		await physics_frame
	var sb: StepBehavior = null
	for b in controller.get_behaviors():
		if b is StepBehavior:
			sb = b
	var steps := {"n": 0}
	controller.step_started.connect(func(foot: String, target: Vector3) -> void:
		steps.n += 1
		print("    >> step %d: %s (%s) -> (%.2f, %.2f)" % [steps.n, foot, sb.last_step_reason, target.x, target.z]))

	if OS.get_environment("PROBE_SCENARIO") == "react":
		print("=== react_front clip, then idle: do the feet come back? ===")
		anim.play("react_front")
		var n := int(ceil(anim.current_animation_length * 60.0))
		for i in n:
			await physics_frame
		anim.play("idle")
		await _log(controller, builder, spring, skeleton, 180, 10)
		quit()
		return
	print("=== root moved +0.25 m forward (z); feet planted ===")
	char_root.position.z += 0.25
	await _log(controller, builder, spring, skeleton, 150, 10)
	print("=== 150 N·s shove +X at the chest ===")
	var chest: RigidBody3D = builder.get_bodies()["Chest"]
	chest.apply_central_impulse(Vector3(150.0, 0.0, 0.0))
	await _log(controller, builder, spring, skeleton, 150, 10)
	quit()


func _log(controller: ActiveRagdollController, builder: PhysicsRigBuilder, spring: SpringResolver, skeleton: Skeleton3D, ticks: int, every: int) -> void:
	var ik: FootIKSolver = controller._foot_ik
	var ctx: BehaviorContext = controller._behavior_ctx
	var sb: StepBehavior = null
	for b in controller.get_behaviors():
		if b is StepBehavior:
			sb = b
	for i in ticks:
		await physics_frame
		if i % every != 0:
			continue
		var bal := controller.get_balance()
		var line := "t=%4.2f ratio=%.2f margin=%+.3f state=%s" % [i / 60.0, bal.ratio, bal.margin, controller.get_state_name()]
		for foot in ["Foot_L", "Foot_R"]:
			var fb: RigidBody3D = builder.get_bodies()[foot]
			var mismatch: float = sb._mismatch(ctx, foot) if sb else -1.0
			line += " | %s mis=%.3f c=%d lock=%s step=%s lift=%.3f" % [foot.substr(5), mismatch, bal.contacts.get(foot, 0),
				"Y" if ik.is_foot_locked(foot) else "n", "Y" if ik.is_foot_stepping(foot) else "n",
				fb.global_position.y - 0.062]
		var err := 0.0
		for rig in ["UpperLeg_L", "LowerLeg_L", "UpperLeg_R", "LowerLeg_R"]:
			err += _error_deg(spring, builder, skeleton, rig)
		line += " | legs err %.1f" % (err / 4.0)
		print(line)


func _error_deg(spring: SpringResolver, builder: PhysicsRigBuilder, skeleton: Skeleton3D, rig: String) -> float:
	var body: RigidBody3D = builder.get_bodies().get(rig)
	if not body:
		return 0.0
	var idx: int = skeleton.find_bone(builder.get_bone_name_for_body(rig))
	var target := (skeleton.global_transform * spring.get_animation_bone_global(idx)).basis.orthonormalized()
	var q := (target * body.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	return rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))
