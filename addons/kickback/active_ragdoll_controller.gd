class_name ActiveRagdollController
extends Node

@export var spring_resolver_path: NodePath
@export var rig_builder_path: NodePath
@export var animation_player_path: NodePath
@export var character_root_path: NodePath
@export var recovery_duration: float = 1.5
@export var safety_timeout: float = 5.0

enum State { NORMAL, RAGDOLL, GETTING_UP }

var _spring: SpringResolver
var _rig_builder: PhysicsRigBuilder
var _anim_player: AnimationPlayer
var _character_root: Node3D
var _adjacency: Dictionary = {}
var _state: int = State.NORMAL
var _recovery_elapsed: float = 0.0
var _ragdoll_elapsed: float = 0.0

signal state_changed(new_state: int)

const RAGDOLL_FORCE_RECOVERY_TIME := 3.0

const MIN_STRENGTH: Dictionary = {
	"Hips": 0.15, "Spine": 0.10, "Chest": 0.10,
	"UpperLeg_L": 0.10, "UpperLeg_R": 0.10,
	"LowerLeg_L": 0.08, "LowerLeg_R": 0.08,
	"Foot_L": 0.05, "Foot_R": 0.05,
}


func _ready() -> void:
	JoltCheck.warn_if_not_jolt()
	_spring = get_node(spring_resolver_path) as SpringResolver
	_rig_builder = get_node(rig_builder_path) as PhysicsRigBuilder
	_anim_player = get_node(animation_player_path) as AnimationPlayer
	if not character_root_path.is_empty():
		_character_root = get_node(character_root_path) as Node3D
	_build_adjacency()


func _build_adjacency() -> void:
	for joint in PhysicsRigBuilder.JOINT_MAP:
		var p: String = joint.parent
		var c: String = joint.child
		if p not in _adjacency:
			_adjacency[p] = PackedStringArray()
		if c not in _adjacency:
			_adjacency[c] = PackedStringArray()
		_adjacency[p].append(c)
		_adjacency[c].append(p)


func _physics_process(delta: float) -> void:
	match _state:
		State.RAGDOLL:
			_ragdoll_elapsed += delta
			if _spring.is_settled(delta) or _ragdoll_elapsed > RAGDOLL_FORCE_RECOVERY_TIME:
				_start_recovery()
		State.GETTING_UP:
			_recovery_elapsed += delta
			var t := clampf(_recovery_elapsed / recovery_duration, 0.0, 1.0)
			for rig_name: String in _spring.get_all_bone_names():
				var base: float = _spring.get_base_strength(rig_name)
				_spring.set_bone_strength(rig_name, base * t)

			if (_spring.get_max_rotation_error() < 0.15 and t >= 0.9) or _recovery_elapsed > safety_timeout:
				_finish_recovery()


func apply_hit(body: RigidBody3D, hit_dir: Vector3, hit_pos: Vector3, profile: WeaponProfile) -> void:
	if _state == State.GETTING_UP:
		_full_ragdoll()
		return

	var final_impulse := profile.base_impulse * profile.impulse_transfer_ratio
	var direction := (hit_dir + Vector3.UP * profile.upward_bias).normalized()
	var local_offset := body.to_local(hit_pos)
	body.apply_impulse(direction * final_impulse, local_offset)

	if _state == State.RAGDOLL:
		_spring.reset_settle_timer()
		return

	_reduce_strength(body.name, profile.strength_reduction, profile.strength_spread)
	_spring.recovery_rate = profile.recovery_rate

	if randf() < profile.ragdoll_probability:
		_full_ragdoll()


func trigger_ragdoll() -> void:
	_full_ragdoll()


func _full_ragdoll() -> void:
	for rig_name: String in _spring.get_all_bone_names():
		_spring.set_bone_strength(rig_name, 0.0)
	_state = State.RAGDOLL
	_ragdoll_elapsed = 0.0
	_spring.recovery_rate = 0.0
	_spring.reset_settle_timer()
	state_changed.emit(_state)


func _start_recovery() -> void:
	_state = State.GETTING_UP
	_recovery_elapsed = 0.0
	state_changed.emit(_state)

	var bodies := _rig_builder.get_bodies()
	var hip_body: RigidBody3D = bodies.get("Hips")
	var chest_body: RigidBody3D = bodies.get("Chest")
	var head_body: RigidBody3D = bodies.get("Head")

	# Detect orientation BEFORE moving root
	var face_up := true
	if chest_body:
		face_up = chest_body.global_basis.y.dot(Vector3.UP) > 0

	# Save all body world transforms before moving root
	var saved_transforms: Dictionary = {}
	for rig_name: String in bodies:
		var body: RigidBody3D = bodies[rig_name]
		saved_transforms[rig_name] = body.global_transform

	# Reposition character root to ragdoll landing position
	if _character_root and hip_body:
		var hip_pos := hip_body.global_position
		_character_root.global_position = Vector3(hip_pos.x, 0.0, hip_pos.z)

		if head_body:
			var head_pos := head_body.global_position
			var facing := Vector3(head_pos.x - hip_pos.x, 0.0, head_pos.z - hip_pos.z)
			if facing.length_squared() > 0.01:
				_character_root.global_rotation.y = atan2(facing.x, facing.z)

	# Restore body world transforms — bodies stay where they were
	# Spring ramp will gradually pull them toward the get-up animation
	for rig_name: String in saved_transforms:
		var body: RigidBody3D = bodies[rig_name]
		body.global_transform = saved_transforms[rig_name]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

	# Play get-up animation
	var anim_name := "get_up_face_up" if face_up else "get_up_face_down"
	if _anim_player:
		if _anim_player.has_animation(anim_name):
			_anim_player.play(anim_name)
		else:
			push_warning("ActiveRagdollController: missing animation '%s'" % anim_name)


func _finish_recovery() -> void:
	_state = State.NORMAL
	_spring.recovery_rate = _spring.get_default_recovery_rate()
	state_changed.emit(_state)

	for rig_name: String in _spring.get_all_bone_names():
		var base: float = _spring.get_base_strength(rig_name)
		_spring.set_bone_strength(rig_name, base)

	if _anim_player and _anim_player.has_animation("idle"):
		_anim_player.play("idle")


func get_state() -> int:
	return _state


func get_state_name() -> String:
	match _state:
		State.NORMAL: return "NORMAL"
		State.RAGDOLL: return "RAGDOLL"
		State.GETTING_UP: return "GETTING UP"
	return "UNKNOWN"


func _reduce_strength(rig_name: String, reduction: float, spread: int) -> void:
	var current := _spring.get_bone_strength(rig_name)
	var floor: float = MIN_STRENGTH.get(rig_name, 0.0)
	_spring.set_bone_strength(rig_name, maxf(current * (1.0 - reduction), floor))

	if spread > 0:
		var visited := {rig_name: true}
		var current_level := PackedStringArray([rig_name])

		for dist in range(1, spread + 1):
			var next_level := PackedStringArray()
			var falloff := 1.0 - (float(dist) / float(spread + 1))

			for bone: String in current_level:
				if bone not in _adjacency:
					continue
				for neighbor: String in _adjacency[bone]:
					if neighbor in visited:
						continue
					visited[neighbor] = true
					next_level.append(neighbor)
					var s := _spring.get_bone_strength(neighbor)
					var nfloor: float = MIN_STRENGTH.get(neighbor, 0.0)
					_spring.set_bone_strength(neighbor, maxf(s * (1.0 - reduction * falloff), nfloor))

			current_level = next_level
