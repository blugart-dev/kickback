class_name PassiveRagdollController
extends Node

@export var simulator_path: NodePath
@export var animation_player_path: NodePath

var _simulator: PhysicalBoneSimulator3D
var _anim_player: AnimationPlayer
var _is_ragdoll: bool = false


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_simulator = get_node(simulator_path) as PhysicalBoneSimulator3D
	_anim_player = get_node(animation_player_path) as AnimationPlayer
	if _anim_player and _anim_player.has_animation("idle"):
		_anim_player.play("idle")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		toggle_ragdoll()


func toggle_ragdoll() -> void:
	if _is_ragdoll:
		_stop_ragdoll()
	else:
		_start_ragdoll()


func _start_ragdoll() -> void:
	_is_ragdoll = true
	# Deferred start — wait one physics frame per GODOT_CONSTRAINTS.md
	await get_tree().physics_frame
	_simulator.physical_bones_start_simulation()


func _stop_ragdoll() -> void:
	_is_ragdoll = false
	_simulator.physical_bones_stop_simulation()


func is_ragdoll() -> bool:
	return _is_ragdoll
