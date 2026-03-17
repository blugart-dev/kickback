class_name ActiveRagdollController
extends Node

@export var spring_resolver_path: NodePath

var _spring: SpringResolver
var _adjacency: Dictionary = {}


func _ready() -> void:
	_spring = get_node(spring_resolver_path) as SpringResolver
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


func apply_hit(body: RigidBody3D, hit_dir: Vector3, hit_pos: Vector3, profile: WeaponProfile) -> void:
	# Compute impulse from profile
	var final_impulse := profile.base_impulse * profile.impulse_transfer_ratio
	var direction := (hit_dir + Vector3.UP * profile.upward_bias).normalized()
	var local_offset := body.to_local(hit_pos)
	body.apply_impulse(direction * final_impulse, local_offset)

	# Reduce spring strength
	var rig_name: String = body.name
	_reduce_strength(rig_name, profile.strength_reduction, profile.strength_spread)

	# Set per-bone recovery rate
	_spring.recovery_rate = profile.recovery_rate

	# Random full ragdoll check
	if randf() < profile.ragdoll_probability:
		_full_ragdoll()


# Load-bearing bones that shouldn't fully collapse from stacking hits
const MIN_STRENGTH: Dictionary = {
	"Hips": 0.15, "Spine": 0.10, "Chest": 0.10,
	"UpperLeg_L": 0.10, "UpperLeg_R": 0.10,
	"LowerLeg_L": 0.08, "LowerLeg_R": 0.08,
	"Foot_L": 0.05, "Foot_R": 0.05,
}


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


func _full_ragdoll() -> void:
	for rig_name: String in _spring._bones:
		_spring.set_bone_strength(rig_name, 0.0)
