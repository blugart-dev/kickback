## Computes directional flinch responses to hits. Used for the far-range LOD
## tier where physics simulation is too expensive. Calculates front/back/left/right
## direction based on hit direction relative to the character and emits a signal.
## Animation playback is handled by RagdollAnimator or user code.
@icon("res://addons/kickback/icons/flinch_controller.svg")
class_name FlinchController
extends Node

## Flinch direction computed from hit angle relative to character facing.
enum Direction {
	FRONT, ## Hit from the front.
	BACK,  ## Hit from the back.
	LEFT,  ## Hit from the left.
	RIGHT, ## Hit from the right.
	HEAD,  ## Headshot (region-based, not angle-based).
}

@export_group("References")
## Path to the character's root Node3D for computing hit direction.
@export var character_path: NodePath
## Path to the PartialRagdollController; flinch is skipped while it is reacting.
@export var ragdoll_controller_path: NodePath

## Emitted when a flinch direction is determined from a hit.
## [param direction] is one of [enum Direction] values.
## Connect to this signal to play flinch animations.
signal flinch_triggered(direction: int)

var _character: Node3D
var _ragdoll_ctrl: PartialRagdollController
var _tuning: RagdollTuning


func configure(tuning: RagdollTuning) -> void:
	_tuning = tuning


func _ready() -> void:
	_character = get_node_or_null(character_path) as Node3D
	if not _character:
		push_warning("FlinchController: character not found at '%s'" % character_path)
	if not ragdoll_controller_path.is_empty():
		_ragdoll_ctrl = get_node_or_null(ragdoll_controller_path) as PartialRagdollController


## Computes the flinch direction from a hit event and emits [signal flinch_triggered].
func on_hit(event: HitEvent) -> void:
	if not _character:
		return

	# Skip flinch if ragdoll is actively reacting (ragdoll takes priority)
	if _ragdoll_ctrl and _ragdoll_ctrl.is_reacting():
		return

	var direction := _get_flinch_direction(event)
	flinch_triggered.emit(direction)


func _get_flinch_direction(event: HitEvent) -> int:
	# Headshot: use HEAD direction if region matches
	if event.hit_bone_region == "head":
		return Direction.HEAD

	var local_dir := _character.global_basis.inverse() * event.hit_direction
	local_dir.y = 0.0

	if local_dir.length_squared() < 0.001:
		return Direction.FRONT

	local_dir = local_dir.normalized()

	if absf(local_dir.z) > absf(local_dir.x):
		if local_dir.z < 0:
			return Direction.FRONT
		else:
			return Direction.BACK
	else:
		if local_dir.x < 0:
			return Direction.LEFT
		else:
			return Direction.RIGHT
