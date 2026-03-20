## Patrol AI that walks between waypoints and handles ALL animations for its
## character, including Kickback reactions (get-up, flinch). Replaces
## RagdollAnimator — game code owns the AnimationPlayer.
##
## IMPORTANT: All movement and rotation happens in _physics_process to stay
## in sync with the active ragdoll physics bodies.
class_name PatrolAgent
extends Node

@export var move_speed: float = 1.2
@export var waypoints: PackedVector3Array = PackedVector3Array()
@export var pause_at_waypoint: float = 1.0
@export var turn_speed: float = 5.0
## Cross-fade duration in seconds when blending between animations.
@export var blend_time: float = 0.5

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
var _waypoint_idx: int = 0
var _wait: float = 0.0
var _active: bool = false
var _ragdolled: bool = false


func _ready() -> void:
	_root = get_parent() as Node3D
	if not _root:
		return
	_anim = _root.get_node_or_null("AnimationPlayer") as AnimationPlayer

	for sibling in _root.get_children():
		if sibling is ActiveRagdollController:
			sibling.state_changed.connect(_on_state_changed)
			sibling.recovery_started.connect(_on_recovery_started)
			sibling.recovery_finished.connect(_on_recovery_finished)
		elif sibling is FlinchController:
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
		_set_anim("idle")
	else:
		_set_anim("walk")


## ALL movement and rotation in _physics_process — same frame as spring resolver.
func _physics_process(delta: float) -> void:
	if not _active or _ragdolled or waypoints.is_empty() or not _root:
		return

	# Waypoint pause
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_waypoint_idx = (_waypoint_idx + 1) % waypoints.size()
			_set_anim("walk")
		return

	# Move toward waypoint
	var target := waypoints[_waypoint_idx]
	var to_target := target - _root.global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.3:
		_wait = pause_at_waypoint
		_set_anim("idle")
		return

	var dir := to_target.normalized()

	# Rotate
	var target_angle := atan2(dir.x, dir.z)
	var angle_diff := angle_difference(_root.rotation.y, target_angle)
	if absf(angle_diff) < 0.05:
		_root.rotation.y = target_angle
	else:
		_root.rotation.y += clampf(angle_diff, -turn_speed * delta, turn_speed * delta)

	# Move
	_root.global_position += dir * move_speed * delta


# --- Kickback signal handlers ---

func _on_state_changed(new_state: int) -> void:
	if new_state == ActiveRagdollController.State.RAGDOLL \
		or new_state == ActiveRagdollController.State.PERSISTENT:
		_ragdolled = true

func _on_recovery_started(face_up: bool) -> void:
	_ragdolled = true
	var anim := get_up_face_up_anim if face_up else get_up_face_down_anim
	_set_anim(anim)

func _on_recovery_finished() -> void:
	_ragdolled = false
	_set_anim("walk" if not waypoints.is_empty() else "idle")

func _on_flinch_triggered(direction: int) -> void:
	if _ragdolled:
		return
	_set_anim(_dir_to_anim(direction))
	if _anim:
		await _anim.animation_finished
		if not _ragdolled:
			_set_anim("walk" if not waypoints.is_empty() else "idle")


func _dir_to_anim(direction: int) -> StringName:
	match direction:
		FlinchController.Direction.FRONT: return flinch_front_anim
		FlinchController.Direction.BACK: return flinch_back_anim
		FlinchController.Direction.LEFT: return flinch_left_anim
		FlinchController.Direction.RIGHT: return flinch_right_anim
		FlinchController.Direction.HEAD: return flinch_head_anim
	return flinch_front_anim


## Play animation ONCE — never call this every frame.
func _set_anim(anim_name: StringName) -> void:
	if _anim and _anim.has_animation(anim_name):
		if _anim.current_animation != anim_name:
			_anim.play(anim_name, blend_time)
