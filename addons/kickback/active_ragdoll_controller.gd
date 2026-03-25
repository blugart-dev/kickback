## Manages the active ragdoll state machine (NORMAL -> STAGGER/RAGDOLL -> GETTING_UP).
## Coordinates hit reactions, full ragdoll transitions, and recovery sequences
## by driving the SpringResolver's per-bone strengths and pose blending.
## Animation playback is NOT handled here — connect to the signals and handle
## animations externally (or use the optional RagdollAnimator node).
##
## State machine:
##   NORMAL ──hit──→ STAGGER ──balance/timer──→ NORMAL
##      │                │
##      │ (ragdoll_prob) │ (balance_ragdoll_threshold)
##      ↓                ↓
##   RAGDOLL ──settle──→ GETTING_UP ──converge──→ NORMAL
##      │
##      │ set_persistent(true)
##      ↓
##   PERSISTENT ──set_persistent(false)──→ GETTING_UP
@icon("res://addons/kickback/icons/active_ragdoll_controller.svg")
class_name ActiveRagdollController
extends Node

const _MOVEMENT_VELOCITY_THRESHOLD_SQ := 0.25  # (0.5 m/s)^2

@export_group("References")
## Path to the SpringResolver node that drives spring-based bone tracking.
@export var spring_resolver_path: NodePath
## Path to the PhysicsRigBuilder that owns the ragdoll RigidBody3D nodes.
@export var rig_builder_path: NodePath
## Path to the character root Node3D for repositioning during get-up recovery.
## Must point to the gameplay root (e.g., CharacterBody3D or top-level Node3D),
## NOT a model sub-node. The setup tool defaults to ".." assuming Kickback nodes
## are direct children of the character root.
@export var character_root_path: NodePath
## Path to PhysicsRigSync for forcing skeleton updates after recovery teleport.
@export var rig_sync_path: NodePath

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
var _rig_sync: PhysicsRigSync
var _adjacency: Dictionary = {}
var _protected_set: Dictionary = {}  # Cached O(1) lookup for protected bones
var _state: int = State.NORMAL
var _recovery_elapsed: float = 0.0
var _ragdoll_elapsed: float = 0.0
var _ragdoll_poses: Dictionary = {}  # rig_name → Transform3D at recovery start
var _stagger_elapsed: float = 0.0
var _stagger_hit_dir: Vector3 = Vector3.ZERO
var _balance_stable_timer: float = 0.0
var _fatigue: float = 0.0
var _pain: float = 0.0
var _last_hit_time: float = 0.0
var _hit_streak: int = 0
var _reaction_pulses: Dictionary = {}  # rig_name → {intensity: float, elapsed: float}
var _injuries: Dictionary = {}  # rig_name → float (0.0-1.0, persistent damage)
var _prev_com: Vector3 = Vector3.ZERO
var _com_velocity: Vector3 = Vector3.ZERO
var _com_initialized: bool = false
var _sway_phase: float = 0.0
var _profile: RagdollProfile
var _tuning: RagdollTuning
var _foot_ik: FootIKSolver

## Emitted whenever the controller transitions between states.
signal state_changed(new_state: int)
## Emitted when the character enters full ragdoll (all springs zeroed).
signal ragdoll_started()
## Emitted when recovery begins after ragdoll settles.
signal recovery_started(face_up: bool)
## Emitted when recovery completes and springs are fully restored.
signal recovery_finished()
## Emitted when a hit reduces spring strength but does NOT trigger ragdoll.
signal hit_absorbed(rig_name: String, new_strength: float)
## Emitted when the character enters stagger (visible loss of balance, stays on feet).
signal stagger_started(hit_direction: Vector3)
## Emitted when the character recovers from stagger and returns to NORMAL.
signal stagger_finished()
## Emitted each physics frame during stagger with the current balance ratio.
signal balance_changed(ratio: float)
## Emitted when fatigue level changes significantly. 0.0 = fresh, 1.0 = exhausted.
signal fatigue_changed(level: float)
## Emitted when a hit during GETTING_UP interrupts recovery and forces re-ragdoll.
signal recovery_interrupted()
## Emitted when pain level changes. 0.0 = no pain, 1.0 = maximum accumulated pain.
signal pain_changed(level: float)
## Emitted when anticipate_threat() is called. Connect for defensive animations.
signal threat_anticipated(direction: Vector3, urgency: float)
## Emitted when a bone region sustains injury from a significant hit.
## Injuries persist longer than spring recovery and cause functional impairment.
signal region_injured(rig_name: String, severity: float)


func configure(profile: RagdollProfile, tuning: RagdollTuning) -> void:
	_profile = profile
	_tuning = tuning
	_rebuild_protected_set()


func _ready() -> void:
	_spring = get_node(spring_resolver_path) as SpringResolver
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	if not character_root_path.is_empty():
		_character_root = get_node(character_root_path) as Node3D
	if not rig_sync_path.is_empty():
		_rig_sync = get_node(rig_sync_path) as PhysicsRigSync
	_ensure_config()
	_build_adjacency()
	_rebuild_protected_set()


func _ensure_config() -> void:
	if not _profile:
		_profile = RagdollProfile.create_mixamo_default()
	if not _tuning:
		_tuning = RagdollTuning.create_default()


func _rebuild_protected_set() -> void:
	_protected_set.clear()
	if _tuning:
		for bone_name: String in _tuning.protected_bones:
			_protected_set[bone_name] = true


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


# ── Physics Process ─────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _spring or not _rig_builder:
		return

	# Lazy foot IK init (deferred until SpringResolver has bones)
	if not _foot_ik and _tuning and _tuning.foot_ik_enabled and _character_root:
		if not _spring.get_all_bone_names().is_empty():
			_foot_ik = FootIKSolver.new()
			if not _foot_ik.initialize(_spring, _tuning, _character_root, _rig_builder):
				push_warning("ActiveRagdollController: foot IK disabled (missing leg bones)")
				_foot_ik = null

	_update_fatigue_decay(delta)
	_tick_reaction_pulses(delta)
	_sync_injuries_to_resolver()

	match _state:
		State.STAGGER:
			_update_stagger(delta)
		State.RAGDOLL:
			_update_ragdoll(delta)
		State.GETTING_UP:
			_update_recovery(delta)

	# Foot IK: solve during NORMAL, blend out during STAGGER, reset otherwise
	if _foot_ik:
		match _state:
			State.NORMAL:
				_foot_ik.process(delta)
			State.STAGGER:
				if _foot_ik.is_active():
					_foot_ik.blend_out(delta)
			_:
				_foot_ik.reset()


func _update_fatigue_decay(delta: float) -> void:
	if _state == State.RAGDOLL or _state == State.PERSISTENT:
		return
	if _fatigue > 0.0:
		var old_fatigue := _fatigue
		_fatigue = move_toward(_fatigue, 0.0, _tuning.fatigue_decay * delta)
		if absf(old_fatigue - _fatigue) > 0.01:
			fatigue_changed.emit(_fatigue)
	if _pain > 0.0:
		_pain = move_toward(_pain, 0.0, _tuning.pain_decay * delta)

	# Injury decay (much slower than fatigue — injuries linger)
	if not _injuries.is_empty():
		var healed := PackedStringArray()
		for rig_name: String in _injuries:
			var injury: float = _injuries[rig_name]
			injury = move_toward(injury, 0.0, _tuning.injury_decay * delta)
			if injury <= 0.001:
				healed.append(rig_name)
			else:
				_injuries[rig_name] = injury
		for healed_name: String in healed:
			_injuries.erase(healed_name)


func _tick_reaction_pulses(delta: float) -> void:
	if _reaction_pulses.is_empty():
		return
	var expired := PackedStringArray()
	for rig_name: String in _reaction_pulses:
		var pulse: Dictionary = _reaction_pulses[rig_name]
		var elapsed: float = pulse["elapsed"] + delta
		pulse["elapsed"] = elapsed
		if elapsed >= _tuning.reaction_pulse_duration:
			expired.append(rig_name)
		else:
			var t: float = elapsed / _tuning.reaction_pulse_duration
			var fade: float = 1.0 - t * t  # Quadratic fade-out
			var pulse_strength: float = float(pulse["intensity"]) * fade
			var current := _spring.get_bone_strength(rig_name)
			_spring.set_bone_strength(rig_name, maxf(current * (1.0 - pulse_strength), 0.0))
	for expired_name: String in expired:
		_reaction_pulses.erase(expired_name)


func _update_stagger(delta: float) -> void:
	_stagger_elapsed += delta

	# Enforce strength floor
	var floor_ratio: float = _tuning.stagger_strength_floor
	for rig_name: String in _spring.get_all_bone_names():
		if _is_bone_protected(rig_name):
			continue
		var effective_base: float = _effective_base_strength(rig_name)
		var floor_val: float = effective_base * floor_ratio
		if _spring.get_bone_strength(rig_name) < floor_val:
			_spring.set_bone_strength(rig_name, floor_val)

	# Active resistance: dynamic per-frame strength adjustment
	_apply_active_resistance(delta)

	# Continuous sway force: fights springs to create visible wobble
	_apply_stagger_sway(delta)

	# Balance-informed stagger
	var balance := _compute_balance_ratio()
	balance_changed.emit(balance)

	# Too far off-balance → ragdoll (tipping over)
	if balance > _tuning.balance_ragdoll_threshold:
		_full_ragdoll()
		return

	# Regained balance → early recovery
	if balance < _tuning.balance_recovery_threshold:
		_balance_stable_timer += delta
		if _balance_stable_timer >= _tuning.balance_recovery_hold_time:
			_finish_stagger()
			return
	else:
		_balance_stable_timer = 0.0

	# Fallback: timer-based stagger end (safety net)
	if _stagger_elapsed >= _tuning.stagger_duration:
		_finish_stagger()


func _update_ragdoll(delta: float) -> void:
	_ragdoll_elapsed += delta
	if _spring.is_settled(delta) or _ragdoll_elapsed > _tuning.ragdoll_force_recovery_time:
		_start_recovery()


func _update_recovery(delta: float) -> void:
	if not _spring.get_skeleton():
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

	# Phase 2: Per-bone staggered strength ramp (fatigue-aware)
	for rig_name: String in _spring.get_all_bone_names():
		var delay: float = _tuning.ramp_delay.get(rig_name, 0.0)
		var effective_elapsed := maxf(0.0, _recovery_elapsed - delay)
		var effective_duration := maxf(0.1, _tuning.recovery_duration - delay)
		var t := clampf(effective_elapsed / effective_duration, 0.0, 1.0)
		var eased_t := t * t * t  # Cubic ease-in per bone
		var target: float = _effective_base_strength(rig_name)
		_spring.set_bone_strength(rig_name, target * eased_t)

	# Recovery completion check
	var global_t := clampf(_recovery_elapsed / _tuning.recovery_duration, 0.0, 1.0)
	var rotation_converged := _spring.get_max_rotation_error() < _tuning.recovery_rotation_threshold
	var min_time_met := global_t >= _tuning.recovery_completion_threshold
	var timed_out := _recovery_elapsed > _tuning.safety_timeout
	if (rotation_converged and min_time_met) or timed_out:
		_finish_recovery()


# ── Hit Handling ────────────────────────────────────────────────────────────

## Applies a hit reaction to [param body] using the given impact [param profile].
## Reduces spring strengths, applies impulse, and may trigger full ragdoll.
func apply_hit(body: RigidBody3D, hit_dir: Vector3, hit_pos: Vector3, profile: ImpactProfile) -> void:
	if not is_instance_valid(body):
		return
	if not _tuning or not _spring:
		push_warning("ActiveRagdollController: apply_hit() called before configure()")
		return

	# Hit streak: rapid consecutive hits escalate
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hit_time < _tuning.rapid_fire_window:
		_hit_streak += 1
	else:
		_hit_streak = 0
	_last_hit_time = now
	var streak_multiplier := 1.0 + (_hit_streak * _tuning.hit_streak_multiplier)

	# Compute impulse once (shared across all state paths)
	var final_impulse := profile.base_impulse * profile.impulse_transfer_ratio
	var direction := (hit_dir + Vector3.UP * profile.upward_bias).normalized()

	# Recovery interruption
	if _state == State.GETTING_UP:
		if profile.strength_reduction * streak_multiplier >= _tuning.recovery_interrupt_threshold:
			recovery_interrupted.emit()
			_full_ragdoll()
		else:
			body.apply_impulse(direction * final_impulse, body.to_local(hit_pos))
		return

	# Apply impulse
	body.apply_impulse(direction * final_impulse, body.to_local(hit_pos))

	# Micro hit reactions: brief angular kicks for immediate impact feel
	if _tuning.micro_reaction_strength > 0.0 and _state != State.RAGDOLL:
		_apply_micro_reaction(hit_dir, profile)

	# During ragdoll, just reset settle timer
	if _state == State.RAGDOLL:
		_spring.reset_settle_timer()
		return

	# Movement-aware scaling: moving characters are less stable
	var movement_multiplier := 1.0
	if _character_root and _tuning.movement_instability_bonus > 0.0:
		var char_speed := _get_character_speed()
		if char_speed > _tuning.movement_instability_min_speed:
			var speed_range := _tuning.movement_instability_max_speed - _tuning.movement_instability_min_speed
			var speed_ratio := clampf((char_speed - _tuning.movement_instability_min_speed) / maxf(speed_range, 0.01), 0.0, 1.0)
			movement_multiplier = 1.0 + speed_ratio * _tuning.movement_instability_bonus

	# Fatigue accumulation
	var old_fatigue := _fatigue
	_fatigue = clampf(_fatigue + profile.strength_reduction * _tuning.fatigue_gain, 0.0, 1.0)
	if absf(old_fatigue - _fatigue) > 0.01:
		fatigue_changed.emit(_fatigue)

	var effective_reduction := profile.strength_reduction * streak_multiplier * movement_multiplier

	# Pain accumulation: deterministic escalation from sustained fire
	_pain = clampf(_pain + effective_reduction * _tuning.pain_gain, 0.0, 1.0)
	pain_changed.emit(_pain)

	if _state == State.STAGGER:
		_handle_stagger_hit(body, hit_dir, effective_reduction, profile)
	else:
		_handle_normal_hit(body, hit_dir, effective_reduction, profile)


func _handle_stagger_hit(body: RigidBody3D, hit_dir: Vector3, effective_reduction: float, profile: ImpactProfile) -> void:
	_reduce_strength(body.name, effective_reduction, profile.strength_spread)
	_spring.recovery_rate = profile.recovery_rate
	var boosted_prob := profile.ragdoll_probability * _tuning.stagger_ragdoll_bonus
	if randf() < boosted_prob:
		_full_ragdoll()
	else:
		_stagger_elapsed = 0.0  # Extend stagger
		_stagger_hit_dir = hit_dir
		hit_absorbed.emit(body.name, _spring.get_bone_strength(body.name))


func _handle_normal_hit(body: RigidBody3D, hit_dir: Vector3, effective_reduction: float, profile: ImpactProfile) -> void:
	_reduce_strength(body.name, effective_reduction, profile.strength_spread)
	_spring.recovery_rate = profile.recovery_rate

	# Ragdoll check: dice roll + pain-driven deterministic escalation
	var should_ragdoll := randf() < profile.ragdoll_probability
	if not should_ragdoll and _tuning.pain_ragdoll_threshold > 0.0:
		should_ragdoll = _pain >= _tuning.pain_ragdoll_threshold
	if should_ragdoll:
		_full_ragdoll()
		return

	# Stagger check: strength ratio + balance + pain-driven escalation
	var avg_ratio := _compute_average_strength_ratio()
	var balance := _compute_balance_ratio()
	var should_stagger := avg_ratio < _tuning.stagger_threshold
	if not should_stagger and _tuning.balance_stagger_threshold > 0.0:
		should_stagger = balance > _tuning.balance_stagger_threshold
	if not should_stagger and _tuning.pain_stagger_threshold > 0.0:
		should_stagger = _pain >= _tuning.pain_stagger_threshold

	if should_stagger:
		_start_stagger(hit_dir)
	else:
		# Reaction pulse for sub-stagger hits (visible micro-wobble)
		var pulse_intensity := effective_reduction * _tuning.reaction_pulse_strength
		if pulse_intensity > 0.01:
			_apply_reaction_pulse(body.name, pulse_intensity, profile.strength_spread)
		hit_absorbed.emit(body.name, _spring.get_bone_strength(body.name))


# ── Public API ──────────────────────────────────────────────────────────────

## Forces an immediate transition to full ragdoll, zeroing all spring strengths.
func trigger_ragdoll() -> void:
	_full_ragdoll()


## Forces the character into a stagger state.
func trigger_stagger(hit_dir: Vector3 = Vector3.FORWARD) -> void:
	if _state == State.NORMAL:
		var floor_ratio: float = _tuning.stagger_strength_floor
		for rig_name: String in _spring.get_all_bone_names():
			var base: float = _spring.get_base_strength(rig_name)
			_spring.set_bone_strength(rig_name, base * floor_ratio)
		_start_stagger(hit_dir)


## Enables or disables persistent ragdoll (death/knockdown).
func set_persistent(enabled: bool) -> void:
	if enabled:
		_full_ragdoll()
		_state = State.PERSISTENT
		state_changed.emit(_state)
	else:
		if _state == State.PERSISTENT:
			_start_recovery()


## Returns the current state as a [enum State] integer value.
func get_state() -> int:
	return _state


## Returns the current center-of-mass balance ratio (0.0 = balanced, 1.0+ = off-balance).
func get_balance_ratio() -> float:
	return _compute_balance_ratio()


## Returns the current fatigue level (0.0 = fresh, 1.0 = exhausted).
func get_fatigue() -> float:
	return _fatigue


## Resets fatigue and pain to zero (e.g., on healing or respawn).
func reset_fatigue() -> void:
	_fatigue = 0.0
	_pain = 0.0
	_hit_streak = 0
	fatigue_changed.emit(0.0)
	pain_changed.emit(0.0)


## Returns the current hit streak count (rapid consecutive hits).
func get_hit_streak() -> int:
	return _hit_streak


## Returns the current pain level (0.0 = no pain, 1.0 = max accumulated pain).
## Pain deterministically escalates reactions from sustained fire.
func get_pain() -> float:
	return _pain


## Resets pain to zero (e.g., on healing or respawn).
func reset_pain() -> void:
	_pain = 0.0
	pain_changed.emit(0.0)


## Causes a brief defensive flinch toward the threat direction.
## Call from game code when the character detects incoming danger
## (e.g., bullets flying nearby, enemy winding up a melee attack).
## [param urgency] scales the effect (0.0 = none, 1.0 = full flinch).
func anticipate_threat(threat_dir: Vector3, urgency: float = 0.5) -> void:
	if _state != State.NORMAL:
		return
	var pulse_intensity := urgency * _tuning.threat_anticipation_strength
	if pulse_intensity > 0.01:
		var bodies := _rig_builder.get_bodies()
		var hips_body: RigidBody3D = bodies.get("Hips")
		if not hips_body:
			return
		# Find the bone closest to the threat direction for targeted pulse
		var best_bone := ""
		var best_dot := -1.0
		var center := hips_body.global_position
		var threat_xz := Vector2(threat_dir.x, threat_dir.z).normalized()
		for rig_name: String in bodies:
			var body: RigidBody3D = bodies[rig_name]
			var offset := Vector2(body.global_position.x - center.x,
				body.global_position.z - center.z)
			if offset.length_squared() < 0.001:
				continue
			var dot := offset.normalized().dot(threat_xz)
			if dot > best_dot:
				best_dot = dot
				best_bone = rig_name
		if best_bone != "":
			_apply_reaction_pulse(best_bone, pulse_intensity, 2)
	threat_anticipated.emit(threat_dir, urgency)


## Returns the injury level for a specific bone (0.0 = healthy, 1.0 = fully injured).
func get_injury(rig_name: String) -> float:
	return _injuries.get(rig_name, 0.0)


## Returns all current injuries as a Dictionary (rig_name → severity).
func get_all_injuries() -> Dictionary:
	return _injuries.duplicate()


## Resets all injuries to zero (e.g., on healing or respawn).
func reset_injuries() -> void:
	_injuries.clear()
	_spring.clear_pin_injuries()


## Returns a human-readable name for the current state (for debug display).
func get_state_name() -> String:
	match _state:
		State.NORMAL: return "NORMAL"
		State.STAGGER: return "STAGGER"
		State.RAGDOLL: return "RAGDOLL"
		State.GETTING_UP: return "GETTING UP"
		State.PERSISTENT: return "PERSISTENT"
	return "UNKNOWN"


# ── State Transitions ───────────────────────────────────────────────────────

func _full_ragdoll() -> void:
	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, 0.0)

	# Transfer character movement velocity to physics bodies
	if _tuning.transfer_character_velocity:
		var char_velocity := _get_character_velocity() * _tuning.velocity_transfer_scale
		if char_velocity.length_squared() > 0.01:
			var bodies := _rig_builder.get_bodies()
			for body: RigidBody3D in bodies.values():
				body.linear_velocity += char_velocity

	_state = State.RAGDOLL
	_ragdoll_elapsed = 0.0
	_reaction_pulses.clear()
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
	if not hip_body:
		_finish_recovery()
		return
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

	# Reposition character root to ragdoll landing position
	if _character_root and hip_body:
		var hip_pos := hip_body.global_position

		# Raycast down from hip to find ground height
		var ground_y := 0.0
		var space_state := _character_root.get_world_3d().direct_space_state
		var ray_origin := Vector3(hip_pos.x, hip_pos.y + _tuning.ground_raycast_up_offset, hip_pos.z)
		var ray_end := Vector3(hip_pos.x, hip_pos.y - _tuning.ground_raycast_down_distance, hip_pos.z)
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
			if _tuning.align_to_slope and ground_normal.dot(Vector3.UP) > _tuning.slope_alignment_threshold:
				var slope_forward := facing.slide(ground_normal).normalized()
				if slope_forward.length_squared() > 0.001:
					_character_root.global_basis = Basis.looking_at(slope_forward, ground_normal)
				else:
					_character_root.global_rotation.y = atan2(facing.x, facing.z)
			else:
				_character_root.global_rotation.y = atan2(facing.x, facing.z)

	# Restore body world transforms — bodies stay where they were
	for rig_name: String in saved_transforms:
		var body: RigidBody3D = bodies[rig_name]
		body.global_transform = saved_transforms[rig_name]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

	_ragdoll_poses = saved_transforms.duplicate()
	recovery_started.emit(face_up)

	# Force skeleton sync to prevent 1-frame visual pop after root teleport
	if _rig_sync:
		_rig_sync.sync_now()


func _finish_recovery() -> void:
	_state = State.NORMAL
	_hit_streak = 0
	_spring.recovery_rate = _spring.get_default_recovery_rate()
	_spring.clear_target_overrides()
	_ragdoll_poses.clear()
	state_changed.emit(_state)

	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, _effective_base_strength(rig_name))

	recovery_finished.emit()


func _start_stagger(hit_dir: Vector3) -> void:
	_state = State.STAGGER
	_stagger_elapsed = 0.0
	_balance_stable_timer = 0.0
	_reaction_pulses.clear()

	# Moving characters stagger in their movement direction, not just hit direction
	if _character_root and _tuning.movement_stagger_blend > 0.0:
		var char_vel := _get_character_velocity()
		if char_vel.length_squared() > _MOVEMENT_VELOCITY_THRESHOLD_SQ:
			hit_dir = hit_dir.lerp(char_vel.normalized(), _tuning.movement_stagger_blend).normalized()

	_stagger_hit_dir = hit_dir
	_com_initialized = false
	_sway_phase = randf() * TAU
	_spring.recovery_rate = _tuning.stagger_recovery_rate

	if _tuning.brace_strength_bonus > 0.0:
		_apply_directional_bracing(hit_dir)

	state_changed.emit(_state)
	stagger_started.emit(hit_dir)


func _finish_stagger() -> void:
	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, _effective_base_strength(rig_name))
	_state = State.NORMAL
	_balance_stable_timer = 0.0
	_com_initialized = false
	_spring.recovery_rate = _spring.get_default_recovery_rate()
	state_changed.emit(_state)
	stagger_finished.emit()


# ── Strength & Balance Helpers ──────────────────────────────────────────────

func _is_bone_protected(rig_name: String) -> bool:
	return rig_name in _protected_set


## Returns the effective base strength for a bone, reduced by fatigue and injury.
func _effective_base_strength(rig_name: String) -> float:
	var base: float = _spring.get_base_strength(rig_name)
	var fatigue_factor := 1.0 - _fatigue * _tuning.fatigue_impact
	var injury: float = _injuries.get(rig_name, 0.0)
	var injury_factor := 1.0 - injury * _tuning.injury_impact
	return base * fatigue_factor * injury_factor


func _reduce_strength(rig_name: String, reduction: float, spread: int) -> void:
	if _is_bone_protected(rig_name):
		return

	var current := _spring.get_bone_strength(rig_name)
	var floor: float = _tuning.min_strength.get(rig_name, 0.0)
	_spring.set_bone_strength(rig_name, maxf(current * (1.0 - reduction), floor))

	# Regional impairment: significant hits cause persistent injury
	if _tuning.injury_gain > 0.0 and reduction > _tuning.injury_threshold:
		var current_injury: float = _injuries.get(rig_name, 0.0)
		var new_injury := clampf(current_injury + reduction * _tuning.injury_gain, 0.0, 1.0)
		_injuries[rig_name] = new_injury
		region_injured.emit(rig_name, new_injury)

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
					if _is_bone_protected(neighbor):
						continue
					var s := _spring.get_bone_strength(neighbor)
					var nfloor: float = _tuning.min_strength.get(neighbor, 0.0)
					_spring.set_bone_strength(neighbor, maxf(s * (1.0 - reduction * falloff), nfloor))

			current_level = next_level


func _compute_average_strength_ratio() -> float:
	var total := 0.0
	var count := 0
	for rig_name: String in _spring.get_all_bone_names():
		var effective_base: float = _effective_base_strength(rig_name)
		if effective_base > 0.001:
			total += _spring.get_bone_strength(rig_name) / effective_base
			count += 1
	return total / float(count) if count > 0 else 1.0


func _compute_balance_state() -> Dictionary:
	var empty := {"com": Vector3.ZERO, "support_center": Vector3.ZERO, "balance_ratio": 0.0, "imbalance_dir": Vector2.ZERO}
	var bodies := _rig_builder.get_bodies()
	var foot_l: RigidBody3D = bodies.get("Foot_L")
	var foot_r: RigidBody3D = bodies.get("Foot_R")
	if not foot_l or not foot_r:
		return empty

	var com := Vector3.ZERO
	var total_mass := 0.0
	for body: RigidBody3D in bodies.values():
		com += body.global_position * body.mass
		total_mass += body.mass
	if total_mass <= 0.001:
		return empty
	com /= total_mass

	var support_center := (foot_l.global_position + foot_r.global_position) * 0.5
	var foot_spread := foot_l.global_position.distance_to(foot_r.global_position)
	var support_radius := maxf(foot_spread * 0.5, _tuning.balance_support_radius_min)

	var com_xz := Vector2(com.x, com.z)
	var support_xz := Vector2(support_center.x, support_center.z)
	var offset_vec := com_xz - support_xz
	var offset := offset_vec.length()
	var imbalance_dir := offset_vec.normalized() if offset > 0.001 else Vector2.ZERO

	return {
		"com": com,
		"support_center": support_center,
		"balance_ratio": clampf(offset / support_radius, 0.0, _tuning.balance_max_ratio),
		"imbalance_dir": imbalance_dir,
	}


func _compute_balance_ratio() -> float:
	return _compute_balance_state().balance_ratio


func _apply_reaction_pulse(rig_name: String, intensity: float, spread: int) -> void:
	if _is_bone_protected(rig_name):
		return
	_reaction_pulses[rig_name] = {"intensity": intensity, "elapsed": 0.0}

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
					if _is_bone_protected(neighbor):
						continue
					_reaction_pulses[neighbor] = {"intensity": intensity * falloff, "elapsed": 0.0}
			current_level = next_level


func _apply_micro_reaction(hit_dir: Vector3, profile: ImpactProfile) -> void:
	var bodies := _rig_builder.get_bodies()
	var intensity: float = profile.strength_reduction * _tuning.micro_reaction_strength

	# Head whip: torque pushes head in hit direction
	var head: RigidBody3D = bodies.get("Head")
	if head:
		var whip_torque := hit_dir.cross(Vector3.UP) * intensity * _tuning.micro_head_whip_strength
		head.apply_torque_impulse(whip_torque)

	# Torso bend: spine/chest bend away from hit direction
	for bone_name: String in ["Spine", "Chest"]:
		var bone_body: RigidBody3D = bodies.get(bone_name)
		if bone_body:
			var bend_torque := (-hit_dir).cross(Vector3.UP) * intensity * _tuning.micro_torso_bend_strength
			bone_body.apply_torque_impulse(bend_torque)

	# Spin: high-caliber hits twist the torso around Y axis
	if profile.base_impulse > 10.0:
		var hips: RigidBody3D = bodies.get("Hips")
		if hips:
			var spin_strength := profile.base_impulse * _tuning.micro_spin_strength * 0.01
			hips.apply_torque_impulse(Vector3.UP * spin_strength * signf(hit_dir.x))


func _sync_injuries_to_resolver() -> void:
	if _injuries.is_empty():
		return
	for rig_name: String in _injuries:
		_spring.set_pin_injury(rig_name, _injuries[rig_name])


## Returns the character root's movement velocity for ragdoll momentum transfer.
## Reads CharacterBody3D.velocity automatically, or calls get_velocity() if present.
## For CharacterBody3D enemies that walk toward the player, set
## transfer_character_velocity = false in RagdollTuning to prevent forward-launching.
func _get_character_velocity() -> Vector3:
	if not _character_root:
		return Vector3.ZERO
	if _character_root is CharacterBody3D:
		return (_character_root as CharacterBody3D).velocity
	elif _character_root.has_method("get_velocity"):
		return _character_root.get_velocity()
	return Vector3.ZERO


func _get_character_speed() -> float:
	return _get_character_velocity().length()


func _apply_directional_bracing(hit_dir: Vector3) -> void:
	var bodies := _rig_builder.get_bodies()
	var hips_body: RigidBody3D = bodies.get("Hips")
	if not hips_body:
		return
	var center := hips_body.global_position
	var hit_xz := Vector2(hit_dir.x, hit_dir.z).normalized()
	if hit_xz.length_squared() < 0.001:
		return

	var floor_ratio: float = _tuning.stagger_strength_floor
	var brace_bonus: float = _tuning.brace_strength_bonus

	for rig_name: String in _spring.get_all_bone_names():
		if _is_bone_protected(rig_name):
			continue
		var effective_base := _effective_base_strength(rig_name)

		# Core bones get a resistance boost to resist torso rotation
		if rig_name in _tuning.core_bracing_bones:
			var boosted := effective_base * (floor_ratio + brace_bonus * 0.5)
			_spring.set_bone_strength(rig_name, minf(boosted, effective_base))
			continue

		var body: RigidBody3D = bodies.get(rig_name)
		if not body:
			continue
		var bone_offset := Vector2(body.global_position.x - center.x,
			body.global_position.z - center.z)
		if bone_offset.length_squared() < 0.001:
			continue
		var dot := bone_offset.normalized().dot(hit_xz)

		var threshold: float = _tuning.bracing_direction_threshold
		if dot > threshold:
			# Hit side: reduce further below floor
			var weakened := effective_base * floor_ratio * (1.0 - dot * _tuning.bracing_hit_side_multiplier)
			_spring.set_bone_strength(rig_name, maxf(weakened, 0.0))
		elif dot < -threshold:
			# Brace side: boost above floor
			var braced := effective_base * (floor_ratio + brace_bonus * absf(dot))
			_spring.set_bone_strength(rig_name, minf(braced, effective_base))


func _is_leg_bone(rig_name: String) -> bool:
	return rig_name.begins_with("UpperLeg") or rig_name.begins_with("LowerLeg") or rig_name.begins_with("Foot")


func _get_bone_side(rig_name: String) -> String:
	if rig_name.ends_with("_L"):
		return "L"
	elif rig_name.ends_with("_R"):
		return "R"
	return ""


func _apply_active_resistance(delta: float) -> void:
	# Early exit if all resistance is disabled
	if _tuning.resistance_counter_strength <= 0.0 and _tuning.resistance_core_ramp <= 0.0 and _tuning.resistance_leg_brace <= 0.0:
		return

	var bodies := _rig_builder.get_bodies()
	var balance_state := _compute_balance_state()
	var com: Vector3 = balance_state.com
	var support_center: Vector3 = balance_state.support_center
	var balance_ratio: float = balance_state.balance_ratio
	var imbalance_dir: Vector2 = balance_state.imbalance_dir

	# CoM velocity tracking
	if _com_initialized:
		_com_velocity = (com - _prev_com) / maxf(delta, 0.001)
	else:
		_com_velocity = Vector3.ZERO
		_com_initialized = true
	_prev_com = com

	# Skip if perfectly balanced (no resistance needed)
	if balance_ratio < 0.05:
		return

	# Resistance capacity degrades with fatigue
	var resistance_capacity := clampf(1.0 - _fatigue * _tuning.fatigue_impact, 0.0, 1.0)

	# Velocity spike: reflexive tensing when CoM is swaying fast
	var com_speed_xz := Vector2(_com_velocity.x, _com_velocity.z).length()
	var velocity_factor := clampf(com_speed_xz / _tuning.resistance_velocity_scale, 0.0, 1.0)
	var velocity_multiplier := 1.0 + velocity_factor * _tuning.resistance_velocity_spike

	# Determine which leg is load-bearing (closer to the fall direction)
	var brace_side := ""
	if _tuning.resistance_leg_brace > 0.0:
		var foot_l: RigidBody3D = bodies.get("Foot_L")
		var foot_r: RigidBody3D = bodies.get("Foot_R")
		if foot_l and foot_r and imbalance_dir.length_squared() > 0.001:
			var support_xz := Vector2(support_center.x, support_center.z)
			var fl_xz := Vector2(foot_l.global_position.x, foot_l.global_position.z)
			var fr_xz := Vector2(foot_r.global_position.x, foot_r.global_position.z)
			var l_offset := fl_xz - support_xz
			var r_offset := fr_xz - support_xz
			var l_dot: float = l_offset.normalized().dot(imbalance_dir) if l_offset.length_squared() > 0.001 else 0.0
			var r_dot: float = r_offset.normalized().dot(imbalance_dir) if r_offset.length_squared() > 0.001 else 0.0
			brace_side = "L" if l_dot > r_dot else "R"

	# Hips center for bone offset computation
	var hips_body: RigidBody3D = bodies.get("Hips")
	if not hips_body:
		return
	var hips_center := Vector2(hips_body.global_position.x, hips_body.global_position.z)

	# Per-bone resistance
	for rig_name: String in _spring.get_all_bone_names():
		if _is_bone_protected(rig_name):
			continue

		var effective_base := _effective_base_strength(rig_name)
		var boost := 0.0

		# Component 1: Counter-imbalance stiffening
		if _tuning.resistance_counter_strength > 0.0 and imbalance_dir.length_squared() > 0.001:
			var body: RigidBody3D = bodies.get(rig_name)
			if body:
				var bone_xz := Vector2(body.global_position.x, body.global_position.z)
				var bone_offset := bone_xz - hips_center
				if bone_offset.length_squared() > 0.001:
					var counter_dot := -bone_offset.normalized().dot(imbalance_dir)
					if counter_dot > 0.0:
						boost += counter_dot * balance_ratio * _tuning.resistance_counter_strength * resistance_capacity

		# Component 2: Core progressive engagement
		if _tuning.resistance_core_ramp > 0.0 and rig_name in _tuning.core_bracing_bones:
			var core_urgency := clampf(balance_ratio / _tuning.balance_ragdoll_threshold, 0.0, 1.0)
			boost += core_urgency * _tuning.resistance_core_ramp * resistance_capacity

		# Component 3: Load-bearing leg bracing
		if _tuning.resistance_leg_brace > 0.0 and brace_side != "":
			if _is_leg_bone(rig_name) and _get_bone_side(rig_name) == brace_side:
				boost += balance_ratio * _tuning.resistance_leg_brace * resistance_capacity

		# Apply velocity multiplier and clamp to effective base
		if boost > 0.001:
			boost *= velocity_multiplier
			var current := _spring.get_bone_strength(rig_name)
			var target := minf(current + boost, effective_base)
			if target > current:
				_spring.set_bone_strength(rig_name, target)


func _apply_stagger_sway(_delta: float) -> void:
	if _tuning.stagger_sway_strength <= 0.0:
		return

	var bodies := _rig_builder.get_bodies()
	var hips: RigidBody3D = bodies.get("Hips")
	if not hips:
		return

	var freq := _tuning.stagger_sway_frequency
	var t := _stagger_elapsed + _sway_phase

	# Layered oscillation: two sin waves at irrational frequency ratio (never sync)
	var osc_primary := sin(t * freq * TAU)
	var osc_secondary := sin(t * freq * _tuning.stagger_sway_secondary_ratio * TAU) * _tuning.stagger_sway_drift

	# Quadratic decay: strong at start, fades over stagger duration
	var progress := clampf(_stagger_elapsed / _tuning.stagger_duration, 0.0, 1.0)
	var decay := (1.0 - progress) * (1.0 - progress)

	# Perpendicular drift: figure-8-like sway instead of straight back-and-forth
	var perp := _stagger_hit_dir.cross(Vector3.UP).normalized()
	var force := (_stagger_hit_dir * osc_primary + perp * osc_secondary) * _tuning.stagger_sway_strength * decay

	# Apply force to core bones (decreasing intensity up the chain)
	hips.apply_central_force(force)
	var spine: RigidBody3D = bodies.get("Spine")
	if spine:
		spine.apply_central_force(force * _tuning.stagger_sway_spine_falloff)
	var chest: RigidBody3D = bodies.get("Chest")
	if chest:
		chest.apply_central_force(force * _tuning.stagger_sway_chest_falloff)

	# Upper body twist: independent torso rotation at a third frequency
	var twist_osc := sin(t * freq * _tuning.stagger_sway_twist_ratio * TAU)
	var torque := Vector3.UP * _tuning.stagger_sway_strength * twist_osc * decay * _tuning.stagger_sway_twist
	if spine:
		spine.apply_torque(torque)
	if chest:
		chest.apply_torque(torque * _tuning.stagger_sway_chest_falloff)
