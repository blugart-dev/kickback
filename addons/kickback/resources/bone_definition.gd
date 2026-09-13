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
## Peak torque (N·m) the muscle driving this bone's PARENT joint can exert when
## the bone is at full spring strength — the joint motor's force limit in
## [enum RagdollTuning.MuscleMode] JOINT_MOTOR (scaled by the bone's current
## strength ratio and [member RagdollTuning.muscle_strength_scale]). Anatomical
## ballpark: hip 200, knee 150, spine 150, shoulder 60, elbow 40, neck 30, wrist
## 10. Unused by the legacy velocity resolver. Ignored on the root bone.
@export_range(0.0, 1000.0) var muscle_torque: float = 50.0

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
## For a [member sole_aligned] box it is instead the fraction of the box LENGTH that
## lies ahead of the bone origin (0.77 = 77 % toes, 23 % heel).
@export_range(0.0, 1.0) var shape_offset: float = 0.5
## Feet only. The box is built LEVEL with the character's up axis (not along the
## bone, which on most rigs points from the ankle down to the toes) with its bottom
## face exactly [member RagdollTuning.foot_ik_ankle_height] below the bone origin —
## the same sole the foot IK plants — so a standing foot's collider rests flat on the
## ground instead of a pitched box whose corner sits several cm below it.
## [member box_size]: x = width, y = thickness, z = heel-to-toe length; the bone
## origin sits [member shape_offset] of the length from the back. This is what lets
## the feet carry the body's weight (docs/PLAN.md 0.6.0).
@export var sole_aligned: bool = false
