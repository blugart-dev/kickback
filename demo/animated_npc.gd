## Reference implementation: how to wire Kickback signals to animations.
## NPC walks between waypoints, reacts to hits with directional flinch/react
## animations, gets up after ragdoll, walks injured, then resumes normal patrol.
extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")

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
	_anim = DemoHelpers.find_descendant_of_type(_char_root, "AnimationPlayer")
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
	DemoHelpers.add_debug_hud(self)

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
	DemoHelpers.orbit_camera(_cam, _cam_yaw, _cam_pitch, _cam_distance, pivot)


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
	return DemoHelpers.build_active_rig(char_root)


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
					# Threat anticipation: NPC flinches before the hit lands
					if _kickback:
						_kickback.anticipate_threat(_last_hit_dir, 0.4)
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
