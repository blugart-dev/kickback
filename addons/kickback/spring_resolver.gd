## Velocity-based spring resolver that drives physics ragdoll bodies toward
## animation skeleton poses. Each frame, computes rotation/position error per
## bone and lerps rigid body velocities toward the correction, weighted by
## per-bone strength. Strength can be reduced on hit so physics wins temporarily,
## then recovers over time.
@icon("res://addons/kickback/icons/spring_resolver.svg")
class_name SpringResolver
extends Node

@export_group("References")
## Path to the Skeleton3D that provides animation target poses.
@export var skeleton_path: NodePath
## Path to the PhysicsRigBuilder whose bodies are spring-driven toward the skeleton.
@export var rig_builder_path: NodePath

var recovery_rate: float = 0.3

var _skeleton: Skeleton3D
var _rig_builder: PhysicsRigBuilder
var _active: bool = false
var _bones: Dictionary = {}  # rig_name → {body, bone_idx, base_strength, strength}
var _settle_timer: float = 0.0
var _default_recovery_rate: float = 0.3
var _target_overrides: Dictionary = {}  # rig_name → Transform3D (temporary blend targets)
var _tuning: RagdollTuning
var _max_angular_vel_sq: float = 400.0
var _max_linear_vel_sq: float = 100.0

const PROPERTY_THRESHOLD := 0.01


func configure(tuning: RagdollTuning) -> void:
	_tuning = tuning


func _ready() -> void:
	_skeleton = get_node(skeleton_path) as Skeleton3D
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_ensure_tuning()
	recovery_rate = _tuning.recovery_rate
	_default_recovery_rate = _tuning.recovery_rate
	_max_angular_vel_sq = _tuning.max_angular_velocity * _tuning.max_angular_velocity
	_max_linear_vel_sq = _tuning.max_linear_velocity * _tuning.max_linear_velocity
	_init_bones()


func _ensure_tuning() -> void:
	if not _tuning:
		_tuning = RagdollTuning.create_default()


func _init_bones() -> void:
	var bodies := _rig_builder.get_bodies()
	for rig_name: String in bodies:
		var bone_name: String = _rig_builder.get_bone_name_for_body(rig_name)
		var bone_idx := _skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		var base_str: float = _tuning.strength_map.get(rig_name, _tuning.default_spring_strength)
		_bones[rig_name] = {
			"body": bodies[rig_name],
			"bone_idx": bone_idx,
			"base_strength": base_str,
			"strength": base_str,
		}


## Returns the Skeleton3D used for animation target poses.
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Enables or disables the spring resolver. When active, bodies are driven toward
## animation poses. When inactive, bodies use passive ragdoll damping and gravity.
func set_active(value: bool) -> void:
	_ensure_tuning()
	_active = value
	for rig_name: String in _bones:
		var body: RigidBody3D = _bones[rig_name].body
		if value:
			body.angular_damp = 3.0
			body.linear_damp = 2.0
			body.gravity_scale = 0.0
		else:
			body.angular_damp = _tuning.angular_damp
			body.linear_damp = _tuning.linear_damp
			body.gravity_scale = _tuning.gravity_scale


## Returns true if the spring resolver is currently active.
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

		if body.angular_velocity.length_squared() > _max_angular_vel_sq:
			body.angular_velocity = body.angular_velocity.normalized() * _tuning.max_angular_velocity
		if body.linear_velocity.length_squared() > _max_linear_vel_sq:
			body.linear_velocity = body.linear_velocity.normalized() * _tuning.max_linear_velocity


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
	return _tuning.pin_strength_overrides.get(rig_name, _tuning.default_pin_strength)


## Computes the skeleton-local global transform for a bone by walking the
## parent chain, since Skeleton3D doesn't expose this directly.
func get_animation_bone_global(bone_idx: int) -> Transform3D:
	var xform := _skeleton.get_bone_pose(bone_idx)
	var parent_idx := _skeleton.get_bone_parent(bone_idx)
	while parent_idx >= 0:
		xform = _skeleton.get_bone_pose(parent_idx) * xform
		parent_idx = _skeleton.get_bone_parent(parent_idx)
	return xform


# --- Public API ---

## Returns the current spring strength for the given bone (0.0 = fully ragdolled).
func get_bone_strength(rig_name: String) -> float:
	if rig_name in _bones:
		return _bones[rig_name].strength
	return 0.0


## Sets the current spring strength for a bone. Typically reduced on hit, then
## recovers toward base_strength each frame.
func set_bone_strength(rig_name: String, value: float) -> void:
	if rig_name in _bones:
		_bones[rig_name].strength = value


## Returns the resting (fully recovered) strength for a bone.
func get_base_strength(rig_name: String) -> float:
	if rig_name in _bones:
		return _bones[rig_name].base_strength
	return 0.0


## Returns the rig names of all registered bones (e.g. "Hips", "Spine", "Head").
func get_all_bone_names() -> PackedStringArray:
	return PackedStringArray(_bones.keys())


func get_default_recovery_rate() -> float:
	return _default_recovery_rate


## Returns true when all bodies have been below velocity thresholds for at least
## the settle duration, indicating the ragdoll has come to rest.
func is_settled(delta: float) -> bool:
	_ensure_tuning()
	if _bones.is_empty():
		return false
	var lin_sq := _tuning.settle_linear_threshold * _tuning.settle_linear_threshold
	var ang_sq := _tuning.settle_angular_threshold * _tuning.settle_angular_threshold
	for state: Dictionary in _bones.values():
		var body: RigidBody3D = state.body
		if body.linear_velocity.length_squared() > lin_sq:
			_settle_timer = 0.0
			return false
		if body.angular_velocity.length_squared() > ang_sq:
			_settle_timer = 0.0
			return false
	_settle_timer += delta
	return _settle_timer >= _tuning.settle_duration


func reset_settle_timer() -> void:
	_settle_timer = 0.0


## Returns the Skeleton3D bone index for a given rig name, or -1 if not found.
func get_bone_idx(rig_name: String) -> int:
	if rig_name in _bones:
		return _bones[rig_name].bone_idx
	return -1


## Sets temporary target pose overrides (rig_name -> Transform3D) that replace
## animation poses for specific bones, used during get-up blending.
func set_target_overrides(overrides: Dictionary) -> void:
	_target_overrides = overrides


## Clears all target pose overrides, reverting to animation-driven targets.
func clear_target_overrides() -> void:
	_target_overrides.clear()


## Returns the largest rotation error (in radians) across all bones between
## their current physics orientation and the animation target.
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
