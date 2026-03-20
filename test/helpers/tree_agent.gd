## AnimationTree-based patrol agent for testing Kickback plugin compatibility
## with complex animation blending. Builds the entire AnimationTree programmatically
## in _ready() — no manual editor setup required. Inspect the tree at runtime via
## Godot's Remote tab in the Scene dock.
##
## Tree structure:
##   locomotion (StateMachine: idle ↔ walk ↔ run ↔ injured_walk)
##   → react_shot (OneShot: directional stagger)
##   → flinch_blend (Add2: additive flinch overlay)
##   → recovery_shot (OneShot: get-up override)
##   → Output
##
## Tests answered by this agent:
##   1. Does get_bone_pose() return AnimationTree-blended output?
##   2. Does additive flinch work with active ragdoll springs?
##   3. Does root motion stripping work with AnimationTree?
##   4. Can OneShot interrupt flinch overlay cleanly?
class_name TreeAgent
extends Node

@export var move_speed: float = 1.5
@export var waypoints: PackedVector3Array = PackedVector3Array()
@export var pause_at_waypoint: float = 1.5
@export var turn_speed: float = 6.0
@export var post_recovery_pause: float = 1.5

@export_group("Locomotion")
@export var acceleration: float = 3.0
@export var deceleration: float = 5.0
@export var injured_duration: float = 4.0

var _root: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _kickback: KickbackCharacter
var _flinch: FlinchController
var _active_ctrl: ActiveRagdollController

var _locomotion_playback: AnimationNodeStateMachinePlayback
var _waypoint_idx: int = 0
var _wait: float = 0.0
var _active: bool = false
var _ragdolled: bool = false
var _injured_timer: float = 0.0

var _current_speed: float = 0.0
var _target_speed: float = 0.0
var _flinch_tween: Tween


func _ready() -> void:
	_root = get_parent() as Node3D
	if not _root:
		return
	_anim_player = _root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if not _anim_player:
		push_warning("TreeAgent: No AnimationPlayer found")
		return

	for sibling in _root.get_children():
		if sibling is ActiveRagdollController:
			_active_ctrl = sibling
			sibling.state_changed.connect(_on_state_changed)
			sibling.recovery_started.connect(_on_recovery_started)
			sibling.recovery_finished.connect(_on_recovery_finished)
			if sibling.has_signal("hit_absorbed"):
				sibling.hit_absorbed.connect(_on_hit_absorbed)
		elif sibling is FlinchController:
			_flinch = sibling
			sibling.flinch_triggered.connect(_on_flinch_triggered)
		elif sibling is KickbackCharacter:
			_kickback = sibling

	_build_tree.call_deferred()

	if _kickback:
		if _kickback.is_setup_complete():
			_start()
		else:
			_kickback.setup_complete.connect(_start, CONNECT_ONE_SHOT)
	else:
		_start()


func _start() -> void:
	# Wait for deferred _build_tree to complete
	if not _anim_tree:
		await get_tree().process_frame
	if not _anim_tree:
		return
	_active = true
	_anim_tree.active = true
	_locomotion_playback = _anim_tree.get("parameters/locomotion/playback")
	if _locomotion_playback:
		_locomotion_playback.travel("walk" if not waypoints.is_empty() else "idle")


# ---- Tree construction ----

func _build_tree() -> void:
	_anim_tree = AnimationTree.new()
	_anim_tree.name = "AnimationTree"
	_root.add_child(_anim_tree)
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)

	var bt := AnimationNodeBlendTree.new()
	_anim_tree.tree_root = bt

	# Locomotion state machine
	bt.add_node("locomotion", _build_locomotion(), Vector2(0, 0))

	# React one-shot (stagger over locomotion)
	bt.add_node("react_shot", AnimationNodeOneShot.new(), Vector2(300, 0))
	var react_anim := AnimationNodeAnimation.new()
	react_anim.animation = &"react_front"
	bt.add_node("react_anim", react_anim, Vector2(300, 200))
	bt.connect_node("react_shot", 0, "locomotion")
	bt.connect_node("react_shot", 1, "react_anim")

	# Flinch additive overlay
	bt.add_node("flinch_blend", AnimationNodeAdd2.new(), Vector2(600, 0))
	var flinch_anim := AnimationNodeAnimation.new()
	flinch_anim.animation = &"flinch_front"
	bt.add_node("flinch_anim", flinch_anim, Vector2(600, 200))
	bt.connect_node("flinch_blend", 0, "react_shot")
	bt.connect_node("flinch_blend", 1, "flinch_anim")

	# Recovery one-shot (overrides everything)
	bt.add_node("recovery_shot", AnimationNodeOneShot.new(), Vector2(900, 0))
	var recovery_anim := AnimationNodeAnimation.new()
	recovery_anim.animation = &"get_up_face_down"
	bt.add_node("recovery_anim", recovery_anim, Vector2(900, 200))
	bt.connect_node("recovery_shot", 0, "flinch_blend")
	bt.connect_node("recovery_shot", 1, "recovery_anim")

	bt.connect_node("output", 0, "recovery_shot")

	# Init parameters
	_anim_tree.set("parameters/flinch_blend/add_amount", 0.0)
	_anim_tree.active = false


func _build_locomotion() -> AnimationNodeStateMachine:
	var sm := AnimationNodeStateMachine.new()

	var idle_n := AnimationNodeAnimation.new()
	idle_n.animation = &"idle"
	sm.add_node("idle", idle_n, Vector2(0, 0))

	var walk_n := AnimationNodeAnimation.new()
	walk_n.animation = &"walk"
	sm.add_node("walk", walk_n, Vector2(200, 0))

	var run_n := AnimationNodeAnimation.new()
	run_n.animation = &"run"
	sm.add_node("run", run_n, Vector2(400, 0))

	var inj_n := AnimationNodeAnimation.new()
	inj_n.animation = &"injured_walk"
	sm.add_node("injured_walk", inj_n, Vector2(200, 200))

	# Transitions with crossfade
	_add_transition(sm, "idle", "walk", 0.3)
	_add_transition(sm, "walk", "idle", 0.3)
	_add_transition(sm, "walk", "run", 0.2)
	_add_transition(sm, "run", "walk", 0.2)
	_add_transition(sm, "idle", "injured_walk", 0.4)
	_add_transition(sm, "injured_walk", "idle", 0.5)
	_add_transition(sm, "injured_walk", "walk", 0.3)
	_add_transition(sm, "walk", "injured_walk", 0.3)

	return sm


func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	sm.add_transition(from, to, t)


# ---- Physics (locomotion) ----

func _physics_process(delta: float) -> void:
	if not _active or not _root:
		return

	if _injured_timer > 0.0:
		_injured_timer -= delta
		if _injured_timer <= 0.0 and not _ragdolled:
			_travel("walk")

	if _ragdolled or waypoints.is_empty():
		_current_speed = 0.0
		return

	if _wait > 0.0:
		_wait -= delta
		_ramp_speed(0.0, delta)
		if _wait <= 0.0:
			_waypoint_idx = (_waypoint_idx + 1) % waypoints.size()
			_travel("injured_walk" if _injured_timer > 0.0 else "walk")
		return

	var target := waypoints[_waypoint_idx]
	var to_target := target - _root.global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.3:
		_wait = pause_at_waypoint
		_target_speed = 0.0
		_travel("idle")
		return

	var dir := to_target.normalized()
	var target_angle := atan2(dir.x, dir.z)
	var angle_diff := angle_difference(_root.rotation.y, target_angle)
	_root.rotation.y += clampf(angle_diff, -turn_speed * delta, turn_speed * delta)

	var decel_dist := _current_speed * 0.5
	if dist < decel_dist and decel_dist > 0.01:
		_target_speed = move_speed * (dist / decel_dist)
	else:
		_target_speed = move_speed
	_ramp_speed(_target_speed, delta)

	if _current_speed > 0.01:
		_root.global_position += dir * _current_speed * delta


func _ramp_speed(target: float, delta: float) -> void:
	if target > _current_speed:
		_current_speed = move_toward(_current_speed, target, acceleration * delta)
	else:
		_current_speed = move_toward(_current_speed, target, deceleration * delta)


func _travel(state: String) -> void:
	if _locomotion_playback and not _ragdolled:
		_locomotion_playback.travel(state)


# ---- Kickback signal handlers ----

func _on_state_changed(new_state: int) -> void:
	if new_state == ActiveRagdollController.State.RAGDOLL \
		or new_state == ActiveRagdollController.State.PERSISTENT:
		_ragdolled = true
		_current_speed = 0.0
		_target_speed = 0.0
		_travel("idle")


func _on_recovery_started(face_up: bool) -> void:
	_ragdolled = true
	# Temporarily disable the AnimationTree so the AnimationPlayer can play the get-up
	# animation directly. The springs use these poses as targets during recovery.
	_anim_tree.active = false
	var anim: StringName
	if face_up:
		anim = &"get_up_face_up"
	else:
		anim = &"kip_up" if randf() < 0.3 else &"get_up_face_down"
	_anim_player.play(anim)


func _on_recovery_finished() -> void:
	# Springs are restored — character is physically standing.
	# Re-enable AnimationTree and resume locomotion.
	_anim_tree.active = true
	_locomotion_playback = _anim_tree.get("parameters/locomotion/playback")
	_injured_timer = injured_duration
	_ragdolled = false
	_travel("idle")
	# Brief pause (catching breath), then resume walking.
	await get_tree().create_timer(post_recovery_pause).timeout
	if _ragdolled:
		return  # Got hit again during pause
	_travel("injured_walk")


func _on_hit_absorbed(rig_name: String, _new_strength: float) -> void:
	if _ragdolled:
		return
	var bt: AnimationNodeBlendTree = _anim_tree.tree_root
	var node: AnimationNodeAnimation = bt.get_node("react_anim")
	node.animation = _bone_to_react(rig_name)
	_anim_tree.set("parameters/react_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _on_flinch_triggered(direction: int) -> void:
	if _ragdolled:
		return
	var bt: AnimationNodeBlendTree = _anim_tree.tree_root
	var flinch_node: AnimationNodeAnimation = bt.get_node("flinch_anim")
	flinch_node.animation = _dir_to_flinch(direction)
	if _flinch_tween and _flinch_tween.is_valid():
		_flinch_tween.kill()
	_flinch_tween = create_tween()
	var intensity: float = _flinch.last_hit_intensity if _flinch else 5.0
	var hold := remap(clampf(intensity, 2.0, 30.0), 2.0, 30.0, 0.1, 0.4)
	_flinch_tween.tween_property(_anim_tree, "parameters/flinch_blend/add_amount", 1.0, 0.05)
	_flinch_tween.tween_interval(hold)
	_flinch_tween.tween_property(_anim_tree, "parameters/flinch_blend/add_amount", 0.0, 0.3)


# ---- Helpers ----

func _dir_to_flinch(direction: int) -> StringName:
	match direction:
		FlinchController.Direction.FRONT: return &"flinch_front"
		FlinchController.Direction.BACK: return &"flinch_back"
		FlinchController.Direction.LEFT: return &"flinch_left"
		FlinchController.Direction.RIGHT: return &"flinch_right"
		FlinchController.Direction.HEAD: return &"flinch_head"
	return &"flinch_front"


func _bone_to_react(rig_name: String) -> StringName:
	match rig_name:
		"Chest", "Spine", "Hips": return &"react_front"
		"Head": return &"react_back"
		"UpperArm_L", "LowerArm_L", "Hand_L", "UpperLeg_L", "LowerLeg_L", "Foot_L": return &"react_left"
		"UpperArm_R", "LowerArm_R", "Hand_R", "UpperLeg_R", "LowerLeg_R", "Foot_R": return &"react_right"
	return &"react_front"


func get_tree_state() -> String:
	if not _anim_tree or not _anim_tree.active:
		return "OFF"
	var parts := PackedStringArray()
	if _locomotion_playback:
		parts.append(_locomotion_playback.get_current_node())
	var flinch_amt: float = _anim_tree.get("parameters/flinch_blend/add_amount")
	if flinch_amt > 0.01:
		parts.append("flinch:%.0f%%" % (flinch_amt * 100))
	if _anim_tree.get("parameters/react_shot/active"):
		parts.append("REACT")
	if _anim_tree.get("parameters/recovery_shot/active"):
		parts.append("RECOVERY")
	return "+".join(parts) if not parts.is_empty() else "idle"
