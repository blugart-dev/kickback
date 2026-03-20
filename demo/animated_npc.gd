## Reference implementation: how to wire Kickback signals to animations.
## NPC walks between waypoints, reacts to hits with directional flinch/react
## animations, gets up after ragdoll, walks injured, then resumes normal patrol.
extends Node3D

const WALK_SPEED := 1.5
const WAYPOINT_A := Vector3(-3, 0, 0)
const WAYPOINT_B := Vector3(3, 0, 0)

var _profiles: Array[ImpactProfile] = []
var _weapon_names := PackedStringArray(["Bullet", "Melee", "Arrow", "Shotgun", "Explosion"])
var _weapon_idx: int = 0

# NPC state
var _char_root: Node3D
var _anim: AnimationPlayer
var _kickback: KickbackCharacter
var _active_ctrl: ActiveRagdollController

var _walk_target: Vector3 = WAYPOINT_B
var _can_walk: bool = true
var _injured_timer: float = 0.0
var _last_hit_dir: Vector3 = Vector3.FORWARD
var _flinch_timer: float = 0.0

# Camera orbit
var _cam: Camera3D
var _cam_distance: float = 5.0
var _cam_yaw: float = 0.0
var _cam_pitch: float = -15.0
var _dragging: bool = false

# HUD
var _weapon_label: Label
var _log_label: Label
var _log_lines: PackedStringArray = []
const MAX_LOG := 12


func _ready() -> void:
	_cam = $Camera3D
	_weapon_label = $HUD/WeaponLabel
	_log_label = $HUD/LogLabel

	# Juicier profiles so reactions are visible
	_profiles = [
		_make_profile(&"Bullet",    15.0, 0.55, 0.0,  0.05, 0.90, 3, 0.35),
		_make_profile(&"Melee",     22.0, 0.80, 0.05, 0.15, 0.92, 4, 0.25),
		_make_profile(&"Arrow",     18.0, 0.60, 0.0,  0.10, 0.90, 2, 0.3),
		_make_profile(&"Shotgun",   30.0, 0.65, 0.10, 0.40, 0.95, 5, 0.20),
		_make_profile(&"Explosion", 50.0, 1.00, 0.50, 0.95, 1.0, 99, 0.12),
	]

	_char_root = $NPC
	_kickback = _setup_active(_char_root)

	# Find AnimationPlayer and ActiveRagdollController
	_anim = _find_child_of_type(_char_root, "AnimationPlayer")
	for child in _char_root.get_children():
		if child is ActiveRagdollController:
			_active_ctrl = child
			break

	# Wire Kickback signals to animation handlers
	if _active_ctrl:
		_active_ctrl.hit_absorbed.connect(_on_hit_absorbed)
		_active_ctrl.stagger_started.connect(_on_stagger_started)
		_active_ctrl.stagger_finished.connect(_on_stagger_finished)
		_active_ctrl.ragdoll_started.connect(_on_ragdoll_started)
		_active_ctrl.recovery_started.connect(_on_recovery_started)
		_active_ctrl.recovery_finished.connect(_on_recovery_finished)

	# Start walking (deferred to override ybot's autoplay idle)
	if _anim:
		_anim.play.call_deferred("walk")

	# Debug gizmos
	var debug_hud := StrengthDebugHUD.new()
	debug_hud.name = "StrengthDebugHUD"
	debug_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(debug_hud)

	_update_weapon_label()


# --- Signal handlers (THIS is the pattern users need) ---

func _on_hit_absorbed(rig_name: String, _strength: float) -> void:
	# Light hit — pause movement, play flinch animation
	_flinch_timer = 0.5
	if _anim:
		var anim_name: String
		if "Head" in rig_name:
			anim_name = "flinch_head"
		else:
			anim_name = _pick_directional("flinch", _last_hit_dir)
		_anim.play(anim_name)
	_log("hit_absorbed(%s) -> flinch" % rig_name)


func _on_stagger_started(hit_dir: Vector3) -> void:
	# Medium hit — play directional react animation
	_can_walk = false
	if _anim:
		_anim.play(_pick_directional("react", hit_dir))
	_log("stagger_started -> react anim")


func _on_stagger_finished() -> void:
	# Recovered from stagger — resume walking
	_can_walk = true
	if _anim:
		_anim.play("walk")
	_log("stagger_finished -> walk")


func _on_ragdoll_started() -> void:
	# Full ragdoll — DON'T stop animation (springs need target poses)
	_can_walk = false
	_log("ragdoll_started (animation keeps playing)")


func _on_recovery_started(face_up: bool) -> void:
	# Getting up — pick animation based on landing orientation
	if _anim:
		_anim.play("get_up_face_up" if face_up else "get_up_face_down")
	_log("recovery_started(face_%s) -> get_up anim" % ("up" if face_up else "down"))


func _on_recovery_finished() -> void:
	# Recovered — walk injured for 3 seconds before resuming normal
	_injured_timer = 3.0
	_can_walk = true
	if _anim:
		_anim.play("injured_walk")
	_log("recovery_finished -> injured_walk (3s)")


# --- NPC Walk Logic (in _physics_process, as required) ---

func _physics_process(delta: float) -> void:
	if not _char_root:
		return

	# Flinch timer — brief pause during flinch animation
	if _flinch_timer > 0.0:
		_flinch_timer -= delta
		if _flinch_timer <= 0.0 and _can_walk:
			if _anim:
				_anim.play("injured_walk" if _injured_timer > 0.0 else "walk")

	# Injured timer
	if _injured_timer > 0.0:
		_injured_timer -= delta
		if _injured_timer <= 0.0 and _can_walk:
			if _anim:
				_anim.play("walk")
			_log("injury recovered -> walk")

	# Walk toward waypoint (paused during flinch, slower when injured)
	if _can_walk and _flinch_timer <= 0.0:
		var pos := _char_root.global_position
		var dir := (_walk_target - pos)
		dir.y = 0
		if dir.length() < 0.3:
			# Switch waypoint
			_walk_target = WAYPOINT_B if _walk_target == WAYPOINT_A else WAYPOINT_A

		var move_dir := dir.normalized()
		var speed := WALK_SPEED * (0.4 if _injured_timer > 0.0 else 1.0)
		_char_root.global_position += move_dir * speed * delta

		# Face movement direction
		if move_dir.length_squared() > 0.01:
			_char_root.global_rotation.y = atan2(move_dir.x, move_dir.z)

	# Camera orbit
	_update_camera()


func _update_camera() -> void:
	if not _cam or not _char_root:
		return
	var pivot := _char_root.global_position + Vector3(0, 1.0, 0)
	var yaw_rad := deg_to_rad(_cam_yaw)
	var pitch_rad := deg_to_rad(_cam_pitch)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		-sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad),
	) * _cam_distance
	_cam.global_position = pivot + offset
	_cam.look_at(pivot)


# --- Directional animation picker ---

func _pick_directional(prefix: String, hit_dir: Vector3) -> String:
	var forward := -_char_root.global_basis.z
	var right := _char_root.global_basis.x
	var dot_fwd := hit_dir.dot(forward)
	var dot_right := hit_dir.dot(right)
	if absf(dot_fwd) > absf(dot_right):
		return prefix + ("_front" if dot_fwd > 0 else "_back")
	else:
		return prefix + ("_right" if dot_right > 0 else "_left")


# --- Kickback setup (same pattern as other demos) ---

func _setup_active(char_root: Node3D) -> KickbackCharacter:
	var ybot_name := ""
	for child in char_root.get_children():
		if _find_child_of_type(child, "Skeleton3D"):
			ybot_name = child.name
			break
	if ybot_name.is_empty():
		return null

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
	tuning.stagger_strength_floor = 0.20
	tuning.stagger_duration = 0.9

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
	return kc


func _find_child_of_type(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null


func _make_profile(pname: StringName, impulse: float, transfer: float, upward: float,
		ragdoll_prob: float, reduction: float, spread: int, recovery: float) -> ImpactProfile:
	var p := ImpactProfile.new()
	p.profile_name = pname
	p.base_impulse = impulse
	p.impulse_transfer_ratio = transfer
	p.upward_bias = upward
	p.ragdoll_probability = ragdoll_prob
	p.strength_reduction = reduction
	p.strength_spread = spread
	p.recovery_rate = recovery
	return p


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_last_hit_dir = -_cam.global_basis.z
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
			KEY_1: _set_weapon(0)
			KEY_2: _set_weapon(1)
			KEY_3: _set_weapon(2)
			KEY_4: _set_weapon(3)
			KEY_5: _set_weapon(4)


func _set_weapon(idx: int) -> void:
	_weapon_idx = clampi(idx, 0, _profiles.size() - 1)
	_update_weapon_label()

func _update_weapon_label() -> void:
	if _weapon_label:
		_weapon_label.text = "Weapon: %s  [1-5]" % _weapon_names[_weapon_idx]


func _log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > MAX_LOG:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LOG)
	if _log_label:
		_log_label.text = "\n".join(_log_lines)
