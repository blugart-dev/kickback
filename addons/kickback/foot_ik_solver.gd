## Two-bone foot IK solver for planting feet on uneven terrain.
## Uses direct math (law of cosines) computed in _physics_process, feeding
## results to SpringResolver.set_target_overrides(). Does NOT use TwoBoneIK3D
## because PhysicsRigSync contaminates SkeletonModifier3D bone pose readings.
##
## Owned by ActiveRagdollController. Called during NORMAL state (full solve),
## STAGGER (pin feet to prevent sliding), and RAGDOLL/GETTING_UP/PERSISTENT
## (silent reset).
class_name FootIKSolver
extends RefCounted

var _spring: SpringResolver
var _tuning: RagdollTuning
var _character_root: Node3D
var _skeleton: Skeleton3D
var _world_3d: World3D

var _upper_leg_len: float = 0.0
var _lower_leg_len: float = 0.0
var _bone_idx: Dictionary = {}  # rig_name → skeleton bone index
var _hips_idx: int = -1

# Resolved role rig-names (from RagdollProfile semantic roles). Defaults match the
# Mixamo convention; initialize() overwrites them from the profile.
var _root: String = "Hips"
var _upper_l: String = "UpperLeg_L"
var _lower_l: String = "LowerLeg_L"
var _foot_l: String = "Foot_L"
var _upper_r: String = "UpperLeg_R"
var _lower_r: String = "LowerLeg_R"
var _foot_r: String = "Foot_R"

var _ik_weight_l: float = 0.0
var _ik_weight_r: float = 0.0
var _pelvis_offset: float = 0.0
var _initialized: bool = false

# Foot collision management
var _foot_body_l: RigidBody3D
var _foot_body_r: RigidBody3D
var _foot_mask_l: int = 0
var _foot_mask_r: int = 0
var _collision_disabled: bool = false

# Stagger foot pinning
var _stagger_pinning: bool = false
var _pin_pos_l: Vector3 = Vector3.ZERO
var _pin_pos_r: Vector3 = Vector3.ZERO

# Per-solve scratch buffers, reused to avoid per-frame allocations.
#   _anim_cache:   bone_idx → world-space animation global, rebuilt each solve so
#                  no bone's parent chain is walked more than once per frame.
#   _overrides_buf: the target-override dict handed to the SpringResolver. Safe to
#                  reuse because the controller's solve and the spring's read of it
#                  never interleave within a physics frame — each node's
#                  _physics_process runs to completion in turn, so the spring never
#                  observes a half-cleared buffer (and a same-frame solve fully
#                  rebuilds it before the spring reads).
var _anim_cache: Dictionary = {}
var _overrides_buf: Dictionary = {}


func initialize(spring: SpringResolver, tuning: RagdollTuning, character_root: Node3D,
		rig_builder: PhysicsRigBuilder, profile: RagdollProfile) -> bool:
	_spring = spring
	_tuning = tuning
	_character_root = character_root
	_skeleton = spring.get_skeleton()
	_world_3d = character_root.get_world_3d()

	if not _skeleton or not _world_3d:
		return false

	# Resolve leg chains + root from the profile's semantic roles. A chain is empty
	# if incomplete (foot IK needs hip→knee→foot), in which case IK is unavailable.
	var left := profile.get_leg_chain("L")
	var right := profile.get_leg_chain("R")
	_root = profile.get_root_rig()
	if left.size() != 3 or right.size() != 3 or _root == "":
		return false
	_upper_l = left[0]
	_lower_l = left[1]
	_foot_l = left[2]
	_upper_r = right[0]
	_lower_r = right[1]
	_foot_r = right[2]

	# Look up bone indices for all required leg bones + root
	for rig_name: String in [_upper_l, _lower_l, _foot_l, _upper_r, _lower_r, _foot_r]:
		var idx := spring.get_bone_idx(rig_name)
		if idx < 0:
			return false
		_bone_idx[rig_name] = idx

	_hips_idx = spring.get_bone_idx(_root)
	if _hips_idx < 0:
		return false

	# Compute bone lengths from rest poses (use left leg — symmetric skeleton)
	var ul := _skeleton.get_bone_global_rest(_bone_idx[_upper_l])
	var ll := _skeleton.get_bone_global_rest(_bone_idx[_lower_l])
	var fl := _skeleton.get_bone_global_rest(_bone_idx[_foot_l])
	_upper_leg_len = ul.origin.distance_to(ll.origin)
	_lower_leg_len = ll.origin.distance_to(fl.origin)

	if _upper_leg_len < 0.01 or _lower_leg_len < 0.01:
		return false

	# Cache foot body refs for collision management
	var bodies := rig_builder.get_bodies()
	_foot_body_l = bodies.get(_foot_l)
	_foot_body_r = bodies.get(_foot_r)
	if _foot_body_l:
		_foot_mask_l = _foot_body_l.collision_mask
	if _foot_body_r:
		_foot_mask_r = _foot_body_r.collision_mask

	_initialized = true
	return true


func is_initialized() -> bool:
	return _initialized


func is_active() -> bool:
	return _ik_weight_l > 0.001 or _ik_weight_r > 0.001 or absf(_pelvis_offset) > 0.001


# ── NORMAL state: full IK solve ────────────────────────────────────────────

func process(delta: float) -> void:
	if not _initialized or not _tuning.foot_ik_enabled:
		return
	_disable_foot_collision()
	_solve_ik(delta, false)


# ── STAGGER state: pin feet or blend out ───────────────────────────────────

func begin_stagger() -> void:
	if not _initialized or not _tuning.foot_ik_stagger_pin:
		return
	# Capture current foot body positions as pin targets
	if _foot_body_l:
		_pin_pos_l = _foot_body_l.global_position
	if _foot_body_r:
		_pin_pos_r = _foot_body_r.global_position
	_stagger_pinning = true


func process_stagger(delta: float) -> void:
	if not _initialized or not _tuning.foot_ik_enabled:
		return
	if not _stagger_pinning:
		_blend_out(delta)
		return
	_disable_foot_collision()
	_boost_leg_strength()
	_solve_ik(delta, true)


func end_stagger() -> void:
	_stagger_pinning = false


func _blend_out(delta: float) -> void:
	var blend := 1.0 - exp(-_tuning.foot_ik_foot_blend_speed * delta)
	_ik_weight_l = lerpf(_ik_weight_l, 0.0, blend)
	_ik_weight_r = lerpf(_ik_weight_r, 0.0, blend)
	_pelvis_offset = lerpf(_pelvis_offset, 0.0,
		1.0 - exp(-_tuning.foot_ik_pelvis_blend_speed * delta))
	if _ik_weight_l < 0.001 and _ik_weight_r < 0.001:
		_spring.clear_target_overrides()
		_restore_foot_collision()


# ── RAGDOLL/GETTING_UP/PERSISTENT: silent reset ───────────────────────────

func reset() -> void:
	_ik_weight_l = 0.0
	_ik_weight_r = 0.0
	_pelvis_offset = 0.0
	_stagger_pinning = false
	_restore_foot_collision()


# ── Shared IK computation ─────────────────────────────────────────────────

func _solve_ik(delta: float, use_pins: bool) -> void:
	var sg := _skeleton.global_transform
	var root_y := _character_root.global_position.y

	# Animation poses (memoized per solve; the cache is reused by the full-body
	# shift below so no bone's parent chain is walked more than once per frame).
	_anim_cache.clear()
	var hips_anim := _anim_global(_hips_idx, sg)
	var hip_y := hips_anim.origin.y
	var upper_l := _anim_global(_bone_idx[_upper_l], sg)
	var lower_l := _anim_global(_bone_idx[_lower_l], sg)
	var foot_l := _anim_global(_bone_idx[_foot_l], sg)
	var upper_r := _anim_global(_bone_idx[_upper_r], sg)
	var lower_r := _anim_global(_bone_idx[_lower_r], sg)
	var foot_r := _anim_global(_bone_idx[_foot_r], sg)

	# Foot XZ source: animation (NORMAL) or pinned positions (STAGGER)
	var foot_xz_l := Vector2(foot_l.origin.x, foot_l.origin.z)
	var foot_xz_r := Vector2(foot_r.origin.x, foot_r.origin.z)
	if use_pins:
		foot_xz_l = Vector2(_pin_pos_l.x, _pin_pos_l.z)
		foot_xz_r = Vector2(_pin_pos_r.x, _pin_pos_r.z)

	# Ground raycasts from hip height at foot XZ positions
	var ray_above := _tuning.foot_ik_ray_above_hip
	var ray_total := ray_above + _tuning.foot_ik_ray_below_hip
	var gl := _raycast_ground(
		Vector3(foot_xz_l.x, hip_y + ray_above, foot_xz_l.y), ray_total)
	var gr := _raycast_ground(
		Vector3(foot_xz_r.x, hip_y + ray_above, foot_xz_r.y), ray_total)

	# Per-foot offsets and target weights
	var offset_l := 0.0
	var offset_r := 0.0
	var tw_l := 0.0
	var tw_r := 0.0
	var gpos_l := foot_l.origin
	var gpos_r := foot_r.origin
	var gnorm_l := Vector3.UP
	var gnorm_r := Vector3.UP
	# A foot only counts as "supporting" the pelvis when it found ground the body
	# can actually reach (see the pelvis adjustment below). offset_* feed ONLY the
	# pelvis drop — the per-leg solves target gpos_*.y directly.
	var supported_l := false
	var supported_r := false

	if not gl.is_empty():
		gpos_l = gl["position"]
		gnorm_l = gl.get("normal", Vector3.UP)
		var raw_offset_l := (gpos_l.y + _tuning.foot_ik_ankle_height) - foot_l.origin.y
		offset_l = clampf(raw_offset_l, -_tuning.foot_ik_max_adjustment, _tuning.foot_ik_max_adjustment)
		# Ground deeper than the pelvis can drop to is a drop-off, not support: such
		# a foot must not drag the body down and break the other foot's plant.
		supported_l = raw_offset_l >= -_tuning.foot_ik_max_pelvis_drop
		var far := foot_l.origin.y - root_y
		if far < _tuning.foot_ik_swing_threshold:
			tw_l = clampf(
				1.0 - (far - _tuning.foot_ik_plant_threshold) / (_tuning.foot_ik_swing_threshold - _tuning.foot_ik_plant_threshold),
				0.0, 1.0)

	if not gr.is_empty():
		gpos_r = gr["position"]
		gnorm_r = gr.get("normal", Vector3.UP)
		var raw_offset_r := (gpos_r.y + _tuning.foot_ik_ankle_height) - foot_r.origin.y
		offset_r = clampf(raw_offset_r, -_tuning.foot_ik_max_adjustment, _tuning.foot_ik_max_adjustment)
		supported_r = raw_offset_r >= -_tuning.foot_ik_max_pelvis_drop
		var far := foot_r.origin.y - root_y
		if far < _tuning.foot_ik_swing_threshold:
			tw_r = clampf(
				1.0 - (far - _tuning.foot_ik_plant_threshold) / (_tuning.foot_ik_swing_threshold - _tuning.foot_ik_plant_threshold),
				0.0, 1.0)

	# Smooth weights
	var blend := 1.0 - exp(-_tuning.foot_ik_foot_blend_speed * delta)
	_ik_weight_l = lerpf(_ik_weight_l, tw_l, blend)
	_ik_weight_r = lerpf(_ik_weight_r, tw_r, blend)

	# Pelvis adjustment — drop the whole body to the lowest *supported* foot so its
	# leg doesn't overstretch. Feet over a gap (no ground hit) or a drop-off beyond
	# pelvis reach are excluded (INF) so they can't pull the pelvis down onto the
	# other, planted foot. If neither foot supports, the pelvis returns to neutral.
	var drop_l: float = (offset_l * _ik_weight_l) if supported_l else INF
	var drop_r: float = (offset_r * _ik_weight_r) if supported_r else INF
	var deepest := minf(drop_l, drop_r)
	var target_pelvis: float = clampf(deepest, -_tuning.foot_ik_max_pelvis_drop, 0.0) if deepest < INF else 0.0
	_pelvis_offset = lerpf(_pelvis_offset, target_pelvis,
		1.0 - exp(-_tuning.foot_ik_pelvis_blend_speed * delta))
	var ps := Vector3(0, _pelvis_offset, 0)

	# Full-body shift. Reuse the persistent override buffer and the per-solve
	# anim-global cache (hip/leg bones were already cached above).
	var overrides := _overrides_buf
	overrides.clear()
	if absf(_pelvis_offset) > 0.001:
		for rig_name: String in _spring.get_all_bone_names():
			var bi: int = _spring.get_bone_idx(rig_name)
			if bi >= 0:
				var ba := _anim_global(bi, sg)
				overrides[rig_name] = Transform3D(ba.basis, ba.origin + ps)

	# Solve left leg (use pinned XZ for foot target)
	if _ik_weight_l > 0.01:
		var ft := Vector3(foot_xz_l.x, gpos_l.y + _tuning.foot_ik_ankle_height, foot_xz_l.y)
		var ik := _solve_two_bone_ik(upper_l.origin + ps, ft, lower_l.origin + ps, gnorm_l, foot_l)
		if not ik.is_empty():
			_blend_leg(overrides, _upper_l, _lower_l, _foot_l,
				upper_l, lower_l, foot_l, ik, _ik_weight_l, ps)

	# Solve right leg
	if _ik_weight_r > 0.01:
		var ft := Vector3(foot_xz_r.x, gpos_r.y + _tuning.foot_ik_ankle_height, foot_xz_r.y)
		var ik := _solve_two_bone_ik(upper_r.origin + ps, ft, lower_r.origin + ps, gnorm_r, foot_r)
		if not ik.is_empty():
			_blend_leg(overrides, _upper_r, _lower_r, _foot_r,
				upper_r, lower_r, foot_r, ik, _ik_weight_r, ps)

	_spring.set_target_overrides(overrides)


## Returns the world-space animation global for a bone index, memoized per solve
## in _anim_cache. get_animation_bone_global walks the parent chain, so caching
## avoids re-walking shared ancestors across the hip/leg reads and the full-body
## shift. Caller must clear _anim_cache at the start of each solve.
func _anim_global(bone_idx: int, sg: Transform3D) -> Transform3D:
	if _anim_cache.has(bone_idx):
		return _anim_cache[bone_idx]
	var g := sg * _spring.get_animation_bone_global(bone_idx)
	_anim_cache[bone_idx] = g
	return g


# ── Two-bone IK solver (law of cosines) ───────────────────────────────────

func _solve_two_bone_ik(hip_pos: Vector3, foot_target: Vector3,
		knee_hint: Vector3, ground_normal: Vector3,
		foot_anim: Transform3D) -> Dictionary:
	var cv := foot_target - hip_pos
	var cl := cv.length()
	var mx := _upper_leg_len + _lower_leg_len - 0.01
	var mn := absf(_upper_leg_len - _lower_leg_len) + 0.01
	if cl < mn or cl > mx + 0.1:
		return {}
	cl = clampf(cl, mn, mx)

	# Law of cosines: hip angle
	var ch := (_upper_leg_len * _upper_leg_len + cl * cl - _lower_leg_len * _lower_leg_len) / (2.0 * _upper_leg_len * cl)
	ch = clampf(ch, -1.0, 1.0)
	var ho := acos(ch)

	# Knee direction from hint
	var cd := cv.normalized()
	var kf := (knee_hint - hip_pos).normalized()
	var side := cd.cross(kf).normalized()
	if side.length_squared() < 0.001:
		side = cd.cross(-_character_root.global_basis.z).normalized()
	if side.length_squared() < 0.001:
		side = cd.cross(Vector3.RIGHT).normalized()
	var bd := side.cross(cd).normalized()

	# Upper and lower leg positions
	var ud := (cd * cos(ho) + bd * sin(ho)).normalized()
	var kp := hip_pos + ud * _upper_leg_len
	var ld := (foot_target - kp).normalized()

	# Build transforms
	var ux := Transform3D(_basis_looking_along(ud, side), hip_pos)
	var lx := Transform3D(_basis_looking_along(ld, side), kp)

	# Foot rotation: apply slope delta to animation pose
	# On flat ground (normal=UP) this is identity — no correction
	var slope_correction := Quaternion(Vector3.UP, ground_normal.normalized())
	var fb := Basis(slope_correction) * foot_anim.basis
	var fx := Transform3D(fb, foot_target)

	return {"upper": ux, "lower": lx, "foot": fx}


func _basis_looking_along(dir: Vector3, hint_side: Vector3) -> Basis:
	var d := dir.normalized()
	var s := d.cross(Vector3.UP).normalized()
	if s.length_squared() < 0.001:
		s = hint_side.normalized()
	var f := s.cross(d).normalized()
	return Basis(s, -d, f)


# ── Leg blend helper ───────────────────────────────────────────────────────

func _blend_leg(overrides: Dictionary, upper_name: String, lower_name: String,
		foot_name: String, upper_anim: Transform3D, lower_anim: Transform3D,
		foot_anim: Transform3D, ik: Dictionary, weight: float,
		pelvis_shift: Vector3) -> void:
	var us := Transform3D(upper_anim.basis, upper_anim.origin + pelvis_shift)
	var ls := Transform3D(lower_anim.basis, lower_anim.origin + pelvis_shift)
	var fs := Transform3D(foot_anim.basis, foot_anim.origin + pelvis_shift)
	overrides[upper_name] = us.interpolate_with(ik["upper"], weight)
	overrides[lower_name] = ls.interpolate_with(ik["lower"], weight)
	overrides[foot_name] = fs.interpolate_with(ik["foot"], weight)


# ── Ground raycast ─────────────────────────────────────────────────────────

func _raycast_ground(origin: Vector3, distance: float) -> Dictionary:
	if not is_instance_valid(_character_root):
		return {}
	var ss := _world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * distance)
	q.collision_mask = _tuning.foot_ik_collision_mask
	q.collide_with_bodies = true
	return ss.intersect_ray(q)


# ── Stagger leg strength boost ─────────────────────────────────────────────

func _boost_leg_strength() -> void:
	var target_str := _tuning.foot_ik_stagger_leg_strength
	for leg_name: String in [_upper_l, _lower_l, _foot_l, _upper_r, _lower_r, _foot_r]:
		var base := _spring.get_base_strength(leg_name)
		var floor_val := base * target_str
		if _spring.get_bone_strength(leg_name) < floor_val:
			_spring.set_bone_strength(leg_name, floor_val)


# ── Foot collision management ──────────────────────────────────────────────

func _disable_foot_collision() -> void:
	if _collision_disabled or not _tuning.foot_ik_disable_foot_collision:
		return
	if _foot_body_l:
		_foot_body_l.collision_mask = 0
	if _foot_body_r:
		_foot_body_r.collision_mask = 0
	_collision_disabled = true


func _restore_foot_collision() -> void:
	if not _collision_disabled:
		return
	if _foot_body_l:
		_foot_body_l.collision_mask = _foot_mask_l
	if _foot_body_r:
		_foot_body_r.collision_mask = _foot_mask_r
	_collision_disabled = false
