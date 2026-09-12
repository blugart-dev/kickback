## Velocity-based spring resolver that drives physics ragdoll bodies toward
## animation skeleton poses. Each frame, computes rotation/position error per
## bone and lerps rigid body velocities toward the correction (plus the target's
## own motion, fed forward), weighted by per-bone strength. Bodies update
## parent-first and a jointed child's linear command follows its parent through
## the joint anchor, so the joint solve has nothing to fight (see
## RagdollTuning.spring_chain_consistency / spring_feed_forward). Strength can be
## reduced on hit so physics wins temporarily, then recovers over time.
## Corrections are normalized to a 60 Hz reference, so the feel is frame-rate
## independent — bit-identical at 60 Hz, stable at 30/120.
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
var _bone_names: PackedStringArray = PackedStringArray()  # cached _bones.keys(); stable after _init_bones()
## Spring update order: parent-first down the joint chain, so a child's linear
## command can be derived from its parent's ALREADY-written velocities.
var _order: PackedStringArray = PackedStringArray()
## rig_name → {parent: String, anchor_parent: Vector3, anchor_child: Vector3}
## for every body that hangs off a joint (from PhysicsRigBuilder.get_joints()).
var _chain: Dictionary = {}
var _chain_consistency: float = 1.0
var _feed_forward: float = 1.0
var _settle_timer: float = 0.0
var _default_recovery_rate: float = 0.3
var _target_overrides: Dictionary = {}  # rig_name → Transform3D (temporary blend targets)
var _pin_injury_modifiers: Dictionary = {}  # rig_name → float (0.0-1.0, reduces pin strength)
var _tuning: RagdollTuning
var _max_angular_vel_sq: float = 400.0
var _max_linear_vel_sq: float = 100.0
var _strip_root_motion: bool = true
var _root_motion_bone: String = "Hips"
## Skeleton bone index of the root-motion rig bone (-1 = none). Resolved from the
## rig name in [method _init_bones] / [method refresh_tuning]; the XZ of THIS bone's
## local pose is zeroed inside [method get_animation_bone_global], so every
## consumer of the animation target (springs, foot/arm IK, the get-up blend) sees
## the same root-motion-free pose — children included.
var _root_motion_bone_idx: int = -1

const PROPERTY_THRESHOLD := 0.01
## Spring tuning is calibrated at 60 Hz. Per-tick blend weights and velocity
## targets are normalized to this reference so behaviour matches across physics
## tick rates (and is bit-identical at 60 Hz). See [method _fr_weight].
const _REFERENCE_HZ := 60.0


func configure(tuning: RagdollTuning) -> void:
	_tuning = tuning
	if _tuning:
		_max_angular_vel_sq = _tuning.max_angular_velocity * _tuning.max_angular_velocity
		_max_linear_vel_sq = _tuning.max_linear_velocity * _tuning.max_linear_velocity
		_chain_consistency = _tuning.spring_chain_consistency
		_feed_forward = _tuning.spring_feed_forward


## Re-caches values that are stored at init time. Call when tuning changes at runtime.
func refresh_tuning() -> void:
	if _tuning:
		_max_angular_vel_sq = _tuning.max_angular_velocity * _tuning.max_angular_velocity
		_max_linear_vel_sq = _tuning.max_linear_velocity * _tuning.max_linear_velocity
		_strip_root_motion = _tuning.strip_root_motion
		_root_motion_bone = _tuning.root_motion_bone
		_chain_consistency = _tuning.spring_chain_consistency
		_feed_forward = _tuning.spring_feed_forward
		_resolve_root_motion_bone()


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
	_strip_root_motion = _tuning.strip_root_motion
	_root_motion_bone = _tuning.root_motion_bone
	_chain_consistency = _tuning.spring_chain_consistency
	_feed_forward = _tuning.spring_feed_forward


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
			"prev_target": Transform3D.IDENTITY,
			"has_prev_target": false,
		}
	# Cache the rig-name list once. The key set is fixed after init (only the
	# per-bone values mutate), and get_all_bone_names() is hit every physics
	# frame by the controller/HUD/foot-IK — returning the cached PackedStringArray
	# avoids rebuilding it from _bones.keys() on each call.
	_bone_names = PackedStringArray(_bones.keys())
	_init_chain()
	_resolve_root_motion_bone()


func _resolve_root_motion_bone() -> void:
	_root_motion_bone_idx = -1
	if not _skeleton or not _rig_builder:
		return
	var bone_name := _rig_builder.get_bone_name_for_body(_root_motion_bone)
	if bone_name != "":
		_root_motion_bone_idx = _skeleton.find_bone(bone_name)


## Builds the joint chain (parent links + anchors) and the parent-first update
## order from the builder's joint registry. Bodies without a registered joint
## (roots, or a rig built by an older baker) are ordered first and get the
## legacy independent linear command.
func _init_chain() -> void:
	_chain.clear()
	var joints := _rig_builder.get_joints()
	for child_rig: String in joints:
		var j: Dictionary = joints[child_rig]
		if child_rig in _bones and j.parent in _bones:
			_chain[child_rig] = {
				"parent": j.parent,
				"anchor_parent": j.anchor_parent,
				"anchor_child": j.anchor_child,
			}
	var depth: Dictionary = {}
	for rig_name: String in _bones:
		var d := 0
		var cur := rig_name
		var guard := 0
		while cur in _chain and guard < 64:
			cur = _chain[cur].parent
			d += 1
			guard += 1
		depth[rig_name] = d
	var names: Array = _bones.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return depth[a] < depth[b] if depth[a] != depth[b] else a < b)
	_order = PackedStringArray(names)


## Returns the Skeleton3D used for animation target poses.
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Enables or disables hit-reactive strength recovery. Springs ALWAYS run and
## drive bodies toward the animation pose; this flag only gates the per-frame
## strength recovery in [method _physics_process].
func set_active(value: bool) -> void:
	_ensure_tuning()
	_active = value


## Returns true if the spring resolver is currently active.
func is_active() -> bool:
	return _active


func _physics_process(delta: float) -> void:
	if _bones.is_empty() or not _skeleton:
		return

	# Cache animation bone globals once per frame
	var skel_global := _skeleton.global_transform
	var has_overrides := not _target_overrides.is_empty()

	# Single merged pass: strength recovery + property updates + spring computation.
	# Parent-first: a child's linear command reads its parent's velocities as
	# written THIS tick (see the chain block below).
	for rig_name: String in _order:
		var state: Dictionary = _bones[rig_name]
		var body: RigidBody3D = state.body

		# Strength recovery (only when hit-reactive mode is active)
		if _active:
			state.strength = move_toward(state.strength, state.base_strength, recovery_rate * delta)
		var ratio := _strength_ratio(state)

		# Property updates: gravity + damping scale with strength ratio. A limp bone
		# (ratio 0) gets the tuning's full gravity_scale; a bone at full strength none.
		var new_gravity := (1.0 - ratio) * _tuning.gravity_scale
		var new_ang_damp := _tuning.spring_angular_damp_base + _tuning.spring_angular_damp_scale * ratio
		var new_lin_damp := _tuning.spring_linear_damp_base + _tuning.spring_linear_damp_scale * ratio
		if absf(body.gravity_scale - new_gravity) > PROPERTY_THRESHOLD:
			body.gravity_scale = new_gravity
		if absf(body.angular_damp - new_ang_damp) > PROPERTY_THRESHOLD:
			body.angular_damp = new_ang_damp
		if absf(body.linear_damp - new_lin_damp) > PROPERTY_THRESHOLD:
			body.linear_damp = new_lin_damp

		# Spring computation
		var strength: float = state.strength
		if strength < 0.001:
			state.has_prev_target = false  # a limp bone's target isn't tracked; no stale feed-forward when it wakes
			continue

		var target_xform: Transform3D
		if has_overrides and rig_name in _target_overrides:
			target_xform = _target_overrides[rig_name]
		else:
			# Root motion (if stripped) is removed inside get_animation_bone_global.
			target_xform = skel_global * get_animation_bone_global(state.bone_idx)
		var current_xform := body.global_transform

		# Feed-forward: how the target itself moved since last tick (world rotation
		# vector + translation), see _apply_angular_spring.
		var ff_rot := Vector3.ZERO
		var ff_lin := Vector3.ZERO
		if _feed_forward > 0.0 and state.has_prev_target:
			var prev: Transform3D = state.prev_target
			var dq: Quaternion = (target_xform.basis.orthonormalized() * prev.basis.orthonormalized().inverse()).get_rotation_quaternion()
			if dq.w < 0:
				dq = -dq
			var dangle := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
			var daxis := Vector3(dq.x, dq.y, dq.z)
			if daxis.length_squared() >= 0.0001 and dangle >= 0.0001:
				ff_rot = daxis.normalized() * dangle * _feed_forward
			ff_lin = (target_xform.origin - prev.origin) * _feed_forward
		state.prev_target = target_xform
		state.has_prev_target = true

		_apply_angular_spring(body, target_xform, current_xform, strength, delta, ff_rot)

		var pin := _get_pin_strength(rig_name) * ratio
		# Injury reduces pin strength (creates visible sag/limp on injured bones)
		var pin_injury: float = _pin_injury_modifiers.get(rig_name, 0.0)
		if pin_injury > 0.0:
			pin *= (1.0 - pin_injury * _tuning.injury_pin_impact)
		var pos_error := target_xform.origin - current_xform.origin
		# Linear settle deadband (see _apply_angular_spring): zero corrective velocity
		# within the deadband, ramping in above it, to kill the position-spring buzz floor.
		var dist := pos_error.length()
		var lin_target := Vector3.ZERO
		if dist > 0.0001:
			lin_target = pos_error * (maxf(dist - _tuning.spring_linear_settle_deadband, 0.0) / dist) * _REFERENCE_HZ
		lin_target += ff_lin / maxf(delta, 1e-6)
		# Chain consistency: the joint locks this body's anchor to its parent's, so
		# whatever linear velocity we command, the solver overwrites it with "parent
		# anchor velocity" — and pays for the mismatch with equal-and-opposite
		# impulses at the anchor. The anchor sits half a bone from each body's
		# centre of mass, so those impulses SPIN the bodies — and on a light one
		# (head, hand, foot: tiny inertia) a 0.1-0.3 m/s anchor pull comes back as
		# several rad/s: measured on a 16-body rig, a head's commanded angular
		# velocity returned from the solve reversed, and 50-90 % of the chest's was
		# rewritten every tick while children were pinned independently (the idle
		# wobble / rig lag). Command the kinematically consistent velocity up front
		# — v_child = v_parent + w_parent x r_parent - w_child x r_child, with the
		# parent's velocities as written this tick (parent-first order) — and scale
		# the child's own position pin out by the same factor: a pull the joint
		# won't allow is exactly such an anchor impulse. The child's position
		# follows from its ancestors' orientation springs and the root pin instead
		# (the joint holds it there); the solver has nothing left to fight.
		var lin_base := body.linear_velocity
		if _chain_consistency > 0.0 and rig_name in _chain:
			var link: Dictionary = _chain[rig_name]
			var parent_body: RigidBody3D = _bones[link.parent].body
			var r_parent: Vector3 = parent_body.global_basis * link.anchor_parent
			var r_child: Vector3 = current_xform.basis * link.anchor_child
			var consistent: Vector3 = parent_body.linear_velocity \
				+ parent_body.angular_velocity.cross(r_parent) \
				- body.angular_velocity.cross(r_child)
			lin_base = lin_base.lerp(consistent, _chain_consistency)
			pin *= 1.0 - _chain_consistency
		body.linear_velocity = lin_base.lerp(lin_target, _fr_weight(pin, delta))

		if body.angular_velocity.length_squared() > _max_angular_vel_sq:
			body.angular_velocity = body.angular_velocity.normalized() * _tuning.max_angular_velocity
		if body.linear_velocity.length_squared() > _max_linear_vel_sq:
			body.linear_velocity = body.linear_velocity.normalized() * _tuning.max_linear_velocity


func _strength_ratio(state: Dictionary) -> float:
	return state.strength / state.base_strength if state.base_strength > 0.001 else 1.0


## [param ff_rot] is the target's own rotation over the last tick (world rotation
## vector, radians), fed forward so a MOVING target is tracked without the
## one-tick-per-tick lag of a pure error spring (see [member RagdollTuning.spring_feed_forward]).
func _apply_angular_spring(body: RigidBody3D, target: Transform3D, current: Transform3D, strength: float, delta: float, ff_rot: Vector3 = Vector3.ZERO) -> void:
	var error_basis := target.basis.orthonormalized() * current.basis.orthonormalized().inverse()
	var det := error_basis.determinant()
	if det < 0.001 and det > -0.001:
		return

	var q := error_basis.get_rotation_quaternion()
	if q.w < 0:
		q = -q

	var angle := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	var axis_raw := Vector3(q.x, q.y, q.z)
	# Settle deadband: command NO correction within the deadband, then ramp in
	# proportionally above it. A tiny irreducible steady-state error (e.g. a planted
	# foot the joints can't perfectly satisfy) would otherwise be amplified by the
	# ×_REFERENCE_HZ conversion into sustained velocity every tick — the idle buzz.
	# Negligible for the large errors of real motion / hit reactions.
	var correction := Vector3.ZERO
	if axis_raw.length_squared() >= 0.0001 and angle >= 0.001:
		var eff_angle := maxf(angle - _tuning.spring_angular_settle_deadband, 0.0)
		correction = (axis_raw.normalized() * eff_angle) * _REFERENCE_HZ
	if correction == Vector3.ZERO and ff_rot == Vector3.ZERO:
		return
	# Feed-forward: the error term alone reaches where the target WAS; add the
	# target's own velocity so the body arrives where it IS (zero steady-state lag
	# on a moving target). Scaled by strength like everything else — a weakened
	# bone follows the animation's motion less, as before.
	var target_vel := correction + ff_rot / maxf(delta, 1e-6)
	body.angular_velocity = body.angular_velocity.lerp(target_vel, _fr_weight(strength, delta))


## Converts a 60 Hz-calibrated lerp weight into a frame-rate-independent weight for
## the current physics step. The per-tick fraction is reparameterized so the
## convergence rate per unit wall-clock time stays constant across tick rates; at
## 60 Hz this returns the weight unchanged (delta * _REFERENCE_HZ == 1). The weight
## is clamped to [0, 1] (a >1 lerp would mean extrapolation, which has no stable
## frame-rate-independent form).
static func _fr_weight(weight: float, delta: float) -> float:
	return 1.0 - pow(1.0 - clampf(weight, 0.0, 1.0), delta * _REFERENCE_HZ)


func _get_pin_strength(rig_name: String) -> float:
	return _tuning.pin_strength_overrides.get(rig_name, _tuning.default_pin_strength)


## Computes the skeleton-local global transform for a bone by walking the
## parent chain of ANIMATION poses (get_bone_pose — never the modifier output).
## When [member RagdollTuning.strip_root_motion] is on, the XZ translation of the
## root-motion bone's local pose is zeroed on the way up, so the bone AND every
## descendant are returned without the clip's horizontal root motion. Stripping
## only the root body's target (pre-0.4.1) left its children's targets displaced
## by the root motion, leaning the whole rig off its pinned pelvis.
func get_animation_bone_global(bone_idx: int) -> Transform3D:
	var xform := _local_anim_pose(bone_idx)
	var parent_idx := _skeleton.get_bone_parent(bone_idx)
	while parent_idx >= 0:
		xform = _local_anim_pose(parent_idx) * xform
		parent_idx = _skeleton.get_bone_parent(parent_idx)
	return xform


func _local_anim_pose(bone_idx: int) -> Transform3D:
	var pose := _skeleton.get_bone_pose(bone_idx)
	if _strip_root_motion and bone_idx == _root_motion_bone_idx:
		pose.origin.x = 0.0
		pose.origin.z = 0.0
	return pose


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
## Cached at init (the key set is fixed once bones are built); callers must treat
## the result as read-only.
func get_all_bone_names() -> PackedStringArray:
	return _bone_names


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


## Merges target pose overrides into the current set (later keys win), so several IK
## contributors (foot + arm) can write the same frame without clobbering each other.
## The controller clears the set once per frame before the solvers run, so stale keys
## don't accumulate.
func merge_target_overrides(overrides: Dictionary) -> void:
	_target_overrides.merge(overrides, true)


## Clears all target pose overrides, reverting to animation-driven targets.
func clear_target_overrides() -> void:
	_target_overrides.clear()


## Sets an injury modifier for a bone's pin strength (0.0-1.0).
## Injured bones have weaker position tracking, causing visible sag.
func set_pin_injury(rig_name: String, injury: float) -> void:
	if injury <= 0.001:
		_pin_injury_modifiers.erase(rig_name)
	else:
		_pin_injury_modifiers[rig_name] = injury


## Clears all pin injury modifiers.
func clear_pin_injuries() -> void:
	_pin_injury_modifiers.clear()


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
