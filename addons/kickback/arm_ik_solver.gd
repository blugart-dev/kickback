## Two-bone arm IK solver for bracing reactions — driving the arms to windmill for
## balance during a stumble and to reach toward the ground when a fall commits.
## Mirrors [FootIKSolver]: direct two-bone IK (via the shared [TwoBoneIK]) computed
## in _physics_process, feeding results to [SpringResolver.set_target_overrides].
## Does NOT use the engine's IK nodes because PhysicsRigSync contaminates
## SkeletonModifier3D bone pose readings.
##
## Owned by [ActiveRagdollController]. The controller decides WHEN each arm reaches
## and WHERE (the directed bracing); this just animates the arm toward a world goal
## and blends the IK in and out by weight.
class_name ArmIKSolver
extends RefCounted

var _spring: SpringResolver
var _tuning: RagdollTuning
var _character_root: Node3D
var _skeleton: Skeleton3D

# Segment lengths measured PER SIDE from the rest pose (skeletons are not
# guaranteed symmetric — see FootIKSolver).
var _upper_arm_len_l: float = 0.0
var _lower_arm_len_l: float = 0.0
var _upper_arm_len_r: float = 0.0
var _lower_arm_len_r: float = 0.0
var _bone_idx: Dictionary = {}  # rig_name → skeleton bone index

# Resolved role rig-names (from RagdollProfile semantic roles). Defaults match the
# Mixamo convention; initialize() overwrites them from the profile.
var _upper_l: String = "UpperArm_L"
var _lower_l: String = "LowerArm_L"
var _hand_l: String = "Hand_L"
var _upper_r: String = "UpperArm_R"
var _lower_r: String = "LowerArm_R"
var _hand_r: String = "Hand_R"

# Per-arm reach state. _reach_active gates a target; _weight is the blended IK
# influence (0 = pure animation, 1 = arm fully at the IK solution); _target_weight
# is what _weight ramps toward (1 while reaching, 0 once released).
var _reach_target_l: Vector3 = Vector3.ZERO
var _reach_target_r: Vector3 = Vector3.ZERO
var _reach_active_l: bool = false
var _reach_active_r: bool = false
var _weight_l: float = 0.0
var _weight_r: float = 0.0
var _target_weight_l: float = 0.0
var _target_weight_r: float = 0.0

# Hand body refs (end-effectors), cached for the fall-reach ground-contact pass.
var _hand_body_l: RigidBody3D
var _hand_body_r: RigidBody3D

# The rig body map, so the solver can anchor to where the arm PHYSICALLY is (see
# _physics_anchored). Stable reference, set once at init.
var _rig_bodies: Dictionary = {}
# When true, the solve anchors to the arm's physical body transforms instead of the
# animation pose. The windmill runs against the animation (springs hold the body near
# it during a stagger); the fall reach must anchor to the limp body, which has fallen
# away from the animation pose, or the reach is computed from a phantom standing arm.
var _physics_anchored: bool = false

var _initialized: bool = false

# Per-solve scratch buffers, reused to avoid per-frame allocations (see FootIKSolver
# for the safety argument — each node's _physics_process runs to completion in turn).
var _anim_cache: Dictionary = {}
var _overrides_buf: Dictionary = {}


func initialize(spring: SpringResolver, tuning: RagdollTuning, character_root: Node3D,
		rig_builder: PhysicsRigBuilder, profile: RagdollProfile) -> bool:
	_spring = spring
	_tuning = tuning
	_character_root = character_root
	_skeleton = spring.get_skeleton()

	if not _skeleton or not _character_root:
		return false

	# Resolve arm chains from the profile's semantic roles. A chain is empty if
	# incomplete (arm IK needs shoulder→elbow→hand), in which case IK is unavailable.
	var left := profile.get_arm_chain("L")
	var right := profile.get_arm_chain("R")
	if left.size() != 3 or right.size() != 3:
		return false
	_upper_l = left[0]
	_lower_l = left[1]
	_hand_l = left[2]
	_upper_r = right[0]
	_lower_r = right[1]
	_hand_r = right[2]

	# Look up bone indices for all required arm bones.
	for rig_name: String in [_upper_l, _lower_l, _hand_l, _upper_r, _lower_r, _hand_r]:
		var idx := spring.get_bone_idx(rig_name)
		if idx < 0:
			return false
		_bone_idx[rig_name] = idx

	# Segment lengths from the rest pose, measured on each arm separately.
	_upper_arm_len_l = _rest_length(_upper_l, _lower_l)
	_lower_arm_len_l = _rest_length(_lower_l, _hand_l)
	_upper_arm_len_r = _rest_length(_upper_r, _lower_r)
	_lower_arm_len_r = _rest_length(_lower_r, _hand_r)

	if _upper_arm_len_l < 0.01 or _lower_arm_len_l < 0.01 \
			or _upper_arm_len_r < 0.01 or _lower_arm_len_r < 0.01:
		return false

	# Cache the body map (physical anchoring) + hand refs (fall-reach contact pass).
	_rig_bodies = rig_builder.get_bodies()
	_hand_body_l = _rig_bodies.get(_hand_l)
	_hand_body_r = _rig_bodies.get(_hand_r)

	_initialized = true
	return true


## Rest-pose distance between two rig bones' origins (a segment length).
func _rest_length(from_rig: String, to_rig: String) -> float:
	var a := _skeleton.get_bone_global_rest(_bone_idx[from_rig])
	var b := _skeleton.get_bone_global_rest(_bone_idx[to_rig])
	return a.origin.distance_to(b.origin)


func is_initialized() -> bool:
	return _initialized


## True while either arm's IK has any influence (mid-blend or fully reaching).
func is_active() -> bool:
	return _weight_l > 0.001 or _weight_r > 0.001


## Full arm reach (upper + lower segment lengths) of the arm on [param side] ("L"/"R").
## Lets the caller place a reach target the arm can actually hit. With no side (or an
## unknown one) returns the SHORTER arm's reach, so a target placed within it is
## reachable by either arm.
func get_reach(side: String = "") -> float:
	var reach_l := _upper_arm_len_l + _lower_arm_len_l
	var reach_r := _upper_arm_len_r + _lower_arm_len_r
	if side == "L":
		return reach_l
	if side == "R":
		return reach_r
	return minf(reach_l, reach_r)


## Anchor the solve to the physical arm bodies (true) or the animation pose (false).
## Use physical anchoring whenever the body has left the animation pose — e.g. a limp
## fall — so the reach is computed from where the arm actually is.
func set_physics_anchored(enabled: bool) -> void:
	_physics_anchored = enabled


## True while either arm has an active reach target (regardless of blend progress).
func is_reaching() -> bool:
	return _reach_active_l or _reach_active_r


# ── Reach control (driven by the controller) ───────────────────────────────

## Starts driving the arm on [param side] ("L"/"R") toward the world-space
## [param target], blending the IK in to [param weight] (1.0 = fully on the IK
## solution, lower = a tendency layered over the loose physics pose). Call
## [method update_reach] each frame to move a windmilling/tracking target, or just call
## this again — it re-asserts the target and weight, so it's safe to call per frame.
func begin_reach(side: String, target: Vector3, weight: float = 1.0) -> void:
	if side == "L":
		_reach_target_l = target
		_reach_active_l = true
		_target_weight_l = weight
	elif side == "R":
		_reach_target_r = target
		_reach_active_r = true
		_target_weight_r = weight


## Moves an already-active reach target without changing its blend (use to animate a
## windmill arc or to track a moving ground contact). No-op if the arm isn't reaching.
func update_reach(side: String, target: Vector3) -> void:
	if side == "L" and _reach_active_l:
		_reach_target_l = target
	elif side == "R" and _reach_active_r:
		_reach_target_r = target


## Releases the arm on [param side]; its IK weight blends back out to the animation
## pose over the next frames.
func end_reach(side: String) -> void:
	if side == "L":
		_reach_active_l = false
		_target_weight_l = 0.0
	elif side == "R":
		_reach_active_r = false
		_target_weight_r = 0.0


# ── Solve ──────────────────────────────────────────────────────────────────

func process(delta: float) -> void:
	if not _initialized:
		return
	# Nothing to do once both arms are released and fully blended out.
	if not is_reaching() and not is_active():
		return
	_solve(delta)


func _solve(delta: float) -> void:
	var sg := _skeleton.global_transform
	_anim_cache.clear()
	var overrides := _overrides_buf
	overrides.clear()

	# Ramp each arm's weight toward its target (frame-rate-independent blend).
	var blend := 1.0 - exp(-_tuning.arm_brace_blend_speed * delta)
	_weight_l = lerpf(_weight_l, _target_weight_l, blend)
	_weight_r = lerpf(_weight_r, _target_weight_r, blend)

	if _weight_l > 0.001:
		_solve_arm(overrides, _upper_arm_len_l, _lower_arm_len_l,
			_upper_l, _lower_l, _hand_l, _reach_target_l, _weight_l, sg)
	if _weight_r > 0.001:
		_solve_arm(overrides, _upper_arm_len_r, _lower_arm_len_r,
			_upper_r, _lower_r, _hand_r, _reach_target_r, _weight_r, sg)

	# Merge (not replace): the controller clears the override set once per frame and the
	# foot solver contributes first; arm runs last so it wins on any shared bone.
	_spring.merge_target_overrides(overrides)


## Solves one arm toward [param target] and writes weight-blended overrides for its
## three bones. The hand keeps its source orientation (no slope concept for a hand) and
## sits at the solver's effective end position — the target clamped onto the arm's
## reach, so an out-of-reach goal (a wide windmill sweep, a distant brace point)
## extends the arm fully toward it instead of dropping the override and popping the
## arm back to its source pose. The shoulder/elbow swing to follow. The source pose is
## the arm's animation pose, or its physical body pose when [member _physics_anchored]
## (so the reach is computed from where the arm actually is, not a fallen-away
## animation pose). [param upper_len]/[param lower_len] are this arm's segment lengths.
func _solve_arm(overrides: Dictionary, upper_len: float, lower_len: float,
		upper_name: String, lower_name: String, hand_name: String,
		target: Vector3, weight: float, sg: Transform3D) -> void:
	var upper_src: Transform3D
	var lower_src: Transform3D
	var hand_src: Transform3D
	if _physics_anchored:
		upper_src = _body_global(upper_name)
		lower_src = _body_global(lower_name)
		hand_src = _body_global(hand_name)
	else:
		upper_src = _anim_global(_bone_idx[upper_name], sg)
		lower_src = _anim_global(_bone_idx[lower_name], sg)
		hand_src = _anim_global(_bone_idx[hand_name], sg)

	var ik := TwoBoneIK.solve(upper_len, lower_len, upper_src.origin,
		target, lower_src.origin, upper_src, lower_src, hand_src,
		_elbow_fallback_axis())
	if ik.is_empty():
		# Degenerate input only (non-finite source / target) — leave this arm at its
		# source pose. Reach is never the reason: the solver clamps to the arm's band.
		return

	var hand_ik := Transform3D(hand_src.basis, ik["end"])
	overrides[upper_name] = upper_src.interpolate_with(ik["upper"], weight)
	overrides[lower_name] = lower_src.interpolate_with(ik["lower"], weight)
	overrides[hand_name] = hand_src.interpolate_with(hand_ik, weight)


## Direction the elbow bends toward when the source arm is straight enough that its
## own elbow gives no bend plane: the character's BACKWARD, honouring the model's
## authoring convention ([member RagdollTuning.character_forward_sign]). An elbow
## folds the forearm toward the front, so the elbow itself is displaced backward —
## the mirror of the knee (see FootIKSolver._knee_fallback_axis).
func _elbow_fallback_axis() -> Vector3:
	return -_character_root.global_basis.z * float(_tuning.character_forward_sign)


## World-space physical transform of a rig body (the physical-anchor source).
func _body_global(rig_name: String) -> Transform3D:
	var body: RigidBody3D = _rig_bodies.get(rig_name)
	return body.global_transform if body else Transform3D.IDENTITY


## World-space animation global for a bone index, memoized per solve (see
## FootIKSolver._anim_global). Caller clears _anim_cache at the start of each solve.
func _anim_global(bone_idx: int, sg: Transform3D) -> Transform3D:
	if _anim_cache.has(bone_idx):
		return _anim_cache[bone_idx]
	var g := sg * _spring.get_animation_bone_global(bone_idx)
	_anim_cache[bone_idx] = g
	return g


# ── Reset (RAGDOLL/GETTING_UP/PERSISTENT) ──────────────────────────────────

func reset() -> void:
	_reach_active_l = false
	_reach_active_r = false
	_target_weight_l = 0.0
	_target_weight_r = 0.0
	_weight_l = 0.0
	_weight_r = 0.0
	_physics_anchored = false
