class_name ActiveRagdollController
extends Node

@export var spring_resolver_path: NodePath
@export var strength_reduction: float = 0.92
@export var strength_spread: int = 2
@export var hit_gravity: float = 0.5

var _spring: SpringResolver
var _adjacency: Dictionary = {}  # rig_name → PackedStringArray of direct neighbors


func _ready() -> void:
	_spring = get_node(spring_resolver_path) as SpringResolver
	_build_adjacency()


func _build_adjacency() -> void:
	# Build neighbor map from PhysicsRigBuilder's JOINT_MAP
	for joint in PhysicsRigBuilder.JOINT_MAP:
		var p: String = joint.parent
		var c: String = joint.child
		if p not in _adjacency:
			_adjacency[p] = PackedStringArray()
		if c not in _adjacency:
			_adjacency[c] = PackedStringArray()
		_adjacency[p].append(c)
		_adjacency[c].append(p)


func apply_hit(body: RigidBody3D, hit_dir: Vector3, impulse_mag: float, hit_pos: Vector3) -> void:
	# Apply impulse
	var local_offset := body.to_local(hit_pos)
	body.apply_impulse(hit_dir * impulse_mag, local_offset)

	# Reduce spring strength on hit bone + neighbors
	# Gravity is managed by spring resolver based on strength ratio
	var rig_name: String = body.name
	_reduce_strength(rig_name)


func _reduce_strength(rig_name: String) -> void:
	# Hit bone: full reduction
	var current := _spring.get_bone_strength(rig_name)
	_spring.set_bone_strength(rig_name, current * (1.0 - strength_reduction))

	# Neighbors with distance falloff
	if strength_spread > 0:
		var visited := {rig_name: true}
		var current_level := PackedStringArray([rig_name])

		for dist in range(1, strength_spread + 1):
			var next_level := PackedStringArray()
			var falloff := 1.0 - (float(dist) / float(strength_spread + 1))

			for bone: String in current_level:
				if bone not in _adjacency:
					continue
				for neighbor: String in _adjacency[bone]:
					if neighbor in visited:
						continue
					visited[neighbor] = true
					next_level.append(neighbor)

					var s := _spring.get_bone_strength(neighbor)
					_spring.set_bone_strength(neighbor, s * (1.0 - strength_reduction * falloff))

			current_level = next_level
