## Phase-2 muscle spike (docs/AUDIT_2026-09-12.md §8): A/B the shipped velocity-
## overwrite SpringResolver against a torque-bounded MOTOR muscle layer that
## drives each Generic6DOFJoint3D's angular motor (velocity mode, force limit =
## muscle torque) toward the animation's joint-space target, with real gravity.
##
## Standalone, headless, no plugin files modified:
##   godot --headless --path . -s tools/spike/motor_spike.gd
##
## Steps: (1) calibrate the motor target-velocity axis mapping under Jolt on one
## joint; (2) for each mode x tick rate, run: HOLD (static pose, gravity),
## TRACK (sine targets on chest + left arm), HIT (8 N.s impulse on the left
## hand) and report mean / max tracking error and hit peak + recovery.
extends SceneTree

const RigHarness := preload("res://test/helpers/rig_harness.gd")
const GODOT_EXE_NOTE := "run with the project's Godot 4.7.2 + Jolt"

## Muscle torque limits (N.m) per rig body's parent joint, spike values.
const TORQUE := {
	"Spine": 150.0, "Chest": 150.0, "Head": 30.0,
	"UpperArm_L": 60.0, "LowerArm_L": 40.0, "Hand_L": 10.0,
	"UpperArm_R": 60.0, "LowerArm_R": 40.0, "Hand_R": 10.0,
	"UpperLeg_L": 200.0, "LowerLeg_L": 150.0, "Foot_L": 60.0,
	"UpperLeg_R": 200.0, "LowerLeg_R": 150.0, "Foot_R": 60.0,
}
const MEASURED := ["Spine", "Chest", "Head", "UpperArm_L", "LowerArm_L", "Hand_L",
	"UpperLeg_L", "LowerLeg_L", "Foot_L"]

var _axis_map: Basis = Basis.IDENTITY  # motor_target = _axis_map * omega_desired(frame A)
var _results: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# The root Window is not ready for children inside _initialize; wait a frame.
	await process_frame
	await process_frame
	print("=== Kickback motor spike (%s) ===" % GODOT_EXE_NOTE)
	print("Physics engine: ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	await _calibrate_axis_map()
	var configs: Array = []
	var preset := OS.get_environment("SPIKE_SET")
	if preset == "iter":
		configs = [
			{"mode": "motor", "hz": 60, "kp": 20.0, "wmax": 15.0, "trace": true},
			{"mode": "motor", "hz": 30, "kp": 20.0, "wmax": 15.0},
		]
	elif preset == "vel":
		configs = [
			{"mode": "spring", "hz": 60},
			{"mode": "motor", "hz": 60, "kp": 10.0, "wmax": 12.0},
			{"mode": "motor", "hz": 60, "kp": 20.0, "wmax": 15.0, "trace": true},
			{"mode": "motor", "hz": 60, "kp": 20.0, "wmax": 15.0, "arm_torque": 0.25},
			{"mode": "motor", "hz": 60, "kp": 20.0, "wmax": 15.0, "arm_torque": 4.0},
		]
	elif preset == "pos":
		await _calibrate_spring_euler()
		configs = [
			{"mode": "spring", "hz": 60},
			{"mode": "posmotor", "hz": 60, "freq": 6.0, "zeta": 1.0, "trace": true},
			{"mode": "posmotor", "hz": 60, "freq": 6.0, "zeta": 1.0, "arm_torque": 0.25, "motor_flag": true},
			{"mode": "posmotor", "hz": 30, "freq": 6.0, "zeta": 1.0},
			{"mode": "posmotor", "hz": 120, "freq": 6.0, "zeta": 1.0},
		]
	else:
		configs = [
			{"mode": "spring", "hz": 60},
			{"mode": "pd", "hz": 60, "freq": 4.0, "zeta": 1.0},
			{"mode": "pd", "hz": 60, "freq": 6.0, "zeta": 1.0, "trace": true},
			{"mode": "pd", "hz": 60, "freq": 8.0, "zeta": 1.0},
			{"mode": "pd", "hz": 60, "freq": 6.0, "zeta": 1.0, "arm_torque": 0.25},
			{"mode": "pd", "hz": 60, "freq": 6.0, "zeta": 1.0, "gcomp": 0.0},
			{"mode": "spring", "hz": 30},
			{"mode": "pd", "hz": 30, "freq": 4.0, "zeta": 1.0},
			{"mode": "pd", "hz": 30, "freq": 6.0, "zeta": 1.0},
			{"mode": "spring", "hz": 120},
			{"mode": "pd", "hz": 120, "freq": 6.0, "zeta": 1.0},
			{"mode": "pd", "hz": 120, "freq": 8.0, "zeta": 1.0},
		]
	print("velocity_iterations = ", ProjectSettings.get_setting("physics/jolt_physics_3d/solver/velocity_iterations"))
	for cfg: Dictionary in configs:
		await _run_mode(cfg)
	print("\n=== RESULTS (error = angle between body basis and animation basis) ===")
	print("%-24s %-4s | %-15s | %-15s | %-30s" % ["config", "hz", "HOLD mean/max", "TRACK mean/max", "HIT peak deg / recover ticks"])
	for line in _results:
		print(line)
	quit()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame


func _spawn(hz: int, tuning: RagdollTuning):
	Engine.physics_ticks_per_second = hz
	Engine.max_physics_steps_per_frame = 32
	var h = RigHarness.new()
	root.add_child(h)
	h.setup(tuning, null, false)  # no ground: the harness foot box sits inside the plane
	var ok: bool = await h.await_ready(60)
	assert(ok, "harness ready")
	return h


func _tuning() -> RagdollTuning:
	var t := RagdollTuning.create_default()
	t.foot_ik_enabled = false
	t.stagger_sway_strength = 0.0
	t.steps_enabled = false
	t.arm_brace_enabled = false
	return t


func _anim_basis(h, rig: String) -> Basis:
	var idx: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(rig))
	return (h.skeleton.global_transform * h.spring.get_animation_bone_global(idx)).basis.orthonormalized()


func _error_deg(h, rig: String) -> float:
	var body: RigidBody3D = h.get_body(rig)
	var q := (_anim_basis(h, rig) * body.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
	return rad_to_deg(q.get_angle() if q.w >= 0.0 else (-q).get_angle())


# ── Calibration: which motor axis/sign moves the child about frame A's axes? ──

func _calibrate_axis_map() -> void:
	var h = await _spawn(60, _tuning())
	h.spring.set_physics_process(false)
	var bodies: Dictionary = h.rig_builder.get_bodies()
	for b: RigidBody3D in bodies.values():
		b.gravity_scale = 0.0
		b.angular_damp = 0.0
		b.linear_damp = 0.0
	(bodies["Hips"] as RigidBody3D).freeze = true
	var joints: Dictionary = h.rig_builder.get_joints()
	# Hold every joint still with a stiff motor at zero velocity.
	for child: String in joints:
		_set_motor(joints[child].joint, Vector3.ZERO, 1000.0)
	await _wait(5)
	var j: Dictionary = joints["Head"]
	var pb: RigidBody3D = bodies["Chest"]
	var cb: RigidBody3D = bodies["Head"]
	var cols: Array[Vector3] = []
	for k in 3:
		var cmd := Vector3.ZERO
		cmd[k] = 1.0
		_set_motor(j.joint, cmd, 1000.0)
		await _wait(3)
		var a: Basis = pb.global_basis.orthonormalized() * (j.frame_parent as Transform3D).basis
		var rel: Vector3 = a.inverse() * (cb.angular_velocity - pb.angular_velocity)
		cols.append(rel)
		print("  motor axis %d -> relative omega in frame A = %s" % [k, rel])
		_set_motor(j.joint, Vector3.ZERO, 1000.0)
		await _wait(5)
		cb.angular_velocity = Vector3.ZERO
	# omega = V * m  =>  m = V^-1 * omega ; snap V to a signed permutation.
	var v := Basis(cols[0], cols[1], cols[2])  # columns
	var snapped := Basis()
	for c in 3:
		var col: Vector3 = v[c] if false else Vector3(v.x[c], v.y[c], v.z[c])
		var best := 0
		for r in range(1, 3):
			if absf(col[r]) > absf(col[best]):
				best = r
		var s := Vector3.ZERO
		s[best] = signf(col[best])
		snapped.x[c] = s.x
		snapped.y[c] = s.y
		snapped.z[c] = s.z
	_axis_map = snapped.inverse()
	print("  V (snapped, columns = response to unit motor axis): ", snapped)
	print("  axis map (motor = M * omega_A): ", _axis_map)
	h.queue_free()
	await _wait(2)


var _euler_order: int = EULER_ORDER_XYZ
var _euler_sign: float = 1.0
var _euler_inv: bool = false

## Finds how Godot+Jolt interpret the three PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT
## values: which Euler order, sign, and whether the target is B-relative-to-A or
## its inverse. Drives the Chest->Head joint to a composite equilibrium with a
## stiff spring and compares the measured relative rotation (frame A coords)
## against every candidate convention.
func _calibrate_spring_euler() -> void:
	var h = await _spawn(60, _tuning())
	h.spring.set_physics_process(false)
	var bodies: Dictionary = h.rig_builder.get_bodies()
	for b: RigidBody3D in bodies.values():
		b.gravity_scale = 0.0
		b.angular_damp = 1.0
		b.linear_damp = 0.0
	(bodies["Hips"] as RigidBody3D).freeze = true
	var joints: Dictionary = h.rig_builder.get_joints()
	for child: String in joints:
		SpringMotorDriver._set_spring(joints[child].joint, Vector3.ZERO, 300.0, 20.0, 1000.0)
	await _wait(10)
	var j: Dictionary = joints["Head"]
	var pb: RigidBody3D = bodies["Chest"]
	var cb: RigidBody3D = bodies["Head"]
	var e := Vector3(0.5, 0.35, 0.2)
	SpringMotorDriver._set_spring(j.joint, e, 300.0, 20.0, 1000.0)
	await _wait(60)
	var a: Basis = pb.global_basis.orthonormalized() * (j.frame_parent as Transform3D).basis
	var b: Basis = cb.global_basis.orthonormalized() * (j.frame_child as Transform3D).basis
	var r_meas: Basis = a.inverse() * b
	print("  spring equilibrium %s -> measured relative rotation (axis-angle, frame A) = %s" % [e, MotorDriver._axis_angle(r_meas)])
	var best := INF
	for order in [EULER_ORDER_XYZ, EULER_ORDER_XZY, EULER_ORDER_YXZ, EULER_ORDER_YZX, EULER_ORDER_ZXY, EULER_ORDER_ZYX]:
		for sign in [1.0, -1.0]:
			for inv in [false, true]:
				var r := Basis.from_euler(e * sign, order)
				if inv:
					r = r.inverse()
				var d: float = (r * r_meas.inverse()).get_rotation_quaternion().get_angle()
				d = minf(d, TAU - d)
				if d < best:
					best = d
					_euler_order = order
					_euler_sign = sign
					_euler_inv = inv
	print("  best convention: order=%d sign=%.0f inverse=%s (residual %.1f deg)" % [_euler_order, _euler_sign, str(_euler_inv), rad_to_deg(best)])
	h.queue_free()
	await _wait(2)


func _set_motor(joint: Generic6DOFJoint3D, target: Vector3, limit: float) -> void:
	joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, target.x)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, target.y)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, target.z)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)


# ── A/B run ─────────────────────────────────────────────────────────────────

func _run_mode(cfg: Dictionary) -> void:
	var mode: String = cfg.mode
	var hz: int = cfg.hz
	var h = await _spawn(hz, _tuning())
	var bodies: Dictionary = h.rig_builder.get_bodies()
	(bodies["Hips"] as RigidBody3D).freeze = true  # isolate joint tracking from root control
	var driver: MotorDriver = null
	var pdriver: SpringMotorDriver = null
	var tdriver: TorquePDDriver = null
	if mode != "spring":
		h.spring.set_physics_process(false)
		for b: RigidBody3D in bodies.values():
			b.gravity_scale = 1.0
			b.angular_damp = 0.5
			b.linear_damp = 0.1
	if mode == "motor":
		driver = MotorDriver.new()
		driver.h = h
		driver.axis_map = _axis_map
		driver.kp = cfg.get("kp", 20.0)
		driver.w_max = cfg.get("wmax", 15.0)
		driver.ff_scale = cfg.get("ff", 1.0)
		driver.arm_torque_scale = cfg.get("arm_torque", 1.0)
		driver.trace = cfg.get("trace", false)
		driver.process_physics_priority = -5
		h.add_child(driver)
	elif mode == "posmotor":
		pdriver = SpringMotorDriver.new()
		pdriver.h = h
		pdriver.euler_order = _euler_order
		pdriver.euler_sign = _euler_sign
		pdriver.euler_inv = _euler_inv
		pdriver.freq = cfg.get("freq", 6.0)
		pdriver.zeta = cfg.get("zeta", 1.0)
		pdriver.arm_torque_scale = cfg.get("arm_torque", 1.0)
		pdriver.motor_flag = cfg.get("motor_flag", false)
		pdriver.process_physics_priority = -5
		h.add_child(pdriver)
	elif mode == "pd":
		tdriver = TorquePDDriver.new()
		tdriver.h = h
		tdriver.freq = cfg.get("freq", 6.0)
		tdriver.zeta = cfg.get("zeta", 1.0)
		tdriver.arm_torque_scale = cfg.get("arm_torque", 1.0)
		tdriver.gravity_comp = cfg.get("gcomp", 1.0)
		tdriver.process_physics_priority = -5
		h.add_child(tdriver)
	var anim := AnimDriver.new()
	anim.h = h
	anim.process_physics_priority = -10
	h.add_child(anim)

	# HOLD: static pose, 1 s settle then 1.5 s measured.
	if cfg.get("trace", false):
		var tr := "    arm trace (UpperArm/LowerArm/Hand deg every 4 ticks): "
		for i in hz:
			await physics_frame
			if i % 4 == 0:
				tr += "%.0f/%.0f/%.0f " % [_error_deg(h, "UpperArm_L"), _error_deg(h, "LowerArm_L"), _error_deg(h, "Hand_L")]
		print(tr)
	else:
		await _wait(hz)
	var hold := await _measure(h, int(hz * 1.5))
	# TRACK: sine targets, 0.5 s lead-in then 2 s measured.
	anim.active = true
	await _wait(hz / 2)
	var track := await _measure(h, hz * 2)
	anim.active = false
	anim.reset()
	await _wait(hz / 2)
	# HIT: 8 N.s on the left hand, sample hand error for 1.5 s.
	var hand: RigidBody3D = bodies["Hand_L"]
	hand.apply_impulse(Vector3(0.0, 0.0, -8.0))
	var peak := 0.0
	var recover := -1
	for i in int(hz * 1.5):
		await physics_frame
		var e := _error_deg(h, "Hand_L")
		peak = maxf(peak, e)
		if recover < 0 and i > 2 and e < 5.0:
			recover = i
	var label := mode
	if mode == "motor":
		label = "motor kp%.0f w%.0f ff%.1f at%.2f" % [driver.kp, driver.w_max, driver.ff_scale, driver.arm_torque_scale]
	elif mode == "posmotor":
		label = "posmotor f%.0f z%.1f at%.2f%s" % [pdriver.freq, pdriver.zeta, pdriver.arm_torque_scale, " +motorflag" if pdriver.motor_flag else ""]
	elif mode == "pd":
		label = "pd f%.0f z%.1f at%.2f g%.1f" % [tdriver.freq, tdriver.zeta, tdriver.arm_torque_scale, tdriver.gravity_comp]
	var line := "%-24s %-4d | %6.2f / %6.2f | %6.2f / %6.2f | %6.1f / %s
    hold per body: %s
    track per body: %s" % [
		label, hz, hold[0], hold[1], track[0], track[1], peak, str(recover) if recover >= 0 else "never",
		hold[2], track[2]]
	_results.append(line)
	print(line)
	h.queue_free()
	await _wait(2)


func _measure(h, ticks: int) -> Array:
	var sum := 0.0
	var n := 0
	var worst := 0.0
	var per: Dictionary = {}
	for i in ticks:
		await physics_frame
		for rig: String in MEASURED:
			var e := _error_deg(h, rig)
			sum += e
			n += 1
			worst = maxf(worst, e)
			per[rig] = per.get(rig, 0.0) + e
	var per_str := ""
	for rig: String in MEASURED:
		per_str += "%s=%.1f " % [rig, per[rig] / ticks]
	return [sum / maxf(n, 1), worst, per_str]


# ── Drivers ─────────────────────────────────────────────────────────────────

## Animates the skeleton: chest nod +-20 deg at 1 Hz, left upper arm +-40 deg at
## 1.5 Hz (about Z: the harness arm points +X, so this swings it up/down).
class AnimDriver extends Node:
	var h
	var active := false
	var t := 0.0
	var _chest := -1
	var _arm := -1

	func _ready() -> void:
		_chest = h.skeleton.find_bone("mixamorig_Spine2")
		_arm = h.skeleton.find_bone("mixamorig_LeftArm")

	func reset() -> void:
		t = 0.0
		h.skeleton.set_bone_pose_rotation(_chest, Quaternion.IDENTITY)
		h.skeleton.set_bone_pose_rotation(_arm, Quaternion.IDENTITY)

	func _physics_process(delta: float) -> void:
		if not active:
			return
		t += delta
		h.skeleton.set_bone_pose_rotation(_chest, Quaternion(Vector3.RIGHT, deg_to_rad(20.0) * sin(TAU * 1.0 * t)))
		h.skeleton.set_bone_pose_rotation(_arm, Quaternion(Vector3.BACK, deg_to_rad(40.0) * sin(TAU * 1.5 * t)))


## Torque-bounded joint-space muscle: per joint, the error between the current
## and the animation's relative rotation (in the parent-side joint frame A) times
## kp, plus the target's own angular velocity (feed-forward), clamped, becomes
## the 6DOF angular motor target; the force limit is the muscle torque.
class MotorDriver extends Node:
	var h
	var axis_map: Basis = Basis.IDENTITY
	var kp := 20.0
	var w_max := 15.0
	var ff_scale := 1.0
	var arm_torque_scale := 1.0
	var trace := false
	var _prev_tgt: Dictionary = {}

	func _physics_process(delta: float) -> void:
		var joints: Dictionary = h.rig_builder.get_joints()
		var bodies: Dictionary = h.rig_builder.get_bodies()
		var sg: Transform3D = h.skeleton.global_transform
		for child: String in joints:
			var j: Dictionary = joints[child]
			var pb: RigidBody3D = bodies[j.parent]
			var cb: RigidBody3D = bodies[child]
			var fp: Basis = (j.frame_parent as Transform3D).basis
			var fc: Basis = (j.frame_child as Transform3D).basis
			var a: Basis = pb.global_basis.orthonormalized() * fp
			var b: Basis = cb.global_basis.orthonormalized() * fc
			var pi: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(j.parent))
			var ci: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(child))
			var pa: Basis = (sg * h.spring.get_animation_bone_global(pi)).basis.orthonormalized() * fp
			var ca: Basis = (sg * h.spring.get_animation_bone_global(ci)).basis.orthonormalized() * fc
			var r_rel: Basis = a.inverse() * b
			var r_tgt: Basis = pa.inverse() * ca
			var err := _axis_angle(r_tgt * r_rel.inverse())
			var ff := Vector3.ZERO
			if child in _prev_tgt:
				ff = _axis_angle(r_tgt * (_prev_tgt[child] as Basis).inverse()) / maxf(delta, 1e-6)
			_prev_tgt[child] = r_tgt
			var w: Vector3 = err * kp + ff * ff_scale
			if w.length() > w_max:
				w = w.normalized() * w_max
			var m: Vector3 = axis_map * w
			var joint: Generic6DOFJoint3D = j.joint
			var limit: float = TORQUE.get(child, 50.0)
			if child.begins_with("UpperArm") or child.begins_with("LowerArm") or child.begins_with("Hand"):
				limit *= arm_torque_scale
			joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
			joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, m.x)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, m.y)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY, m.z)
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)

	static func _axis_angle(r: Basis) -> Vector3:
		var q := r.get_rotation_quaternion()
		if q.w < 0.0:
			q = -q
		var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
		var axis := Vector3(q.x, q.y, q.z)
		if axis.length_squared() < 1e-10 or angle < 1e-5:
			return Vector3.ZERO
		return axis.normalized() * angle


## Position-mode muscle: each joint angular SPRING (Jolt position motor, solved
## implicitly) is pointed at the animation relative rotation every tick via the
## equilibrium point; stiffness/damping derive from the joint effective inertia
## (subtree mass about the anchor) for a target natural frequency and damping
## ratio, and the motor force limit is the muscle torque.
class SpringMotorDriver extends Node:
	var h
	var euler_order: int = EULER_ORDER_XYZ
	var euler_sign: float = 1.0
	var euler_inv: bool = false
	var freq := 6.0
	var zeta := 1.0
	var arm_torque_scale := 1.0
	var motor_flag := false
	var _inertia: Dictionary = {}

	func _ready() -> void:
		var joints: Dictionary = h.rig_builder.get_joints()
		var bodies: Dictionary = h.rig_builder.get_bodies()
		var kids: Dictionary = {}
		for child: String in joints:
			var p: String = joints[child].parent
			if p not in kids:
				kids[p] = []
			kids[p].append(child)
		for child: String in joints:
			var j: Dictionary = joints[child]
			var pb: RigidBody3D = bodies[j.parent]
			var anchor: Vector3 = pb.global_transform * (j.anchor_parent as Vector3)
			var stack: Array = [child]
			var inertia := 0.0
			while not stack.is_empty():
				var n: String = stack.pop_back()
				var b: RigidBody3D = bodies[n]
				var r: float = b.global_position.distance_to(anchor)
				inertia += b.mass * (r * r + 0.05 * 0.05)
				for k in kids.get(n, []):
					stack.append(k)
			_inertia[child] = maxf(inertia, 0.002)
			var limit: float = TORQUE.get(child, 50.0)
			if child.begins_with("UpperArm") or child.begins_with("LowerArm") or child.begins_with("Hand"):
				limit *= arm_torque_scale
			var w := TAU * freq
			var inertia_j: float = _inertia[child]
			var k_s: float = w * w * inertia_j
			var c_s: float = 2.0 * zeta * sqrt(k_s * inertia_j)
			_set_spring(j.joint, Vector3.ZERO, k_s, c_s, limit)
			if motor_flag:
				(j.joint as Generic6DOFJoint3D).set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
				(j.joint as Generic6DOFJoint3D).set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)
				(j.joint as Generic6DOFJoint3D).set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, true)

	func _physics_process(_delta: float) -> void:
		var joints: Dictionary = h.rig_builder.get_joints()
		var sg: Transform3D = h.skeleton.global_transform
		for child: String in joints:
			var j: Dictionary = joints[child]
			var fp: Basis = (j.frame_parent as Transform3D).basis
			var fc: Basis = (j.frame_child as Transform3D).basis
			var pi: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(j.parent))
			var ci: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(child))
			var pa: Basis = (sg * h.spring.get_animation_bone_global(pi)).basis.orthonormalized() * fp
			var ca: Basis = (sg * h.spring.get_animation_bone_global(ci)).basis.orthonormalized() * fc
			var r_tgt: Basis = pa.inverse() * ca
			if euler_inv:
				r_tgt = r_tgt.inverse()
			var e: Vector3 = r_tgt.get_euler(euler_order) * euler_sign
			var joint: Generic6DOFJoint3D = j.joint
			joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, e.x)
			joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, e.y)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, e.z)

	static func _set_spring(joint: Generic6DOFJoint3D, eq: Vector3, k: float, c: float, limit: float) -> void:
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
		joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
		joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, k)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, k)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, k)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, c)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, c)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, c)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, eq.x)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, eq.y)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT, eq.z)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
		joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT, limit)



## Script PD muscle: per joint, a torque proportional to the relative-rotation
## error and to the relative angular-velocity error (target angular velocity fed
## forward), scaled by the joint effective inertia for a target natural
## frequency / damping ratio, plus the gravity torque of the subtree about the
## anchor (gravity compensation), clamped to the muscle torque limit, applied as
## +tau on the child and -tau on the parent (apply_torque). No engine motors.
class TorquePDDriver extends Node:
	var h
	var freq := 6.0
	var zeta := 1.0
	var arm_torque_scale := 1.0
	var gravity_comp := 1.0
	var _inertia: Dictionary = {}
	var _subtree: Dictionary = {}  # child rig -> Array[String] of rig names in its subtree
	var _prev_tgt: Dictionary = {}

	func _ready() -> void:
		var joints: Dictionary = h.rig_builder.get_joints()
		var bodies: Dictionary = h.rig_builder.get_bodies()
		var kids: Dictionary = {}
		for child: String in joints:
			var p: String = joints[child].parent
			if p not in kids:
				kids[p] = []
			kids[p].append(child)
		for child: String in joints:
			var j: Dictionary = joints[child]
			var pb: RigidBody3D = bodies[j.parent]
			var anchor: Vector3 = pb.global_transform * (j.anchor_parent as Vector3)
			var stack: Array = [child]
			var members: Array[String] = []
			var inertia := 0.0
			while not stack.is_empty():
				var n: String = stack.pop_back()
				members.append(n)
				var b: RigidBody3D = bodies[n]
				var r: float = b.global_position.distance_to(anchor)
				inertia += b.mass * (r * r + 0.05 * 0.05)
				for k in kids.get(n, []):
					stack.append(k)
			_inertia[child] = maxf(inertia, 0.002)
			_subtree[child] = members

	func _physics_process(delta: float) -> void:
		var joints: Dictionary = h.rig_builder.get_joints()
		var bodies: Dictionary = h.rig_builder.get_bodies()
		var sg: Transform3D = h.skeleton.global_transform
		var g: Vector3 = Vector3.DOWN * 9.8
		var w_n := TAU * freq
		var kp := w_n * w_n
		var kd := 2.0 * zeta * w_n
		for child: String in joints:
			var j: Dictionary = joints[child]
			var pb: RigidBody3D = bodies[j.parent]
			var cb: RigidBody3D = bodies[child]
			var fp: Basis = (j.frame_parent as Transform3D).basis
			var fc: Basis = (j.frame_child as Transform3D).basis
			var a: Basis = pb.global_basis.orthonormalized() * fp
			var b: Basis = cb.global_basis.orthonormalized() * fc
			var pi: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(j.parent))
			var ci: int = h.skeleton.find_bone(h.rig_builder.get_bone_name_for_body(child))
			var pa: Basis = (sg * h.spring.get_animation_bone_global(pi)).basis.orthonormalized() * fp
			var ca: Basis = (sg * h.spring.get_animation_bone_global(ci)).basis.orthonormalized() * fc
			var r_rel: Basis = a.inverse() * b
			var r_tgt: Basis = pa.inverse() * ca
			# error and feed-forward in frame A, then to world
			var err_a := MotorDriver._axis_angle(r_tgt * r_rel.inverse())
			var ff_a := Vector3.ZERO
			if child in _prev_tgt:
				ff_a = MotorDriver._axis_angle(r_tgt * (_prev_tgt[child] as Basis).inverse()) / maxf(delta, 1e-6)
			_prev_tgt[child] = r_tgt
			var err_w: Vector3 = a * err_a
			var w_tgt_w: Vector3 = a * ff_a
			var w_rel_w: Vector3 = cb.angular_velocity - pb.angular_velocity
			# Gains scale with the CHILD BODY's own world inertia tensor (what the
			# torque acts on this step); the subtree inertia is only used for the
			# gravity term below. Using the subtree inertia for the gains multiplied
			# the effective gain ~40x on light limb bodies and blew up (spike run 1).
			var st := PhysicsServer3D.body_get_direct_state(cb.get_rid())
			var inv_i: Basis = st.inverse_inertia_tensor
			var i_world: Basis = inv_i.inverse() if absf(inv_i.determinant()) > 1e-12 else Basis.IDENTITY * 0.001
			var tau: Vector3 = i_world * (kp * err_w + kd * (w_tgt_w - w_rel_w))
			# gravity compensation: torque of the subtree weight about the anchor
			if gravity_comp > 0.0:
				var anchor: Vector3 = pb.global_transform * (j.anchor_parent as Vector3)
				var tg := Vector3.ZERO
				for n: String in _subtree[child]:
					var nb: RigidBody3D = bodies[n]
					tg += (nb.global_position - anchor).cross(nb.mass * g)
				tau -= tg * gravity_comp
			var limit: float = TORQUE.get(child, 50.0)
			if child.begins_with("UpperArm") or child.begins_with("LowerArm") or child.begins_with("Hand"):
				limit *= arm_torque_scale
			if tau.length() > limit:
				tau = tau.normalized() * limit
			cb.apply_torque(tau)
			pb.apply_torque(-tau)
