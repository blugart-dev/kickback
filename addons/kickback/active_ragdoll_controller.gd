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
## Group used to discover the optional KickbackManager budget node.
const _BUDGET_GROUP := "kickback_manager"

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
var _disabled_collision_masks: Dictionary = {}  # rig_name → original collision_mask
var _state: int = State.NORMAL
var _recovery_elapsed: float = 0.0
var _ragdoll_elapsed: float = 0.0
var _ragdoll_poses: Dictionary = {}  # rig_name → Transform3D at recovery start
var _stagger_elapsed: float = 0.0
var _stagger_hit_dir: Vector3 = Vector3.ZERO
var _balance_stable_timer: float = 0.0
var _stumble_step_count: int = 0  # Steps taken this stumble (vs stumble_max_steps).
var _stumbling: bool = false  # In an active directed stumble (suspends tip-over ragdoll).
var _stumble_dir: Vector3 = Vector3.ZERO  # Horizontal knockback direction of the stumble.
var _stumble_drift: float = 0.0  # Current knockback drift speed (m/s), decays to 0.
var _stumble_dist_since_step: float = 0.0  # Drift distance accumulated toward the next step.
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
var _hit_guard_frame: int = -1
var _hit_guard_bodies: Dictionary = {}
var _profile: RagdollProfile
var _tuning: RagdollTuning
var _foot_ik: FootIKSolver
var _arm_ik: ArmIKSolver

# Arm bracing (0.4.0 Self-Preservation): the windmill sweep phase advances while
# stumbling; the cached shoulder rig-names anchor each arm's windmill circle.
var _windmill_phase: float = 0.0
var _arm_shoulder_l: String = ""
var _arm_shoulder_r: String = ""

# Cached semantic role rig-names, resolved from the profile (see RagdollProfile roles).
# Consumers query these instead of hardcoding "Hips"/"Foot_L"/... so non-Mixamo rigs work.
var _root_rig: String = "Hips"
var _chest_rig: String = "Chest"
var _head_rig: String = "Head"
var _foot_rigs: PackedStringArray = ["Foot_L", "Foot_R"]
var _torso_rigs: PackedStringArray = ["Hips", "Spine", "Chest"]
var _leg_rig_set: Dictionary = {}  # rig_name → true, O(1) leg membership

# Budget manager (optional, discovered via group). Holds at most one ragdoll slot.
var _manager: Node = null
var _holds_ragdoll_slot: bool = false

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
## Not emitted outside STAGGER — poll [method get_balance_ratio] for continuous monitoring.
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
## Emitted when a stumble recovery step begins during stagger. [param foot_rig] is
## the stepping foot; [param target] is the world-space step goal. Connect for step
## footstep SFX or a step animation hint. (0.4.0 Self-Preservation.)
signal stumble_step_started(foot_rig: String, target: Vector3)


func configure(profile: RagdollProfile, tuning: RagdollTuning) -> void:
	_profile = profile
	_tuning = tuning
	_resolve_roles()
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
	_resolve_roles()


## Resolves and caches semantic role rig-names from the profile.
func _resolve_roles() -> void:
	if not _profile:
		return
	_root_rig = _profile.get_root_rig()
	_chest_rig = _profile.get_chest_rig()
	_head_rig = _profile.get_head_rig()
	_foot_rigs = _profile.get_foot_rigs()
	_torso_rigs = _profile.get_torso_rigs()
	_leg_rig_set.clear()
	for leg: String in _profile.get_all_leg_rigs():
		_leg_rig_set[leg] = true
	# Shoulder rig-names anchor the windmill circles (chain[0] of each arm chain).
	var arm_l := _profile.get_arm_chain("L")
	var arm_r := _profile.get_arm_chain("R")
	_arm_shoulder_l = arm_l[0] if arm_l.size() == 3 else ""
	_arm_shoulder_r = arm_r[0] if arm_r.size() == 3 else ""


func _rebuild_protected_set() -> void:
	_protected_set.clear()
	if _tuning:
		for bone_name: String in _tuning.protected_bones:
			_protected_set[bone_name] = true


## Re-caches values that are stored at init time. Call when tuning changes at runtime.
func refresh_tuning() -> void:
	_rebuild_protected_set()


## Disables collision_mask for bones listed in normal_state_disabled_collision.
## Call when entering NORMAL state. Caches original masks for restoration.
func _disable_normal_collisions() -> void:
	if not _tuning or _tuning.normal_state_disabled_collision.is_empty():
		return
	if not _spring:
		return
	var bodies: Dictionary = _rig_builder.get_bodies() if _rig_builder else {}
	for rig_name: String in _tuning.normal_state_disabled_collision:
		if rig_name in bodies:
			var body: RigidBody3D = bodies[rig_name]
			if rig_name not in _disabled_collision_masks:
				_disabled_collision_masks[rig_name] = body.collision_mask
			body.collision_mask = 0


## Restores collision_mask for bones disabled by _disable_normal_collisions().
## Call when entering STAGGER or RAGDOLL state.
func _restore_disabled_collisions() -> void:
	if _disabled_collision_masks.is_empty():
		return
	var bodies: Dictionary = _rig_builder.get_bodies() if _rig_builder else {}
	for rig_name: String in _disabled_collision_masks:
		if rig_name in bodies:
			var body: RigidBody3D = bodies[rig_name]
			body.collision_mask = _disabled_collision_masks[rig_name]
	_disabled_collision_masks.clear()


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
			if not _foot_ik.initialize(_spring, _tuning, _character_root, _rig_builder, _profile):
				push_warning("ActiveRagdollController: foot IK disabled (missing leg bones)")
				_foot_ik = null

	# Lazy arm IK init (arm bracing — same deferral as foot IK)
	if not _arm_ik and _tuning and _tuning.arm_brace_enabled and _character_root:
		if not _spring.get_all_bone_names().is_empty():
			_arm_ik = ArmIKSolver.new()
			if not _arm_ik.initialize(_spring, _tuning, _character_root, _rig_builder, _profile):
				push_warning("ActiveRagdollController: arm bracing disabled (missing arm bones)")
				_arm_ik = null

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

	# IK solvers (foot + arm) share the spring's override channel and MERGE their
	# contributions, so clear it once per frame before they run. Only in NORMAL/STAGGER
	# (the IK-writing states); recovery in GETTING_UP owns the channel via its own
	# set_target_overrides. Foot solves first; arm last so it wins on any shared bone.
	match _state:
		State.NORMAL, State.STAGGER:
			_spring.clear_target_overrides()

	# Foot IK: solve during NORMAL, pin during STAGGER, reset otherwise
	if _foot_ik:
		match _state:
			State.NORMAL:
				_foot_ik.process(delta)
			State.STAGGER:
				_foot_ik.process_stagger(delta)
			_:
				_foot_ik.reset()

	# Arm IK: run during NORMAL/STAGGER (windmill is driven from the stumble update;
	# NORMAL keeps processing so a released brace blends out gracefully), reset otherwise
	if _arm_ik:
		match _state:
			State.NORMAL, State.STAGGER:
				_arm_ik.process(delta)
			_:
				_arm_ik.reset()


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

	# Balance is read by both active resistance and the tip/recovery checks below.
	# It sums CoM over every body, so compute it once per stagger frame and share
	# it (bodies don't move between these reads — only spring strengths change).
	var balance_state := _compute_balance_state()

	# Active resistance: dynamic per-frame strength adjustment
	_apply_active_resistance(delta, balance_state)

	# Continuous sway force: fights springs to create visible wobble
	_apply_stagger_sway(delta)

	# Balance-informed stagger (only when foot support can actually be measured)
	var balance: float = balance_state.balance_ratio
	var has_support: bool = balance_state.has_support
	balance_changed.emit(balance)

	# Directed stumble: a staggering hit knocks the character along the hit direction
	# (visible displacement) with the feet stepping to follow, while the body stiffens
	# to stay upright. Runs regardless of measured support (it's hit-driven, not
	# balance-driven) and COMMITS — the tip-over→ragdoll transition is suspended while
	# stumbling so the reaction plays out instead of collapsing mid-step.
	_update_directed_stumble(delta)

	if has_support:
		# Too far off-balance → ragdoll (tipping over), unless mid-stumble. Hard cap: if
		# the budget denies the slot, keep fighting in stagger instead of a full fall —
		# and retry on later frames, so it ragdolls as soon as a slot frees up.
		if balance > _tuning.balance_ragdoll_threshold and not _stumbling:
			if _try_acquire_ragdoll_slot():
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

	# Fallback: timer-based stagger end (safety net, and the sole exit without support)
	if _stagger_elapsed >= _tuning.stagger_duration:
		_finish_stagger()


## Drives the directed stumble (0.4.0 Self-Preservation): a staggering hit knocks the
## character root along the hit direction so the reaction visibly DISPLACES it, with
## the feet stepping to follow and the body stiffening to stay upright. The drift
## decays (momentum absorbed) over [member RagdollTuning.stumble_push_decel]; a step
## fires every [member RagdollTuning.stumble_step_length] of travel (trailing foot,
## up to [member RagdollTuning.stumble_max_steps]). Ends when the drift is spent and no
## step is in flight. While stumbling ([member _stumbling]) the caller suspends the
## tip-over→ragdoll transition so the reaction plays out. No-op without foot-IK pinning.
func _update_directed_stumble(delta: float) -> void:
	if not _stumbling:
		return
	if not _tuning.stumble_enabled or not _foot_ik or not _character_root:
		_stumbling = false
		_end_arm_brace()
		return

	# Drift the root along the hit direction (horizontal), decaying the speed.
	if _stumble_drift > 0.01:
		var step_move := _stumble_dir * _stumble_drift * delta
		_character_root.global_position += step_move
		_stumble_dist_since_step += step_move.length()
		_stumble_drift = maxf(_stumble_drift - _tuning.stumble_push_decel * delta, 0.0)

	# Pace a step every step_length of travel so the feet keep up with the body.
	if _stumble_step_count < _tuning.stumble_max_steps \
			and _stumble_dist_since_step >= _tuning.stumble_step_length \
			and not _foot_ik.is_stepping():
		_do_directed_step()
		_stumble_dist_since_step = 0.0

	# Stiffen the lower body so it stays upright as it lurches, while the upper body
	# stays loose and reacts (differential stiffness — see _apply_stumble_brace).
	_apply_stumble_brace()

	# Windmill the arms for balance — the active upper-body layer over the loose flail.
	_update_arm_windmill(delta)

	# Stumble is over once the momentum is spent and the last step has planted.
	if _stumble_drift <= 0.01 and not _foot_ik.is_stepping():
		_stumbling = false
		_end_arm_brace()  # release the windmill; the arms blend back to animation


## Steps the trailing foot (the one furthest back along the stumble direction) forward
## in that direction, through the foot IK solver. Returns nothing; bumps the step count
## and emits [signal stumble_step_started] when a step starts.
func _do_directed_step() -> void:
	var bodies := _rig_builder.get_bodies()
	var step_foot := ""
	var lowest := INF
	var dir2 := Vector2(_stumble_dir.x, _stumble_dir.z)
	for foot_rig: String in _foot_rigs:
		var fb: RigidBody3D = bodies.get(foot_rig)
		if not fb:
			continue
		var d := Vector2(fb.global_position.x, fb.global_position.z).dot(dir2)
		if d < lowest:
			lowest = d
			step_foot = foot_rig
	if step_foot.is_empty():
		return
	var fb: RigidBody3D = bodies[step_foot]

	# Place the step ahead of the HIPS in the stumble direction, but PRESERVE the
	# foot's lateral offset (its left/right side of the body) so the feet stay in their
	# own lanes and don't cross. Plant a step ahead of the body so it catches the drift.
	var hips: RigidBody3D = bodies.get(_root_rig)
	var center: Vector3 = hips.global_position if hips else fb.global_position
	var perp := Vector3(-_stumble_dir.z, 0.0, _stumble_dir.x)  # 90° in the ground plane
	var lateral := (fb.global_position - center).dot(perp)  # signed offset onto this foot's side
	var target := center + _stumble_dir * _tuning.stumble_step_length + perp * lateral
	target.y = fb.global_position.y  # the foot IK ground-snaps + lifts this
	if _foot_ik.begin_stumble(step_foot, target, _tuning.stumble_step_duration):
		_stumble_step_count += 1
		stumble_step_started.emit(step_foot, target)


## Differential stiffening while stumbling. Braces only the LOWER body (leg chains +
## pelvis) toward base so it steps and holds the character upright — but deliberately
## leaves the upper body (torso, arms, head) at the stagger floor so it stays LOOSE and
## reacts to the hit impulse and the stumble momentum. That contrast (purposeful legs,
## flailing upper body) is what reads as a live body caught off guard, rather than a
## rigid mannequin sliding on stepping feet. Transient — applied only while
## [member _stumbling]; strengths relax to the floor when the stumble ends.
func _apply_stumble_brace() -> void:
	var brace: float = _tuning.stumble_brace_strength
	if brace <= 0.0:
		return
	for rig_name: String in _spring.get_all_bone_names():
		if _is_bone_protected(rig_name):
			continue
		# Lower body only — legs (stepping + support) and the pelvis (root upright).
		if not (_is_leg_bone(rig_name) or rig_name == _root_rig):
			continue
		var target := _effective_base_strength(rig_name) * brace
		if _spring.get_bone_strength(rig_name) < target:
			_spring.set_bone_strength(rig_name, target)


## Drives the arm windmill while stumbling (0.4.0 Self-Preservation): each hand sweeps
## a wide vertical circle out to its own side, the two arms in opposite phase, so the
## upper body actively fights for balance instead of only flailing loosely. Targets are
## recomputed in world space each frame so the circles follow the displacing body. The
## arm IK blends these in by weight; an unreachable point just holds the animation pose.
func _update_arm_windmill(delta: float) -> void:
	if not _arm_ik or not _tuning.arm_brace_enabled:
		return
	_windmill_phase += _tuning.arm_windmill_speed * delta
	_drive_windmill_arm("L", _arm_shoulder_l, _windmill_phase)
	_drive_windmill_arm("R", _arm_shoulder_r, _windmill_phase + PI)


## Points one arm's windmill target for this frame. [param shoulder_rig] is the chain's
## shoulder body (the circle anchor); [param phase] is its position around the sweep.
func _drive_windmill_arm(side: String, shoulder_rig: String, phase: float) -> void:
	if shoulder_rig == "":
		return
	var bodies := _rig_builder.get_bodies()
	var shoulder_body: RigidBody3D = bodies.get(shoulder_rig)
	if not shoulder_body:
		return
	var shoulder := shoulder_body.global_position

	# Outward = the shoulder's horizontal offset from the body center, so each circle
	# sits on its own side regardless of facing (falls back to the character's lateral
	# axis if the shoulder sits on the centerline).
	var center_body: RigidBody3D = bodies.get(_root_rig)
	var outward := shoulder - (center_body.global_position if center_body else shoulder)
	outward.y = 0.0
	if outward.length_squared() < 0.0001:
		outward = _character_root.global_basis.x * (1.0 if side == "L" else -1.0)
	outward = outward.normalized()

	# Circle in the forward/up plane, offset out to the side and raised.
	var fwd := -_character_root.global_basis.z
	var circle_center := shoulder + outward * _tuning.arm_windmill_lateral \
		+ Vector3.UP * _tuning.arm_windmill_height
	var sweep := (fwd * cos(phase) + Vector3.UP * sin(phase)) * _tuning.arm_windmill_radius
	_arm_ik.begin_reach(side, circle_center + sweep)


## Releases the arm windmill (blends the arms back toward the animation pose).
func _end_arm_brace() -> void:
	if not _arm_ik:
		return
	_arm_ik.end_reach("L")
	_arm_ik.end_reach("R")


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

	# Per-frame debounce: ignore duplicate hits on the same body within a single
	# physics frame. Prevents feedback loops when body_entered re-triggers hits.
	var frame := Engine.get_physics_frames()
	if frame != _hit_guard_frame:
		_hit_guard_frame = frame
		_hit_guard_bodies.clear()
	var body_rid := body.get_rid()
	if body_rid in _hit_guard_bodies:
		return
	_hit_guard_bodies[body_rid] = true

	# Resolve the rig name from the builder's body map rather than trusting
	# body.name (Godot may suffix-rename on a node-name collision, and a baked rig
	# keys bodies by metadata, not node name). A body that isn't a registered rig
	# body is not part of this ragdoll — warn and ignore rather than silently no-op
	# the strength logic.
	var rig_name := _rig_name_for_body(body)
	if rig_name.is_empty():
		push_warning("ActiveRagdollController.apply_hit: '%s' is not a registered rig body — ignoring." % body.name)
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
		_handle_stagger_hit(rig_name, hit_dir, effective_reduction, profile)
	else:
		_handle_normal_hit(rig_name, hit_dir, effective_reduction, profile)


func _handle_stagger_hit(rig_name: String, hit_dir: Vector3, effective_reduction: float, profile: ImpactProfile) -> void:
	_reduce_strength(rig_name, effective_reduction, profile.strength_spread)
	_spring.recovery_rate = profile.recovery_rate
	var boosted_prob := profile.ragdoll_probability * _tuning.stagger_ragdoll_bonus
	# Hard cap: if the budget denies the slot, fall through to extend the stagger
	# (the cheaper reaction) rather than ragdoll.
	if randf() < boosted_prob and _try_acquire_ragdoll_slot():
		_full_ragdoll()
	else:
		_stagger_elapsed = 0.0  # Extend stagger
		_stagger_hit_dir = hit_dir
		hit_absorbed.emit(rig_name, _spring.get_bone_strength(rig_name))


func _handle_normal_hit(rig_name: String, hit_dir: Vector3, effective_reduction: float, profile: ImpactProfile) -> void:
	_reduce_strength(rig_name, effective_reduction, profile.strength_spread)
	_spring.recovery_rate = profile.recovery_rate

	# Ragdoll check: dice roll + pain-driven deterministic escalation
	var should_ragdoll := randf() < profile.ragdoll_probability
	if not should_ragdoll and _tuning.pain_ragdoll_threshold > 0.0:
		should_ragdoll = _pain >= _tuning.pain_ragdoll_threshold
	if should_ragdoll:
		if _try_acquire_ragdoll_slot():
			_full_ragdoll()
		else:
			_start_stagger(hit_dir)  # hard cap: downgrade to the cheaper reaction
		return

	# Stagger check: strength ratio + balance + pain-driven escalation
	var avg_ratio := _compute_average_strength_ratio()
	var balance_state := _compute_balance_state()
	var should_stagger := avg_ratio < _tuning.stagger_threshold
	if not should_stagger and balance_state.has_support and _tuning.balance_stagger_threshold > 0.0:
		should_stagger = balance_state.balance_ratio > _tuning.balance_stagger_threshold
	if not should_stagger and _tuning.pain_stagger_threshold > 0.0:
		should_stagger = _pain >= _tuning.pain_stagger_threshold

	if should_stagger:
		_start_stagger(hit_dir)
	else:
		# Reaction pulse for sub-stagger hits (visible micro-wobble)
		var pulse_intensity := effective_reduction * _tuning.reaction_pulse_strength
		if pulse_intensity > 0.01:
			_apply_reaction_pulse(rig_name, pulse_intensity, profile.strength_spread)
		hit_absorbed.emit(rig_name, _spring.get_bone_strength(rig_name))


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


## Returns the full balance state: {com, support_center, balance_ratio, imbalance_dir}.
func get_balance_state() -> Dictionary:
	return _compute_balance_state()


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
		var hips_body: RigidBody3D = bodies.get(_root_rig)
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


## Resolved root rig name (for the debug HUD / external queries).
func get_root_rig() -> String:
	return _root_rig

## Resolved head rig name.
func get_head_rig() -> String:
	return _head_rig

## Resolved foot rig names.
func get_foot_rigs() -> PackedStringArray:
	return _foot_rigs


# ── State Transitions ───────────────────────────────────────────────────────

func _full_ragdoll() -> void:
	_restore_disabled_collisions()
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

	# Budget slot bookkeeping. Spontaneous hit/balance ragdolls already reserved a
	# slot via _try_acquire_ragdoll_slot() (so this is a no-op for them). Explicit
	# trigger_ragdoll()/set_persistent() reach here WITHOUT a reservation and
	# acquire opportunistically — they bypass the hard cap (a scripted or death
	# ragdoll must always proceed) but still hold a slot for accurate accounting
	# when one is free.
	if not _holds_ragdoll_slot:
		var mgr := _resolve_manager()
		if mgr:
			_holds_ragdoll_slot = mgr.request_active_ragdoll()


func _start_recovery() -> void:
	_state = State.GETTING_UP
	_recovery_elapsed = 0.0
	state_changed.emit(_state)

	var bodies := _rig_builder.get_bodies()
	var hip_body: RigidBody3D = bodies.get(_root_rig)
	if not hip_body:
		_finish_recovery()
		return
	var chest_body: RigidBody3D = bodies.get(_chest_rig)
	var head_body: RigidBody3D = bodies.get(_head_rig)

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
	_disable_normal_collisions()
	state_changed.emit(_state)

	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, _effective_base_strength(rig_name))

	_release_ragdoll_slot()
	recovery_finished.emit()


func _start_stagger(hit_dir: Vector3) -> void:
	_restore_disabled_collisions()
	_state = State.STAGGER
	_stagger_elapsed = 0.0
	_balance_stable_timer = 0.0
	_stumble_step_count = 0
	_stumbling = false
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

	# Begin a directed stumble: knock the character along the hit direction so the
	# reaction visibly DISPLACES it, with the feet stepping to follow. The horizontal
	# hit direction drives both the drift and the step direction.
	_stumble_dir = Vector3(hit_dir.x, 0.0, hit_dir.z)
	if _tuning.stumble_enabled and _foot_ik and _character_root and _stumble_dir.length() > 0.01:
		_stumble_dir = _stumble_dir.normalized()
		_stumble_drift = _tuning.stumble_push_speed
		_stumble_dist_since_step = _tuning.stumble_step_length  # step on the first frame
		_stumbling = true
		_windmill_phase = 0.0  # arms windmill for balance for the duration of the stumble
	else:
		_stumble_dir = Vector3.ZERO
		_stumble_drift = 0.0
		_stumbling = false

	if _tuning.brace_strength_bonus > 0.0:
		_apply_directional_bracing(hit_dir)

	if _foot_ik:
		_foot_ik.begin_stagger()

	state_changed.emit(_state)
	stagger_started.emit(hit_dir)


func _finish_stagger() -> void:
	if _foot_ik:
		_foot_ik.end_stagger()
	_end_arm_brace()
	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, _effective_base_strength(rig_name))
	_state = State.NORMAL
	_balance_stable_timer = 0.0
	_com_initialized = false
	_stumbling = false
	_stumble_drift = 0.0
	_spring.recovery_rate = _spring.get_default_recovery_rate()
	_disable_normal_collisions()
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
	var empty := {"com": Vector3.ZERO, "support_center": Vector3.ZERO, "balance_ratio": 0.0, "imbalance_dir": Vector2.ZERO, "has_support": false}
	var bodies := _rig_builder.get_bodies()

	# Collect the foot bodies that actually exist (role-driven, multi-rig safe).
	var feet: Array[RigidBody3D] = []
	for foot_rig: String in _foot_rigs:
		var fb: RigidBody3D = bodies.get(foot_rig)
		if fb:
			feet.append(fb)
	if feet.is_empty():
		return empty

	var com := Vector3.ZERO
	var total_mass := 0.0
	for body: RigidBody3D in bodies.values():
		com += body.global_position * body.mass
		total_mass += body.mass
	if total_mass <= 0.001:
		return empty
	com /= total_mass

	var support_center := Vector3.ZERO
	for f: RigidBody3D in feet:
		support_center += f.global_position
	support_center /= feet.size()

	# Support radius = furthest foot from the centre (= half the spread for two feet).
	var support_radius := _tuning.balance_support_radius_min
	for f: RigidBody3D in feet:
		support_radius = maxf(support_radius, f.global_position.distance_to(support_center))

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
		"has_support": true,
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
	var head: RigidBody3D = bodies.get(_head_rig)
	if head:
		var whip_torque := hit_dir.cross(Vector3.UP) * intensity * _tuning.micro_head_whip_strength
		head.apply_torque_impulse(whip_torque)

	# Torso bend: spine/chest bend away from hit direction (skip the root/pelvis)
	for torso_rig: String in _torso_rigs:
		if torso_rig == _root_rig:
			continue
		var bone_body: RigidBody3D = bodies.get(torso_rig)
		if bone_body:
			var bend_torque := (-hit_dir).cross(Vector3.UP) * intensity * _tuning.micro_torso_bend_strength
			bone_body.apply_torque_impulse(bend_torque)

	# Spin: high-caliber hits twist the torso around Y axis
	if profile.base_impulse > 10.0:
		var hips: RigidBody3D = bodies.get(_root_rig)
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


# ── Budget (optional KickbackManager) ───────────────────────────────────────

func _exit_tree() -> void:
	# Release any held budget slot if the character is removed mid-ragdoll.
	_release_ragdoll_slot()


## Resolves the optional budget manager via its group (works for autoload or
## in-scene placement). Cached after first lookup; null if none present.
func _resolve_manager() -> Node:
	if _manager and is_instance_valid(_manager):
		return _manager
	if is_inside_tree():
		var m: Node = get_tree().get_first_node_in_group(_BUDGET_GROUP)
		if m and m.has_method("request_active_ragdoll"):
			_manager = m
	return _manager


## Tries to reserve a budget slot for a NEW spontaneous full ragdoll. Returns
## true (caller may ragdoll) when a slot is granted, when one is already held, or
## when no KickbackManager is present (unbudgeted). Returns false ONLY when a
## manager is present and at capacity — the hard cap, telling the caller to
## substitute a cheaper reaction (stagger). Explicit trigger_ragdoll() and
## set_persistent() do NOT gate on this: deliberate and death ragdolls always
## proceed (a scripted death must not silently become a stagger).
func _try_acquire_ragdoll_slot() -> bool:
	if _holds_ragdoll_slot:
		return true
	var mgr := _resolve_manager()
	if not mgr:
		return true
	_holds_ragdoll_slot = mgr.request_active_ragdoll()
	return _holds_ragdoll_slot


func _release_ragdoll_slot() -> void:
	if _holds_ragdoll_slot:
		if _manager and is_instance_valid(_manager):
			_manager.release_active_ragdoll()
		_holds_ragdoll_slot = false


## Resolves the rig name for a hit body via the builder's body map, rather than
## trusting body.name (Godot may suffix-rename on a node-name collision; a baked
## rig keys bodies by metadata). Returns "" if the body isn't a registered rig body.
func _rig_name_for_body(body: RigidBody3D) -> String:
	var bodies := _rig_builder.get_bodies()
	for candidate: String in bodies:
		if bodies[candidate] == body:
			return candidate
	return ""


func _apply_directional_bracing(hit_dir: Vector3) -> void:
	var bodies := _rig_builder.get_bodies()
	var hips_body: RigidBody3D = bodies.get(_root_rig)
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
	return _leg_rig_set.has(rig_name)


func _apply_active_resistance(delta: float, balance_state: Dictionary) -> void:
	# Early exit if all resistance is disabled
	if _tuning.resistance_counter_strength <= 0.0 and _tuning.resistance_core_ramp <= 0.0 and _tuning.resistance_leg_brace <= 0.0:
		return

	var bodies := _rig_builder.get_bodies()
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
	# Load-bearing leg = the foot furthest in the fall direction; brace its side.
	var brace_side := ""
	if _tuning.resistance_leg_brace > 0.0 and imbalance_dir.length_squared() > 0.001:
		var support_xz := Vector2(support_center.x, support_center.z)
		var best_dot := -INF
		for foot_rig: String in _foot_rigs:
			var fb: RigidBody3D = bodies.get(foot_rig)
			if not fb:
				continue
			var f_offset := Vector2(fb.global_position.x, fb.global_position.z) - support_xz
			if f_offset.length_squared() <= 0.001:
				continue
			var d := f_offset.normalized().dot(imbalance_dir)
			if d > best_dot:
				best_dot = d
				brace_side = _profile.get_leg_side(foot_rig)

	# Hips center for bone offset computation
	var hips_body: RigidBody3D = bodies.get(_root_rig)
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
			if _is_leg_bone(rig_name) and _profile.get_leg_side(rig_name) == brace_side:
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
	var hips: RigidBody3D = bodies.get(_root_rig)
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

	# Apply full force to the root, then the rest of the torso with falloff
	# (chest_rig uses the chest falloff; other torso bones use the spine falloff).
	hips.apply_central_force(force)

	# Upper body twist: independent torso rotation at a third frequency
	var twist_osc := sin(t * freq * _tuning.stagger_sway_twist_ratio * TAU)
	var torque := Vector3.UP * _tuning.stagger_sway_strength * twist_osc * decay * _tuning.stagger_sway_twist

	for torso_rig: String in _torso_rigs:
		if torso_rig == _root_rig:
			continue
		var tb: RigidBody3D = bodies.get(torso_rig)
		if not tb:
			continue
		var is_chest := torso_rig == _chest_rig
		var force_falloff: float = _tuning.stagger_sway_chest_falloff if is_chest else _tuning.stagger_sway_spine_falloff
		tb.apply_central_force(force * force_falloff)
		var twist_falloff: float = _tuning.stagger_sway_chest_falloff if is_chest else 1.0
		tb.apply_torque(torque * twist_falloff)
