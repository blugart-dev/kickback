## Manages the active ragdoll state machine (NORMAL -> STAGGER/RAGDOLL -> GETTING_UP).
## Coordinates hit reactions, full ragdoll transitions, and recovery sequences
## by driving the SpringResolver's per-bone strengths and pose blending.
## Animation playback is NOT handled here — connect to the signals and handle
## animations externally (or use the optional RagdollAnimator node).
@icon("res://addons/kickback/icons/active_ragdoll_controller.svg")
class_name ActiveRagdollController
extends Node

@export_group("References")
## Path to the SpringResolver node that drives spring-based bone tracking.
@export var spring_resolver_path: NodePath
## Path to the PhysicsRigBuilder that owns the ragdoll RigidBody3D nodes.
@export var rig_builder_path: NodePath
## Path to the character root Node3D for repositioning during get-up recovery.
@export var character_root_path: NodePath

## Character state for the active ragdoll lifecycle.
enum State {
	NORMAL,      ## Fully animated; springs at full strength.
	STAGGER,     ## Hit-reactive but on feet; springs at reduced strength.
	RAGDOLL,     ## All springs zeroed; physics drives the body.
	GETTING_UP,  ## Recovering from ragdoll; springs ramping back up.
	PERSISTENT,  ## Persistent ragdoll; stays until set_persistent(false) is called.
}

var _spring: SpringResolver
var _rig_builder: PhysicsRigBuilder
var _character_root: Node3D
var _adjacency: Dictionary = {}
var _state: int = State.NORMAL
var _recovery_elapsed: float = 0.0
var _ragdoll_elapsed: float = 0.0
var _ragdoll_poses: Dictionary = {}  # rig_name → Transform3D at recovery start
var _stagger_elapsed: float = 0.0
var _stagger_hit_dir: Vector3 = Vector3.ZERO
var _profile: RagdollProfile
var _tuning: RagdollTuning

## Emitted whenever the controller transitions between states.
## [param new_state] is one of [enum State] values (NORMAL, STAGGER, RAGDOLL, GETTING_UP, PERSISTENT).
signal state_changed(new_state: int)
## Emitted when the character enters full ragdoll (all springs zeroed).
signal ragdoll_started()
## Emitted when recovery begins after ragdoll settles. [param face_up] indicates
## whether the character landed face-up (true) or face-down (false).
## Connect to this to play get-up animations.
signal recovery_started(face_up: bool)
## Emitted when recovery completes and springs are fully restored.
## Connect to this to play idle or transition animations.
signal recovery_finished()
## Emitted when a hit reduces spring strength but does NOT trigger ragdoll.
## Useful for subtle visual feedback (pain sound, flinch animation) in NORMAL state.
signal hit_absorbed(rig_name: String, new_strength: float)
## Emitted when the character enters stagger (visible loss of balance, stays on feet).
## [param hit_direction] is the world-space direction of the triggering hit.
signal stagger_started(hit_direction: Vector3)
## Emitted when the character recovers from stagger and returns to NORMAL.
signal stagger_finished()


func configure(profile: RagdollProfile, tuning: RagdollTuning) -> void:
	_profile = profile
	_tuning = tuning


func _ready() -> void:
	_spring = get_node(spring_resolver_path) as SpringResolver
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	if not character_root_path.is_empty():
		_character_root = get_node(character_root_path) as Node3D
	_ensure_config()
	_build_adjacency()


func _ensure_config() -> void:
	if not _profile:
		_profile = RagdollProfile.create_mixamo_default()
	if not _tuning:
		_tuning = RagdollTuning.create_default()


func _build_adjacency() -> void:
	for joint_def: JointDefinition in _profile.joints:
		var p: String = joint_def.parent_rig
		var c: String = joint_def.child_rig
		if p not in _adjacency:
			_adjacency[p] = PackedStringArray()
		if c not in _adjacency:
			_adjacency[c] = PackedStringArray()
		_adjacency[p].append(c)
		_adjacency[c].append(p)


func _physics_process(delta: float) -> void:
	match _state:
		State.STAGGER:
			_stagger_elapsed += delta
			var floor_ratio: float = _tuning.stagger_strength_floor
			for rig_name: String in _spring.get_all_bone_names():
				var base: float = _spring.get_base_strength(rig_name)
				var floor_val: float = base * floor_ratio
				if _spring.get_bone_strength(rig_name) < floor_val:
					_spring.set_bone_strength(rig_name, floor_val)
			if _stagger_elapsed >= _tuning.stagger_duration:
				_finish_stagger()
		State.RAGDOLL:
			_ragdoll_elapsed += delta
			if _spring.is_settled(delta) or _ragdoll_elapsed > _tuning.ragdoll_force_recovery_time:
				_start_recovery()
		State.PERSISTENT:
			pass  # Stay ragdolled permanently
		State.GETTING_UP:
			if not _spring or not _spring.get_skeleton():
				return
			_recovery_elapsed += delta

			# Phase 1: Pose interpolation — blend ragdoll landing pose toward animation
			var blend_t := clampf(_recovery_elapsed / _tuning.pose_blend_duration, 0.0, 1.0)
			if blend_t < 1.0 and not _ragdoll_poses.is_empty():
				var eased_blend := blend_t * blend_t  # Quadratic ease-in
				var skel_global := _spring.get_skeleton().global_transform
				var overrides: Dictionary = {}
				for rig_name: String in _ragdoll_poses:
					var bone_idx: int = _spring.get_bone_idx(rig_name)
					if bone_idx < 0:
						continue
					var ragdoll_xform: Transform3D = _ragdoll_poses[rig_name]
					var anim_xform: Transform3D = skel_global * _spring.get_animation_bone_global(bone_idx)
					var blended_origin := ragdoll_xform.origin.lerp(anim_xform.origin, eased_blend)
					var q_ragdoll := ragdoll_xform.basis.get_rotation_quaternion()
					var q_anim := anim_xform.basis.get_rotation_quaternion()
					var q_blend := q_ragdoll.slerp(q_anim, eased_blend)
					overrides[rig_name] = Transform3D(Basis(q_blend), blended_origin)
				_spring.set_target_overrides(overrides)
			else:
				_spring.clear_target_overrides()

			# Phase 2: Per-bone staggered strength ramp
			for rig_name: String in _spring.get_all_bone_names():
				var delay: float = _tuning.ramp_delay.get(rig_name, 0.0)
				var effective_elapsed := maxf(0.0, _recovery_elapsed - delay)
				var effective_duration := maxf(0.1, _tuning.recovery_duration - delay)
				var t := clampf(effective_elapsed / effective_duration, 0.0, 1.0)
				var eased_t := t * t * t  # Cubic ease-in per bone
				var base: float = _spring.get_base_strength(rig_name)
				_spring.set_bone_strength(rig_name, base * eased_t)

			# Recovery completion: physics-driven, independent of animation duration.
			# recovery_finished fires when springs converge, not when animation ends.
			# Users who need animation-synchronized timing should check animation
			# state in their recovery_finished handler.
			var global_t := clampf(_recovery_elapsed / _tuning.recovery_duration, 0.0, 1.0)
			if (_spring.get_max_rotation_error() < _tuning.recovery_rotation_threshold and global_t >= _tuning.recovery_completion_threshold) or _recovery_elapsed > _tuning.safety_timeout:
				_finish_recovery()


## Applies a hit reaction to [param body] using the given impact [param profile].
## Reduces spring strengths, applies impulse, and may trigger full ragdoll.
func apply_hit(body: RigidBody3D, hit_dir: Vector3, hit_pos: Vector3, profile: ImpactProfile) -> void:
	if not is_instance_valid(body):
		return
	if _state == State.GETTING_UP:
		_full_ragdoll()
		return

	var final_impulse := profile.base_impulse * profile.impulse_transfer_ratio
	var direction := (hit_dir + Vector3.UP * profile.upward_bias).normalized()
	var local_offset := body.to_local(hit_pos)
	body.apply_impulse(direction * final_impulse, local_offset)

	if _state == State.RAGDOLL:
		_spring.reset_settle_timer()
		return

	if _state == State.STAGGER:
		_reduce_strength(body.name, profile.strength_reduction, profile.strength_spread)
		_spring.recovery_rate = profile.recovery_rate
		var boosted_prob := profile.ragdoll_probability * _tuning.stagger_ragdoll_bonus
		if randf() < boosted_prob:
			_full_ragdoll()
		else:
			_stagger_elapsed = 0.0  # Extend stagger
			_stagger_hit_dir = hit_dir
			hit_absorbed.emit(body.name, _spring.get_bone_strength(body.name))
		return

	# NORMAL state
	_reduce_strength(body.name, profile.strength_reduction, profile.strength_spread)
	_spring.recovery_rate = profile.recovery_rate

	if randf() < profile.ragdoll_probability:
		_full_ragdoll()
	else:
		var avg_ratio := _compute_average_strength_ratio()
		if avg_ratio < _tuning.stagger_threshold:
			_start_stagger(hit_dir)
		else:
			hit_absorbed.emit(body.name, _spring.get_bone_strength(body.name))


## Forces an immediate transition to full ragdoll, zeroing all spring strengths.
## The character will recover automatically after settling.
func trigger_ragdoll() -> void:
	_full_ragdoll()


## Forces the character into a stagger state. Springs are reduced to the stagger
## floor and recover automatically after stagger_duration.
func trigger_stagger(hit_dir: Vector3 = Vector3.FORWARD) -> void:
	if _state == State.NORMAL:
		var floor_ratio: float = _tuning.stagger_strength_floor
		for rig_name: String in _spring.get_all_bone_names():
			var base: float = _spring.get_base_strength(rig_name)
			_spring.set_bone_strength(rig_name, base * floor_ratio)
		_start_stagger(hit_dir)


## Enables or disables persistent ragdoll. When enabled, the character enters
## full ragdoll and stays down until set_persistent(false) is called.
## When disabled, triggers normal recovery (GETTING_UP state).
func set_persistent(enabled: bool) -> void:
	if enabled:
		_full_ragdoll()
		_state = State.PERSISTENT
		state_changed.emit(_state)
	else:
		if _state == State.PERSISTENT:
			_start_recovery()


func _full_ragdoll() -> void:
	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, 0.0)
	_state = State.RAGDOLL
	_ragdoll_elapsed = 0.0
	_spring.recovery_rate = 0.0
	_spring.reset_settle_timer()
	_spring.clear_target_overrides()
	_ragdoll_poses.clear()
	state_changed.emit(_state)
	ragdoll_started.emit()


func _start_recovery() -> void:
	_state = State.GETTING_UP
	_recovery_elapsed = 0.0
	state_changed.emit(_state)

	var bodies := _rig_builder.get_bodies()
	var hip_body: RigidBody3D = bodies.get("Hips")
	var chest_body: RigidBody3D = bodies.get("Chest")
	var head_body: RigidBody3D = bodies.get("Head")

	# Detect orientation BEFORE moving root
	var face_up := true
	if chest_body:
		var chest_forward_dot := chest_body.global_basis.z.dot(Vector3.UP)
		face_up = chest_forward_dot > 0

	# Save all body world transforms before moving root
	var saved_transforms: Dictionary = {}
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		saved_transforms[rig_name] = body.global_transform

	# Reposition character root to ragdoll landing position (physics-essential)
	if _character_root and hip_body:
		var hip_pos := hip_body.global_position

		# Raycast down from hip to find ground height
		var ground_y := 0.0
		var space_state := _character_root.get_world_3d().direct_space_state
		var ray_origin := Vector3(hip_pos.x, hip_pos.y + 1.0, hip_pos.z)
		var ray_end := Vector3(hip_pos.x, hip_pos.y - 3.0, hip_pos.z)
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collision_mask = _tuning.ground_raycast_mask
		query.collide_with_bodies = true
		var result := space_state.intersect_ray(query)
		var ground_normal := Vector3.UP
		if not result.is_empty():
			ground_y = result["position"].y
			ground_normal = result["normal"]

		_character_root.global_position = Vector3(hip_pos.x, ground_y, hip_pos.z)

		# Compute facing direction from head-hip vector
		var facing := Vector3.FORWARD
		if head_body:
			var head_pos := head_body.global_position
			facing = Vector3(head_pos.x - hip_pos.x, 0.0, head_pos.z - hip_pos.z)
			if face_up:
				facing = -facing

		# Set character root orientation
		if facing.length_squared() > 0.01:
			if _tuning.align_to_slope and ground_normal.dot(Vector3.UP) > 0.5:
				# Align to slope: project facing onto the slope plane
				var slope_forward := facing.slide(ground_normal).normalized()
				if slope_forward.length_squared() > 0.001:
					_character_root.global_basis = Basis.looking_at(slope_forward, ground_normal)
				else:
					_character_root.global_rotation.y = atan2(facing.x, facing.z)
			else:
				# Stay upright (default)
				_character_root.global_rotation.y = atan2(facing.x, facing.z)

	# Restore body world transforms — bodies stay where they were
	for rig_name: String in saved_transforms:
		var body: RigidBody3D = bodies[rig_name]
		body.global_transform = saved_transforms[rig_name]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

	# Capture ragdoll poses for pose interpolation during recovery
	_ragdoll_poses = saved_transforms.duplicate()

	# Signal that recovery has started — RagdollAnimator (or user code) handles animation
	recovery_started.emit(face_up)


func _finish_recovery() -> void:
	_state = State.NORMAL
	_spring.recovery_rate = _spring.get_default_recovery_rate()
	_spring.clear_target_overrides()
	_ragdoll_poses.clear()
	state_changed.emit(_state)

	for rig_name: String in _spring.get_all_bone_names():
		var base: float = _spring.get_base_strength(rig_name)
		_spring.set_bone_strength(rig_name, base)

	# Signal that recovery is complete — RagdollAnimator (or user code) handles animation
	recovery_finished.emit()


## Returns the current state as a [enum State] integer value.
func get_state() -> int:
	return _state


## Returns a human-readable name for the current state (for debug display).
func get_state_name() -> String:
	match _state:
		State.NORMAL: return "NORMAL"
		State.STAGGER: return "STAGGER"
		State.RAGDOLL: return "RAGDOLL"
		State.GETTING_UP: return "GETTING UP"
		State.PERSISTENT: return "PERSISTENT"
	return "UNKNOWN"


func _reduce_strength(rig_name: String, reduction: float, spread: int) -> void:
	var current := _spring.get_bone_strength(rig_name)
	var floor: float = _tuning.min_strength.get(rig_name, 0.0)
	_spring.set_bone_strength(rig_name, maxf(current * (1.0 - reduction), floor))

	if spread > 0:
		var visited := {rig_name: true}
		var current_level := PackedStringArray([rig_name])

		for dist in range(1, spread + 1):
			var next_level := PackedStringArray()
			var falloff := 1.0 - (float(dist) / float(spread + 1))

			for bone: String in current_level:
				if bone not in _adjacency:
					continue
				for neighbor: String in _adjacency[bone]:
					if neighbor in visited:
						continue
					visited[neighbor] = true
					next_level.append(neighbor)
					var s := _spring.get_bone_strength(neighbor)
					var nfloor: float = _tuning.min_strength.get(neighbor, 0.0)
					_spring.set_bone_strength(neighbor, maxf(s * (1.0 - reduction * falloff), nfloor))

			current_level = next_level


func _compute_average_strength_ratio() -> float:
	var total := 0.0
	var count := 0
	for rig_name: String in _spring.get_all_bone_names():
		var base: float = _spring.get_base_strength(rig_name)
		if base > 0.001:
			total += _spring.get_bone_strength(rig_name) / base
			count += 1
	return total / float(count) if count > 0 else 1.0


func _start_stagger(hit_dir: Vector3) -> void:
	_state = State.STAGGER
	_stagger_elapsed = 0.0
	_stagger_hit_dir = hit_dir
	state_changed.emit(_state)
	stagger_started.emit(hit_dir)


func _finish_stagger() -> void:
	for rig_name: String in _spring.get_all_bone_names():
		var base: float = _spring.get_base_strength(rig_name)
		_spring.set_bone_strength(rig_name, base)
	_state = State.NORMAL
	_spring.recovery_rate = _spring.get_default_recovery_rate()
	state_changed.emit(_state)
	stagger_finished.emit()
