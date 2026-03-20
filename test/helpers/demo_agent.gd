## Professional-grade patrol agent with animation state machine, smooth locomotion,
## priority-based interrupt handling, and intensity-aware hit reactions.
## Replaces RagdollAnimator — game code owns the AnimationPlayer.
##
## IMPORTANT: All movement and rotation happens in _physics_process to stay
## in sync with the active ragdoll spring resolver.
class_name DemoAgent
extends Node

## Animation state machine with priority-based interrupts.
enum AnimState {
	IDLE,            ## Standing still. Priority 0.
	LOCOMOTION,      ## Walking toward waypoint. Priority 0.
	FLINCHING,       ## Playing directional flinch. Priority 1.
	POST_RECOVERY,   ## Brief pause after get-up. Priority 1.
	RECOVERING,      ## Playing get-up animation. Priority 2.
	RAGDOLLED,       ## Physics-driven, no animation control. Priority 3.
}

const STATE_PRIORITY := {
	AnimState.IDLE: 0,
	AnimState.LOCOMOTION: 0,
	AnimState.FLINCHING: 1,
	AnimState.POST_RECOVERY: 1,
	AnimState.RECOVERING: 2,
	AnimState.RAGDOLLED: 3,
}

@export var move_speed: float = 1.5
@export var waypoints: PackedVector3Array = PackedVector3Array()
@export var pause_at_waypoint: float = 1.5
@export var turn_speed: float = 6.0
@export var post_recovery_pause: float = 0.8

@export_group("Blend Times")
@export var blend_fast: float = 0.1
@export var blend_medium: float = 0.25
@export var blend_slow: float = 0.4

@export_group("Locomotion")
@export var acceleration: float = 3.0
@export var deceleration: float = 5.0

@export_group("Kickback Animations")
@export var get_up_face_up_anim: StringName = &"get_up_face_up"
@export var get_up_face_down_anim: StringName = &"get_up_face_down"
@export var flinch_front_anim: StringName = &"flinch_front"
@export var flinch_back_anim: StringName = &"flinch_back"
@export var flinch_left_anim: StringName = &"flinch_left"
@export var flinch_right_anim: StringName = &"flinch_right"
@export var flinch_head_anim: StringName = &"flinch_head"

var _root: Node3D
var _anim: AnimationPlayer
var _kickback: KickbackCharacter
var _flinch: FlinchController
var _active_ctrl: ActiveRagdollController

var _anim_state: int = AnimState.IDLE
var _waypoint_idx: int = 0
var _wait: float = 0.0
var _active: bool = false

# Smooth locomotion
var _current_speed: float = 0.0
var _target_speed: float = 0.0
var _base_walk_speed: float = 1.5  # Animation's natural walk speed

# Hit absorption stagger
var _stagger_active: bool = false


func _ready() -> void:
	_root = get_parent() as Node3D
	if not _root:
		return
	_anim = _root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_base_walk_speed = move_speed

	for sibling in _root.get_children():
		if sibling is ActiveRagdollController:
			_active_ctrl = sibling
			sibling.state_changed.connect(_on_state_changed)
			sibling.recovery_started.connect(_on_recovery_started)
			sibling.recovery_finished.connect(_on_recovery_finished)
			sibling.hit_absorbed.connect(_on_hit_absorbed)
		elif sibling is FlinchController:
			_flinch = sibling
			sibling.flinch_triggered.connect(_on_flinch_triggered)
		elif sibling is KickbackCharacter:
			_kickback = sibling

	if _kickback:
		if _kickback.is_setup_complete():
			_start()
		else:
			_kickback.setup_complete.connect(_start, CONNECT_ONE_SHOT)
	else:
		_start()


func _start() -> void:
	_active = true
	if waypoints.is_empty():
		_set_state(AnimState.IDLE)
		_play_anim("idle", 0.0)
	else:
		_resume_patrol()


## ALL movement and rotation in _physics_process — same frame as spring resolver.
func _physics_process(delta: float) -> void:
	if not _active or not _root:
		return

	# Only move during IDLE or LOCOMOTION states
	if _anim_state != AnimState.LOCOMOTION and _anim_state != AnimState.IDLE:
		_current_speed = 0.0
		return

	if waypoints.is_empty():
		return

	# Waypoint pause
	if _wait > 0.0:
		_wait -= delta
		_ramp_speed(0.0, delta)
		_update_anim_speed()
		if _wait <= 0.0:
			_waypoint_idx = (_waypoint_idx + 1) % waypoints.size()
			_resume_patrol()
		return

	# Navigate toward waypoint
	var target := waypoints[_waypoint_idx]
	var to_target := target - _root.global_position
	to_target.y = 0.0
	var dist := to_target.length()

	# Arrival check
	if dist < 0.3:
		_wait = pause_at_waypoint
		_target_speed = 0.0
		_set_state(AnimState.IDLE)
		_play_anim("idle", blend_medium)
		return

	var dir := to_target.normalized()

	# Smooth rotation
	var target_angle := atan2(dir.x, dir.z)
	var angle_diff := angle_difference(_root.rotation.y, target_angle)
	_root.rotation.y += clampf(angle_diff, -turn_speed * delta, turn_speed * delta)

	# Waypoint approach deceleration
	var decel_dist := _current_speed * 0.5
	if dist < decel_dist and decel_dist > 0.01:
		_target_speed = move_speed * (dist / decel_dist)
	else:
		_target_speed = move_speed

	# Ramp speed
	_ramp_speed(_target_speed, delta)

	# Move
	if _current_speed > 0.01:
		_root.global_position += dir * _current_speed * delta
		if _anim_state != AnimState.LOCOMOTION:
			_set_state(AnimState.LOCOMOTION)
			_play_anim("walk", blend_medium)

	_update_anim_speed()


# --- Speed ramping ---

func _ramp_speed(target: float, delta: float) -> void:
	if target > _current_speed:
		_current_speed = move_toward(_current_speed, target, acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, target, deceleration * delta)


func _update_anim_speed() -> void:
	if not _anim or _stagger_active:
		return
	if _anim_state == AnimState.LOCOMOTION and _base_walk_speed > 0.01:
		_anim.speed_scale = maxf(_current_speed / _base_walk_speed, 0.3)
	elif _anim_state == AnimState.IDLE:
		_anim.speed_scale = 1.0


# --- State machine ---

func _set_state(new_state: int) -> void:
	_anim_state = new_state


func _can_interrupt(new_state: int) -> bool:
	return STATE_PRIORITY[new_state] >= STATE_PRIORITY[_anim_state]


func _resume_patrol() -> void:
	_target_speed = move_speed
	_set_state(AnimState.LOCOMOTION)
	_play_anim("walk", blend_medium)


# --- Kickback signal handlers ---

func _on_state_changed(new_state: int) -> void:
	if new_state == ActiveRagdollController.State.RAGDOLL \
		or new_state == ActiveRagdollController.State.PERSISTENT:
		_set_state(AnimState.RAGDOLLED)
		_current_speed = 0.0
		_target_speed = 0.0
		if _anim:
			_anim.speed_scale = 1.0


func _on_recovery_started(face_up: bool) -> void:
	_set_state(AnimState.RECOVERING)
	var anim := get_up_face_up_anim if face_up else get_up_face_down_anim
	_play_anim(anim, blend_fast)
	if _anim:
		_anim.speed_scale = 1.0


func _on_recovery_finished() -> void:
	_set_state(AnimState.POST_RECOVERY)
	_play_anim("idle", blend_slow)
	if _anim:
		_anim.speed_scale = 1.0
	# Brief pause — catching breath before resuming patrol
	await get_tree().create_timer(post_recovery_pause).timeout
	if _anim_state == AnimState.POST_RECOVERY:
		_resume_patrol()


func _on_hit_absorbed(_rig_name: String, _new_strength: float) -> void:
	if _anim_state != AnimState.LOCOMOTION and _anim_state != AnimState.IDLE:
		return
	if _stagger_active or not _anim:
		return
	# Subtle speed dip — simulates stumble without changing animation
	_stagger_active = true
	_anim.speed_scale *= 0.4
	await get_tree().create_timer(0.15).timeout
	_stagger_active = false
	_update_anim_speed()


func _on_flinch_triggered(direction: int) -> void:
	if not _can_interrupt(AnimState.FLINCHING):
		return
	_set_state(AnimState.FLINCHING)

	# Intensity-aware playback speed
	var intensity: float = _flinch.last_hit_intensity if _flinch else 5.0
	var speed := remap(clampf(intensity, 2.0, 30.0), 2.0, 30.0, 1.4, 0.7)

	var anim_name := _dir_to_anim(direction)
	_play_anim(anim_name, blend_fast)
	if _anim:
		_anim.speed_scale = speed

	if _anim:
		await _anim.animation_finished
		if _anim_state == AnimState.FLINCHING:
			if _anim:
				_anim.speed_scale = 1.0
			_resume_patrol()


func _dir_to_anim(direction: int) -> StringName:
	match direction:
		FlinchController.Direction.FRONT: return flinch_front_anim
		FlinchController.Direction.BACK: return flinch_back_anim
		FlinchController.Direction.LEFT: return flinch_left_anim
		FlinchController.Direction.RIGHT: return flinch_right_anim
		FlinchController.Direction.HEAD: return flinch_head_anim
	return flinch_front_anim


## Play animation ONCE with specified blend time.
func _play_anim(anim_name: StringName, blend: float) -> void:
	if _anim and _anim.has_animation(anim_name):
		if _anim.current_animation != anim_name:
			_anim.play(anim_name, blend)


## Returns the current animation state name (for debug HUD).
func get_anim_state_name() -> String:
	match _anim_state:
		AnimState.IDLE: return "IDLE"
		AnimState.LOCOMOTION: return "WALK"
		AnimState.FLINCHING: return "FLINCH"
		AnimState.RAGDOLLED: return "RAGDOLL"
		AnimState.RECOVERING: return "RECOVER"
		AnimState.POST_RECOVERY: return "BREATHE"
	return "UNKNOWN"


## Returns the current movement speed.
func get_current_speed() -> float:
	return _current_speed
