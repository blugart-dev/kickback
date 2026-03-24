## Research spike: Side-by-side comparison of two foot IK approaches.
##
## NPC (Z=0):     Direct two-bone IK math — computed in _physics_process
## NPC_TwoBone (Z=2.5): Godot TwoBoneIK3D — solved by engine, read via skeleton_updated
##
## Both share: pelvis adjustment, full-body shift, smooth blending, hip-height raycasts
extends Node3D

const WALK_SPEED := 1.5
const WAYPOINT_A := Vector3(-5, 0, 0)
const WAYPOINT_B := Vector3(5, 0, 0)

# Raycast / IK tuning (shared)
const GROUND_MASK := 1
const RAY_ABOVE_HIP := 0.3
const RAY_BELOW_HIP := 2.5
const ANKLE_HEIGHT := 0.065
const MAX_PELVIS_DROP := 0.35
const SWING_HEIGHT_THRESHOLD := 0.25
const NEAR_GROUND_THRESHOLD := 0.17
const PELVIS_BLEND_SPEED := 8.0
const FOOT_BLEND_SPEED := 10.0

# Bone lengths (shared — same skeleton)
var _upper_leg_len: float = 0.0
var _lower_leg_len: float = 0.0

# Per-NPC state stored in dictionaries for clean code
var _npc: Dictionary = {}   # Direct math NPC
var _npc_tb: Dictionary = {}  # TwoBoneIK3D NPC

var _ik_active: bool = true
var _profiles: Array[ImpactProfile] = []
var _weapon_idx: int = 0

# Camera
var _cam: Camera3D
var _cam_distance: float = 6.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -20.0
var _dragging: bool = false

# HUD
var _status_label: Label


func _ready() -> void:
	_cam = $Camera3D

	# --- Direct Math NPC ---
	_npc = _init_npc($NPC, "DirectMath")
	if _npc.is_empty():
		push_error("Failed to set up Direct Math NPC")
		return

	# Compute bone lengths from first NPC (shared by both)
	var skel: Skeleton3D = _npc.skeleton
	var ul := skel.get_bone_global_rest(skel.find_bone("mixamorig_LeftUpLeg"))
	var ll := skel.get_bone_global_rest(skel.find_bone("mixamorig_LeftLeg"))
	var fl := skel.get_bone_global_rest(skel.find_bone("mixamorig_LeftFoot"))
	_upper_leg_len = ul.origin.distance_to(ll.origin)
	_lower_leg_len = ll.origin.distance_to(fl.origin)

	# --- TwoBoneIK3D NPC ---
	_npc_tb = _init_npc($NPC_TwoBone, "TwoBoneIK")
	if not _npc_tb.is_empty():
		_setup_twobone_ik_nodes(_npc_tb)

	# --- T-pose ref ---
	var tpose := get_node_or_null("TPoseRef")
	if tpose:
		_setup_active(tpose)
		var ta: AnimationPlayer = _find_child_of_type(tpose, "AnimationPlayer")
		if ta: ta.stop()

	_profiles = [ImpactProfile.create_bullet(), ImpactProfile.create_melee(), ImpactProfile.create_shotgun()]
	_setup_hud()

	var dh := StrengthDebugHUD.new()
	dh.name = "StrengthDebugHUD"
	dh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dh)

	print("IK Research: upper=%.3f lower=%.3f" % [_upper_leg_len, _lower_leg_len])


# =============================================================================
# NPC INITIALIZATION
# =============================================================================

func _init_npc(char_root: Node3D, label: String) -> Dictionary:
	if not char_root:
		return {}
	var kc := _setup_active(char_root)
	if not kc:
		return {}

	var anim: AnimationPlayer = _find_child_of_type(char_root, "AnimationPlayer")
	var active_ctrl: ActiveRagdollController
	var spring: SpringResolver
	var rig_builder: PhysicsRigBuilder
	for child in char_root.get_children():
		if child is ActiveRagdollController: active_ctrl = child
		elif child is SpringResolver: spring = child
		elif child is PhysicsRigBuilder: rig_builder = child

	var skeleton: Skeleton3D
	for child in char_root.get_children():
		var s := _find_child_of_type(child, "Skeleton3D") as Skeleton3D
		if s:
			skeleton = s
			break

	if not skeleton:
		push_error("%s: No Skeleton3D" % label)
		return {}

	var bone_idx := {
		"UpperLeg_L": skeleton.find_bone("mixamorig_LeftUpLeg"),
		"LowerLeg_L": skeleton.find_bone("mixamorig_LeftLeg"),
		"Foot_L": skeleton.find_bone("mixamorig_LeftFoot"),
		"UpperLeg_R": skeleton.find_bone("mixamorig_RightUpLeg"),
		"LowerLeg_R": skeleton.find_bone("mixamorig_RightLeg"),
		"Foot_R": skeleton.find_bone("mixamorig_RightFoot"),
	}

	# Wire signals
	var can_walk := [true]  # Array so lambda captures by reference
	if active_ctrl:
		active_ctrl.stagger_started.connect(func(_d: Vector3) -> void: can_walk[0] = false)
		active_ctrl.stagger_finished.connect(func() -> void: can_walk[0] = true; anim.play("walk"))
		active_ctrl.ragdoll_started.connect(func() -> void: can_walk[0] = false)
		active_ctrl.recovery_started.connect(func(fu: bool) -> void:
			if anim: anim.play("get_up_face_up" if fu else "get_up_face_down"))
		active_ctrl.recovery_finished.connect(func() -> void: can_walk[0] = true; anim.play("walk"))

	if anim:
		anim.play.call_deferred("walk")

	return {
		"label": label,
		"char_root": char_root,
		"anim": anim,
		"active_ctrl": active_ctrl,
		"spring": spring,
		"rig_builder": rig_builder,
		"skeleton": skeleton,
		"bone_idx": bone_idx,
		"hips_idx": skeleton.find_bone("mixamorig_Hips"),
		"can_walk": can_walk,
		"walk_target": WAYPOINT_B,
		"home_z": char_root.global_position.z,
		"ik_weight_l": 0.0,
		"ik_weight_r": 0.0,
		"pelvis_offset": 0.0,
	}


func _setup_twobone_ik_nodes(npc: Dictionary) -> void:
	var skel: Skeleton3D = npc.skeleton
	skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS

	# Target + pole markers
	var tl := Node3D.new(); tl.name = "TB_TgtL"; add_child(tl)
	var tr := Node3D.new(); tr.name = "TB_TgtR"; add_child(tr)
	var pl := Node3D.new(); pl.name = "TB_PoleL"; add_child(pl)
	var pr := Node3D.new(); pr.name = "TB_PoleR"; add_child(pr)

	# TwoBoneIK3D nodes
	var ik_l := TwoBoneIK3D.new()
	ik_l.name = "TB_IK_L"
	ik_l.setting_count = 1
	ik_l.set_root_bone_name(0, "mixamorig_LeftUpLeg")
	ik_l.set_middle_bone_name(0, "mixamorig_LeftLeg")
	ik_l.set_end_bone_name(0, "mixamorig_LeftFoot")
	skel.add_child(ik_l)
	ik_l.set_target_node(0, ik_l.get_path_to(tl))
	ik_l.set_pole_node(0, ik_l.get_path_to(pl))

	var ik_r := TwoBoneIK3D.new()
	ik_r.name = "TB_IK_R"
	ik_r.setting_count = 1
	ik_r.set_root_bone_name(0, "mixamorig_RightUpLeg")
	ik_r.set_middle_bone_name(0, "mixamorig_RightLeg")
	ik_r.set_end_bone_name(0, "mixamorig_RightFoot")
	skel.add_child(ik_r)
	ik_r.set_target_node(0, ik_r.get_path_to(tr))
	ik_r.set_pole_node(0, ik_r.get_path_to(pr))

	npc["ik_left"] = ik_l
	npc["ik_right"] = ik_r
	npc["target_left"] = tl
	npc["target_right"] = tr
	npc["pole_left"] = pl
	npc["pole_right"] = pr
	npc["ik_cache"] = {}

	skel.skeleton_updated.connect(_on_tb_skeleton_updated)
	print("TwoBoneIK3D NPC set up at ", npc.char_root.global_position)


func _on_tb_skeleton_updated() -> void:
	if _npc_tb.is_empty() or not _ik_active:
		return
	var ac: ActiveRagdollController = _npc_tb.active_ctrl
	if ac and ac.get_state() != ActiveRagdollController.State.NORMAL:
		return

	var skel: Skeleton3D = _npc_tb.skeleton
	var sg := skel.global_transform
	var cache := {}
	for rig_name: String in _npc_tb.bone_idx:
		var bi: int = _npc_tb.bone_idx[rig_name]
		if bi >= 0:
			cache[rig_name] = sg * skel.get_bone_global_pose(bi)
	_npc_tb["ik_cache"] = cache


# =============================================================================
# PHYSICS LOOP
# =============================================================================

func _physics_process(delta: float) -> void:
	if _npc.is_empty():
		return

	# Walk both NPCs
	_walk_npc(_npc, delta)
	if not _npc_tb.is_empty():
		_walk_npc(_npc_tb, delta)

	# IK for Direct Math NPC
	_update_ik_direct_math(_npc, delta)

	# IK for TwoBoneIK3D NPC
	if not _npc_tb.is_empty():
		_update_ik_twobone(_npc_tb, delta)

	_update_camera()
	_update_status()


func _walk_npc(npc: Dictionary, delta: float) -> void:
	if not npc.can_walk[0]:
		return
	var root: Node3D = npc.char_root
	var pos := root.global_position
	var home_z: float = npc.home_z  # Each NPC stays on its own Z lane
	var tgt: Vector3 = npc.walk_target
	# Waypoints use NPC's home Z, not global Z=0
	var lane_tgt := Vector3(tgt.x, 0, home_z)
	var dir := (lane_tgt - pos)
	dir.y = 0
	if dir.length() < 0.3:
		tgt = WAYPOINT_B if tgt == WAYPOINT_A else WAYPOINT_A
		npc["walk_target"] = tgt
		lane_tgt = Vector3(tgt.x, 0, home_z)
		dir = (lane_tgt - pos)
		dir.y = 0

	var md := dir.normalized()
	var np := pos + md * WALK_SPEED * delta
	np.z = home_z  # Lock to lane
	var g := _raycast_ground_from(np + Vector3(0, 2.0, 0), 4.0)
	if not g.is_empty():
		np.y = g["position"].y
	root.global_position = np
	if md.length_squared() > 0.01:
		root.global_rotation.y = atan2(md.x, md.z)


# =============================================================================
# SHARED IK: ground analysis, pelvis, weights, full-body shift
# =============================================================================

func _compute_ik_context(npc: Dictionary, delta: float) -> Dictionary:
	## Returns all data needed for IK: ground hits, offsets, weights, pelvis, overrides
	var spring: SpringResolver = npc.spring
	var skel: Skeleton3D = npc.skeleton
	var root: Node3D = npc.char_root
	var bidx: Dictionary = npc.bone_idx
	var sg := skel.global_transform
	var root_y := root.global_position.y

	# Animation poses
	var hips_anim := sg * spring.get_animation_bone_global(npc.hips_idx)
	var hip_y := hips_anim.origin.y
	var upper_l := sg * spring.get_animation_bone_global(bidx["UpperLeg_L"])
	var lower_l := sg * spring.get_animation_bone_global(bidx["LowerLeg_L"])
	var foot_l := sg * spring.get_animation_bone_global(bidx["Foot_L"])
	var upper_r := sg * spring.get_animation_bone_global(bidx["UpperLeg_R"])
	var lower_r := sg * spring.get_animation_bone_global(bidx["LowerLeg_R"])
	var foot_r := sg * spring.get_animation_bone_global(bidx["Foot_R"])

	# Ground raycasts from hip height
	var gl := _raycast_ground_from(Vector3(foot_l.origin.x, hip_y + RAY_ABOVE_HIP, foot_l.origin.z), RAY_ABOVE_HIP + RAY_BELOW_HIP)
	var gr := _raycast_ground_from(Vector3(foot_r.origin.x, hip_y + RAY_ABOVE_HIP, foot_r.origin.z), RAY_ABOVE_HIP + RAY_BELOW_HIP)

	# Per-foot offsets and weights
	var offset_l := 0.0; var offset_r := 0.0
	var tw_l := 0.0; var tw_r := 0.0
	var gpos_l := foot_l.origin; var gpos_r := foot_r.origin
	var gnorm_l := Vector3.UP; var gnorm_r := Vector3.UP

	if not gl.is_empty():
		gpos_l = gl["position"]; gnorm_l = gl.get("normal", Vector3.UP)
		offset_l = (gpos_l.y + ANKLE_HEIGHT) - foot_l.origin.y
		var far := foot_l.origin.y - root_y
		if far < SWING_HEIGHT_THRESHOLD:
			tw_l = clampf(1.0 - (far - NEAR_GROUND_THRESHOLD) / (SWING_HEIGHT_THRESHOLD - NEAR_GROUND_THRESHOLD), 0.0, 1.0)

	if not gr.is_empty():
		gpos_r = gr["position"]; gnorm_r = gr.get("normal", Vector3.UP)
		offset_r = (gpos_r.y + ANKLE_HEIGHT) - foot_r.origin.y
		var far := foot_r.origin.y - root_y
		if far < SWING_HEIGHT_THRESHOLD:
			tw_r = clampf(1.0 - (far - NEAR_GROUND_THRESHOLD) / (SWING_HEIGHT_THRESHOLD - NEAR_GROUND_THRESHOLD), 0.0, 1.0)

	# Smooth weights
	var blend := 1.0 - exp(-FOOT_BLEND_SPEED * delta)
	var wl: float = lerpf(npc.ik_weight_l, tw_l, blend)
	var wr: float = lerpf(npc.ik_weight_r, tw_r, blend)
	npc["ik_weight_l"] = wl
	npc["ik_weight_r"] = wr

	# Pelvis
	var tp := clampf(minf(offset_l * wl, offset_r * wr), -MAX_PELVIS_DROP, 0.0)
	var po: float = lerpf(npc.pelvis_offset, tp, 1.0 - exp(-PELVIS_BLEND_SPEED * delta))
	npc["pelvis_offset"] = po
	var ps := Vector3(0, po, 0)

	# Full-body shift overrides
	var overrides := {}
	if absf(po) > 0.001:
		for rn in spring.get_all_bone_names():
			var bi: int = spring.get_bone_idx(rn)
			if bi >= 0:
				var ba := sg * spring.get_animation_bone_global(bi)
				overrides[rn] = Transform3D(ba.basis, ba.origin + ps)

	return {
		"sg": sg, "ps": ps, "overrides": overrides,
		"upper_l": upper_l, "lower_l": lower_l, "foot_l": foot_l,
		"upper_r": upper_r, "lower_r": lower_r, "foot_r": foot_r,
		"gpos_l": gpos_l, "gpos_r": gpos_r,
		"gnorm_l": gnorm_l, "gnorm_r": gnorm_r,
		"wl": wl, "wr": wr, "hip_y": hip_y,
	}


# =============================================================================
# DIRECT MATH IK
# =============================================================================

func _update_ik_direct_math(npc: Dictionary, delta: float) -> void:
	var spring: SpringResolver = npc.spring
	var ac: ActiveRagdollController = npc.active_ctrl
	if not spring or not ac:
		return
	if not _ik_active or ac.get_state() != ActiveRagdollController.State.NORMAL:
		_blend_out(npc, delta)
		return

	var ctx := _compute_ik_context(npc, delta)
	var overrides: Dictionary = ctx.overrides
	var ps: Vector3 = ctx.ps

	# Solve left leg
	if ctx.wl > 0.01:
		var ft := Vector3(ctx.foot_l.origin.x, ctx.gpos_l.y + ANKLE_HEIGHT, ctx.foot_l.origin.z)
		var ik := _solve_two_bone_ik(ctx.upper_l.origin + ps, ft, ctx.lower_l.origin + ps, ctx.gnorm_l, ctx.foot_l, npc.char_root)
		if not ik.is_empty():
			_blend_leg(overrides, "UpperLeg_L", "LowerLeg_L", "Foot_L", ctx.upper_l, ctx.lower_l, ctx.foot_l, ik, ctx.wl, ps)

	# Solve right leg
	if ctx.wr > 0.01:
		var ft := Vector3(ctx.foot_r.origin.x, ctx.gpos_r.y + ANKLE_HEIGHT, ctx.foot_r.origin.z)
		var ik := _solve_two_bone_ik(ctx.upper_r.origin + ps, ft, ctx.lower_r.origin + ps, ctx.gnorm_r, ctx.foot_r, npc.char_root)
		if not ik.is_empty():
			_blend_leg(overrides, "UpperLeg_R", "LowerLeg_R", "Foot_R", ctx.upper_r, ctx.lower_r, ctx.foot_r, ik, ctx.wr, ps)

	spring.set_target_overrides(overrides)


# =============================================================================
# TWOBONE IK3D (Godot nodes)
# =============================================================================

func _update_ik_twobone(npc: Dictionary, delta: float) -> void:
	var spring: SpringResolver = npc.spring
	var ac: ActiveRagdollController = npc.active_ctrl
	if not spring or not ac:
		return
	if not _ik_active or ac.get_state() != ActiveRagdollController.State.NORMAL:
		_blend_out(npc, delta)
		npc["ik_cache"] = {}
		return

	var ctx := _compute_ik_context(npc, delta)
	var overrides: Dictionary = ctx.overrides
	var ps: Vector3 = ctx.ps

	# Move TwoBoneIK3D target markers to ground + ankle offset
	var tl: Node3D = npc.target_left
	var tr: Node3D = npc.target_right
	tl.global_position = Vector3(ctx.foot_l.origin.x, ctx.gpos_l.y + ANKLE_HEIGHT, ctx.foot_l.origin.z)
	tr.global_position = Vector3(ctx.foot_r.origin.x, ctx.gpos_r.y + ANKLE_HEIGHT, ctx.foot_r.origin.z)

	# Pole targets
	var pl: Node3D = npc.pole_left
	var pr: Node3D = npc.pole_right
	pl.global_position = ctx.lower_l.origin + npc.char_root.global_basis.z * -0.5
	pr.global_position = ctx.lower_r.origin + npc.char_root.global_basis.z * -0.5

	# Use IK cache from skeleton_updated (1 frame delay)
	var cache: Dictionary = npc.get("ik_cache", {})
	if cache.is_empty():
		spring.set_target_overrides(overrides)
		return

	# Blend cached IK leg poses with animation (same as direct math blend)
	if ctx.wl > 0.01 and cache.has("UpperLeg_L"):
		var ik := {"upper": cache["UpperLeg_L"], "lower": cache["LowerLeg_L"], "foot": cache["Foot_L"]}
		_blend_leg(overrides, "UpperLeg_L", "LowerLeg_L", "Foot_L", ctx.upper_l, ctx.lower_l, ctx.foot_l, ik, ctx.wl, ps)

	if ctx.wr > 0.01 and cache.has("UpperLeg_R"):
		var ik := {"upper": cache["UpperLeg_R"], "lower": cache["LowerLeg_R"], "foot": cache["Foot_R"]}
		_blend_leg(overrides, "UpperLeg_R", "LowerLeg_R", "Foot_R", ctx.upper_r, ctx.lower_r, ctx.foot_r, ik, ctx.wr, ps)

	spring.set_target_overrides(overrides)


# =============================================================================
# SHARED: blend out, leg blend, two-bone solver
# =============================================================================

func _blend_out(npc: Dictionary, delta: float) -> void:
	var b := 1.0 - exp(-FOOT_BLEND_SPEED * delta)
	npc["ik_weight_l"] = lerpf(npc.ik_weight_l, 0.0, b)
	npc["ik_weight_r"] = lerpf(npc.ik_weight_r, 0.0, b)
	npc["pelvis_offset"] = lerpf(npc.pelvis_offset, 0.0, 1.0 - exp(-PELVIS_BLEND_SPEED * delta))
	if npc.ik_weight_l < 0.001 and npc.ik_weight_r < 0.001:
		npc.spring.clear_target_overrides()


func _blend_leg(overrides: Dictionary, un: String, ln: String, fn: String,
		ua: Transform3D, la: Transform3D, fa: Transform3D,
		ik: Dictionary, w: float, ps: Vector3) -> void:
	var us := Transform3D(ua.basis, ua.origin + ps)
	var ls := Transform3D(la.basis, la.origin + ps)
	var fs := Transform3D(fa.basis, fa.origin + ps)
	overrides[un] = us.interpolate_with(ik["upper"], w)
	overrides[ln] = ls.interpolate_with(ik["lower"], w)
	overrides[fn] = fs.interpolate_with(ik["foot"], w)


func _solve_two_bone_ik(hip_pos: Vector3, foot_target: Vector3, knee_hint: Vector3,
		ground_normal: Vector3, foot_anim: Transform3D, char_root: Node3D) -> Dictionary:
	var cv := foot_target - hip_pos
	var cl := cv.length()
	var mx := _upper_leg_len + _lower_leg_len - 0.01
	var mn := absf(_upper_leg_len - _lower_leg_len) + 0.01
	if cl < mn or cl > mx + 0.1:
		return {}
	cl = clampf(cl, mn, mx)

	var ch := (_upper_leg_len * _upper_leg_len + cl * cl - _lower_leg_len * _lower_leg_len) / (2.0 * _upper_leg_len * cl)
	ch = clampf(ch, -1.0, 1.0)
	var ho := acos(ch)

	var cd := cv.normalized()
	var kf := (knee_hint - hip_pos).normalized()
	var side := cd.cross(kf).normalized()
	if side.length_squared() < 0.001:
		side = cd.cross(-char_root.global_basis.z).normalized()
	if side.length_squared() < 0.001:
		side = cd.cross(Vector3.RIGHT).normalized()
	var bd := side.cross(cd).normalized()

	var ud := (cd * cos(ho) + bd * sin(ho)).normalized()
	var kp := hip_pos + ud * _upper_leg_len
	var ld := (foot_target - kp).normalized()

	var ux := Transform3D(_basis_looking_along(ud, side), hip_pos)
	var lx := Transform3D(_basis_looking_along(ld, side), kp)

	var au := foot_anim.basis.y.normalized()
	var corr := Quaternion(au, ground_normal.normalized())
	var fb := Basis(corr) * foot_anim.basis
	var fx := Transform3D(fb, foot_target)

	return {"upper": ux, "lower": lx, "foot": fx}


func _basis_looking_along(dir: Vector3, hint_side: Vector3) -> Basis:
	var d := dir.normalized()
	var s := d.cross(Vector3.UP).normalized()
	if s.length_squared() < 0.001:
		s = hint_side.normalized()
	var f := s.cross(d).normalized()
	return Basis(s, -d, f)


func _raycast_ground_from(origin: Vector3, distance: float) -> Dictionary:
	var ss := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * distance)
	q.collision_mask = GROUND_MASK
	q.collide_with_bodies = true
	return ss.intersect_ray(q)


# =============================================================================
# KICKBACK SETUP
# =============================================================================

func _setup_active(char_root: Node3D) -> KickbackCharacter:
	var ybot_name := ""
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			ybot_name = child.name; break
	if ybot_name.is_empty():
		return null

	var sp := NodePath("../%s/Skeleton3D" % ybot_name)
	var rp := NodePath(".."); var bp := NodePath("../PhysicsRigBuilder"); var srp := NodePath("../SpringResolver")

	var rb := PhysicsRigBuilder.new(); rb.name = "PhysicsRigBuilder"; rb.skeleton_path = sp
	var rs := PhysicsRigSync.new(); rs.name = "PhysicsRigSync"; rs.skeleton_path = sp; rs.rig_builder_path = bp
	var sv := SpringResolver.new(); sv.name = "SpringResolver"; sv.skeleton_path = sp; sv.rig_builder_path = bp
	var ac := ActiveRagdollController.new(); ac.name = "ActiveRagdollController"; ac.spring_resolver_path = srp; ac.rig_builder_path = bp; ac.character_root_path = rp
	var kc := KickbackCharacter.new(); kc.name = "KickbackCharacter"; kc.skeleton_path = sp; kc.character_root_path = rp
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default(); kc.ragdoll_tuning = RagdollTuning.create_default()

	char_root.add_child(rb); char_root.add_child(rs); char_root.add_child(sv); char_root.add_child(ac); char_root.add_child(kc)
	return kc


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name: return child
		var found := _find_child_of_type(child, type_name)
		if found: return found
	return null


# =============================================================================
# CAMERA / INPUT / HUD
# =============================================================================

func _update_camera() -> void:
	if not _cam or _npc.is_empty(): return
	var pivot: Vector3 = _npc.char_root.global_position + Vector3(0, 1.0, 1.25)  # Between both NPCs
	var yr := deg_to_rad(_cam_yaw); var pr := deg_to_rad(_cam_pitch)
	var off := Vector3(sin(yr) * cos(pr), -sin(pr), cos(yr) * cos(pr)) * _cam_distance
	_cam.global_position = pivot + off
	_cam.look_at(pivot)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					KickbackRaycast.shoot_from_camera(get_viewport(), mb.position, _profiles[_weapon_idx])
			MOUSE_BUTTON_RIGHT: _dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: _cam_distance = maxf(_cam_distance - 0.5, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: _cam_distance = minf(_cam_distance + 0.5, 15.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 80.0)
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_TAB:
				_ik_active = not _ik_active
				if not _ik_active:
					_npc.spring.clear_target_overrides()
					if not _npc_tb.is_empty(): _npc_tb.spring.clear_target_overrides()
				print("IK: %s" % ("ON" if _ik_active else "OFF"))
			KEY_1: _weapon_idx = 0
			KEY_2: _weapon_idx = 1
			KEY_3: _weapon_idx = 2


func _setup_hud() -> void:
	var hud := CanvasLayer.new(); hud.name = "HUD"; add_child(hud)
	_status_label = Label.new(); _status_label.name = "Status"
	_status_label.position = Vector2(20, 20)
	_status_label.add_theme_font_size_override("font_size", 16)
	hud.add_child(_status_label)
	var cl := Label.new(); cl.name = "Controls"
	cl.position = Vector2(20, 200)
	cl.add_theme_font_size_override("font_size", 14)
	cl.text = "LMB: Shoot | RMB: Orbit | Scroll: Zoom | Tab: Toggle IK | 1-3: Weapon"
	hud.add_child(cl)


func _update_status() -> void:
	if not _status_label: return
	var w := ["Bullet", "Melee", "Shotgun"]
	var dm_p := _npc.get("pelvis_offset", 0.0) as float
	var dm_wl := _npc.get("ik_weight_l", 0.0) as float
	var dm_wr := _npc.get("ik_weight_r", 0.0) as float
	var tb_p: float = float(_npc_tb.get("pelvis_offset", 0.0)) if not _npc_tb.is_empty() else 0.0
	var tb_wl: float = float(_npc_tb.get("ik_weight_l", 0.0)) if not _npc_tb.is_empty() else 0.0
	var tb_wr: float = float(_npc_tb.get("ik_weight_r", 0.0)) if not _npc_tb.is_empty() else 0.0
	var tb_cache: int = (_npc_tb.get("ik_cache", {}) as Dictionary).size() if not _npc_tb.is_empty() else 0
	_status_label.text = "Foot IK Side-by-Side  |  IK: %s  |  %s\n\nZ=0: Direct Math\n  Pelvis: %.3f  Wt: %.2f / %.2f\n\nZ=2.5: TwoBoneIK3D\n  Pelvis: %.3f  Wt: %.2f / %.2f  Cache: %d" % [
		"ON" if _ik_active else "OFF", w[_weapon_idx] if _weapon_idx < w.size() else "?",
		dm_p, dm_wl, dm_wr, tb_p, tb_wl, tb_wr, tb_cache]
