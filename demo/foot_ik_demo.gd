## Foot IK demo: side-by-side comparison of IK ON vs IK OFF.
## Two characters walk over varied terrain (steps, ramp, plateau).
## Left (Z=0): foot IK enabled — feet plant on ground, pelvis adjusts.
## Right (Z=2.5): foot IK disabled — feet float through terrain.
extends Node3D

const WALK_SPEED := 1.5
const WAYPOINT_A := Vector3(-6, 0, 0)
const WAYPOINT_B := Vector3(6, 0, 0)
const GROUND_MASK := 1

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Shotgun"])
var _weapon_idx: int = 0

var _npc_ik: Dictionary = {}
var _npc_no_ik: Dictionary = {}

# Camera
var _cam: Camera3D
var _cam_distance: float = 7.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -20.0
var _dragging: bool = false

# HUD
var _status_label: Label


func _ready() -> void:
	_cam = $Camera3D

	# IK character (Z=0)
	_npc_ik = _init_npc($NPC_IK, "Foot IK: ON", true)

	# No-IK character (Z=2.5)
	_npc_no_ik = _init_npc($NPC_NoIK, "Foot IK: OFF", false)

	_profiles = [
		ImpactProfile.create_bullet(),
		ImpactProfile.create_melee(),
		ImpactProfile.create_shotgun(),
	]

	_setup_hud()
	_add_3d_labels()

	var dh := StrengthDebugHUD.new()
	dh.name = "StrengthDebugHUD"
	dh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dh)


# =============================================================================
# NPC SETUP
# =============================================================================

func _init_npc(char_root: Node3D, label: String, ik_enabled: bool) -> Dictionary:
	if not char_root:
		return {}

	var ybot_name := _get_ybot_name(char_root)
	if ybot_name.is_empty():
		return {}

	var skel_path := NodePath("../%s/Skeleton3D" % ybot_name)
	var root_path := NodePath("..")
	var builder_path := NodePath("../PhysicsRigBuilder")
	var spring_path := NodePath("../SpringResolver")

	var rb := PhysicsRigBuilder.new()
	rb.name = "PhysicsRigBuilder"
	rb.skeleton_path = skel_path

	var rs := PhysicsRigSync.new()
	rs.name = "PhysicsRigSync"
	rs.skeleton_path = skel_path
	rs.rig_builder_path = builder_path

	var sp := SpringResolver.new()
	sp.name = "SpringResolver"
	sp.skeleton_path = skel_path
	sp.rig_builder_path = builder_path

	var ac := ActiveRagdollController.new()
	ac.name = "ActiveRagdollController"
	ac.spring_resolver_path = spring_path
	ac.rig_builder_path = builder_path
	ac.character_root_path = root_path

	var tuning := RagdollTuning.create_default()
	tuning.foot_ik_enabled = ik_enabled

	var kc := KickbackCharacter.new()
	kc.name = "KickbackCharacter"
	kc.skeleton_path = skel_path
	kc.character_root_path = root_path
	kc.ragdoll_profile = RagdollProfile.create_mixamo_default()
	kc.ragdoll_tuning = tuning

	char_root.add_child(rb)
	char_root.add_child(rs)
	char_root.add_child(sp)
	char_root.add_child(ac)
	char_root.add_child(kc)

	# Find anim player + skeleton
	var anim: AnimationPlayer
	var skeleton: Skeleton3D
	for child in char_root.get_children():
		var a := _find_child_of_type(child, "AnimationPlayer") as AnimationPlayer
		if a:
			anim = a
		var s := _find_child_of_type(child, "Skeleton3D") as Skeleton3D
		if s:
			skeleton = s

	# Wire signals
	var can_walk := [true]
	ac.stagger_started.connect(func(_d: Vector3) -> void: can_walk[0] = false)
	ac.stagger_finished.connect(func() -> void: can_walk[0] = true; if anim: anim.play("walk"))
	ac.ragdoll_started.connect(func() -> void: can_walk[0] = false)
	ac.recovery_started.connect(func(fu: bool) -> void:
		if anim: anim.play("get_up_face_up" if fu else "get_up_face_down"))
	ac.recovery_finished.connect(func() -> void: can_walk[0] = true; if anim: anim.play("walk"))

	if anim:
		anim.play.call_deferred("walk")

	return {
		"label": label,
		"char_root": char_root,
		"kickback": kc,
		"active_ctrl": ac,
		"anim": anim,
		"skeleton": skeleton,
		"can_walk": can_walk,
		"walk_target": WAYPOINT_B,
		"home_z": char_root.global_position.z,
	}


# =============================================================================
# PHYSICS LOOP
# =============================================================================

func _physics_process(delta: float) -> void:
	if not _npc_ik.is_empty():
		_walk_npc(_npc_ik, delta)
	if not _npc_no_ik.is_empty():
		_walk_npc(_npc_no_ik, delta)

	_update_camera()
	_update_status()


func _walk_npc(npc: Dictionary, delta: float) -> void:
	if not npc.can_walk[0]:
		return
	var root: Node3D = npc.char_root
	var pos := root.global_position
	var home_z: float = npc.home_z
	var tgt: Vector3 = npc.walk_target
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
	np.z = home_z
	var g := _raycast_ground(np + Vector3(0, 2.0, 0), 4.0)
	if not g.is_empty():
		np.y = g["position"].y
	root.global_position = np
	if md.length_squared() > 0.01:
		root.global_rotation.y = atan2(md.x, md.z)


func _raycast_ground(origin: Vector3, distance: float) -> Dictionary:
	var ss := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * distance)
	q.collision_mask = GROUND_MASK
	q.collide_with_bodies = true
	return ss.intersect_ray(q)


# =============================================================================
# CAMERA
# =============================================================================

func _update_camera() -> void:
	if not _cam or _npc_ik.is_empty():
		return
	var pivot: Vector3 = _npc_ik.char_root.global_position + Vector3(0, 1.0, 1.25)
	var yr := deg_to_rad(_cam_yaw)
	var pr := deg_to_rad(_cam_pitch)
	var off := Vector3(sin(yr) * cos(pr), -sin(pr), cos(yr) * cos(pr)) * _cam_distance
	_cam.global_position = pivot + off
	_cam.look_at(pivot)


# =============================================================================
# INPUT
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					KickbackRaycast.shoot_from_camera(
						get_viewport(), mb.position, _profiles[_weapon_idx])
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_cam_distance = maxf(_cam_distance - 0.5, 2.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_cam_distance = minf(_cam_distance + 0.5, 15.0)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.3, -80.0, 80.0)
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_1: _weapon_idx = 0
			KEY_2: _weapon_idx = 1
			KEY_3: _weapon_idx = 2
			KEY_R:
				if not _npc_ik.is_empty():
					(_npc_ik.kickback as KickbackCharacter).trigger_ragdoll()
			KEY_T:
				if not _npc_ik.is_empty():
					(_npc_ik.kickback as KickbackCharacter).trigger_stagger(
						-_cam.global_basis.z)


# =============================================================================
# HUD
# =============================================================================

func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.position = Vector2(20, 20)
	_status_label.add_theme_font_size_override("font_size", 16)
	hud.add_child(_status_label)

	var controls := Label.new()
	controls.name = "Controls"
	controls.position = Vector2(20, 160)
	controls.add_theme_font_size_override("font_size", 14)
	controls.text = "LMB: Shoot | RMB: Orbit | Scroll: Zoom\n1-3: Weapon | R: Ragdoll | T: Stagger | F3: Debug"
	hud.add_child(controls)


func _update_status() -> void:
	if not _status_label or _npc_ik.is_empty():
		return
	var ac: ActiveRagdollController = _npc_ik.active_ctrl
	var state_name := ac.get_state_name() if ac else "N/A"
	var w := _weapon_names[_weapon_idx] if _weapon_idx < _weapon_names.size() else "?"
	_status_label.text = "FOOT IK DEMO\n\nLeft (Z=0): IK ON  |  State: %s\nRight (Z=2.5): IK OFF\n\nWeapon: %s" % [
		state_name, w]


func _add_3d_labels() -> void:
	var label_ik := Label3D.new()
	label_ik.name = "Label_IK_ON"
	label_ik.text = "FOOT IK: ON"
	label_ik.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_ik.font_size = 24
	label_ik.outline_size = 10
	label_ik.modulate = Color(0.4, 1.0, 0.4)
	add_child(label_ik)
	label_ik.position = Vector3(0, 2.5, 0)

	var label_no_ik := Label3D.new()
	label_no_ik.name = "Label_IK_OFF"
	label_no_ik.text = "FOOT IK: OFF"
	label_no_ik.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_no_ik.font_size = 24
	label_no_ik.outline_size = 10
	label_no_ik.modulate = Color(1.0, 0.4, 0.4)
	add_child(label_no_ik)
	label_no_ik.position = Vector3(0, 2.5, 2.5)


# =============================================================================
# UTILITIES
# =============================================================================

func _get_ybot_name(char_root: Node3D) -> String:
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			return child.name
	push_error("FootIKDemo: No Skeleton3D found in %s" % char_root.name)
	return ""


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null
