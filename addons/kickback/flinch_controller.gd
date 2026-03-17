class_name FlinchController
extends Node

## Path to the AnimationPlayer that has the flinch animations in its library.
@export var animation_player_path: NodePath
## Path to the character root (for direction calculation).
@export var character_path: NodePath
@export var blend_time: float = 0.1
@export var fade_duration: float = 0.3

signal flinch_triggered(direction_name: String)

var _anim_player: AnimationPlayer
var _character: Node3D


func _ready() -> void:
	_anim_player = get_node(animation_player_path) as AnimationPlayer
	_character = get_node(character_path) as Node3D


func on_hit(event: HitEvent) -> void:
	if not _anim_player or not _character:
		return

	var anim_name := _get_flinch_direction(event)
	flinch_triggered.emit(anim_name)

	# Play the flinch with a quick blend, then queue idle back
	_anim_player.play(anim_name, blend_time)
	_anim_player.queue("idle")


func _get_flinch_direction(event: HitEvent) -> String:
	var local_dir := _character.global_basis.inverse() * event.hit_direction
	local_dir.y = 0.0

	if local_dir.length_squared() < 0.001:
		return "flinch_front"

	local_dir = local_dir.normalized()

	# Animations are named by hit source: "flinch_front" = hit from front = recoil back
	# Godot: -Z is forward, +X is right
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
