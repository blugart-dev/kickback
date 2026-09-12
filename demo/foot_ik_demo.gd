## Foot IK demo: side-by-side comparison of IK ON vs IK OFF.
## Two characters walk over varied terrain (steps, ramp, plateau).
## Left (Z=0): foot IK enabled — feet plant on ground, pelvis adjusts.
## Right (Z=2.5): foot IK disabled — feet float through terrain.
extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")
const OrbitCamera := preload("res://demo/orbit_camera.gd")

const WALK_SPEED := 1.5
const WAYPOINT_A := Vector3(-6, 0, 0)
const WAYPOINT_B := Vector3(6, 0, 0)
const GROUND_MASK := KickbackLayers.ENVIRONMENT_LAYER


## One walking NPC of the comparison: its nodes, Kickback handles and walk state.
## The signal lambdas in _init_npc capture this record, so the walk flag is a
## plain bool on it rather than a closure cell.
class Npc extends RefCounted:
	var label: String
	var char_root: Node3D
	var kickback: KickbackCharacter
	var active_ctrl: ActiveRagdollController
	var anim: AnimationPlayer
	var can_walk: bool = true
	var walk_target: Vector3
	var home_z: float


var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Shotgun"])
var _weapon_idx: int = 0

var _npc_ik: Npc
var _npc_no_ik: Npc

# Camera
var _cam: Camera3D
var _orbit: OrbitCamera

# HUD
var _status_label: Label


func _ready() -> void:
	_cam = $Camera3D
	_orbit = OrbitCamera.new(_cam, 7.0, -20.0, 0.5, 2.0, 15.0)

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

	DemoHelpers.add_debug_hud(self)


# =============================================================================
# NPC SETUP
# =============================================================================

func _init_npc(char_root: Node3D, label: String, ik_enabled: bool) -> Npc:
	if not char_root:
		return null

	var tuning := RagdollTuning.create_default()
	tuning.foot_ik_enabled = ik_enabled
	var kc := DemoHelpers.build_active_rig(char_root, "", tuning)
	if not kc:
		return null

	var npc := Npc.new()
	npc.label = label
	npc.char_root = char_root
	npc.kickback = kc
	npc.active_ctrl = kc.get_active_controller()
	npc.anim = DemoHelpers.find_descendant_of_type(char_root, "AnimationPlayer")
	npc.walk_target = WAYPOINT_B
	npc.home_z = char_root.global_position.z

	# Wire signals
	var ac := npc.active_ctrl
	ac.stagger_started.connect(func(_d: Vector3) -> void: npc.can_walk = false)
	ac.stagger_finished.connect(func() -> void:
		npc.can_walk = true
		if npc.anim: npc.anim.play("walk"))
	ac.ragdoll_started.connect(func() -> void: npc.can_walk = false)
	ac.recovery_started.connect(func(fu: bool) -> void:
		if npc.anim: npc.anim.play("get_up_face_up" if fu else "get_up_face_down"))
	ac.recovery_finished.connect(func() -> void:
		npc.can_walk = true
		if npc.anim: npc.anim.play("walk"))

	if npc.anim:
		npc.anim.play.call_deferred("walk")

	return npc


# =============================================================================
# PHYSICS LOOP
# =============================================================================

func _physics_process(delta: float) -> void:
	if _npc_ik:
		_walk_npc(_npc_ik, delta)
	if _npc_no_ik:
		_walk_npc(_npc_no_ik, delta)

	_update_camera()
	_update_status()


func _walk_npc(npc: Npc, delta: float) -> void:
	if not npc.can_walk:
		return
	var root := npc.char_root
	var pos := root.global_position
	var home_z := npc.home_z
	var tgt := npc.walk_target
	var lane_tgt := Vector3(tgt.x, 0, home_z)
	var dir := (lane_tgt - pos)
	dir.y = 0
	if dir.length() < 0.3:
		tgt = WAYPOINT_B if tgt == WAYPOINT_A else WAYPOINT_A
		npc.walk_target = tgt
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
	if not _npc_ik:
		return
	_orbit.update(_npc_ik.char_root.global_position + Vector3(0, 1.0, 1.25))


# =============================================================================
# INPUT
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			KickbackRaycast.shoot_from_camera(
				get_viewport(), mb.position, _profiles[_weapon_idx])
	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		_weapon_idx = DemoHelpers.select_weapon_by_key(key, _weapon_idx, _weapon_names, null)
		match key:
			KEY_R:
				if _npc_ik:
					_npc_ik.kickback.trigger_ragdoll()
			KEY_T:
				if _npc_ik:
					_npc_ik.kickback.trigger_stagger(-_cam.global_basis.z)


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
	if not _status_label or not _npc_ik:
		return
	var ac := _npc_ik.active_ctrl
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
