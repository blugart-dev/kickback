class_name SpringResolver
extends Node

@export var skeleton_path: NodePath
@export var rig_builder_path: NodePath
@export var hip_pin_strength: float = 0.85
@export var foot_pin_strength: float = 0.4
@export var default_pin_strength: float = 0.1
@export var recovery_rate: float = 0.3
@export var settle_duration: float = 0.6
@export var settle_linear_threshold: float = 0.5
@export var settle_angular_threshold: float = 0.3

var _skeleton: Skeleton3D
var _rig_builder: PhysicsRigBuilder
var _active: bool = false
var _bones: Dictionary = {}  # rig_name → {body, bone_idx, base_strength, strength}
var _settle_timer: float = 0.0
var _default_recovery_rate: float = 0.3
var _target_overrides: Dictionary = {}  # rig_name → Transform3D (temporary blend targets)

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
const MAX_ANGULAR_VEL_SQ := MAX_ANGULAR_VEL * MAX_ANGULAR_VEL
const MAX_LINEAR_VEL_SQ := MAX_LINEAR_VEL * MAX_LINEAR_VEL
const PROPERTY_THRESHOLD := 0.01


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	_default_recovery_rate = recovery_rate
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

	# Cache animation bone globals once per frame
	var skel_global := _skeleton.global_transform
	var has_overrides := not _target_overrides.is_empty()

	# Single merged pass: strength recovery + property updates + spring computation
	for rig_name: String in _bones:
		var state: Dictionary = _bones[rig_name]
		var body: RigidBody3D = state.body

		# Strength recovery
		state.strength = move_toward(state.strength, state.base_strength, recovery_rate * delta)
		var ratio := _strength_ratio(state)

		# Property updates — skip if unchanged
		var new_gravity := (1.0 - ratio) * 0.5
		var new_ang_damp := 1.0 + 2.0 * ratio
		var new_lin_damp := 0.5 + 1.5 * ratio
		if absf(body.gravity_scale - new_gravity) > PROPERTY_THRESHOLD:
			body.gravity_scale = new_gravity
		if absf(body.angular_damp - new_ang_damp) > PROPERTY_THRESHOLD:
			body.angular_damp = new_ang_damp
		if absf(body.linear_damp - new_lin_damp) > PROPERTY_THRESHOLD:
			body.linear_damp = new_lin_damp

		# Spring computation
		var strength: float = state.strength
		if strength < 0.001:
			continue

		var target_xform: Transform3D
		if has_overrides and rig_name in _target_overrides:
			target_xform = _target_overrides[rig_name]
		else:
			target_xform = skel_global * get_animation_bone_global(state.bone_idx)
		var current_xform := body.global_transform

		_apply_angular_spring(body, target_xform, current_xform, strength, delta)

		var pin := _get_pin_strength(rig_name) * ratio
		var pos_error := target_xform.origin - current_xform.origin
		body.linear_velocity = body.linear_velocity.lerp(pos_error / delta, pin)

		if body.angular_velocity.length_squared() > MAX_ANGULAR_VEL_SQ:
			body.angular_velocity = body.angular_velocity.normalized() * MAX_ANGULAR_VEL
		if body.linear_velocity.length_squared() > MAX_LINEAR_VEL_SQ:
			body.linear_velocity = body.linear_velocity.normalized() * MAX_LINEAR_VEL


func _strength_ratio(state: Dictionary) -> float:
	return state.strength / state.base_strength if state.base_strength > 0.001 else 1.0


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


func get_animation_bone_global(bone_idx: int) -> Transform3D:
	var xform := _skeleton.get_bone_pose(bone_idx)
	var parent_idx := _skeleton.get_bone_parent(bone_idx)
	while parent_idx >= 0:
		xform = _skeleton.get_bone_pose(parent_idx) * xform
		parent_idx = _skeleton.get_bone_parent(parent_idx)
	return xform


# --- Public API ---

func get_bone_strength(rig_name: String) -> float:
	if rig_name in _bones:
		return _bones[rig_name].strength
	return 0.0


func set_bone_strength(rig_name: String, value: float) -> void:
	if rig_name in _bones:
		_bones[rig_name].strength = value


func get_base_strength(rig_name: String) -> float:
	if rig_name in _bones:
		return _bones[rig_name].base_strength
	return 0.0


func get_all_bone_names() -> PackedStringArray:
	return PackedStringArray(_bones.keys())


func get_default_recovery_rate() -> float:
	return _default_recovery_rate


func is_settled(delta: float) -> bool:
	if _bones.is_empty():
		return false
	var lin_sq := settle_linear_threshold * settle_linear_threshold
	var ang_sq := settle_angular_threshold * settle_angular_threshold
	for state: Dictionary in _bones.values():
		var body: RigidBody3D = state.body
		if body.linear_velocity.length_squared() > lin_sq:
			_settle_timer = 0.0
			return false
		if body.angular_velocity.length_squared() > ang_sq:
			_settle_timer = 0.0
			return false
	_settle_timer += delta
	return _settle_timer >= settle_duration


func reset_settle_timer() -> void:
	_settle_timer = 0.0


func get_bone_idx(rig_name: String) -> int:
	if rig_name in _bones:
		return _bones[rig_name].bone_idx
	return -1


func set_target_overrides(overrides: Dictionary) -> void:
	_target_overrides = overrides


func clear_target_overrides() -> void:
	_target_overrides.clear()


func get_max_rotation_error() -> float:
	if _bones.is_empty() or not _active:
		return 999.0
	var skel_global := _skeleton.global_transform
	var max_err := 0.0
	for state: Dictionary in _bones.values():
		var bone_idx: int = state.bone_idx
		var body: RigidBody3D = state.body
		var target_basis: Basis = (skel_global * get_animation_bone_global(bone_idx)).basis.orthonormalized()
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
