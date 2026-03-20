## Optional animation handler for Kickback. Listens to controller signals and
## plays get-up, flinch, and idle animations. Remove or extend this node to
## customize animation behavior. Users who want full control over animations
## can delete this node and connect directly to controller signals.
@icon("res://addons/kickback/icons/ragdoll_animator.svg")
class_name RagdollAnimator
extends Node

@export_group("References")
## Path to the AnimationPlayer that plays character animations.
@export var animation_player_path: NodePath

@export_group("Get-Up Animations")
## Animation played after recovering from face-up ragdoll.
@export var get_up_face_up_anim: StringName = &"get_up_face_up"
## Animation played after recovering from face-down ragdoll.
@export var get_up_face_down_anim: StringName = &"get_up_face_down"

@export_group("Idle")
## Idle animation used after recovery completes.
@export var idle_anim: StringName = &"idle"
## Cross-fade duration in seconds when blending to idle after recovery.
@export var idle_blend_time: float = 0.5

@export_group("Flinch Animations")
## Animation for hits from the front.
@export var flinch_front_anim: StringName = &"flinch_front"
## Animation for hits from the back.
@export var flinch_back_anim: StringName = &"flinch_back"
## Animation for hits from the left.
@export var flinch_left_anim: StringName = &"flinch_left"
## Animation for hits from the right.
@export var flinch_right_anim: StringName = &"flinch_right"
## Optional animation for headshot flinch.
@export var flinch_head_anim: StringName = &"flinch_head"
## Cross-fade duration in seconds when blending into a flinch animation.
@export var flinch_blend_time: float = 0.1

var _anim_player: AnimationPlayer


func _ready() -> void:
	_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer

	# Auto-connect to sibling controllers
	for sibling in get_parent().get_children():
		if sibling is ActiveRagdollController:
			sibling.recovery_started.connect(_on_recovery_started)
			sibling.recovery_finished.connect(_on_recovery_finished)
		elif sibling is FlinchController:
			sibling.flinch_triggered.connect(_on_flinch_triggered)

	_validate_animations()


## Called when the active ragdoll begins recovery from a ragdoll state.
## Override this to play custom get-up animations.
func _on_recovery_started(face_up: bool) -> void:
	if not _anim_player:
		return
	var anim := get_up_face_up_anim if face_up else get_up_face_down_anim
	if _anim_player.has_animation(anim):
		_anim_player.play(anim)


## Called when recovery completes and the character returns to normal.
## Override this to play a custom post-recovery animation.
func _on_recovery_finished() -> void:
	if not _anim_player:
		return
	if _anim_player.has_animation(idle_anim):
		_anim_player.play(idle_anim, idle_blend_time)


## Called when a flinch direction is determined from a hit.
## Override this to play custom flinch animations.
func _on_flinch_triggered(direction: int) -> void:
	if not _anim_player:
		return
	var anim := _direction_to_anim(direction)
	if anim and _anim_player.has_animation(anim):
		_anim_player.play(anim, flinch_blend_time)
		if _anim_player.has_animation(idle_anim):
			_anim_player.queue(idle_anim)


func _direction_to_anim(direction: int) -> StringName:
	match direction:
		FlinchController.Direction.FRONT: return flinch_front_anim
		FlinchController.Direction.BACK: return flinch_back_anim
		FlinchController.Direction.LEFT: return flinch_left_anim
		FlinchController.Direction.RIGHT: return flinch_right_anim
		FlinchController.Direction.HEAD: return flinch_head_anim
	return flinch_front_anim


func _validate_animations() -> void:
	if not _anim_player:
		return
	var anims: Array[StringName] = [
		idle_anim, get_up_face_up_anim, get_up_face_down_anim,
		flinch_front_anim, flinch_back_anim,
		flinch_left_anim, flinch_right_anim,
	]
	var missing := PackedStringArray()
	for anim: StringName in anims:
		if not _anim_player.has_animation(anim):
			missing.append(anim)
	if not missing.is_empty():
		push_warning("RagdollAnimator: missing animations: %s" % ", ".join(missing))
