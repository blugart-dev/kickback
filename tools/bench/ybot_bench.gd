## Ybot muscle bench (docs/PLAN.md 0.5.0 acceptance). Loads the real demo character
## (assets/characters/ybot/ybot.tscn) with its AnimationPlayer in PHYSICS callback
## mode, builds the Kickback rig through KickbackSetup, and reports tracking numbers
## for both muscle modes:
##   IDLE   : "idle" clip, 1 s settle then 3 s measured (mean / max error over all bodies)
##   REACT  : "react_front" clip once, measured while it plays; SETTLE = the idle
##            error over the following second + the balance ratio at its end
##   HIT    : the bullet preset (ragdoll dice disabled) on the left hand through
##            KickbackCharacter.receive_hit (peak hand error, ticks until back under
##            5 deg, any joint stuck past a limit?)
##   CPU    : mean SpringResolver tick time (ms) during IDLE
##   SAG    : mean pelvis height below the resolver's own target during IDLE (mm);
##   FEET   : share of IDLE ticks on which both feet reported a ground contact
## Env: BENCH_HZ=30|60|120, BENCH_DIAG=1 (per-joint dump), BENCH_VARIANT=nofootik,
## nofootcol,support025,support05,support1,nopin,pin03,gain05,gain15,gain20,gain30,
## damp2,noff (comma-separated).
##
##   godot --headless --path . -s tools/bench/ybot_bench.gd
##   BENCH_HZ=30 godot --headless --path . -s tools/bench/ybot_bench.gd
## Standalone; not part of the plugin or the test suite.
extends SceneTree

const YBOT := "res://assets/characters/ybot/ybot.tscn"
const BULLET := "res://addons/kickback/presets/bullet.tres"
const MEASURED := ["Hips", "Spine", "Chest", "Head", "UpperArm_L", "LowerArm_L", "Hand_L",
	"UpperArm_R", "LowerArm_R", "Hand_R", "UpperLeg_L", "LowerLeg_L", "Foot_L",
	"UpperLeg_R", "LowerLeg_R", "Foot_R"]

var _results: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	seed(20260913)
	var hz := 60
	var env := OS.get_environment("BENCH_HZ")
	if env != "":
		hz = int(env)
	print("=== ybot bench: Godot %s, %s, %d Hz ===" % [Engine.get_version_info().string,
		ProjectSettings.get_setting("physics/3d/physics_engine"), hz])
	for mode in [RagdollTuning.MuscleMode.VELOCITY_OVERWRITE, RagdollTuning.MuscleMode.JOINT_MOTOR]:
		await _run_mode(mode, hz)
	print("\n%-18s | %-14s | %-14s | %-26s | %s" % ["mode", "IDLE mean/max", "REACT mean/max", "HIT peak / recover / stuck", "resolver ms/tick"])
	for line in _results:
		print(line)
	quit()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


func _run_mode(mode: int, hz: int) -> void:
	Engine.physics_ticks_per_second = hz
	Engine.max_physics_steps_per_frame = 32
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
	char_root.name = "Character"
	world.add_child(char_root)
	var model: Node = (load(YBOT) as PackedScene).instantiate()
	char_root.add_child(model)
	# The asset ships a baked PhysicalBoneSimulator3D for the comparison demo; drop it.
	var sim := model.find_child("PhysicalBoneSimulator3D", true, false)
	if sim:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
	var skeleton := KickbackSetup.find_skeleton(char_root)
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

	var tuning := RagdollTuning.create_default()
	tuning.muscle_mode = mode
	# BENCH_VARIANT: comma-separated experiments (nofootik, nopin, gain05, damp2, noff)
	var variant := OS.get_environment("BENCH_VARIANT")
	if "nofootik" in variant:
		tuning.foot_ik_enabled = false
	if "nopin" in variant:
		tuning.muscle_root_pin = 0.0
	if "pin03" in variant:
		tuning.muscle_root_pin = 0.3
	if "pin10" in variant:
		tuning.muscle_root_pin = 1.0
	if "rootforce5k" in variant:
		tuning.muscle_root_force = 5000.0
	if "rootforce10k" in variant:
		tuning.muscle_root_force = 10000.0
	if "nofootcol" in variant:
		tuning.foot_ik_disable_foot_collision = true  # pre-0.6.0: feet masked out, anchor carries the body
	if "support1" in variant:
		tuning.muscle_root_support = 1.0
	elif "support05" in variant:
		tuning.muscle_root_support = 0.5
	elif "support025" in variant:
		tuning.muscle_root_support = 0.25
	if "gain05" in variant:
		tuning.muscle_gain = 0.05
	if "gain15" in variant:
		tuning.muscle_gain = 0.15
	if "gain20" in variant:
		tuning.muscle_gain = 0.20
	if "gain30" in variant:
		tuning.muscle_gain = 0.30
	if "damp2" in variant:
		tuning.muscle_angular_damp = 2.0
	if "noff" in variant:
		tuning.spring_feed_forward = 0.0
	if variant != "":
		print("  variant: ", variant)
	var nodes := KickbackSetup.add_active_rig(char_root, skeleton, null, tuning)
	var kc: KickbackCharacter = nodes[nodes.size() - 1]
	var spring: SpringResolver = nodes[2]
	var builder: PhysicsRigBuilder = nodes[0]
	anim.play("idle")
	if not kc.is_setup_complete():
		await kc.setup_complete
	var label := "legacy" if mode == RagdollTuning.MuscleMode.VELOCITY_OVERWRITE else "JOINT_MOTOR"
	var warnings := kc.get_setup_warnings()
	if not warnings.is_empty():
		print("  [%s] setup warnings: %s" % [label, warnings])

	# IDLE
	if OS.get_environment("BENCH_DIAG") != "" and mode == RagdollTuning.MuscleMode.JOINT_MOTOR:
		var series := "  spine error per 5 ticks during settle:"
		for i in hz:
			await physics_frame
			if i % 5 == 0:
				series += " %.0f" % _error_deg(spring, builder, skeleton, "Spine")
		print(series)
	else:
		await _wait(hz)
	var cpu := {"sum": 0.0, "sag": 0.0, "feet": 0}  # lambdas capture by value; use a holder
	var hips: RigidBody3D = builder.get_bodies()["Hips"]
	var feet: Array = [builder.get_bodies().get("Foot_L"), builder.get_bodies().get("Foot_R")]
	var idle := await _measure(spring, builder, skeleton, hz * 3, func() -> void:
		cpu.sum += float(spring.get_last_tick_usec())
		# SAG: pelvis height below the resolver's own (foot-IK-shifted) target. FEET:
		# ticks on which both feet reported a ground contact (load-bearing feet).
		cpu.sag += spring.get_bone_target_global("Hips").origin.y - hips.global_position.y
		var both := true
		for f in feet:
			if not f or f.get_contact_count() == 0:
				both = false
		if both:
			cpu.feet += 1)
	var cpu_ms: float = cpu.sum / float(hz * 3) / 1000.0  # resolver tick only (ms)
	var sag_mm: float = cpu.sag / float(hz * 3) * 1000.0
	var feet_pct: float = 100.0 * float(cpu.feet) / float(hz * 3)
	if OS.get_environment("BENCH_DIAG") != "":
		_print_joint_diag(spring, builder, skeleton, label)

	# HIT (from the settled idle, before the react clip: with load-bearing feet a
	# violent clip leaves the feet where friction planted them, and a hit measured from
	# that stance measures the stance, not the muscle)
	var hand: RigidBody3D = builder.get_bodies()["Hand_L"]
	# Deterministic: the bullet preset's ragdoll dice roll is disabled so the number
	# measures the muscle response to the impulse + strength reduction, not a state
	# transition; seed() at start pins the stagger sway phase.
	var profile: ImpactProfile = (load(BULLET) as ImpactProfile).duplicate()
	profile.ragdoll_probability = 0.0
	var controller: ActiveRagdollController = nodes[3]
	var balance_before: float = controller.get_balance_ratio()
	kc.receive_hit(hand, Vector3(0.0, 0.0, -1.0), hand.global_position, profile)
	var peak := 0.0
	var recover := -1
	var stuck := false
	var worst_state: int = controller.get_state()
	for i in int(hz * 1.5):
		await physics_frame
		worst_state = maxi(worst_state, controller.get_state())
		var e := _error_deg(spring, builder, skeleton, "Hand_L")
		peak = maxf(peak, e)
		if recover < 0 and i > 3 and e < 5.0:
			recover = i
	# stuck past a limit: any joint angle beyond its authored bound + 15 deg after the hit
	var prof := builder.get_profile()
	for jd: JointDefinition in prof.joints:
		var ang: Vector3 = builder.get_joint_angles(jd.child_rig)
		if not ang.is_finite():
			continue
		var lims := [jd.limit_x, jd.limit_y, jd.limit_z]
		for k in 3:
			var lim: Vector2 = lims[k]
			if ang[k] < lim.x - 15.0 or ang[k] > lim.y + 15.0:
				stuck = true
	# REACT: the clip once, then 1 s of idle — SETTLE is the idle error over that second
	# (did the body, feet included, come back to the animation?) and the balance ratio
	# at its end.
	await _wait(hz)
	anim.play("react_front")
	var react_ticks := int(ceil(anim.current_animation_length * hz))
	var react := await _measure(spring, builder, skeleton, react_ticks, Callable())
	anim.play("idle")
	var settle := await _measure(spring, builder, skeleton, hz, Callable())
	var settle_balance: float = controller.get_balance_ratio()

	var line := "%-18s | %6.2f / %6.2f | %6.2f / %6.2f | %6.1f / %-6s / %-5s | %.3f | %+5.1f mm / %3.0f %%" % [
		label, idle[0], idle[1], react[0], react[1], peak, str(recover) if recover >= 0 else "never", str(stuck), cpu_ms, sag_mm, feet_pct]
	print(line)
	print("    hit: state reached %s (balance ratio before the hit %.2f)" % [ActiveRagdollController.State.keys()[worst_state], balance_before])
	print("    settle after react: idle error %.2f / %.2f, balance ratio %.2f" % [settle[0], settle[1], settle_balance])
	print("    idle per body: %s" % idle[2])
	print("    react per body: %s" % react[2])
	_results.append(line)
	world.queue_free()
	await _wait(3)


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


func _measure(spring: SpringResolver, builder: PhysicsRigBuilder, skeleton: Skeleton3D, ticks: int, per_tick: Callable) -> Array:
	var sum := 0.0
	var n := 0
	var worst := 0.0
	var per: Dictionary = {}
	for i in ticks:
		await physics_frame
		if per_tick.is_valid():
			per_tick.call()
		for rig: String in MEASURED:
			if rig not in builder.get_bodies():
				continue
			var e := _error_deg(spring, builder, skeleton, rig)
			sum += e
			n += 1
			worst = maxf(worst, e)
			per[rig] = per.get(rig, 0.0) + e
	var per_str := ""
	for rig: String in MEASURED:
		if rig in per:
			per_str += "%s=%.1f " % [rig, per[rig] / ticks]
	return [sum / maxf(n, 1), worst, per_str]


## Per-joint diagnostic: joint-space angles of the bodies vs of the animation (deg,
## in the joint limit frame), the authored limits, and the motor command.
func _print_joint_diag(spring: SpringResolver, builder: PhysicsRigBuilder, skeleton: Skeleton3D, label: String) -> void:
	print("  --- %s joint diag (body angles | anim angles | limits x/y/z | cmd) ---" % label)
	var sg := skeleton.global_transform
	for jd: JointDefinition in builder.get_profile().joints:
		var child := jd.child_rig
		var pi: int = skeleton.find_bone(builder.get_bone_name_for_body(jd.parent_rig))
		var ci: int = skeleton.find_bone(builder.get_bone_name_for_body(child))
		var body_ang: Vector3 = builder.get_joint_angles(child)
		var anim_ang: Vector3 = builder.get_joint_angles(child, sg * spring.get_animation_bone_global(pi), sg * spring.get_animation_bone_global(ci))
		var cmd: Dictionary = spring.get_motor_command(child)
		var joints: Dictionary = builder.get_joints()
		var pb: RigidBody3D = builder.get_bodies()[jd.parent_rig]
		var cb: RigidBody3D = builder.get_bodies()[child]
		var fp: Basis = (joints[child].frame_parent as Transform3D).basis
		var a: Basis = pb.global_basis.orthonormalized() * fp
		var relw: Vector3 = a.inverse() * (cb.angular_velocity - pb.angular_velocity)
		print("  %-11s body=(%6.1f %6.1f %6.1f) anim=(%6.1f %6.1f %6.1f) cmd=%s relwA=(%.2f %.2f %.2f) strength=%.2f" % [
			child, body_ang.x, body_ang.y, body_ang.z, anim_ang.x, anim_ang.y, anim_ang.z,
			cmd.target, relw.x, relw.y, relw.z, spring.get_bone_strength(child) / maxf(spring.get_base_strength(child), 0.001)])
