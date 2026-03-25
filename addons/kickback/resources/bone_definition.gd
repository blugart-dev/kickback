## Defines a single bone in the physics ragdoll rig: its mapping to the
## skeleton, mass, collision shape, and the child bone used for shape offset.
class_name BoneDefinition
extends Resource

## Internal rig name (e.g. "Hips", "UpperArm_L"). Used as the RigidBody3D node name.
@export var rig_name: String
## Actual skeleton bone name (e.g. "mixamorig_Hips"). Must match Skeleton3D.
@export var skeleton_bone: String
## Child skeleton bone for computing collision shape offset. Empty if none.
@export var child_bone: String = ""
## Mass of the RigidBody3D for this bone.
@export var mass: float = 5.0

@export_group("Collision Shape")
## Collision shape type: "box", "capsule", or "sphere".
@export_enum("box", "capsule", "sphere") var shape_type: String = "box"
## Size of the box collision shape (only used when shape_type is "box").
@export var box_size: Vector3 = Vector3(0.2, 0.2, 0.2)
## Radius of the capsule collision shape (only used when shape_type is "capsule").
@export var capsule_radius: float = 0.05
## Height of the capsule collision shape (only used when shape_type is "capsule").
@export var capsule_height: float = 0.25
## Radius of the sphere collision shape (only used when shape_type is "sphere").
@export var sphere_radius: float = 0.1
## Where the collision shape sits along the bone direction toward the child bone.
## 0.5 = centered between bone and child. Higher values shift toward the child.
@export_range(0.0, 1.0) var shape_offset: float = 0.5
