class_name SpringResolver
extends Node

@export var skeleton_path: NodePath
@export var rig_builder_path: NodePath
@export var hip_pin_strength: float = 0.85
@export var foot_pin_strength: float = 0.4
@export var default_pin_strength: float = 0.1
@export var recovery_rate: float = 0.3

var _skeleton: Skeleton3D
var _rig_builder: PhysicsRigBuilder
var _active: bool = false
var _bones: Dictionary = {}  # rig_name → {body, bone_idx, base_strength, strength}
var _settle_timer: float = 0.0

const SETTLE_LINEAR_THRESHOLD := 0.5
const SETTLE_ANGULAR_THRESHOLD := 0.3
const SETTLE_DURATION := 0.6

const STRENGTH_MAP: Dictionary = {
	"Hips": 0.65, "Spine": 0.60, "Chest": 0.60,
	"Head": 0.35,
	"UpperArm_L": 0.45, "LowerArm_L": 0.40, "Hand_L": 0.25,
	"UpperArm_R": 0.45, "LowerArm_R": 0.40, "Hand_R": 0.25,
	"UpperLeg_L": 0.55, "LowerLeg_L": 0.45, "Foot_L": 0.30,
	"UpperLeg_R": 0.55, "LowerLeg_R": 0.45, "Foot_R": 0.30,
}

const MAX_ANGULAR_VEL := 20.0
const MAX_LINEAR_VEL := 10.0


func _ready() -> void:
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_init_bones()


func _init_bones() -> void:
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var bone_name: String = _rig_builder.get_bone_name_for_body(rig_name)
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		var base_str: float = STRENGTH_MAP.get(rig_name, 0.25)
		_bones[rig_name] = {
			"body": bodies[rig_name],
			"bone_idx": bone_idx,
			"base_strength": base_str,
			"strength": base_str,
		}


func set_active(value: bool) -> void:
	_active = value
	for rig_name: String in _bones:
		var body: RigidBody3D = _bones[rig_name].body
		if value:
			body.angular_damp = 3.0
			body.linear_damp = 2.0
			body.gravity_scale = 0.0
		else:
			body.angular_damp = 8.0
			body.linear_damp = 2.0
			body.gravity_scale = 0.8


func is_active() -> bool:
	return _active


func _physics_process(delta: float) -> void:
	if not _active or _bones.is_empty():
		return

	# Recover strength + restore gravity as strength returns
	for rig_name: String in _bones:
		var state: Dictionary = _bones[rig_name]
		state.strength = move_toward(state.strength, state.base_strength, recovery_rate * delta)
		# Scale gravity and damping by how weakened the bone is
		var strength_ratio: float = state.strength / state.base_strength if state.base_strength > 0.001 else 1.0
		state.body.gravity_scale = (1.0 - strength_ratio) * 0.5
		# Low strength = low damping (limbs swing freely on hit)
		# Full strength = full damping (stable pose hold)
		state.body.angular_damp = 1.0 + 2.0 * strength_ratio  # 1.0 when hit, 3.0 at full
		state.body.linear_damp = 0.5 + 1.5 * strength_ratio   # 0.5 when hit, 2.0 at full

	var skel_global := _skeleton.global_transform

	for rig_name: String in _bones:
		var state: Dictionary = _bones[rig_name]
		var body: RigidBody3D = state.body
		var bone_idx: int = state.bone_idx
		var strength: float = state.strength
		if strength < 0.001:
			continue

		# Read animation target (ignoring sync overrides)
		var target_xform := skel_global * _get_animation_bone_global(bone_idx)
		var current_xform := body.global_transform

		# Angular spring: drive rotation toward animation pose
		_apply_angular_spring(body, target_xform, current_xform, strength, delta)

		# Position pin: scale by strength ratio so hit limbs drift freely
		var base_pin := _get_pin_strength(rig_name)
		var strength_ratio: float = strength / state.base_strength if state.base_strength > 0.001 else 1.0
		var pin := base_pin * strength_ratio
		var pos_error := target_xform.origin - current_xform.origin
		body.linear_velocity = body.linear_velocity.lerp(pos_error / delta, pin)

		# Clamp to prevent runaway velocities
		if body.angular_velocity.length() > MAX_ANGULAR_VEL:
			body.angular_velocity = body.angular_velocity.normalized() * MAX_ANGULAR_VEL
		if body.linear_velocity.length() > MAX_LINEAR_VEL:
			body.linear_velocity = body.linear_velocity.normalized() * MAX_LINEAR_VEL


func _apply_angular_spring(body: RigidBody3D, target: Transform3D, current: Transform3D, strength: float, delta: float) -> void:
	var error_basis := target.basis.orthonormalized() * current.basis.orthonormalized().inverse()
	var det := error_basis.determinant()
	if det < 0.001 and det > -0.001:
		return

	var q := error_basis.get_rotation_quaternion()
	if q.w < 0:
		q = -q

	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var axis_raw := Vector3(q.x, q.y, q.z)
	if axis_raw.length_squared() < 0.0001 or angle < 0.001:
		return

	var target_vel := (axis_raw.normalized() * angle) / delta
	body.angular_velocity = body.angular_velocity.lerp(target_vel, strength)


func _get_pin_strength(rig_name: String) -> float:
	if rig_name == "Hips":
		return hip_pin_strength
	if rig_name == "Foot_L" or rig_name == "Foot_R":
		return foot_pin_strength
	return default_pin_strength


func _get_animation_bone_global(bone_idx: int) -> Transform3D:
	# Compute global pose from local animation poses (ignores sync overrides)
	var xform := _skeleton.get_bone_pose(bone_idx)
	var parent_idx := _skeleton.get_bone_parent(bone_idx)
	while parent_idx >= 0:
		xform = _skeleton.get_bone_pose(parent_idx) * xform
		parent_idx = _skeleton.get_bone_parent(parent_idx)
	return xform


func get_bone_strength(rig_name: String) -> float:
	if rig_name in _bones:
		return _bones[rig_name].strength
	return 0.0


func set_bone_strength(rig_name: String, value: float) -> void:
	if rig_name in _bones:
		_bones[rig_name].strength = value


func is_settled(delta: float) -> bool:
	if _bones.is_empty():
		return false
	for state: Dictionary in _bones.values():
		var body: RigidBody3D = state.body
		if body.linear_velocity.length() > SETTLE_LINEAR_THRESHOLD:
			_settle_timer = 0.0
			return false
		if body.angular_velocity.length() > SETTLE_ANGULAR_THRESHOLD:
			_settle_timer = 0.0
			return false
	_settle_timer += delta
	return _settle_timer >= SETTLE_DURATION


func reset_settle_timer() -> void:
	_settle_timer = 0.0


func get_max_rotation_error() -> float:
	if _bones.is_empty() or not _active:
		return 999.0
	var skel_global := _skeleton.global_transform
	var max_err := 0.0
	for state: Dictionary in _bones.values():
		var bone_idx: int = state.bone_idx
		var body: RigidBody3D = state.body
		var target_basis: Basis = (skel_global * _get_animation_bone_global(bone_idx)).basis.orthonormalized()
		var current_basis: Basis = body.global_transform.basis.orthonormalized()
		var error_basis: Basis = target_basis * current_basis.inverse()
		var det: float = error_basis.determinant()
		if det < 0.001 and det > -0.001:
			continue
		var q: Quaternion = error_basis.get_rotation_quaternion()
		if q.w < 0:
			q = -q
		var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
		max_err = maxf(max_err, angle)
	return max_err
