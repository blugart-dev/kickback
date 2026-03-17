class_name FlinchController
extends Node

@export var animation_player_path: NodePath
@export var character_path: NodePath
@export var ragdoll_controller_path: NodePath
@export var blend_time: float = 0.1

signal flinch_triggered(direction_name: String)

var _anim_player: AnimationPlayer
var _character: Node3D
var _ragdoll_ctrl: PartialRagdollController

const REQUIRED_ANIMS := ["flinch_front", "flinch_back", "flinch_left", "flinch_right"]


func _ready() -> void:
	_anim_player = get_node(animation_player_path) as AnimationPlayer
	_character = get_node(character_path) as Node3D
	if not ragdoll_controller_path.is_empty():
		_ragdoll_ctrl = get_node(ragdoll_controller_path) as PartialRagdollController
	_validate_animations()


func _validate_animations() -> void:
	if not _anim_player:
		return
	for anim_name in REQUIRED_ANIMS:
		if not _anim_player.has_animation(anim_name):
			push_warning("FlinchController: missing animation '%s'" % anim_name)


func on_hit(event: HitEvent) -> void:
	if not _anim_player or not _character:
		return

	# Skip flinch if ragdoll is actively reacting (ragdoll takes priority)
	if _ragdoll_ctrl and _ragdoll_ctrl.is_reacting():
		return

	var anim_name := _get_flinch_animation(event)
	flinch_triggered.emit(anim_name)
	_anim_player.play(anim_name, blend_time)
	_anim_player.queue("idle")


func _get_flinch_animation(event: HitEvent) -> String:
	# Headshot: use flinch_head if available
	if event.hit_bone_region == "head" and _anim_player.has_animation("flinch_head"):
		return "flinch_head"
	return _get_flinch_direction(event)


func _get_flinch_direction(event: HitEvent) -> String:
	var local_dir := _character.global_basis.inverse() * event.hit_direction
	local_dir.y = 0.0

	if local_dir.length_squared() < 0.001:
		return "flinch_front"

	local_dir = local_dir.normalized()

	# Animations named by hit source: "flinch_front" = hit from front = recoil back
	if absf(local_dir.z) > absf(local_dir.x):
		if local_dir.z < 0:
			return "flinch_front"
		else:
			return "flinch_back"
	else:
		if local_dir.x < 0:
			return "flinch_left"
		else:
			return "flinch_right"
