## Rig self-overlap probe (docs/PLAN.md 0.6.0 "ragdoll look": self-collision). Loads the
## ybot in JOINT_MOTOR mode and reports every pair of the rig's own bodies whose
## collision shapes geometrically overlap (a space query — collision exceptions do not
## hide anything) at: the build pose, the settled idle, and a settled ragdoll on the
## ground; plus the idle tracking error, so `self_collision` on/off can be compared.
## Standalone; not part of the plugin or the suite.
##
##   godot --headless --path . -s tools/bench/overlap_probe.gd
##   PROBE_SELF_COLLISION=0 godot --headless --path . -s tools/bench/overlap_probe.gd
extends SceneTree

const YBOT := "res://assets/characters/ybot/ybot.tscn"
const MEASURED := ["Hips", "Spine", "Chest", "Head", "UpperArm_L", "LowerArm_L", "Hand_L",
	"UpperArm_R", "LowerArm_R", "Hand_R", "UpperLeg_L", "LowerLeg_L", "Foot_L",
	"UpperLeg_R", "LowerLeg_R", "Foot_R"]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 32
	seed(20260913)
	# Default follows the tuning (on since 0.6.0); PROBE_SELF_COLLISION=0 turns it off.
	var self_col := OS.get_environment("PROBE_SELF_COLLISION") != "0"
	await _run_case(self_col)
	quit()


func _run_case(self_col: bool) -> void:
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
	tuning.self_collision = self_col
	var nodes := KickbackSetup.add_active_rig(char_root, skeleton, null, tuning)
	var kc: KickbackCharacter = nodes[nodes.size() - 1]
	var spring: SpringResolver = nodes[2]
	var builder: PhysicsRigBuilder = nodes[0]
	anim.play("idle")
	if not kc.is_setup_complete():
		await kc.setup_complete
	print("\n=== self_collision=%s ===" % str(self_col))
	await physics_frame
	await physics_frame
	_report_overlaps("build pose (second tick)", builder, world)
	_report_rest_overlaps(builder, skeleton)

	for i in 120:
		await physics_frame
	_report_overlaps("idle, settled 2 s", builder, world)
	var err := await _measure(spring, builder, skeleton, 120)
	print("  idle tracking over 2 s: mean %.2f deg, max %.2f deg" % [err[0], err[1]])

	kc.trigger_ragdoll()
	for i in 240:
		await physics_frame
	_report_overlaps("ragdoll, 4 s on the ground", builder, world)
	world.queue_free()
	for i in 3:
		await physics_frame


## Non-adjacent body pairs whose shapes overlap right now (PhysicsRigBuilder's space
## query; collision exceptions do not hide anything), plus the safety-net exclusions.
func _report_overlaps(label: String, builder: PhysicsRigBuilder, _world: Node3D) -> void:
	var listed := PackedStringArray()
	for pair: Array in builder.find_overlapping_pairs():
		listed.append("%s+%s" % [pair[0], pair[1]])
	print("  [%s] non-adjacent overlapping pairs: %d — %s" % [label, listed.size(), ", ".join(listed) if not listed.is_empty() else "none"])


func _report_rest_overlaps(builder: PhysicsRigBuilder, _skeleton: Skeleton3D) -> void:
	var listed := PackedStringArray()
	for pair: Array in builder.get_self_collision_exclusions():
		listed.append("%s+%s" % [pair[0], pair[1]])
	print("  [build-pose safety net] pairs excluded from self-collision: %d — %s" % [listed.size(), ", ".join(listed) if not listed.is_empty() else "none"])


func _anim_basis(spring: SpringResolver, builder: PhysicsRigBuilder, skeleton: Skeleton3D, rig: String) -> Basis:
	var idx: int = skeleton.find_bone(builder.get_bone_name_for_body(rig))
	return (skeleton.global_transform * spring.get_animation_bone_global(idx)).basis.orthonormalized()


func _error_deg(spring: SpringResolver, builder: PhysicsRigBuilder, skeleton: Skeleton3D, rig: String) -> float:
	var body: RigidBody3D = builder.get_bodies().get(rig)
	if not body:
		return 0.0
	var q := (_anim_basis(spring, builder, skeleton, rig) * body.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	return rad_to_deg(2.0 * acos(clampf(q.w, -1.0, 1.0)))


func _measure(spring: SpringResolver, builder: PhysicsRigBuilder, skeleton: Skeleton3D, ticks: int) -> Array:
	var sum := 0.0
	var n := 0
	var worst := 0.0
	for i in ticks:
		await physics_frame
		for rig: String in MEASURED:
			if rig not in builder.get_bodies():
				continue
			var e := _error_deg(spring, builder, skeleton, rig)
			sum += e
			n += 1
			worst = maxf(worst, e)
	return [sum / maxf(n, 1), worst]
