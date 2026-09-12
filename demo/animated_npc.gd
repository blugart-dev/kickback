## Reference implementation: how to wire Kickback signals to animations.
## NPC walks between waypoints, reacts to hits with directional flinch/react
## animations, gets up after ragdoll, walks injured, then resumes normal patrol.
extends Node3D

const DemoHelpers := preload("res://demo/demo_helpers.gd")
const OrbitCamera := preload("res://demo/orbit_camera.gd")

const WALK_SPEED := 1.5
const WAYPOINT_A := Vector3(-3, 0, 0)
const WAYPOINT_B := Vector3(3, 0, 0)
const MAX_LOG := 12

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
var _orbit: OrbitCamera

# HUD
var _weapon_label: Label
var _hud_log: DemoHelpers.LogPanel


func _ready() -> void:
	_cam = $Camera3D
	_orbit = OrbitCamera.new(_cam, 5.0, -15.0, 0.5, 2.0, 15.0)
	_weapon_label = $HUD/WeaponLabel
	_hud_log = DemoHelpers.LogPanel.new($HUD/LogLabel, MAX_LOG)

	# Juicier profiles so reactions are visible
	_profiles = DemoHelpers.create_cranked_profiles()

	_char_root = $NPC
	_kickback = _setup_active(_char_root)

	# Find AnimationPlayer and ActiveRagdollController
	_anim = DemoHelpers.find_descendant_of_type(_char_root, "AnimationPlayer")
	if _kickback:
		_active_ctrl = _kickback.get_active_controller()

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

	_weapon_idx = DemoHelpers.select_weapon(_weapon_idx, _weapon_names, _weapon_label)


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
	_hud_log.add("hit_absorbed(%s) -> flinch" % rig_name)


func _on_stagger_started(hit_dir: Vector3) -> void:
	# Medium hit — play directional react animation
	_can_walk = false
	if _anim:
		_anim.play(_pick_directional("react", hit_dir))
	_hud_log.add("stagger_started -> react anim")


func _on_stagger_finished() -> void:
	# Recovered from stagger — resume walking
	_can_walk = true
	if _anim:
		_anim.play("walk")
	_hud_log.add("stagger_finished -> walk")


func _on_ragdoll_started() -> void:
	# Full ragdoll — DON'T stop animation (springs need target poses)
	_can_walk = false
	_hud_log.add("ragdoll_started (animation keeps playing)")


func _on_recovery_started(face_up: bool) -> void:
	# Getting up — pick animation based on landing orientation
	if _anim:
		_anim.play("get_up_face_up" if face_up else "get_up_face_down")
	_hud_log.add("recovery_started(face_%s) -> get_up anim" % ("up" if face_up else "down"))


func _on_recovery_finished() -> void:
	# Recovered — walk injured for 3 seconds before resuming normal
	_injured_timer = 3.0
	_can_walk = true
	if _anim:
		_anim.play("injured_walk")
	_hud_log.add("recovery_finished -> injured_walk (3s)")


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
			_hud_log.add("injury recovered -> walk")

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
	if not _char_root:
		return
	_orbit.update(_char_root.global_position + Vector3(0, 1.0, 0))


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


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_last_hit_dir = -_cam.global_basis.z
			# Threat anticipation: NPC flinches before the hit lands
			if _kickback:
				_kickback.anticipate_threat(_last_hit_dir, 0.4)
			KickbackRaycast.shoot_from_camera(
				get_viewport(), mb.position, _profiles[_weapon_idx])

	elif event is InputEventKey and event.pressed:
		_weapon_idx = DemoHelpers.select_weapon_by_key(
			(event as InputEventKey).keycode, _weapon_idx, _weapon_names, _weapon_label)
