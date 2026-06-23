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

var _upper_arm_len: float = 0.0
var _lower_arm_len: float = 0.0
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

	# Compute arm segment lengths from rest poses (use left arm — symmetric skeleton).
	var ua := _skeleton.get_bone_global_rest(_bone_idx[_upper_l])
	var la := _skeleton.get_bone_global_rest(_bone_idx[_lower_l])
	var ha := _skeleton.get_bone_global_rest(_bone_idx[_hand_l])
	_upper_arm_len = ua.origin.distance_to(la.origin)
	_lower_arm_len = la.origin.distance_to(ha.origin)

	if _upper_arm_len < 0.01 or _lower_arm_len < 0.01:
		return false

	# Cache hand body refs (end-effectors) for the fall-reach contact pass.
	var bodies := rig_builder.get_bodies()
	_hand_body_l = bodies.get(_hand_l)
	_hand_body_r = bodies.get(_hand_r)

	_initialized = true
	return true


func is_initialized() -> bool:
	return _initialized


## True while either arm's IK has any influence (mid-blend or fully reaching).
func is_active() -> bool:
	return _weight_l > 0.001 or _weight_r > 0.001


## True while either arm has an active reach target (regardless of blend progress).
func is_reaching() -> bool:
	return _reach_active_l or _reach_active_r


# ── Reach control (driven by the controller) ───────────────────────────────

## Starts driving the arm on [param side] ("L"/"R") toward the world-space
## [param target]. The IK weight blends in over the next frames. Call
## [method update_reach] each frame to move a windmilling/tracking target.
func begin_reach(side: String, target: Vector3) -> void:
	if side == "L":
		_reach_target_l = target
		_reach_active_l = true
		_target_weight_l = 1.0
	elif side == "R":
		_reach_target_r = target
		_reach_active_r = true
		_target_weight_r = 1.0


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
		_solve_arm(overrides, _upper_l, _lower_l, _hand_l, _reach_target_l, _weight_l, sg)
	if _weight_r > 0.001:
		_solve_arm(overrides, _upper_r, _lower_r, _hand_r, _reach_target_r, _weight_r, sg)

	# Merge (not replace): the controller clears the override set once per frame and the
	# foot solver contributes first; arm runs last so it wins on any shared bone.
	_spring.merge_target_overrides(overrides)


## Solves one arm toward [param target] and writes weight-blended overrides for its
## three bones. The hand keeps its animation orientation (no slope concept for a
## hand) and sits at the target; the shoulder/elbow swing to follow.
func _solve_arm(overrides: Dictionary, upper_name: String, lower_name: String,
		hand_name: String, target: Vector3, weight: float, sg: Transform3D) -> void:
	var upper_anim := _anim_global(_bone_idx[upper_name], sg)
	var lower_anim := _anim_global(_bone_idx[lower_name], sg)
	var hand_anim := _anim_global(_bone_idx[hand_name], sg)

	var ik := TwoBoneIK.solve(_upper_arm_len, _lower_arm_len, upper_anim.origin,
		target, lower_anim.origin, upper_anim, lower_anim, hand_anim,
		-_character_root.global_basis.z)
	if ik.is_empty():
		# Target unreachable — leave this arm at its animation pose (no override).
		return

	var hand_ik := Transform3D(hand_anim.basis, target)
	overrides[upper_name] = upper_anim.interpolate_with(ik["upper"], weight)
	overrides[lower_name] = lower_anim.interpolate_with(ik["lower"], weight)
	overrides[hand_name] = hand_anim.interpolate_with(hand_ik, weight)


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
